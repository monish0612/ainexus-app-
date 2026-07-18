import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/expense_entities.dart';
import '../platform/platform_capabilities.dart';
import '../theme/app_colors.dart';
import 'telegram_logger.dart';

/// Pure, immutable snapshot of everything the native Expense widget renders.
/// Computed by [ExpenseWidgetService.computeWidgetData] so the aggregation can
/// be unit-tested without SharedPreferences or a MethodChannel.
@immutable
class ExpenseWidgetData {
  const ExpenseWidgetData({
    required this.todayTotal,
    required this.todayCount,
    required this.monthSpent,
    required this.monthCount,
    required this.topCatName,
    required this.topCatEmoji,
    required this.topCatAmount,
    required this.topCatColor,
  });

  final double todayTotal;
  final int todayCount;
  final double monthSpent;
  final int monthCount;
  final String topCatName;
  final String topCatEmoji;
  final double topCatAmount;
  final String topCatColor;
}

/// Writes today's expense summary to SharedPreferences so the native
/// Android ExpenseWidgetProvider can read it, then triggers a widget refresh.
///
/// Data freshness is guaranteed by:
///   1. A date stamp (`expense_widget_update_date`) stored alongside the data —
///      the native side zeros out today's totals if the stamp is stale.
///   2. A native AlarmManager fires at midnight to force a widget redraw.
///   3. [refreshOnAppStart] is called during app init so the widget gets
///      fresh data even if the user hasn't opened the expense tab yet.
///
/// Retry strategy: [_triggerNativeRefreshWithRetry] tries up to 3 times with
/// exponential backoff (500ms → 1s → 2s). This covers the startup race where
/// the MethodChannel may not be ready yet.
class ExpenseWidgetService {
  ExpenseWidgetService._();
  static final instance = ExpenseWidgetService._();

  static const _channel = MethodChannel('app.ainexus.ai_nexus/expense_widget');
  static const _maxRetries = 3;

  int _lastHash = 0;
  Timer? _debounce;

