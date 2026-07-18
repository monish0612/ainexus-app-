import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/expense_insight_engine.dart';
import '../../../core/services/insight_grounding.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/expense_repository.dart';
import '../../../domain/entities/expense_entities.dart';
import '../../../domain/entities/expense_insight.dart';
import '../settings/settings_controller.dart';
import 'modals/edit_expense_modal.dart';
import 'modals/expense_ai_ask_sheet.dart';
import 'widgets/ai_recommendation_card.dart';
import 'widgets/expense_item.dart';

/// Identifies a slice of spending history opened from the Tracker's
/// "Spending Analysis" section. [startIso] is an inclusive lower bound on the
/// expense `date`; `null` means "All" (no lower bound). [endIso] is an
/// exclusive upper bound; usually `null`.
class ExpenseTimeframe {
  const ExpenseTimeframe({
    required this.label,
    required this.startIso,
    this.endIso,
    this.subtitle,
    this.seedSearch,
    this.seedSearchTerms = const [],
    this.seedCategory,
    this.sort = ExpenseSort.dateDesc,
    this.aiAnswer,
    this.chart = ExpenseChart.none,
    this.aiInsight = false,
    this.aiQuestion,
  });

  final String label;
  final String? startIso;
  final String? endIso;
  final String? subtitle;

  /// Pre-filled, editable free-text filter (used by AI search).
  final String? seedSearch;

  /// Semantic OR-group terms from AI query expansion (e.g. "anything related to
  /// my car" → car/fuel/garage/…). Applied as a base filter; shown as chips.
  final List<String> seedSearchTerms;

  /// Pre-selected category filter (used by AI search).
  final String? seedCategory;

  /// Row ordering — AI queries like "highest expense" use [ExpenseSort.amountDesc].
  final ExpenseSort sort;

  /// Friendly one-line answer from the AI, shown as a banner above the summary.
  final String? aiAnswer;

  /// Optional visualization to render above the (still editable) list.
  final ExpenseChart chart;

  /// When true the screen computes a generative, grounded AI recommendation
  /// (greeting by name + saving tip + chips) above the summary. Set by the
  /// "Ask AI" flow; fixed-timeframe drilldowns leave it false (no extra LLM
  /// call, unchanged behavior).
  final bool aiInsight;

  /// The user's original natural-language question, passed to the composer so
  /// the recommendation matches their intent. Falls back to [label].
  final String? aiQuestion;
}

/// Opens the full-screen timeframe drill-down with a slide-up transition over
/// the whole app (root navigator), so the bottom nav is hidden for a focused
/// editing experience.
Future<void> showExpenseTimeframeScreen(
  BuildContext context,
  ExpenseTimeframe timeframe,
) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => ExpenseTimeframeScreen(timeframe: timeframe),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class ExpenseTimeframeScreen extends ConsumerStatefulWidget {
  const ExpenseTimeframeScreen({super.key, required this.timeframe});

  final ExpenseTimeframe timeframe;

  @override
  ConsumerState<ExpenseTimeframeScreen> createState() =>
      _ExpenseTimeframeScreenState();
}

