import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide ProcessTextService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:async';

import '../../core/auth/auth_service.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/services/expense_widget_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/notification_tap.dart';
import '../../core/services/process_text_service.dart';
import '../../core/services/telegram_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/tidy_url.dart';
import '../../core/utils/time_greeting.dart';
import '../../data/services/price_watch/store_url.dart';
import '../../data/services/sms_auto_expense/sms_auto_expense_service.dart';
import '../screens/expense/expense_screen.dart';
import '../screens/news/news_controller.dart';
import '../screens/news/news_screen.dart';
import '../screens/tutor/dictionary_lookup_screen.dart';
import '../screens/tutor/rephrase_lookup_screen.dart';
import '../screens/tutor/search_lookup_screen.dart';
import '../screens/tutor/tutor_screen.dart';
import '../screens/cloud/cloud_screen.dart';
import '../screens/watch/watch_providers.dart';
import 'bottom_nav.dart';

final currentTabProvider = StateProvider<int>((ref) => 0);
final pendingSubtabProvider = StateProvider<int?>((ref) => null);
final pendingWidgetLaunchProvider = StateProvider<bool>((ref) => false);

/// Pure, side-effect-free description of where a shortcut/widget tap should
/// navigate. Kept separate from [_AppShellState] so the routing decision is
/// fully unit-testable without pumping the whole shell.
@immutable
class ShortcutRoute {
  const ShortcutRoute({
    required this.tab,
    this.subtab,
    this.openExpenseSearch = false,
    this.openExpenseAdd = false,
    this.focusWebSearch = false,
  });

  /// Bottom-nav tab index (0..3).
  final int tab;

  /// Optional Tutor sub-tab index to switch to.
  final int? subtab;

  /// Open the Expense Tracker "Ask AI" search (search widget, Expense mode).
  final bool openExpenseSearch;

  /// Open the Expense Tracker "Add expense" sheet (Expense widget "Add" pill).
  final bool openExpenseAdd;

  /// Focus the Tutor online-search field (search widget Web mode / legacy
  /// search widget).
  final bool focusWebSearch;
}