  /// Call whenever expenses or budget change.
  /// Debounces rapid calls (300ms) and skips if data hasn't changed.
  void scheduleUpdate({
    required List<Expense> expenses,
    required double monthBudget,
  }) {
    if (!PlatformCapabilities.canUseExpenseWidget) return;
    double amountSum = 0;
    for (final e in expenses) {
      amountSum += e.amount;
    }
    final hash = Object.hash(expenses.length, monthBudget, amountSum);
    if (hash == _lastHash) return;
    _lastHash = hash;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _doUpdate(expenses: expenses, monthBudget: monthBudget);
    });
  }

  /// Lightweight startup call: if the stored date is stale, immediately
  /// write zeros for today and trigger a native refresh so the widget
  /// doesn't show yesterday's data while the expense stream loads.
  Future<void> refreshOnAppStart() async {
    if (!PlatformCapabilities.canUseExpenseWidget) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedDate = prefs.getString('expense_widget_update_date') ?? '';
      final today = _todayDateString();

      if (storedDate == today) {
        _triggerNativeRefreshWithRetry('startup-fresh');
        TLog.d('ExpWidget', 'Startup: date fresh, triggered refresh');
        return;
      }

      final storedMonth = storedDate.length >= 7
          ? storedDate.substring(0, 7)
          : '';
      final currentMonth = today.substring(0, 7);
      final isMonthStale = storedMonth != currentMonth;

      final writes = <Future<bool>>[
        prefs.setString('expense_widget_today_total', '0.00'),
        prefs.setInt('expense_widget_today_count', 0),
        prefs.setString('expense_widget_update_date', today),
      ];

      if (isMonthStale) {
        // Month rolled over — clear every month-scoped metric so the widget
        // never shows last month's spend/top-category before the stream reloads.
        writes
          ..add(prefs.setString('expense_widget_month_spent', '0.00'))
          ..add(prefs.setInt('expense_widget_month_count', 0))
          ..add(prefs.setString('expense_widget_top_cat_name', ''))
          ..add(prefs.setString('expense_widget_top_cat_emoji', ''))
          ..add(prefs.setString('expense_widget_top_cat_amount', '0.00'))
          ..add(prefs.setString('expense_widget_top_cat_color', ''));
      }

      await Future.wait(writes);
      _triggerNativeRefreshWithRetry('startup-stale');

      if (isMonthStale) {
        TLog.i('ExpWidget',
            'Startup: month boundary ($storedMonth→$currentMonth), zeroed today + month');
      } else {
        TLog.i('ExpWidget',
            'Startup: date stale ($storedDate→$today), zeroed today');
      }
    } catch (e, st) {
      TLog.e('ExpWidget', 'refreshOnAppStart failed', error: e, st: st);
    }
  }

  /// Pure aggregation of [expenses] into the widget snapshot, as of [now].
  ///
  /// Rules (mirror the in-app expense totals):
  ///  - Investments are excluded from every total (wealth-building, not spend).
  ///  - Rows with an unparseable [Expense.date] are skipped.
  ///  - "Today" is `[todayStart, tomorrowStart)`; "month" is `>= monthStart`.
  ///  - The top category is the single biggest month spend; ties keep the first
  ///    seen at the winning amount (a later equal amount does not replace it).
  ///  - A blank category is bucketed as `Others`.
  @visibleForTesting
  static ExpenseWidgetData computeWidgetData({
    required List<Expense> expenses,
    required DateTime now,
  }) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final monthStart = DateTime(now.year, now.month, 1);

    double todayTotal = 0;
    int todayCount = 0;
    double monthSpent = 0;
    int monthCount = 0;
    final monthByCategory = <String, double>{};

    for (final e in expenses) {
      if (isNonSpendCategory(e.category)) continue;
      final d = DateTime.tryParse(e.date);
      if (d == null) continue;

      if (!d.isBefore(monthStart)) {
        monthSpent += e.amount;
        monthCount++;
        final cat = e.category.trim().isEmpty ? 'Others' : e.category.trim();
        monthByCategory[cat] = (monthByCategory[cat] ?? 0) + e.amount;
      }
      if (!d.isBefore(todayStart) && d.isBefore(tomorrowStart)) {
        todayTotal += e.amount;
        todayCount++;
      }
    }

    String topCatName = '';
    double topCatAmount = 0;
    monthByCategory.forEach((cat, amount) {
      if (amount > topCatAmount) {
        topCatAmount = amount;
        topCatName = cat;
      }
    });
    final topCatEmoji = topCatName.isEmpty
        ? ''
        : (AppColors.categoryIcons[topCatName] ?? '📦');
    final topCatColor = topCatName.isEmpty
        ? ''
        : _hex(AppColors.categoryColors[topCatName] ?? AppColors.categoryOthers);

    return ExpenseWidgetData(
      todayTotal: todayTotal,
      todayCount: todayCount,
      monthSpent: monthSpent,
      monthCount: monthCount,
      topCatName: topCatName,
      topCatEmoji: topCatEmoji,
      topCatAmount: topCatAmount,
      topCatColor: topCatColor,
    );
  }

  Future<void> _doUpdate({
    required List<Expense> expenses,
    required double monthBudget,
  }) async {
    try {
      final data = computeWidgetData(expenses: expenses, now: DateTime.now());

      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString('expense_widget_today_total', data.todayTotal.toStringAsFixed(2)),
        prefs.setInt('expense_widget_today_count', data.todayCount),
        prefs.setString('expense_widget_month_budget', monthBudget.toStringAsFixed(2)),
        prefs.setString('expense_widget_month_spent', data.monthSpent.toStringAsFixed(2)),
        prefs.setInt('expense_widget_month_count', data.monthCount),
        prefs.setString('expense_widget_top_cat_name', data.topCatName),
        prefs.setString('expense_widget_top_cat_emoji', data.topCatEmoji),
        prefs.setString('expense_widget_top_cat_amount', data.topCatAmount.toStringAsFixed(2)),
        prefs.setString('expense_widget_top_cat_color', data.topCatColor),
        prefs.setString('expense_widget_update_date', _todayDateString()),
      ]);

      _triggerNativeRefreshWithRetry('update');
      TLog.i('ExpWidget',
          'Widget synced: today=₹${data.todayTotal} (${data.todayCount}), budget=₹$monthBudget, month=₹${data.monthSpent} (${data.monthCount}), top=${data.topCatName} ₹${data.topCatAmount}');
    } catch (e, st) {
      TLog.e('ExpWidget', 'Failed to update expense widget data', error: e, st: st);
    }
  }

  /// Retry up to [_maxRetries] times with exponential backoff.
  /// Covers the startup race where the MethodChannel may not be wired yet.
  void _triggerNativeRefreshWithRetry(String reason, [int attempt = 1]) {
    if (!PlatformCapabilities.canUseExpenseWidget) return;
    _channel.invokeMethod<void>('updateExpenseWidget').then((_) {
      if (attempt > 1) {
        TLog.i('ExpWidget', 'Native refresh succeeded on attempt $attempt ($reason)');
      }
    }).catchError((Object e) {
      if (attempt < _maxRetries) {
        final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
        TLog.w('ExpWidget',
            'Native refresh attempt $attempt/$_maxRetries failed ($reason), retry in ${delay.inMilliseconds}ms',
            error: e);
        Timer(delay, () => _triggerNativeRefreshWithRetry(reason, attempt + 1));
      } else {
        TLog.e('ExpWidget',
            'Native refresh failed after $_maxRetries attempts ($reason)',
            error: e);
      }
    });
  }

  static String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// `#RRGGBB` for the native side to tint the top-category accent.
  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}