class _ExpenseTimeframeScreenState
    extends ConsumerState<ExpenseTimeframeScreen> {
  static const int _pageSize = 40;

  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();

  final List<Expense> _items = [];
  Timer? _searchDebounce;

  String _search = '';
  String? _categoryFilter;

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _hasError = false;
  int _offset = 0;

  int _count = 0;
  double _total = 0;
  List<({String category, double total, int count})> _categories = const [];
  List<ExpenseBucket> _timeBuckets = const [];

  // Generative AI recommendation (only when opened from "Ask AI").
  GroundedRecommendation? _recommendation;
  bool _insightLoading = false;

  @override
  void initState() {
    super.initState();
    // Seed editable filters from the (optional) AI query spec.
    _search = widget.timeframe.seedSearch?.trim() ?? '';
    _searchCtrl.text = _search;
    _categoryFilter = widget.timeframe.seedCategory;
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reset());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _reset() async {
    setState(() {
      _items.clear();
      _offset = 0;
      _hasMore = true;
      _hasError = false;
      _initialLoading = true;
    });
    await Future.wait([_loadSummary(), _loadMore()]);
    if (mounted) setState(() => _initialLoading = false);
    // The summary is now loaded; build the AI recommendation off it (the table
    // is already painting, so the insight "streams in" without blocking).
    if (widget.timeframe.aiInsight) unawaited(_loadInsight());
  }

  /// Computes deterministic facts from the loaded slice + the memory layer,
  /// shows the grounded template instantly, then upgrades to the composed
  /// (LLM-authored) version. Every figure shown is verified — the model only
  /// phrases pre-computed tokens, and ungrounded prose falls back to template.
  Future<void> _loadInsight() async {
    if (!mounted) return;
    setState(() => _insightLoading = true);
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final memory = await repo.memorySnapshot();
      final tf = widget.timeframe;
      final facts = ExpenseInsightEngine.compute(
        question: (tf.aiQuestion?.trim().isNotEmpty ?? false)
            ? tf.aiQuestion!.trim()
            : tf.label,
        firstName: AuthService.instance.username,
        sliceTotal: _total,
        sliceCount: _count,
        sliceCategories: _categories,
        timeBuckets: _timeBuckets,
        memory: memory,
      );

      // Instant, always-grounded fallback so the user never waits on the
      // network for a useful insight.
      if (mounted) {
        setState(() => _recommendation = InsightGrounding.template(facts));
      }

      final liteModel = ref.read(settingsProvider).liteModel;
      final spec = await ref
          .read(expenseInsightServiceProvider)
          .compose(facts, liteModel: liteModel);
      if (!mounted) return;
      setState(() {
        _recommendation = InsightGrounding.ground(spec, facts);
        _insightLoading = false;
      });
    } catch (e) {
      TLog.w('ExpenseTimeframe', 'AI recommendation failed', error: e);
      if (mounted) setState(() => _insightLoading = false);
    }
  }

  void _onInsightChip(String chip) {
    HapticFeedback.selectionClick();
    // A chip is a fresh follow-up question — reopen Ask AI primed with it.
    Navigator.of(context).maybePop().then((_) {
      if (!mounted) return;
      showExpenseAiAskSheet(context, initialQuestion: chip);
    });
  }

  Future<void> _loadSummary() async {
    final repo = ref.read(expenseRepositoryProvider);
    final tf = widget.timeframe;
    // Investments (wealth) and loan repayments (debt) are not spending, so the
    // spending drill-down excludes them — UNLESS the view is explicitly scoped
    // to one of those categories (its dedicated card view), in which case we
    // want to show them.
    final excludeNonSpend = !isNonSpendCategory(_categoryFilter);
    final summary = await repo.rangeSummary(
      startIso: tf.startIso,
      endIso: tf.endIso,
      category: _categoryFilter,
      search: _search,
      searchTerms: tf.seedSearchTerms,
      excludeNonSpend: excludeNonSpend,
    );
    // Category chips reflect the unfiltered-by-category scope so the user can
    // always switch categories; search still narrows them.
    final cats = await repo.categoryBreakdown(
      startIso: tf.startIso,
      endIso: tf.endIso,
      search: _search,
      searchTerms: tf.seedSearchTerms,
      excludeNonSpend: excludeNonSpend,
    );
    // Time-series buckets only when a daily/monthly chart was requested.
    final wantsTime =
        tf.chart == ExpenseChart.daily || tf.chart == ExpenseChart.monthly;
    final buckets = wantsTime
        ? await repo.timeBreakdown(
            monthly: tf.chart == ExpenseChart.monthly,
            startIso: tf.startIso,
            endIso: tf.endIso,
            category: _categoryFilter,
            search: _search,
            searchTerms: tf.seedSearchTerms,
            excludeNonSpend: excludeNonSpend,
          )
        : const <ExpenseBucket>[];
    if (!mounted) return;
    setState(() {
      _count = summary.count;
      _total = summary.total;
      _categories = cats;
      _timeBuckets = buckets;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    final repo = ref.read(expenseRepositoryProvider);
    final tf = widget.timeframe;
    try {
      final page = await repo.getExpensesPage(
        startIso: tf.startIso,
        endIso: tf.endIso,
        category: _categoryFilter,
        search: _search,
        searchTerms: tf.seedSearchTerms,
        sort: tf.sort,
        excludeNonSpend: !isNonSpendCategory(_categoryFilter),
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _pageSize;
        _hasError = false;
      });
    } catch (e) {
      TLog.e('ExpenseTimeframe',
          'Page load failed (${tf.label}, offset=$_offset)', error: e);
      if (mounted) {
        setState(() {
          _hasError = true;
          _hasMore = false;
        });
      }
    } finally {
      _loadingMore = false;
      if (mounted) setState(() {});
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      final next = value.trim();
      if (next == _search) return;
      _search = next;
      _reset();
    });
  }

  void _toggleCategory(String category) {
    HapticFeedback.selectionClick();
    setState(() {
      _categoryFilter = _categoryFilter == category ? null : category;
    });
    _reset();
  }

  // ── Mutations (edit / delete) ──────────────────────────────────────────────

  void _editExpense(Expense e) {
    showEditExpenseModal(
      context,
      expense: e,
      bankConfigs: ref.read(settingsProvider).banks,
      onUpdate: (updated) {
        // 1) Reflect the edit in the list IMMEDIATELY (zero perceived latency).
        if (mounted) {
          final idx = _items.indexWhere((x) => x.id == updated.id);
          final dropsOut =
              _categoryFilter != null && updated.category != _categoryFilter;
          setState(() {
            if (idx >= 0) {
              if (dropsOut) {
                _items.removeAt(idx);
              } else {
                _items[idx] = updated;
              }
            }
          });
        }
        // 2) Persist locally + push to cloud right away (don't block the UI).
        unawaited(_syncUpdate(updated));
      },
    );
  }

  /// Local write + immediate cloud sync (repo handles retry/backoff). Kept off
  /// the UI thread of the edit so the row updates instantly while the sync runs.
  Future<void> _syncUpdate(Expense updated) async {
    final repo = ref.read(expenseRepositoryProvider);
    final sw = Stopwatch()..start();
    try {
      final synced = await repo.updateExpense(updated);
      sw.stop();
      TLog.i('ExpenseTimeframe',
          '✏️ Updated + synced in ${sw.elapsedMilliseconds}ms: ${updated.id}');
      if (!mounted) return;
      unawaited(_loadSummary());
      if (!synced) _toast('Saved locally — sync pending', warn: true);
    } catch (err) {
      sw.stop();
      TLog.e('ExpenseTimeframe', 'Update failed: ${updated.id}', error: err);
      if (mounted) _toast('Could not update expense', warn: true);
    }
  }

  void _showDetail(Expense e) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseDetailSheet(
        expense: e,
        onEdit: () {
          Navigator.of(context).pop();
          _editExpense(e);
        },
        onDelete: () {
          Navigator.of(context).pop();
          _deleteExpense(e);
        },
      ),
    );
  }

  Future<void> _deleteExpense(Expense e) async {
    final idx = _items.indexWhere((x) => x.id == e.id);
    // Optimistic removal for a fluid feel; restored on hard failure.
    if (idx >= 0) setState(() => _items.removeAt(idx));
    final repo = ref.read(expenseRepositoryProvider);
    final sw = Stopwatch()..start();
    try {
      final synced = await repo.deleteExpense(e.id);
      sw.stop();
      TLog.i('ExpenseTimeframe',
          '🗑️ Deleted in ${sw.elapsedMilliseconds}ms: ${e.id}');
      unawaited(_loadSummary());
      if (!synced && mounted) _toast('Deleted locally — sync pending', warn: true);
    } catch (err) {
      sw.stop();
      TLog.e('ExpenseTimeframe', 'Delete failed: ${e.id}', error: err);
      if (mounted) {
        setState(() {
          if (idx >= 0 && idx <= _items.length) _items.insert(idx, e);
        });
        _toast('Could not delete expense', warn: true);
      }
    }
  }

  void _toast(String message, {bool warn = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            (warn ? const Color(0xFFF59E0B) : const Color(0xFF22C55E))
                .withValues(alpha: 0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              colors: colors,
              timeframe: widget.timeframe,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            // Everything below the header scrolls together, so the (often tall)
            // AI insight card and summary hero scroll away to give the matched
            // expenses the full screen instead of a cramped bottom strip.
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await ref.read(expenseRepositoryProvider).syncFromServer();
                  await _reset();
                },
                color: AppColors.accent,
                backgroundColor: colors.bg2,
                child: CustomScrollView(
                  controller: _scrollCtrl,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (widget.timeframe.aiInsight)
                      SliverToBoxAdapter(
                        child: AiRecommendationCard(
                          colors: colors,
                          loading: _insightLoading,
                          recommendation: _recommendation,
                          onChip: _onInsightChip,
                        ),
                      )
                    else if ((widget.timeframe.aiAnswer ?? '').trim().isNotEmpty)
                      SliverToBoxAdapter(
                        child: _AiAnswerBanner(
                          colors: colors,
                          answer: widget.timeframe.aiAnswer!.trim(),
                        ),
                      ),
                    if (widget.timeframe.seedSearchTerms.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _SemanticTermsRow(
                          colors: colors,
                          terms: widget.timeframe.seedSearchTerms,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: _SummaryHero(
                        colors: colors,
                        total: _total,
                        count: _count,
                        startIso: widget.timeframe.startIso,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SearchBar(
                        colors: colors,
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        onClear: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      ),
                    ),
                    if (_categories.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _CategoryFilterRow(
                          colors: colors,
                          categories: _categories,
                          selected: _categoryFilter,
                          onTap: _toggleCategory,
                        ),
                      ),
                    _buildBodySliver(colors),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodySliver(AppColors colors) {
    if (_initialLoading) {
      return SliverToBoxAdapter(child: _ListSkeleton(colors: colors));
    }
    if (_hasError && _items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _ErrorState(colors: colors, onRetry: _reset),
      );
    }
    if (_items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(colors: colors, isFiltered: _isFiltered),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, rawIndex) {
            if (_hasChart && rawIndex == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ExpenseChartCard(
                  colors: colors,
                  chart: widget.timeframe.chart,
                  categories: _categories,
                  buckets: _timeBuckets,
                  total: _total,
                ),
              );
            }
            final index = _hasChart ? rawIndex - 1 : rawIndex;
            if (index == _items.length) return _buildFooter(colors);
            final e = _items[index];
            final showHeader = index == 0 ||
                !_sameDay(_items[index - 1].date, e.date);
            final child = Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ExpenseItem(
                key: ValueKey(e.id),
                expense: _toData(e),
                onEdit: () => _editExpense(e),
                onDelete: () => _deleteExpense(e),
                onTap: () => _showDetail(e),
              ),
            );
            if (!showHeader) return child;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DayHeader(colors: colors, dateIso: e.date),
                child,
              ],
            );
          },
          // Optional leading chart item, then expense rows, then footer.
          childCount: _items.length + 1 + (_hasChart ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildFooter(AppColors colors) {
    if (_hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() => _hasError = false);
              _loadMore();
            },
            icon: const Icon(LucideIcons.rotateCw, size: 14),
            label: Text(
              'Retry loading more',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
      );
    }
    if (_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppColors.accent,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          '${_items.length} of $_count shown · end of list',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.text5,
          ),
        ),
      ),
    );
  }

  bool get _isFiltered =>
      _search.isNotEmpty ||
      _categoryFilter != null ||
      widget.timeframe.seedSearchTerms.isNotEmpty;

  bool get _hasChart {
    switch (widget.timeframe.chart) {
      case ExpenseChart.none:
        return false;
      case ExpenseChart.category:
        return _categories.isNotEmpty;
      case ExpenseChart.daily:
      case ExpenseChart.monthly:
        return _timeBuckets.isNotEmpty;
    }
  }

  bool _sameDay(String aIso, String bIso) {
    final a = DateTime.tryParse(aIso);
    final b = DateTime.tryParse(bIso);
    if (a == null || b == null) return aIso == bIso;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  ExpenseData _toData(Expense e) => ExpenseData(
        id: e.id,
        amount: e.amount,
        description: e.description,
        category: e.category,
        bank: e.bank,
        cardType: e.cardType,
        date: e.date,
        isManualCategory: e.isManualCategory,
        comments: e.comments,
      );
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.timeframe,
    required this.onClose,
  });

  final AppColors colors;
  final ExpenseTimeframe timeframe;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(LucideIcons.arrowLeft, color: colors.text, size: 22),
            tooltip: 'Back',
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // AI-provided titles are used verbatim; the fixed Spending-
                  // Analysis timeframes get their friendly long-form name.
                  timeframe.aiAnswer != null
                      ? timeframe.label
                      : _title(timeframe.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
                Text(
                  timeframe.subtitle ?? _defaultSubtitle(timeframe),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.text4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  static String _title(String label) {
    switch (label) {
      case 'Today':
        return "Today's Expenses";
      case '7D':
        return 'Last 7 Days';
      case '1M':
        return 'This Month';
      case '6M':
        return 'Last 6 Months';
      case 'All':
        return 'All Expenses';
      default:
        return '$label Expenses';
    }
  }

  static String _defaultSubtitle(ExpenseTimeframe tf) {
    if (tf.startIso == null) return 'Complete history · tap to edit';
    final start = DateTime.tryParse(tf.startIso!);
    if (start == null) return 'tap any expense to edit';
    return 'Since ${formatDate(tf.startIso!)} · tap to edit';
  }
}

// ─── Summary hero ─────────────────────────────────────────────────────────────

// ─── Visualization card (AI "visualize" queries) ─────────────────────────────

String _compactCurrency(double v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(v % 10000000 == 0 ? 0 : 1)}Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(v % 100000 == 0 ? 0 : 1)}L';
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
  return '₹${v.toStringAsFixed(0)}';
}

