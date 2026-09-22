import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide ProcessTextService;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../core/auth/auth_service.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/services/expense_widget_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/notification_tap.dart';
import '../../core/services/process_text_service.dart';
import '../../core/services/telegram_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_elevation.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/reduced_motion.dart';
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
          children: [
            for (var i = 0; i < _screens.length; i++)
              TickerMode(
                enabled: currentTab == i,
                child: _screens[i],
              ),
          ],
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
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: AppMotion.emphasizedEnter,
    );
    _slide = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _anim, curve: AppMotion.emphasizedDecelerate),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _anim, curve: AppMotion.standardDecelerate),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled) return;
    _settled = true;
    // Reduced motion lands the panel already in place — no slide, no fade-in.
    if (reducedMotion(context)) {
      _anim.value = 1;
    } else {
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final text = Theme.of(context).textTheme;
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
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.cardGradientTop, colors.cardGradientBottom],
          ),
          borderRadius: AppRadii.brSheet,
          border: Border.all(color: colors.border, width: 1),
          boxShadow: AppElevation.high(colors),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSpacing.gapMd,
            _Grabber(colors: colors),
            AppSpacing.gapLg,
            Padding(
              padding: AppSpacing.pageH,
              child: Text(
                'What would you like to do?',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
            ),
            AppSpacing.gapS,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '"$preview"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
                  color: colors.text3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            AppSpacing.gapXl,
            Padding(
              padding: AppSpacing.pageH,
              child: Row(
                children: [
                  Expanded(
                    child: _ChooserOption(
                      emoji: '📖',
                      label: 'Dictionary',
                      sublabel: 'Look up meaning',
                      color: AppColors.categoryTransport,
                      colors: colors,
                      onTap: () => Navigator.of(context).pop('dictionary'),
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: _ChooserOption(
                      emoji: '✨',
                      label: 'Rephrase',
                      sublabel: 'Rewrite text',
                      color: AppColors.deepViolet,
                      colors: colors,
                      onTap: () => Navigator.of(context).pop('rephrase'),
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: _ChooserOption(
                      emoji: '🔍',
                      label: 'Search',
                      sublabel: 'Search the web',
                      color: AppColors.successGreen,
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

/// Shared sheet grabber.
class _Grabber extends StatelessWidget {
  const _Grabber({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: colors.text5,
        borderRadius: AppRadii.brPill,
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
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.brCard,
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: AppRadii.brCard,
            border: Border.all(
              color: color.withValues(alpha: 0.22),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              // Halo behind the glyph so the three options read as a set of
              // tokens rather than three loose emoji.
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.24)),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
              AppSpacing.gapSm,
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall,
              ),
              AppSpacing.gapXxs,
              Text(
                sublabel,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(color: colors.text3),
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
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: AppMotion.emphasizedEnter,
    );
    _slide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _anim, curve: AppMotion.emphasizedDecelerate),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _anim, curve: AppMotion.standardDecelerate),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled) return;
    _settled = true;
    // Reduced motion lands the panel already in place, and the per-option
    // stagger below collapses with it.
    if (reducedMotion(context)) {
      _anim.value = 1;
    } else {
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final text = Theme.of(context).textTheme;
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
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[c.cardGradientTop, c.cardGradientBottom],
          ),
          borderRadius: AppRadii.brSheet,
          border: Border.all(color: c.border),
          boxShadow: AppElevation.high(c),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSpacing.gapMd,
            _Grabber(colors: c),
            AppSpacing.gapLg,
            Text('Send to…', style: text.titleLarge),
            AppSpacing.gapS,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '"$preview"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
                  color: c.text3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            AppSpacing.gapXl,
            if (widget.hasWatch)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Material(
                  color: c.warning.withValues(alpha: 0.14),
                  borderRadius: AppRadii.brCard,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop('watch'),
                    borderRadius: AppRadii.brCard,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.local_offer_outlined, color: c.warning),
                          AppSpacing.hGapMd,
                          Expanded(
                            child: Text(
                              'Watch this price',
                              style: text.titleSmall,
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
                    color: AppColors.categoryFood,
                    colors: c,
                    delay: 0,
                    parentAnim: _anim,
                    onTap: () => Navigator.of(context).pop('expense'),
                  ),
                  AppSpacing.hGapSm,
                  _ShareOption(
                    icon: Icons.link_rounded,
                    label: 'Summarize',
                    sublabel: 'URL summary',
                    color: AppColors.categoryTransport,
                    colors: c,
                    delay: 1,
                    parentAnim: _anim,
                    onTap: () => Navigator.of(context).pop('summarizer'),
                  ),
                  AppSpacing.hGapSm,
                  _ShareOption(
                    icon: Icons.menu_book_rounded,
                    label: 'Dictionary',
                    sublabel: 'Look up',
                    color: AppColors.categoryGrocery,
                    colors: c,
                    delay: 2,
                    parentAnim: _anim,
                    enabled: widget.text != null,
                    onTap: () => Navigator.of(context).pop('dictionary'),
                  ),
                  AppSpacing.hGapSm,
                  _ShareOption(
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Rephrase',
                    sublabel: 'Rewrite',
                    color: AppColors.deepViolet,
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
    final text = Theme.of(context).textTheme;
    final alpha = widget.enabled ? 1.0 : 0.35;
    final still = reducedMotion(context);

    final tile = GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _scale = 0.92) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _scale = 1.0);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: still ? 1.0 : _scale,
        duration: still ? Duration.zero : AppMotion.microPress,
        curve: AppMotion.standard,
        child: Opacity(
          opacity: alpha,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.08),
              borderRadius: AppRadii.brCard,
              border: Border.all(color: widget.color.withValues(alpha: 0.20)),
            ),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: <Color>[
                        widget.color.withValues(alpha: 0.26),
                        widget.color.withValues(alpha: 0.10),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(widget.icon, size: 20, color: widget.color),
                ),
                AppSpacing.gapSm,
                // Four columns share the width, so "Dictionary" and
                // "Summarize" are already at the edge at 100% text scale.
                // Wrapping to a second line beats ellipsising the word away
                // the moment the user bumps the system font size.
                Text(
                  widget.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  widget.sublabel,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  // text4, not text5 — this is readable copy.
                  style: text.labelSmall?.copyWith(color: c.text4),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Reduced motion keeps the same layout and option order; the staggered
    // rise collapses to the panel's own cross-fade.
    if (still) return Expanded(child: tile);

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
        child: tile,
      ),
    );
  }
}