/// Resolves raw shortcut extras (forwarded from the native side) into a
/// [ShortcutRoute]. Returns `null` when the payload is missing/invalid so the
/// caller can safely ignore it.
///
/// Precedence: the search widget's `widget_search_mode == 'expense'` always
/// wins over the legacy `widget_launch` flag, so Expense mode never also
/// triggers the web-search focus.
ShortcutRoute? resolveShortcutRoute(Map<String, String> data) {
  final tabStr = data['tab'];
  if (tabStr == null || tabStr.isEmpty) return null;

  final tab = int.tryParse(tabStr);
  if (tab == null || tab < 0 || tab > 3) return null;

  final subtab = int.tryParse(data['subtab'] ?? '');
  final isWidgetLaunch = data['widget_launch'] == 'true';
  final openExpenseSearch = data['widget_search_mode'] == 'expense';
  final openExpenseAdd = data['expense_action'] == 'add';

  return ShortcutRoute(
    tab: tab,
    subtab: subtab,
    openExpenseSearch: openExpenseSearch,
    openExpenseAdd: openExpenseAdd,
    focusWebSearch: !openExpenseSearch && !openExpenseAdd && isWidgetLaunch,
  );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _screens = <Widget>[
    ExpenseScreen(),
    NewsScreen(),
    TutorScreen(),
    CloudScreen(),
  ];

  bool _chooserVisible = false;
  static const _shortcutChannel =
      MethodChannel('app.ainexus.ai_nexus/shortcuts');
  StreamSubscription<String>? _notifSub;
  Timer? _clockTick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Kick News bootstrap while the user is still on Expenses so the
      // feed is already painted (and an RSS refresh is in flight) by the
      // time they tap the News tab.
      ref.read(newsControllerProvider);
    });

    // ProcessTextService.initialize already no-ops on web (kIsWeb guard
    // inside the service); keeping the call here unconditional preserves
    // identical Android behaviour.
    ProcessTextService.initialize(
      onTextReceived: _onIncomingText,
      onSharedReceived: _onSharedContent,
      onSharedImageReceived: _onSharedImage,
    );

    if (PlatformCapabilities.canUseShortcuts) {
      _shortcutChannel.setMethodCallHandler((call) async {
        if (call.method == 'onShortcut') {
          try {
            final args = Map<String, String>.from(call.arguments as Map);
            TLog.i('Shortcut', 'Received via push: $args');
            _handleShortcut(args);
          } catch (e) {
            TLog.e('Shortcut', 'Failed to parse onShortcut args', error: e);
          }
        }
      });
    }

    _notifSub = notificationPayloadStream.stream.listen(_applyNotificationPayload);
    _scheduleClockTick();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForProcessedText();
      _checkForSharedText();
      _checkForShortcut();
      final queued = takeQueuedNotificationRoute();
      if (queued != null) _applyNotificationPayload(queued);
    });
  }

  void _applyNotificationPayload(String payload) {
    if (payload == kNotifPayloadExpenseAdd) {
      ref.read(currentTabProvider.notifier).state = 0;
      ref.read(pendingExpenseAddProvider.notifier).state = true;
      return;
    }
    if (payload == kNotifPayloadExpenseTab) {
      ref.read(currentTabProvider.notifier).state = 0;
      return;
    }
    if (payload == kNotifPayloadNewsTab || payload == 'news_summary') {
      ref.read(currentTabProvider.notifier).state = 1;
      return;
    }
    if (payload == kNotifPayloadTutorTab) {
      ref.read(currentTabProvider.notifier).state = 2;
      return;
    }
    if (payload.startsWith('watch:')) {
      final id = payload.substring('watch:'.length);
      if (!mounted) return;
      openWatch(context, ref, productId: id);
    }
  }

  Future<void> _checkForShortcut() async {
    if (!PlatformCapabilities.canUseShortcuts) return;
    try {
      final result = await _shortcutChannel.invokeMethod('getShortcutAction');
      if (!mounted) return;
      if (result != null && result is Map) {
        final data = <String, String>{};
        for (final entry in result.entries) {
          data[entry.key.toString()] = entry.value.toString();
        }
        TLog.i('Shortcut', 'Received via pull: $data');
        _handleShortcut(data);
      }
    } catch (e) {
      TLog.w('Shortcut', 'getShortcutAction failed', error: e);
    }
  }

  void _handleShortcut(Map<String, String> data) {
    try {
      final route = resolveShortcutRoute(data);
      if (route == null) {
        TLog.w('Shortcut', 'Ignored invalid shortcut data: $data');
        return;
      }

      TLog.i(
        'Shortcut',
        'Navigating → tab=${route.tab}, subtab=${route.subtab}, '
            'expenseSearch=${route.openExpenseSearch}, '
            'webSearch=${route.focusWebSearch}',
      );
      ref.read(currentTabProvider.notifier).state = route.tab;

      final subtab = route.subtab;
      if (subtab != null) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          activeTutorSubtabSwitcher?.call(subtab);
        });
      }

      if (route.openExpenseAdd) {
        // Expense widget "Add" pill → open the Add-expense sheet.
        TLog.i('Widget', 'Expense widget (Add) tap → opening Add expense');
        ref.read(pendingExpenseAddProvider.notifier).state = true;
      } else if (route.openExpenseSearch) {
        // Search widget, Expense mode → open the Expense Tracker "Ask AI" search.
        TLog.i('Widget', 'Search widget (Expense) tap → opening Ask AI');
        ref.read(pendingExpenseSearchProvider.notifier).state = true;
      } else if (route.focusWebSearch) {
        // Search widget, Web mode (or legacy widget) → focus the online search.
        TLog.i('Widget', 'Search widget (Web) tap → opening Summarizer');
        ref.read(pendingWidgetLaunchProvider.notifier).state = true;
      }
    } catch (e) {
      TLog.e('Shortcut', 'Failed to handle shortcut data: $data', error: e);
    }
  }

  @override
  void dispose() {
    _clockTick?.cancel();
    _notifSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleClockTick() {
    _clockTick?.cancel();
    final now = DateTime.now();
    final next = nextUiClockTick(now);
    final wait = next.difference(now) + const Duration(seconds: 1);
    _clockTick = Timer(wait, () {
      _bumpClockDay();
      _scheduleClockTick();
    });
  }

  void _bumpClockDay() {
    if (!mounted) return;
    ref.read(clockDayEpochProvider.notifier).state++;
    unawaited(ExpenseWidgetService.instance.refreshOnAppStart());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AuthService.instance.checkSessionValidity();
      _checkForProcessedText();
      _checkForSharedText();
      _checkForShortcut();
      unawaited(ref.read(smsAutoExpenseProvider.notifier).drainOnResume());
      unawaited(ref.read(newsControllerProvider.notifier).ensureFresh(force: true));
      _bumpClockDay();
      _scheduleClockTick();
    }
  }

  Future<void> _checkForProcessedText() async {
    final text = await ProcessTextService.getProcessedText();
    if (text != null && text.isNotEmpty) {
      _onIncomingText(text);
    }
  }

  Future<void> _checkForSharedText() async {
    final imagePath = await ProcessTextService.getSharedImagePath();
    if (imagePath != null && imagePath.isNotEmpty) {
      _onSharedImage(imagePath);
      return;
    }
    final text = await ProcessTextService.getSharedText();
    if (text != null && text.isNotEmpty) {
      _onSharedContent(text);
    }
  }

  void _onIncomingText(String text) {
    if (_chooserVisible) return;
    _showFeatureChooser(text);
  }

  void _onSharedContent(String text) {
    if (_chooserVisible) return;
    _showShareChooser(text: text);
  }

  void _onSharedImage(String imagePath) {
    if (_chooserVisible) return;
    _showShareChooser(imagePath: imagePath);
  }

  void _showShareChooser({String? text, String? imagePath}) {
    _chooserVisible = true;
    final colors = Theme.of(context).extension<AppColors>()!;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final hasUrl = text != null && TidyUrl.extractSharedUrl(text) != null;
    final hasWatch = text != null && isWatchShareCandidate(text);

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ShareChooser(
        text: text,
        hasImage: hasImage,
        hasUrl: hasUrl,
        hasWatch: hasWatch,
        colors: colors,
      ),
    ).then((feature) {
      _chooserVisible = false;
      if (feature == null || !mounted) return;

      switch (feature) {
        case 'watch':
          final url = text != null ? (extractHttpUrl(text) ?? text) : '';
          openWatch(context, ref, seedUrl: url);
        case 'expense':
          ref.read(currentTabProvider.notifier).state = 0;
          if (hasImage) {
            ref.read(pendingExpenseImageProvider.notifier).state = imagePath;
          } else if (text != null && text.trim().isNotEmpty) {
            // Shared text (e.g. a bank transaction SMS) → feed it through the
            // same smart-parse pipeline the bill scanner uses to auto-fill the
            // add-expense form.
            ref.read(pendingExpenseTextProvider.notifier).state = text;
          }
        case 'summarizer':
          final url = text != null ? TidyUrl.normalizeForSummarize(text) : '';
          if (url.isEmpty) return;
          ref.read(currentTabProvider.notifier).state = 2;
          Future.delayed(const Duration(milliseconds: 200), () {
            activeTutorSubtabSwitcher?.call(0);
            ref.read(pendingSummarizerUrlProvider.notifier).state = url;
          });
        case 'dictionary':
          if (text != null && mounted) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DictionaryLookupScreen(word: text),
              ),
            );
          }
        case 'rephrase':
          if (text != null && mounted) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => RephraseLookupScreen(text: text),
              ),
            );
          }
      }
    });
  }

  void _showFeatureChooser(String text) {
    _chooserVisible = true;
    final colors = Theme.of(context).extension<AppColors>()!;

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ProcessTextChooser(
        text: text,
        colors: colors,
      ),
    ).then((feature) {
      _chooserVisible = false;
      if (feature == null || !context.mounted) return;

      switch (feature) {
        case 'rephrase':
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => RephraseLookupScreen(text: text),
            ),
          );
        case 'search':
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => SearchLookupScreen(query: text),
            ),
          );
        default:
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => DictionaryLookupScreen(word: text),
            ),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentTabProvider);

    // Always-on bridge: keep the home-screen Expense widget in sync with the
    // local DB from ANY tab — including changes pulled in by cross-device sync
    // (an expense added/cleared on another phone or the web app). ExpenseScreen
    // also pushes updates while it's mounted, but these listeners make the
    // behaviour explicit and resilient to future navigation changes. Downstream
    // scheduleUpdate is debounced + skips when the data hash is unchanged, so
    // the duplicate path costs nothing. No-ops on platforms without the widget.
    ref.listen(expensesStreamProvider, (_, next) {
      final expenses = next.valueOrNull;
      if (expenses == null) return;
      ExpenseWidgetService.instance.scheduleUpdate(
        expenses: expenses,
        monthBudget: ref.read(currentBudgetProvider),
      );
    });
    ref.listen(smsOpenExpenseTabTickProvider, (prev, next) {
      if (prev == next) return;
      ref.read(currentTabProvider.notifier).state = 0;
    });
    ref.listen(currentBudgetProvider, (_, budget) {
      final expenses = ref.read(expensesStreamProvider).valueOrNull;
      if (expenses == null) return;
      ExpenseWidgetService.instance.scheduleUpdate(
        expenses: expenses,
        monthBudget: budget,
      );
    });
    ref.listen(clockDayEpochProvider, (_, __) {
      final expenses = ref.read(expensesStreamProvider).valueOrNull;
      if (expenses == null) return;
      ExpenseWidgetService.instance.scheduleUpdate(
        expenses: expenses,
        monthBudget: ref.read(currentBudgetProvider),
      );
    });
    ref.listen(currentTabProvider, (prev, next) {
      if (next != 1) return;
      unawaited(ref.read(newsControllerProvider.notifier).ensureFresh(force: true));
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: currentTab,
          children: _screens,
        ),
      ),
      bottomNavigationBar: BottomNav(
        currentIndex: currentTab,
        onTap: (i) => ref.read(currentTabProvider.notifier).state = i,
      ),
    );
  }
}

