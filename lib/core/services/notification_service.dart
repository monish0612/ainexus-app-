import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../../data/local/database/app_database.dart';
import '../platform/platform_capabilities.dart';
import 'telegram_logger.dart';

// ── Shared Constants ─────────────────────────────────────────────────────────

const _kAccent = Color(0xFF0D59F2);

// ── Expense Notification Constants ───────────────────────────────────────────

const _kExpenseTask = 'dailyExpenseNotification';
const _kExpenseUniqueId = 'app.ainexus.daily_expense_9pm';
const _kExpenseChannelId = 'nexus_daily_recap';
const _kExpenseChannelName = 'Daily Expense Recap';
const _kExpenseChannelDesc = 'Nightly summary of your daily spending';
const _kExpenseNotifId = 9000;
const _kExpenseLastDateKey = 'last_expense_notif_date';

// ── News Notification Constants ──────────────────────────────────────────────

const _kNewsTask = 'newsArticleCheck';
const _kNewsUniquePrefix = 'app.ainexus.news_check_';
const _kNewsChannelId = 'nexus_news_alerts';
const _kNewsChannelName = 'News Alerts';
const _kNewsChannelDesc = 'Alerts when new articles are ready to read';
const _kNewsNotifId = 9100;
const _kNewsLastSlotKey = 'last_news_notif_slot';
const _kNewsLastCountKey = 'last_news_unread_count';

const _kNewsSlots = <int>[730, 1100, 1400, 1700, 2100];

// ── Category Emojis (Expense) ────────────────────────────────────────────────

const _categoryEmojis = <String, String>{
  'Food': '\u{1F37D}\u{FE0F}',
  'Grocery': '\u{1F6D2}',
  'Transport': '\u{1F697}',
  'Entertainment': '\u{1F3AC}',
  'Shopping': '\u{1F6CD}\u{FE0F}',
  'Bills': '\u{1F4C4}',
  'Health': '\u{1F48A}',
  'Others': '\u{1F4E6}',
};

final _noExpenseMessages = [
  'Your wallet is quiet! Did you forget to log something?',
  'Zero expenses today \u2014 either you\'re very disciplined or very forgetful!',
  'Your wallet took a day off! Tap to log any expenses before you forget.',
  'Nothing tracked today \u2014 quick-log anything you spent!',
  'A clean slate today. Tap \u201CAdd Expense\u201D to catch up.',
];

// ── News Notification Titles (rotated) ───────────────────────────────────────

final _newsTitles = [
  '\u{1F4F0} Fresh reads just dropped',
  '\u{1F4E8} New articles waiting for you',
  '\u{1F525} Trending now on your feed',
  '\u{2728} Your daily briefing is ready',
  '\u{1F4DA} Catch up on what\'s new',
  '\u{1F680} Don\'t miss today\'s top stories',
  '\u{1F30D} The world moved \u2014 here\'s what happened',
];

final _newsBodyTemplates = [
  '{n} unread article{s} ready to explore. Tap to dive in.',
  'You\'ve got {n} fresh article{s}. Your reading list awaits.',
  '{n} new story{ies} just landed in your feed.',
  'Your feed has {n} unread piece{s}. Stay informed!',
  '{n} article{s} you haven\'t seen yet \u2014 take a look.',
];

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND CALLBACK — WorkManager entry point (runs in separate isolate)
// ═══════════════════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (taskName == _kExpenseTask) {
        await _ExpenseBot.execute();
        _TaskScheduler.scheduleNextExpense();
      } else if (taskName == _kNewsTask) {
        await _NewsBot.execute();
        _TaskScheduler.scheduleNextNews();
      }
    } catch (e, st) {
      TLog.e('Notif', 'Background task "$taskName" crashed', error: e, st: st);
    }
    return true;
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// 1. TASK SCHEDULER
// ═══════════════════════════════════════════════════════════════════════════════

class _TaskScheduler {
  _TaskScheduler._();

  static void _ensureTz() => tz.initializeTimeZones();

  static tz.TZDateTime _nowIST() {
    _ensureTz();
    return tz.TZDateTime.now(tz.getLocation('Asia/Kolkata'));
  }

  // ── Expense: next 9 PM IST ────────────────────────────────────────────────

  static Duration durationUntilNext9PMIST() {
    final now = _nowIST();
    final ist = tz.getLocation('Asia/Kolkata');
    var next = tz.TZDateTime(ist, now.year, now.month, now.day, 21, 0);
    if (now.isAfter(next)) next = next.add(const Duration(days: 1));
    return next.difference(now);
  }