class _ExpenseChartCard extends StatelessWidget {
  const _ExpenseChartCard({
    required this.colors,
    required this.chart,
    required this.categories,
    required this.buckets,
    required this.total,
  });

  final AppColors colors;
  final ExpenseChart chart;
  final List<({String category, double total, int count})> categories;
  final List<ExpenseBucket> buckets;
  final double total;

  @override
  Widget build(BuildContext context) {
    final isCategory = chart == ExpenseChart.category;
    final title = switch (chart) {
      ExpenseChart.category => 'Spending by category',
      ExpenseChart.daily => 'Daily spending',
      ExpenseChart.monthly => 'Monthly spending',
      ExpenseChart.none => '',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.bg1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCategory ? LucideIcons.pieChart : LucideIcons.barChart3,
                size: 16,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
              ),
              Text(
                _compactCurrency(total),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isCategory)
            _CategoryBars(colors: colors, categories: categories, total: total)
          else
            _TimeBars(colors: colors, buckets: buckets, monthly: chart == ExpenseChart.monthly),
        ],
      ),
    );
  }
}

/// Animated horizontal bars per category — beautiful + readable at any width.
class _CategoryBars extends StatelessWidget {
  const _CategoryBars({
    required this.colors,
    required this.categories,
    required this.total,
  });