// ── Chooser bottom sheet ──────────────────────────────────────────────────────

class _ProcessTextChooser extends StatefulWidget {
  const _ProcessTextChooser({required this.text, required this.colors});

  final String text;
  final AppColors colors;

  @override
  State<_ProcessTextChooser> createState() => _ProcessTextChooserState();
}

class _ProcessTextChooserState extends State<_ProcessTextChooser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slide = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final preview = widget.text.length > 60
        ? '${widget.text.substring(0, 60)}...'
        : widget.text;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slide.value),
        child: Opacity(opacity: _fade.value, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: colors.shadowColor,
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.text5,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'What would you like to do?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '"$preview"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.text3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ChooserOption(
                      emoji: '📖',
                      label: 'Dictionary',
                      sublabel: 'Look up meaning',
                      color: const Color(0xFF339AF0),
                      colors: colors,
                      onTap: () => Navigator.of(context).pop('dictionary'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ChooserOption(
                      emoji: '✨',
                      label: 'Rephrase',
                      sublabel: 'Rewrite text',
                      color: const Color(0xFFC084FC),
                      colors: colors,
                      onTap: () => Navigator.of(context).pop('rephrase'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ChooserOption(
                      emoji: '🔍',
                      label: 'Search',
                      sublabel: 'Search the web',
                      color: const Color(0xFF34D399),
                      colors: colors,
                      onTap: () => Navigator.of(context).pop('search'),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _ChooserOption extends StatelessWidget {
  const _ChooserOption({
    required this.emoji,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.colors,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final String sublabel;
  final Color color;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Share chooser (from ACTION_SEND) ──────────────────────────────────────────

class _ShareChooser extends StatefulWidget {
  const _ShareChooser({
    this.text,
    required this.hasImage,
    required this.hasUrl,
    required this.hasWatch,
    required this.colors,
  });

  final String? text;
  final bool hasImage;
  final bool hasUrl;
  final bool hasWatch;
  final AppColors colors;

  @override
  State<_ShareChooser> createState() => _ShareChooserState();
}

class _ShareChooserState extends State<_ShareChooser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final preview = widget.text != null
        ? (widget.text!.length > 50
            ? '${widget.text!.substring(0, 50)}…'
            : widget.text!)
        : 'Image shared';

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slide.value),
        child: Opacity(opacity: _fade.value, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: c.bg1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: c.shadowColor,
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.text5,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Send to…',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: c.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '"$preview"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: c.text4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (widget.hasWatch)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Material(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop('watch'),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_offer_outlined,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Watch this price',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: c.text,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: c.text3),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _ShareOption(
                    icon: Icons.receipt_long_rounded,
                    label: 'Expense',
                    sublabel: 'Scan receipt',
                    color: const Color(0xFFFF6B6B),
                    colors: c,
                    delay: 0,
                    parentAnim: _anim,
                    onTap: () => Navigator.of(context).pop('expense'),
                  ),
                  const SizedBox(width: 8),
                  _ShareOption(
                    icon: Icons.link_rounded,
                    label: 'Summarize',
                    sublabel: 'URL summary',
                    color: const Color(0xFF339AF0),
                    colors: c,
                    delay: 1,
                    parentAnim: _anim,
                    onTap: () => Navigator.of(context).pop('summarizer'),
                  ),
                  const SizedBox(width: 8),
                  _ShareOption(
                    icon: Icons.menu_book_rounded,
                    label: 'Dictionary',
                    sublabel: 'Look up',
                    color: const Color(0xFF51CF66),
                    colors: c,
                    delay: 2,
                    parentAnim: _anim,
                    enabled: widget.text != null,
                    onTap: () => Navigator.of(context).pop('dictionary'),
                  ),
                  const SizedBox(width: 8),
                  _ShareOption(
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Rephrase',
                    sublabel: 'Rewrite',
                    color: const Color(0xFFC084FC),
                    colors: c,
                    delay: 3,
                    parentAnim: _anim,
                    enabled: widget.text != null,
                    onTap: () => Navigator.of(context).pop('rephrase'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _ShareOption extends StatefulWidget {
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.colors,
    required this.delay,
    required this.parentAnim,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final AppColors colors;
  final int delay;
  final Animation<double> parentAnim;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_ShareOption> createState() => _ShareOptionState();
}

class _ShareOptionState extends State<_ShareOption>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  late final Animation<double> _stagger;

  @override
  void initState() {
    super.initState();
    final start = (widget.delay * 0.12).clamp(0.0, 0.7);
    _stagger = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: widget.parentAnim,
        curve: Interval(start, 1.0, curve: Curves.easeOutBack),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final alpha = widget.enabled ? 1.0 : 0.35;

    return Expanded(
      child: AnimatedBuilder(
        animation: _stagger,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 20 * (1 - _stagger.value)),
          child: Opacity(
            opacity: _stagger.value.clamp(0.0, 1.0),
            child: child,
          ),
        ),
        child: GestureDetector(
          onTapDown:
              widget.enabled ? (_) => setState(() => _scale = 0.92) : null,
          onTapUp: widget.enabled
              ? (_) {
                  setState(() => _scale = 1.0);
                  widget.onTap();
                }
              : null,
          onTapCancel: () => setState(() => _scale = 1.0),
          child: AnimatedScale(
            scale: _scale,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: Opacity(
              opacity: alpha,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(widget.icon, size: 20, color: widget.color),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.sublabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9.5,
                        color: c.text4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
