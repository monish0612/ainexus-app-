import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/services/news_summarize_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/news_entities.dart';
import 'article_detail_modal.dart';
import 'news_controller.dart';

/// Full-screen "catch-up" reader that streams Gemini Lite quick summaries
/// for the user's unread For You pile.
///
/// Design notes:
///   - Vertical [PageView] with snap physics so each article gets a focused
///     full-screen card. Feels app-like for 200+ items vs free scroll.
///   - Sticky frosted header with progress bar + close.
///   - Per-card states: pending/loading shimmer → ready fade-in → error pill.
///   - Right-edge dots column shows scroll position over the entire pile.
///   - Sticky bottom "Done" gradient pill — clears only the unsaved articles
///     in this set when tapped (Saved ones stay in Saved tab).
class SummaryReaderScreen extends ConsumerStatefulWidget {
  const SummaryReaderScreen({super.key, required this.articles});

  final List<Article> articles;

  @override
  ConsumerState<SummaryReaderScreen> createState() =>
      _SummaryReaderScreenState();
}

class _SummaryReaderScreenState extends ConsumerState<SummaryReaderScreen> {
  late final PageController _pageCtrl;
  final NewsSummarizeStore _store = NewsSummarizeStore.instance;
  int _currentPage = 0;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    // viewportFraction: 1.0 → no peek of neighbour pages, so each card snaps
    // perfectly to the screen height. keepPage: false → we always start at
    // page 0 (the user's first unread article) when the reader is reopened
    // from the FAB or the "Resume summary" pill rather than restoring a
    // stale PageStorage index from a previous session.
    _pageCtrl = PageController(viewportFraction: 1.0, keepPage: false);
    _store.addListener(_onStoreChange);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChange);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  /// Live snapshot of articles in their current saved state from the
  /// repository stream. Falls back to the constructor list if the live
  /// state hasn't loaded yet (rare; the controller bootstraps on launch).
  List<Article> _liveArticles() {
    final all = ref.read(newsControllerProvider).valueOrNull ?? const <Article>[];
    if (all.isEmpty) return widget.articles;
    final byId = {for (final a in all) a.id: a};
    return [
      for (final a in widget.articles) byId[a.id] ?? a,
    ];
  }

  Future<void> _onDone() async {
    if (_completing) return;
    setState(() => _completing = true);

    final live = _liveArticles();
    final unsavedIds = [
      for (final a in live)
        if (!a.isSaved) a.id,
    ];
    final savedCount = live.length - unsavedIds.length;

    if (unsavedIds.isNotEmpty) {
      try {
        await ref
            .read(newsControllerProvider.notifier)
            .markManyRead(unsavedIds);
      } catch (_) {
        // markManyRead writes locally first; remote failure is logged but we
        // still consider the user's "Done" intent honored.
      }
    }

    // Done = "I'm finished reviewing." We ALWAYS dismiss the session UI
    // here so the For You tab's "Catch-up summary ready" pill disappears
    // immediately. [dismissCompletedSession] also cancels any in-flight
    // batches and stops the foreground service if the session was still
    // running (rare: user sped through faster than batches completed).
    // Articles whose summaries already landed in the DB before Done are
    // preserved forever, so re-summarizing them later is instant.
    _store.dismissCompletedSession();
    HapticFeedback.mediumImpact();

    if (!mounted) return;
    Navigator.of(context).pop();

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              savedCount > 0
                  ? 'Cleared ${unsavedIds.length} · Kept $savedCount in Saved'
                  : 'Cleared ${unsavedIds.length} article${unsavedIds.length == 1 ? '' : 's'}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF34D399),
          ),
        );
    }
  }

  /// Closes the reader UI WITHOUT cancelling the session — the foreground
  /// service keeps running and the user can re-open the reader at any time
  /// from the "Resume summary" pill on the For You tab, or via the
  /// completion notification.
  void _onClose() {
    _store.detachReader();
    Navigator.of(context).maybePop();
  }

  Future<void> _openFull(Article raw) async {
    final article =
        await ref.read(newsControllerProvider.notifier).loadArticle(raw.id) ??
            raw;
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ArticleDetailModal(
          article: article,
          onToggleSave: (_) {
            ref.read(newsControllerProvider.notifier).toggleSaved(raw.id);
          },
          onMarkRead: () {
            // Don't mark read here — the summary "Done" handler does that
            // in bulk so the article stays in the active reader.
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final live = _liveArticles();
    final progress = _store.progress;
    final unsavedRemaining = live.where((a) => !a.isSaved).length;

    // Defensive: the FAB only opens the reader with a non-empty article
    // list, but if the local DB sync clears everything mid-session (rare
    // multi-device race) we close the screen on the next frame rather
    // than crashing on the [clamp(0, -1)] below.
    if (live.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _store.detachReader();
        Navigator.of(context).maybePop();
      });
      return Scaffold(backgroundColor: colors.bg);
    }

    final safeIndex = _currentPage.clamp(0, live.length - 1);

    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          // ── Body: vertical PageView ─────────────────────────────────
          //
          // Behaviour notes:
          //   • Each card is internally scrollable (see [_SummaryCard]
          //     for the rationale — comprehensive 220-280 word
          //     magazine-formatted summaries don't fit on a single phone
          //     screen). The card claims all vertical drags within its
          //     body, so the PageView's NATIVE swipe-to-page gesture is
          //     unused.
          //   • Page navigation happens via OVERSCROLL POSITION: when the
          //     inner scroll's [ScrollMetrics.pixels] exceeds max (or
          //     drops below min) by ≥28 px, we programmatically call
          //     [PageController.nextPage] / [previousPage]. The 28 px
          //     threshold is past kTouchSlop so accidental bounces don't
          //     fire, while a normal upward swipe at the end of a long
          //     summary cleanly triggers the next page. (Old per-frame
          //     accumulator approach got stuck because BouncingScroll-
          //     Physics rubber-bands deltas to near-zero.)
          //   • Page snap animation is 220 ms — ultra-fast feel. The
          //     [HapticFeedback.selectionClick] on [onPageChanged] masks
          //     the final 30 ms of motion so the page change reads as
          //     instantaneous.
          //   • [BouncingScrollPhysics] on this PageView is largely
          //     vestigial (inner scroll wins drags) but kept for the
          //     programmatic snap animation feel.
          //   • [pageSnapping] is true by default — we name it explicitly
          //     so future maintainers don't accidentally turn it off.
          Positioned.fill(
            child: PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              physics: const PageScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              pageSnapping: true,
              allowImplicitScrolling: true,
              itemCount: live.length,
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => _currentPage = i);
              },
              itemBuilder: (ctx, i) {
                final a = live[i];
                final st = _store.statusOf(a.id);
                return _SummaryCard(
                  article: a,
                  state: st,
                  colors: colors,
                  index: i,
                  total: live.length,
                  pageController: _pageCtrl,
                  onSaveToggle: () => ref
                      .read(newsControllerProvider.notifier)
                      .toggleSaved(a.id),
                  onReadFull: () => _openFull(a),
                  onRetry: () => _store.retryArticle(a.id),
                );
              },
            ),
          ),

          // ── Sticky frosted header ───────────────────────────────────
          _Header(
            colors: colors,
            progress: progress,
            currentIndex: safeIndex,
            total: live.length,
            onClose: _onClose,
          ),

          // ── Right-edge progress dots ────────────────────────────────
          if (live.length > 1)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _PageDots(
                  total: live.length,
                  current: _currentPage,
                  colors: colors,
                ),
              ),
            ),

          // ── Bottom Done pill ────────────────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
            child: _DoneButton(
              count: unsavedRemaining,
              loading: _completing,
              onTap: _onDone,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.progress,
    required this.currentIndex,
    required this.total,
    required this.onClose,
  });

  final AppColors colors;
  final SummaryProgress progress;
  final int currentIndex;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.viewPaddingOf(context).top;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: EdgeInsets.fromLTRB(16, topPad + 10, 12, 12),
            decoration: BoxDecoration(
              color: colors.isDark
                  ? const Color(0xCC000000)
                  : const Color(0xE6FFFFFF),
              border: Border(
                bottom: BorderSide(color: colors.border),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                        ),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.sparkles,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Quick Summary',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Counter moved here from the bottom of each card so it
                    // stays sticky as the user pages. The animated progress
                    // bar below already conveys summarization-ready status,
                    // so we don't duplicate "X/Y ready" here.
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${currentIndex + 1} / $total',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: colors.text,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          progress.total > 0 && progress.ready < progress.total
                              ? '${progress.ready}/${progress.total} ready'
                              : 'all ready',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: colors.text4,
                            letterSpacing: 0.4,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: colors.bg3,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: onClose,
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            LucideIcons.x,
                            size: 14,
                            color: colors.text3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Container(color: colors.bg3),
                        AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 300),
                          alignment: Alignment.centerLeft,
                          widthFactor: progress.fraction.clamp(0.0, 1.0),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF6366F1),
                                  Color(0xFFA855F7),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Page dots