  final AppColors colors;
  final List<({String category, double total, int count})> categories;
  final double total;

  @override
  Widget build(BuildContext context) {
    final top = categories.take(8).toList();
    final maxTotal =
        top.fold<double>(0, (m, c) => c.total > m ? c.total : m);
    return Column(
      children: [
        for (final c in top)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CategoryBarRow(
              colors: colors,
              category: c.category,
              amount: c.total,
              count: c.count,
              fraction: maxTotal > 0 ? c.total / maxTotal : 0,
              pct: total > 0 ? c.total / total : 0,
            ),
          ),
      ],
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  const _CategoryBarRow({
    required this.colors,
    required this.category,
    required this.amount,
    required this.count,
    required this.fraction,
    required this.pct,
  });

  final AppColors colors;
  final String category;
  final double amount;
  final int count;
  final double fraction;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final color =
        AppColors.categoryColors[category] ?? AppColors.categoryOthers;
    final emoji = AppColors.categoryIcons[category] ?? '📦';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
            ),
            Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: colors.text4,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatCurrency(amount),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Container(height: 7, color: colors.bg3),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction.clamp(0.02, 1.0)),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.55)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// fl_chart bar chart for daily / monthly spend with touch tooltips.
class _TimeBars extends StatelessWidget {
  const _TimeBars({
    required this.colors,
    required this.buckets,
    required this.monthly,
  });