  static void scheduleNextExpense() {
    final delay = durationUntilNext9PMIST();
    Workmanager().registerOneOffTask(
      _kExpenseUniqueId,
      _kExpenseTask,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.not_required),
    );
  }

  // ── News: next slot from [7:30, 11:00, 14:00, 17:00, 21:00] IST ──────────

  static Duration durationUntilNextNewsSlot() {
    final now = _nowIST();
    final ist = tz.getLocation('Asia/Kolkata');
    final nowMinutes = now.hour * 100 + now.minute;

    for (final slot in _kNewsSlots) {
      if (nowMinutes < slot) {
        final h = slot ~/ 100;
        final m = slot % 100;
        final target = tz.TZDateTime(ist, now.year, now.month, now.day, h, m);
        return target.difference(now);
      }
    }

    final firstSlot = _kNewsSlots.first;
    final h = firstSlot ~/ 100;
    final m = firstSlot % 100;
    final tomorrow = now.add(const Duration(days: 1));
    final target = tz.TZDateTime(
      ist,
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      h,
      m,
    );
    return target.difference(now);
  }

  static void scheduleNextNews() {
    final delay = durationUntilNextNewsSlot();
    Workmanager().registerOneOffTask(
      '${_kNewsUniquePrefix}next',
      _kNewsTask,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.not_required),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2. DATA FETCHERS (background-safe DB access)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Expense ──────────────────────────────────────────────────────────────────

class _ExpenseDataFetcher {
  _ExpenseDataFetcher._();

  static Future<_DailySummary> fetchTodaySummary() async {
    final db = AppDatabase.background();
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final tomorrowStart = todayStart.add(const Duration(days: 1));

      final allExpenses = await db.select(db.expenses).get();
      final today = allExpenses.where((e) {
        final d = DateTime.tryParse(e.date);
        if (d == null) return false;
        return !d.isBefore(todayStart) && d.isBefore(tomorrowStart);
      }).toList();

      final total = today.fold<double>(0, (s, e) => s + e.amount);
      final count = today.length;

      final byCategory = <String, double>{};
      for (final e in today) {
        byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
      }

      final budgetRow = await (db.select(db.budgetEntries)
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.setAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(1))
          .getSingleOrNull();

      return _DailySummary(
        total: total,
        count: count,
        budget: budgetRow?.amount,
        categoryBreakdown: byCategory,
      );
    } finally {
      await db.close();
    }
  }
}

class _DailySummary {
  const _DailySummary({
    required this.total,
    required this.count,
    required this.budget,
    required this.categoryBreakdown,
  });

  final double total;
  final int count;
  final double? budget;
  final Map<String, double> categoryBreakdown;

  bool get hasExpenses => count > 0;
  bool get hasBudget => budget != null && budget! > 0;

  int? get budgetProgressPercent {
    if (!hasBudget) return null;
    return ((total / budget!) * 100).clamp(0, 100).toInt();
  }
}

// ── News ─────────────────────────────────────────────────────────────────────

class _NewsDataFetcher {
  _NewsDataFetcher._();

  static Future<_NewsSummary> fetchUnreadSummary() async {
    final db = AppDatabase.background();
    try {
      final all = await db.select(db.newsArticles).get();
      final unread = all.where((a) => !a.isRead && !a.isSaved).toList();

      String? topTitle;
      String? topSource;
      if (unread.isNotEmpty) {
        final newest = unread.first;
        topTitle = newest.title;
        topSource = newest.source;
      }

      return _NewsSummary(
        unreadCount: unread.length,
        topTitle: topTitle,
        topSource: topSource,
      );
    } finally {
      await db.close();
    }
  }
}

class _NewsSummary {
  const _NewsSummary({
    required this.unreadCount,
    this.topTitle,
    this.topSource,
  });

  final int unreadCount;
  final String? topTitle;
  final String? topSource;

  bool get hasUnread => unreadCount > 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. NOTIFICATION UI
// ═══════════════════════════════════════════════════════════════════════════════

class _NotificationUI {
  _NotificationUI._();

  static final _fmt = NumberFormat.currency(
    symbol: '\u20B9',
    locale: 'en_IN',
    decimalDigits: 0,
  );

  static Future<FlutterLocalNotificationsPlugin> _backgroundFln() async {
    final fln = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await fln.initialize(const InitializationSettings(android: android));
    return fln;
  }

  // ── Expense Notification ───────────────────────────────────────────────────