// ─────────────────────────────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.total,
    required this.current,
    required this.colors,
  });

  final int total;
  final int current;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    // Show at most 9 dots — current + 4 above + 4 below; window slides as we
    // page through. Past pages render as filled, future as outlined.
    const window = 9;
    final start = (current - window ~/ 2).clamp(0, (total - window).clamp(0, total));
    final end = (start + window).clamp(0, total);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: colors.isDark
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = start; i < end; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == current ? 8 : 5,
                height: i == current ? 8 : 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == current
                      ? const Color(0xFFA855F7)
                      : (i < current
                          ? colors.text4
                          : Colors.transparent),
                  border: i >= current && i != current
                      ? Border.all(color: colors.text4)
                      : null,
                  boxShadow: i == current
                      ? [
                          BoxShadow(
                            color: const Color(0xFFA855F7)
                                .withValues(alpha: 0.7),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Done button
// ─────────────────────────────────────────────────────────────────────────

class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.count,
    required this.loading,
    required this.onTap,
  });

  final int count;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = count <= 0 || loading;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: disabled
                  ? const [Color(0xFF374151), Color(0xFF1F2937)]
                  : const [Color(0xFF10B981), Color(0xFF059669)],
            ),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.42),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.check,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        count <= 0
                            ? 'All caught up'
                            : 'Done — Mark $count as read',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Summary card