  final AppColors colors;
  final List<ExpenseBucket> buckets;
  final bool monthly;

  @override
  Widget build(BuildContext context) {
    // Cap visible bars so dense ranges stay readable; show the most recent.
    final visible = buckets.length > 31
        ? buckets.sublist(buckets.length - 31)
        : buckets;
    final maxY = visible.fold<double>(0, (m, b) => b.total > m ? b.total : m);
    final safeMaxY = maxY <= 0 ? 1.0 : maxY * 1.18;
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: safeMaxY,
          alignment: visible.length <= 12
              ? BarChartAlignment.spaceAround
              : BarChartAlignment.spaceBetween,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: safeMaxY / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colors.border2.withValues(alpha: 0.5),
              strokeWidth: 0.8,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: safeMaxY / 4,
                getTitlesWidget: (v, meta) {
                  if (v < 0 || v > safeMaxY * 1.01) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      _compactCurrency(v),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: colors.text4,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= visible.length) {
                    return const SizedBox.shrink();
                  }
                  // Thin out labels when crowded.
                  final step = (visible.length / 6).ceil();
                  if (visible.length > 8 && i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      _bucketLabel(visible[i].bucket),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: colors.text3,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => colors.bg1.withValues(alpha: 0.97),
              tooltipBorder:
                  BorderSide(color: AppColors.accent.withValues(alpha: 0.45)),
              tooltipRoundedRadius: 12,
              getTooltipItem: (group, _, rod, __) {
                final b = visible[group.x];
                return BarTooltipItem(
                  '${_bucketLabel(b.bucket, full: true)}\n'
                  '${formatCurrency(b.total)} · ${b.count} txns',
                  GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < visible.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: visible[i].total > 0 ? visible[i].total : safeMaxY * 0.01,
                    width: visible.length > 16 ? 6 : 14,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(6)),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.accent,
                        AppColors.accent.withValues(alpha: 0.45),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _bucketLabel(String bucket, {bool full = false}) {
    if (monthly) {
      // 'YYYY-MM'
      final parts = bucket.split('-');
      if (parts.length < 2) return bucket;
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final mi = int.tryParse(parts[1]) ?? 0;
      final m = (mi >= 1 && mi <= 12) ? months[mi - 1] : parts[1];
      return full ? '$m ${parts[0]}' : m;
    }
    // 'YYYY-MM-DD' → day number (full: 'DD Mon')
    final parts = bucket.split('-');
    if (parts.length < 3) return bucket;
    if (!full) return parts[2];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final mi = int.tryParse(parts[1]) ?? 0;
    final m = (mi >= 1 && mi <= 12) ? months[mi - 1] : parts[1];
    return '${parts[2]} $m';
  }
}

/// Read-only chips showing the exact keywords the semantic search matched on.
/// Surfacing them keeps results transparent and trustworthy — the user can see
/// precisely what was queried (nothing is invented by the AI).
class _SemanticTermsRow extends StatelessWidget {
  const _SemanticTermsRow({required this.colors, required this.terms});

  final AppColors colors;
  final List<String> terms;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 8),
            child: Icon(LucideIcons.search, size: 13, color: colors.text4),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in terms)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      t,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.text2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiAnswerBanner extends StatelessWidget {
  const _AiAnswerBanner({required this.colors, required this.answer});

  final AppColors colors;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.16),
            AppColors.accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✨', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              answer,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({
    required this.colors,
    required this.total,
    required this.count,
    required this.startIso,
  });

  final AppColors colors;
  final double total;
  final int count;
  final String? startIso;

  @override
  Widget build(BuildContext context) {
    final isDark = colors.isDark;
    final avg = _dailyAvg();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF1A1035), Color(0xFF241748)]
              : const [Color(0xFFF5F3FF), Color(0xFFEDE9FE)],
        ),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: isDark ? 0.32 : 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: isDark ? 0.22 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL SPENT',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: colors.text3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(total),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$count transaction${count == 1 ? '' : 's'}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
          ),
          if (avg != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'DAILY AVG',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colors.text4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(avg),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFA78BFA),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  double? _dailyAvg() {
    if (startIso == null || count == 0) return null;
    final start = DateTime.tryParse(startIso!);
    if (start == null) return null;
    final days = DateTime.now().difference(start).inDays + 1;
    if (days <= 1) return null;
    return total / days;
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.colors,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final AppColors colors;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: colors.text),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.bg2,
          hintText: 'Search description, category or note…',
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            color: colors.text5,
          ),
          prefixIcon: Icon(LucideIcons.search, size: 16, color: colors.text4),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: Icon(LucideIcons.x, size: 15, color: colors.text4),
                    onPressed: onClear,
                  ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}