  static Future<void> showExpense(
    _DailySummary summary, {
    FlutterLocalNotificationsPlugin? plugin,
  }) async {
    final fln = plugin ?? await _backgroundFln();

    final title = summary.hasExpenses
        ? '\u{1F4B0} Today\'s Financial Snapshot'
        : '\u{1F4C9} No Expenses Logged Today';

    final body = _buildExpenseBody(summary);

    final showProgress = summary.hasExpenses && summary.hasBudget;
    final progress = summary.budgetProgressPercent ?? 0;

    final details = AndroidNotificationDetails(
      _kExpenseChannelId,
      _kExpenseChannelName,
      channelDescription: _kExpenseChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: summary.hasExpenses
            ? '${summary.count} transaction${summary.count == 1 ? '' : 's'}'
            : 'Tap to log your expenses',
      ),
      showProgress: showProgress,
      maxProgress: 100,
      progress: progress,
      color: _kAccent,
      ledColor: _kAccent,
      ledOnMs: 1000,
      ledOffMs: 500,
      enableLights: true,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'add_expense',
          '\u2795 Add Expense',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'dismiss',
          'Done',
          cancelNotification: true,
        ),
      ],
    );

    await fln.show(
      _kExpenseNotifId,
      title,
      body,
      NotificationDetails(android: details),
      payload: 'expense_tab',
    );
  }

  static String _buildExpenseBody(_DailySummary summary) {
    if (!summary.hasExpenses) {
      return _noExpenseMessages[Random().nextInt(_noExpenseMessages.length)];
    }

    final total = _fmt.format(summary.total);
    final count = summary.count;
    final buf = StringBuffer()
      ..write('You\'ve spent $total across $count ')
      ..write(count == 1 ? 'transaction' : 'transactions')
      ..write(' today.');

    if (summary.hasBudget) {
      final pct = summary.budgetProgressPercent!;
      final budgetStr = _fmt.format(summary.budget!);
      buf.write('\n\u{1F4CA} Budget used: $pct% of $budgetStr');
      if (pct >= 90) {
        buf.write(' \u26A0\u{FE0F} Almost maxed out!');
      } else if (pct >= 70) {
        buf.write(' \u2014 getting close.');
      }
    }

    final sorted = summary.categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.isNotEmpty) {
      final top = sorted.first;
      final emoji = _categoryEmojis[top.key] ?? '\u{1F4B0}';
      buf.write(
        '\n$emoji ${top.key} was your biggest spend (${_fmt.format(top.value)})',
      );
    }

    if (sorted.length > 1) {
      final second = sorted[1];
      final emoji2 = _categoryEmojis[second.key] ?? '\u{1F4B0}';
      buf.write('\n$emoji2 ${second.key}: ${_fmt.format(second.value)}');
    }

    return buf.toString();
  }

  // ── News Notification ──────────────────────────────────────────────────────

  static Future<void> showNews(
    _NewsSummary summary, {
    FlutterLocalNotificationsPlugin? plugin,
  }) async {
    if (!summary.hasUnread) return;

    final fln = plugin ?? await _backgroundFln();

    final rng = Random();
    final title = _newsTitles[rng.nextInt(_newsTitles.length)];

    final n = summary.unreadCount;
    final template = _newsBodyTemplates[rng.nextInt(_newsBodyTemplates.length)];
    var body = template
        .replaceAll('{n}', n.toString())
        .replaceAll('{s}', n == 1 ? '' : 's')
        .replaceAll('{ies}', n == 1 ? 'y' : 'ies');

    if (summary.topTitle != null && summary.topTitle!.isNotEmpty) {
      body += '\n\u{1F4CC} "${summary.topTitle}"';
      if (summary.topSource != null && summary.topSource!.isNotEmpty) {
        body += ' \u2014 ${summary.topSource}';
      }
    }

    final details = AndroidNotificationDetails(
      _kNewsChannelId,
      _kNewsChannelName,
      channelDescription: _kNewsChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: '$n unread article${n == 1 ? '' : 's'}',
      ),
      color: _kAccent,
      ledColor: _kAccent,
      ledOnMs: 1000,
      ledOffMs: 500,
      enableLights: true,
      category: AndroidNotificationCategory.recommendation,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'open_news',
          '\u{1F4F0} Read Now',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'dismiss',
          'Later',
          cancelNotification: true,
        ),
      ],
    );

    await fln.show(
      _kNewsNotifId,
      title,
      body,
      NotificationDetails(android: details),
      payload: 'news_tab',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. NOTIFICATION BOTS (background controllers)
// ═══════════════════════════════════════════════════════════════════════════════

class _ExpenseBot {
  _ExpenseBot._();

  static Future<void> execute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = _todayDateString();
      if (prefs.getString(_kExpenseLastDateKey) == todayStr) return;

      final summary = await _ExpenseDataFetcher.fetchTodaySummary();
      await _NotificationUI.showExpense(summary);
      await prefs.setString(_kExpenseLastDateKey, todayStr);
    } catch (e, st) {
      TLog.e('Notif', 'Expense notification failed', error: e, st: st);
    }
  }
}