// ─────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatefulWidget {
  const _SummaryCard({
    required this.article,
    required this.state,
    required this.colors,
    required this.index,
    required this.total,
    required this.pageController,
    required this.onSaveToggle,
    required this.onReadFull,
    required this.onRetry,
  });

  final Article article;
  final SummaryArticleState state;
  final AppColors colors;
  final int index;
  final int total;
  final PageController pageController;
  final VoidCallback onSaveToggle;
  final VoidCallback onReadFull;
  final VoidCallback onRetry;

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  late final ScrollController _scrollCtrl;

  /// Guards against firing nextPage / previousPage twice in a row while
  /// the page-snap animation is still running. Reset on
  /// [ScrollEndNotification] (inner scroll has settled back to its
  /// boundary after the rubber-band).
  bool _pageChangeInFlight = false;

  /// Pixels the inner scroll position must exceed its min/max boundary
  /// to trigger a page change.
  ///
  /// Why 28 px and NOT a per-frame accumulator (the old approach):
  ///   The old code summed [OverscrollNotification.overscroll] deltas
  ///   and triggered at 90 px accumulated. That broke under
  ///   [BouncingScrollPhysics] because:
  ///     1. Rubber-band ATTENUATES the per-frame delta — a finger drag of
  ///        100 px past the edge produces 30-50 px of actual overscroll
  ///        spread across many frames.
  ///     2. As the bounce-back phase begins, deltas reverse sign, causing
  ///        the accumulator to oscillate near zero and never reach 90.
  ///   Result: a "normal" swipe up at the bottom of a long summary did
  ///   nothing — user reported being stuck on article 1.
  ///
  ///   The new approach reads [ScrollMetrics.pixels] directly. Once the
  ///   absolute scroll position passes max+28 (or min-28), we trigger.
  ///   This is deterministic, single-frame, and matches the iOS-native
  ///   "pull to reveal next" feel. 28 px is just past the kTouchSlop
  ///   threshold so accidental bounces (where pixels barely exceed the
  ///   boundary) don't fire, while deliberate swipes do.
  static const double _kPagePastBoundaryPx = 28;

  /// Snap animation length when overscroll triggers a page change.
  /// 220 ms reads as "ultra fast" without feeling jerky — the haptic
  /// click on [PageView.onPageChanged] masks the last 30 ms of motion.
  static const Duration _kPageSnapDuration = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification n) {
    // Reset the in-flight guard the moment the inner scroll settles.
    // We do this BEFORE the early-return below so a settled state
    // immediately re-enables the next gesture.
    if (n is ScrollEndNotification) {
      _pageChangeInFlight = false;
      return false;
    }

    if (_pageChangeInFlight) return false;

    final m = n.metrics;
    if (!m.hasContentDimensions) return false;

    // Position-based trigger: how far past the boundary is the user?
    // [BouncingScrollPhysics] rubber-bands the position, so values are
    // already attenuated — past=28 corresponds to a deliberate swipe.
    final pastBottom = m.pixels - m.maxScrollExtent;
    final pastTop = m.minScrollExtent - m.pixels;

    if (pastBottom >= _kPagePastBoundaryPx) {
      _pageChangeInFlight = true;
      widget.pageController.nextPage(
        duration: _kPageSnapDuration,
        curve: Curves.easeOutCubic,
      );
    } else if (pastTop >= _kPagePastBoundaryPx) {
      _pageChangeInFlight = true;
      widget.pageController.previousPage(
        duration: _kPageSnapDuration,
        curve: Curves.easeOutCubic,
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cat = newsCategoryColor(widget.article.category);
    // Reserve top space for the frosted header and bottom for the Done pill.
    final topInset = MediaQuery.viewPaddingOf(context).top + 92;
    final bottomInset =
        MediaQuery.viewPaddingOf(context).bottom + 16 + 56 + 16;

    // Card layout strategy (rev. 3):
    //   • The entire card body is now a single vertically-scrollable
    //     [SingleChildScrollView]. This lets the new ~150-180 word
    //     comprehensive summaries render in full — the user scrolls
    //     within the card to read everything.
    //   • Page navigation between articles still works: pulling past
    //     the top OR bottom edge accumulates overscroll, and at 90 px
    //     the parent [PageView] snaps to the previous / next card.
    //     This is the Apple News pattern — feels native on both
    //     platforms thanks to [BouncingScrollPhysics].
    //   • Tap-anywhere-to-open: the card body is wrapped in
    //     [Material] + [InkWell]; tap fires [onReadFull]. Vertical drag
    //     is claimed by the inner scroll view and never fires onTap.
    //   • The save heart uses its own [GestureDetector] with
    //     [HitTestBehavior.opaque] so its taps never reach the InkWell.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onReadFull,
        splashColor: cat.withValues(alpha: 0.06),
        highlightColor: cat.withValues(alpha: 0.03),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(20, topInset, 20, bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero (16:9) with the save heart overlaid top-right.
                Stack(
                  children: [
                    _ParallaxHero(
                      article: widget.article,
                      cat: cat,
                      index: widget.index,
                      controller: widget.pageController,
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _OverlaySaveButton(
                        isSaved: widget.article.isSaved,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onSaveToggle();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _MetaRow(
                  article: widget.article,
                  cat: cat,
                  colors: widget.colors,
                ),
                const SizedBox(height: 10),
                // Title can take 3 lines now that the card scrolls — no
                // need to be aggressive about saving vertical space.
                Text(
                  widget.article.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.22,
                    letterSpacing: -0.4,
                    color: widget.colors.text,
                  ),
                ),
                const SizedBox(height: 14),
                _SummaryBlock(
                  state: widget.state,
                  colors: widget.colors,
                  cat: cat,
                  onRetry: widget.onRetry,
                ),
                const SizedBox(height: 12),
                // Discovery hint — the entire card is the tap target.
                _TapToOpenHint(colors: widget.colors, cat: cat),
                // Bottom breathing room so the last line of the summary
                // never sits flush against the Done pill.
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// "Tap to open full article" hint — sits where the old Read Full button
// did, but as a passive label. The whole card is the tap target now.
// ─────────────────────────────────────────────────────────────────────────

class _TapToOpenHint extends StatelessWidget {
  const _TapToOpenHint({required this.colors, required this.cat});

  final AppColors colors;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: cat.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cat.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bookOpen, size: 12, color: cat),
            const SizedBox(width: 7),
            Text(
              'Tap anywhere to read full article',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cat,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 5),
            Icon(LucideIcons.arrowRight, size: 11, color: cat),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Hero with subtle parallax — translates the image opposite to swipe so
// the card feels "physical" without distracting from the read.
// ─────────────────────────────────────────────────────────────────────────

class _ParallaxHero extends StatelessWidget {
  const _ParallaxHero({
    required this.article,
    required this.cat,
    required this.index,
    required this.controller,
  });

  final Article article;
  final Color cat;
  final int index;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Compute current page float offset (0.0 → N) so we know how far the
        // current card is from screen-center. We translate by ~28 px max,
        // which is just enough to feel alive without making text jitter.
        var delta = 0.0;
        if (controller.hasClients &&
            controller.position.haveDimensions &&
            controller.position.hasContentDimensions) {
          delta = (controller.page ?? index.toDouble()) - index;
        }
        final dy = (delta.clamp(-1.0, 1.0)) * -28.0;
        final scale = 1.0 - delta.abs().clamp(0.0, 1.0) * 0.04;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: _HeroImage(article: article, cat: cat),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.article, required this.cat});

  final Article article;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      // 16:9 instead of 16:10 — saves ~25 px of vertical space on a typical
      // 372 px-wide content area, redirected to the now-richer summary card.
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (article.imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: article.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: cat.withValues(alpha: 0.08),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: cat.withValues(alpha: 0.08),
                  child: Center(
                    child: Icon(
                      LucideIcons.newspaper,
                      size: 36,
                      color: cat.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cat.withValues(alpha: 0.18),
                      cat.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.newspaper,
                    size: 40,
                    color: cat.withValues(alpha: 0.3),
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.article,
    required this.cat,
    required this.colors,
  });

  final Article article;
  final Color cat;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: cat.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cat.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                article.category == 'Finance'
                    ? LucideIcons.trendingUp
                    : article.category == 'AI News'
                        ? LucideIcons.cpu
                        : LucideIcons.newspaper,
                size: 11,
                color: cat,
              ),
              const SizedBox(width: 5),
              Text(
                article.category,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cat,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${article.source} · ${article.timeAgo ?? article.date}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: colors.text4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(LucideIcons.clock, size: 10, color: colors.text5),
        const SizedBox(width: 3),
        Text(
          '${article.readTime}m',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: colors.text4,
          ),
        ),
      ],
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.state,
    required this.colors,
    required this.cat,
    required this.onRetry,
  });

  final SummaryArticleState state;
  final AppColors colors;
  final Color cat;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case SummaryStatus.ready:
        return _ReadySummary(
          summary: state.summary ?? '',
          colors: colors,
          cat: cat,
        );
      case SummaryStatus.error:
        return _ErrorSummary(
          message: state.error ?? 'Could not summarize',
          colors: colors,
          onRetry: onRetry,
        );
      case SummaryStatus.pending:
      case SummaryStatus.loading:
        return _SkeletonSummary(colors: colors, cat: cat);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// _ReadySummary: magazine-formatted body of a successful summary.
//
// Backend (rev. 4 prompt) returns a structured plain-text string with:
//   • paragraph 1            → LEDE (1–2 sentence punchy takeaway)
//   • blank line, paragraph N → BODY paragraphs (context / details / impact)
//   • optional trailing block where every line starts with "• "
//                             → KEY FACTS (3–5 bulleted scannable facts)
//
// Backward-compatible: if the cached summary is plain (no \n\n), it
// renders exactly like before (single body paragraph, no lede emphasis).
// ─────────────────────────────────────────────────────────────────────────

enum _SummaryPartKind { lede, body, bullets }

/// One renderable piece of a structured summary.
/// (Named `_SummaryPart` to avoid colliding with the existing
/// `_SummaryBlock` *widget* defined earlier in this file, which
/// dispatches between ready / error / skeleton states.)
@immutable
class _SummaryPart {
  const _SummaryPart.lede(this.text)
      : kind = _SummaryPartKind.lede,
        bullets = const <String>[];
  const _SummaryPart.body(this.text)
      : kind = _SummaryPartKind.body,
        bullets = const <String>[];
  const _SummaryPart.bullets(this.bullets)
      : kind = _SummaryPartKind.bullets,
        text = '';

  final _SummaryPartKind kind;
  final String text;
  final List<String> bullets;
}

/// Splits a structured summary string into renderable parts.
///
/// Algorithm:
///   1. Split on one or more blank lines (`\n\s*\n+`) into paragraphs.
///   2. For each paragraph, if every non-empty line starts with a bullet
///      marker (`• `, `- `, or `* `) AND there are 2+ such lines, treat
///      the paragraph as a bullet block. Otherwise treat it as prose.
///   3. The FIRST prose paragraph becomes the lede (typographic emphasis).
///   4. All subsequent prose paragraphs are body paragraphs.
///   5. Bullet blocks render as a styled list regardless of position
///      (typically they're last — the KEY FACTS block — but we don't
///      enforce that).
///
/// Edge cases:
///   • Empty / whitespace-only input → an empty list (caller renders
///     nothing; defensive — the SummaryBlock dispatcher never feeds an
///     empty string here).
///   • Single-paragraph input (legacy / cached pre-rev.4 summaries) →
///     a single BODY block (NOT lede) so the appearance matches the old
///     "one giant paragraph" rendering. No visual regression for users
///     with cached summaries.
List<_SummaryPart> _parseSummary(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const <_SummaryPart>[];

  // Split on blank lines (one or more). Use a generous regex so we
  // tolerate the model emitting "\n \n" or "\n\n\n".
  final paragraphs = trimmed
      .split(RegExp(r'\n[ \t]*\n+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  if (paragraphs.length == 1) {
    // Legacy single-paragraph (or model collapsed to one): render as
    // a body paragraph. No lede emphasis to avoid surprising users
    // looking at cached summaries.
    return [_SummaryPart.body(paragraphs.single)];
  }

  final parts = <_SummaryPart>[];
  var ledeAssigned = false;
  for (final p in paragraphs) {
    // Note: we deliberately do NOT trimRight here — a line like "• "
    // (bullet marker + space, an empty bullet the model occasionally
    // emits) needs its trailing space preserved so the prefix check
    // below still recognises it as a bullet line. The empty bullet
    // text gets filtered out further down via `.isNotEmpty`.
    final lines = p
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final isBulletBlock = lines.length >= 2 &&
        lines.every((l) {
          final t = l.trimLeft();
          return t.startsWith('• ') ||
              t.startsWith('- ') ||
              t.startsWith('* ');
        });

    if (isBulletBlock) {
      final bullets = lines
          .map((l) => l.trimLeft().substring(2).trim())
          .where((b) => b.isNotEmpty)
          .toList();
      if (bullets.isNotEmpty) {
        parts.add(_SummaryPart.bullets(bullets));
      }
    } else if (!ledeAssigned) {
      parts.add(_SummaryPart.lede(p));
      ledeAssigned = true;
    } else {
      parts.add(_SummaryPart.body(p));
    }
  }

  return parts;
}

class _ReadySummary extends StatelessWidget {
  const _ReadySummary({
    required this.summary,
    required this.colors,
    required this.cat,
  });

  final String summary;
  final AppColors colors;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    final parts = _parseSummary(summary);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cat.withValues(alpha: 0.20)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.bg2,
              Color.alphaBlend(
                cat.withValues(alpha: 0.04),
                colors.bg2,
              ),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: cat.withValues(alpha: 0.08),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Section label with a tiny accent line — gives the card a
            // magazine-style "lede" look without taking much space.
            Row(
              children: [
                Icon(LucideIcons.sparkles, size: 13, color: cat),
                const SizedBox(width: 6),
                Text(
                  'QUICK SUMMARY',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: cat,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cat.withValues(alpha: 0.32),
                          cat.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Render parsed parts with appropriate typography per part.
            // Spacing between parts is generous (16-18 px) so paragraphs
            // and bullet lists feel like a real magazine layout, not a
            // wall of text.
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) SizedBox(height: _gapBefore(parts[i])),
              _SummaryPartView(
                part: parts[i],
                colors: colors,
                cat: cat,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Gap to insert BEFORE each part (after the previous one). Bullet
  /// blocks get a slightly larger top gap because they introduce a
  /// distinct "key facts" section.
  double _gapBefore(_SummaryPart part) {
    switch (part.kind) {
      case _SummaryPartKind.lede:
        return 16;
      case _SummaryPartKind.body:
        return 16;
      case _SummaryPartKind.bullets:
        return 18;
    }
  }
}

/// Renders a single parsed [_SummaryPart] with the right typography.
///   • LEDE    → 17.5 px, w700, slightly tighter line-height. The reader
///               reads the lede first; we make it visually heavier so it
///               stands out as the "TL;DR" of the story.
///   • BODY    → 15.5 px, w500, line-height 1.62. Long-form sweet spot.
///   • BULLETS → 14 px, w600, with a coloured bullet, hanging indent for
///               wrapped lines, and 8 px row spacing.
class _SummaryPartView extends StatelessWidget {
  const _SummaryPartView({
    required this.part,
    required this.colors,
    required this.cat,
  });

  final _SummaryPart part;
  final AppColors colors;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    switch (part.kind) {
      case _SummaryPartKind.lede:
        return Text(
          part.text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17.5,
            height: 1.45,
            color: colors.text,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        );
      case _SummaryPartKind.body:
        return Text(
          part.text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15.5,
            height: 1.62,
            color: colors.text2,
            letterSpacing: -0.05,
            fontWeight: FontWeight.w500,
          ),
        );
      case _SummaryPartKind.bullets:
        return _KeyFactsList(bullets: part.bullets, colors: colors, cat: cat);
    }
  }
}

/// Renders the optional KEY FACTS bullet block with a coloured bullet,
/// hanging indent, and a faint section header so the user knows it's a
/// distinct scannable list, not just continuation prose.
class _KeyFactsList extends StatelessWidget {
  const _KeyFactsList({
    required this.bullets,
    required this.colors,
    required this.cat,
  });

  final List<String> bullets;
  final AppColors colors;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tiny section header — sets the bullet block visually apart.
        Row(
          children: [
            Container(
              width: 4,
              height: 12,
              decoration: BoxDecoration(
                color: cat,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'KEY FACTS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: cat,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < bullets.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coloured bullet — slightly larger and bolder than a plain
              // "• " character so it visually anchors the row.
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 8, right: 10),
                decoration: BoxDecoration(
                  color: cat,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  bullets[i],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.5,
                    color: colors.text,
                    letterSpacing: -0.05,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ErrorSummary extends StatelessWidget {
  const _ErrorSummary({
    required this.message,
    required this.colors,
    required this.onRetry,
  });

  final String message;
  final AppColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0x14EF4444),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33EF4444)),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.alertTriangle,
            size: 16,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: colors.text2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.refreshCw,
                      size: 11,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Retry',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonSummary extends StatefulWidget {
  const _SkeletonSummary({required this.colors, required this.cat});

  final AppColors colors;
  final Color cat;

  @override
  State<_SkeletonSummary> createState() => _SkeletonSummaryState();
}

class _SkeletonSummaryState extends State<_SkeletonSummary>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: widget.colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 12, color: widget.cat),
              const SizedBox(width: 6),
              Text(
                'GENERATING SUMMARY…',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: widget.cat,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBar(width: double.infinity, t: _ctrl.value),
                  const SizedBox(height: 8),
                  _shimmerBar(width: double.infinity, t: (_ctrl.value + 0.2) % 1),
                  const SizedBox(height: 8),
                  _shimmerBar(width: 200, t: (_ctrl.value + 0.4) % 1),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _shimmerBar({required double width, required double t}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        width: width,
        child: ColoredBox(
          color: widget.colors.bg3,
          child: ShaderMask(
            shaderCallback: (bounds) {
              final dx = (t * 2 - 1) * bounds.width;
              return LinearGradient(
                colors: [
                  Colors.transparent,
                  widget.cat.withValues(alpha: 0.32),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: Alignment(-1 + dx / bounds.width * 2, 0),
                end: Alignment(1 + dx / bounds.width * 2, 0),
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: Container(color: widget.colors.bg3),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Overlay save button — sits on top of the hero image (Apple-News style).
// Uses [HitTestBehavior.opaque] so its tap NEVER bubbles to the parent
// InkWell that opens the full article. Glassmorphism background ensures
// the icon stays legible regardless of the underlying image.
// ─────────────────────────────────────────────────────────────────────────

class _OverlaySaveButton extends StatefulWidget {
  const _OverlaySaveButton({required this.isSaved, required this.onTap});

  final bool isSaved;
  final VoidCallback onTap;

  @override
  State<_OverlaySaveButton> createState() => _OverlaySaveButtonState();
}

class _OverlaySaveButtonState extends State<_OverlaySaveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.isSaved;
    return GestureDetector(
      // Opaque hit-testing absorbs every tap inside this button so it
      // never reaches the card's [InkWell.onTap] that would otherwise
      // open the full article.
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await _ctrl.animateTo(0.88,
            duration: const Duration(milliseconds: 90));
        await _ctrl.animateTo(1.0,
            duration: const Duration(milliseconds: 130));
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) =>
            Transform.scale(scale: _ctrl.value, child: child),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: saved
                    ? const Color(0xCCEF4444)
                    : Colors.black.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: saved
                      ? const Color(0xFFEF4444).withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.18),
                  width: 1.2,
                ),
                boxShadow: saved
                    ? [
                        BoxShadow(
                          color: const Color(0xFFEF4444)
                              .withValues(alpha: 0.40),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: const Icon(
                LucideIcons.heart,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