// ─── Category filter row ───────────────────────────────────────────────────────

class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({
    required this.colors,
    required this.categories,
    required this.selected,
    required this.onTap,
  });

  final AppColors colors;
  final List<({String category, double total, int count})> categories;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = categories[i];
          final color =
              AppColors.categoryColors[c.category] ?? AppColors.categoryOthers;
          final emoji = AppColors.categoryIcons[c.category] ?? '📦';
          final isSel = selected == c.category;
          return GestureDetector(
            onTap: () => onTap(c.category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isSel ? color.withValues(alpha: 0.18) : colors.bg2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSel
                      ? color.withValues(alpha: 0.7)
                      : colors.border,
                ),
              ),
              child: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Text(
                    c.category,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isSel ? color : colors.text3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatCurrency(c.total),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isSel ? color : colors.text4,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Day header ───────────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.colors, required this.dateIso});

  final AppColors colors;
  final String dateIso;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Text(
            formatDate(dateIso),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: colors.text3,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: colors.border)),
        ],
      ),
    );
  }
}

// ─── States ───────────────────────────────────────────────────────────────────

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: 7,
      itemBuilder: (_, __) => Container(
        height: 66,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors, required this.isFiltered});

  final AppColors colors;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(isFiltered ? '🔍' : '💸', style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No matching expenses' : 'No expenses in this period',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.text3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltered
                ? 'Try a different search or category'
                : 'Logged expenses will appear here',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: colors.text5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail sheet (full, scrollable — handles huge text gracefully) ───────────

class _ExpenseDetailSheet extends StatelessWidget {
  const _ExpenseDetailSheet({
    required this.expense,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final e = expense;
    final categoryColor =
        AppColors.categoryColors[e.category] ?? AppColors.categoryOthers;
    final categoryIcon = AppColors.categoryIcons[e.category] ?? '📦';
    final dt = DateTime.tryParse(e.date);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.text4,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: categoryColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(categoryIcon,
                              style: const TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '-${formatCurrency(e.amount)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                              Text(
                                e.category,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: categoryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DetailField(
                      colors: colors,
                      label: 'DESCRIPTION',
                      child: SelectableText(
                        e.description.isEmpty ? '—' : e.description,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          height: 1.5,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DetailField(
                            colors: colors,
                            label: 'BANK',
                            child: Text(
                              e.bank.isEmpty ? '—' : e.bank,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.text,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DetailField(
                            colors: colors,
                            label: 'PAYMENT',
                            child: Text(
                              e.cardType.isEmpty ? '—' : e.cardType,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.text,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DetailField(
                      colors: colors,
                      label: 'WHEN',
                      child: Text(
                        dt == null
                            ? e.date
                            : '${formatDate(e.date)} · ${formatTime(e.date)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    if (e.comments.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _DetailField(
                        colors: colors,
                        label: '📝 COMMENTS',
                        accent: true,
                        child: SelectableText(
                          e.comments.trim(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            height: 1.55,
                            color: colors.text2,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onDelete,
                            icon: const Icon(LucideIcons.trash2, size: 16),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0x66EF4444)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: onEdit,
                            icon: const Icon(LucideIcons.pencil,
                                size: 16, color: Colors.white),
                            label: const Text('Edit Expense'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.colors,
    required this.label,
    required this.child,
    this.accent = false,
  });

  final AppColors colors;
  final String label;
  final Widget child;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: accent ? AppColors.accent.withValues(alpha: 0.06) : colors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent
              ? AppColors.accent.withValues(alpha: 0.25)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colors.text4,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.colors, required this.onRetry});

  final AppColors colors;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.cloudOff, size: 44, color: Color(0xFFF59E0B)),
          const SizedBox(height: 14),
          Text(
            'Could not load expenses',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.text3,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.rotateCw, size: 16),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