class _NewsBot {
  _NewsBot._();

  static Future<void> execute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final slotKey = _currentSlotKey();
      if (prefs.getString(_kNewsLastSlotKey) == slotKey) return;

      final summary = await _NewsDataFetcher.fetchUnreadSummary();
      if (!summary.hasUnread) return;

      final lastCount = prefs.getInt(_kNewsLastCountKey) ?? 0;
      if (summary.unreadCount <= lastCount && lastCount > 0) return;

      await _NotificationUI.showNews(summary);
      await prefs.setString(_kNewsLastSlotKey, slotKey);
      await prefs.setInt(_kNewsLastCountKey, summary.unreadCount);
    } catch (e, st) {
      TLog.e('Notif', 'News notification failed', error: e, st: st);
    }
  }

  static String _currentSlotKey() {
    final now = _TaskScheduler._nowIST();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final minutes = now.hour * 100 + now.minute;

    var matchedSlot = _kNewsSlots.last;
    for (final slot in _kNewsSlots) {
      if (minutes <= slot + 30) {
        matchedSlot = slot;
        break;
      }
    }
    return '$date-$matchedSlot';
  }
}

String _todayDateString() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════════════════════════

/// Stream that emits notification payloads when the user taps a notification.
/// Consumed by AppShell to navigate to the correct tab.
final notificationPayloadStream = StreamController<String>.broadcast();

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _fln = FlutterLocalNotificationsPlugin();
  void Function(String? payload)? _onTap;

  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    _onTap = onTap;

    // Web doesn't support local scheduled notifications, foreground services
    // or workmanager. Skip the entire pipeline and let the rest of the app
    // run normally; the in-app realtime stream still drives navigation.
    if (!PlatformCapabilities.canUseNotifications) {
      TLog.d('Notif', 'Web build — notification pipeline disabled');
      return;
    }

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _fln.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _handleResponse,
    );

    final androidPlugin = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    await Workmanager().initialize(
      notificationCallbackDispatcher,
      isInDebugMode: false,
    );

    final launchDetails = await _fln.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails!.notificationResponse?.payload;
      if (payload != null) _onTap?.call(payload);
    }
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    final actionId = response.actionId;
    if (actionId == 'add_expense' || payload == 'expense_tab') {
      _onTap?.call('expense_tab');
    } else if (actionId == 'open_news' || payload == 'news_tab') {
      _onTap?.call('news_tab');
    } else if (payload != null && payload.isNotEmpty) {
      // Forward any other payload verbatim (e.g. tutor_tab, news_summary).
      // The main.dart handler decides which strings are valid before routing
      // them onto the broadcast stream.
      _onTap?.call(payload);
    }
  }

  /// Schedule both daily expense (9 PM) and news (5 slots) tasks.
  Future<void> scheduleAll() async {
    if (!PlatformCapabilities.canUseNotifications) return;
    final expDelay = _TaskScheduler.durationUntilNext9PMIST();
    TLog.i(
      'Notif',
      'Expense recap in ${expDelay.inHours}h ${expDelay.inMinutes % 60}m',
    );
    await Workmanager().registerOneOffTask(
      _kExpenseUniqueId,
      _kExpenseTask,
      initialDelay: expDelay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.not_required),
    );

    final newsDelay = _TaskScheduler.durationUntilNextNewsSlot();
    TLog.i(
      'Notif',
      'News check in ${newsDelay.inHours}h ${newsDelay.inMinutes % 60}m',
    );
    await Workmanager().registerOneOffTask(
      '${_kNewsUniquePrefix}next',
      _kNewsTask,
      initialDelay: newsDelay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.not_required),
    );
  }

  @Deprecated('Use scheduleAll() instead')
  Future<void> scheduleDailyReminder() => scheduleAll();

  Future<void> cancelAll() async {
    if (!PlatformCapabilities.canUseNotifications) return;
    await Workmanager().cancelAll();
    await _fln.cancelAll();
  }

  /// Fire a test notification immediately (debug only).
  Future<void> debugFireNow({bool news = false}) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    TLog.i('Notif', 'DEBUG: firing ${news ? 'news' : 'expense'} notification');
    if (news) {
      final summary = await _NewsDataFetcher.fetchUnreadSummary();
      TLog.i('Notif', 'DEBUG: unread=${summary.unreadCount}');
      await _NotificationUI.showNews(summary, plugin: _fln);
    } else {
      final summary = await _ExpenseDataFetcher.fetchTodaySummary();
      TLog.i('Notif', 'DEBUG: total=${summary.total}, count=${summary.count}');
      await _NotificationUI.showExpense(summary, plugin: _fln);
    }
  }
}
