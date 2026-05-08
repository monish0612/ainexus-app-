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

    // Done = "I'm finished reviewing." Two cases:
    //   1. Session has fully finished → drop the sticky pill so the For
    //      You tab returns to its normal layout.
    //   2. Session still has in-flight batches → keep them running; their
    //      results are cached to the DB and the user can re-enter the
    //      reader later via the pill.
    if (!_store.hasActiveSession) {
      _store.dismissCompletedSession();
    } else {
      _store.detachReader();
    }
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

    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          // ── Body: vertical PageView ─────────────────────────────────
          //
          // Behaviour notes:
          //   • [BouncingScrollPhysics] makes overscroll at the first/last
          //     card feel iOS-native (rubber-banding) which reads as
          //     "buttery" on both platforms.
          //   • [pageSnapping] is true by default — we name it explicitly
          //     so future maintainers don't accidentally turn it off.
          //   • Light haptic on each page change gives a tactile "tick"
          //     that masks the 300ms snap animation latency.
          //   • The inner card layout deliberately avoids any nested
          //     Scrollable on the vertical axis (was a SingleChildScrollView
          //     before — that stole every drag from the PageView and pinned
          //     the user to page 1). See [_SummaryCard.build] for details.
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
    required this.onClose,
  });

  final AppColors colors;
  final SummaryProgress progress;
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
                    Text(
                      '${progress.ready} / ${progress.total} ready',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.text2,
                      ),
                    ),
                    const SizedBox(width: 8),
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

class _SummaryCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cat = newsCategoryColor(article.category);
    // Reserve top space for the frosted header and bottom for the Done pill.
    final topInset = MediaQuery.viewPaddingOf(context).top + 84;
    final bottomInset =
        MediaQuery.viewPaddingOf(context).bottom + 16 + 56 + 16;

    // No nested vertical scrollable here — that previously stole drags
    // from the parent vertical PageView and pinned the user to page 1.
    // Instead we lay the card out as a Column whose [_SummaryBlock] is
    // wrapped in [Flexible] so any unusually long summary text shrinks
    // / fades gracefully rather than overflowing the viewport. The hero
    // is sized by its inner [AspectRatio(16/10)] so it never grows
    // beyond its intrinsic height.
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset, 20, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          _ParallaxHero(
            article: article,
            cat: cat,
            index: index,
            controller: pageController,
          ),
          const SizedBox(height: 14),
          _MetaRow(article: article, cat: cat, colors: colors),
          const SizedBox(height: 10),
          Text(
            article.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: -0.4,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: _SummaryBlock(
              state: state,
              colors: colors,
              cat: cat,
              onRetry: onRetry,
            ),
          ),
          const SizedBox(height: 18),
          _ActionsRow(
            article: article,
            colors: colors,
            cat: cat,
            onSaveToggle: onSaveToggle,
            onReadFull: onReadFull,
          ),
          const SizedBox(height: 10),
          Text(
            'Article ${index + 1} of $total',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: colors.text5,
              letterSpacing: 0.4,
            ),
          ),
        ],
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
      child: AspectRatio(
        aspectRatio: 16 / 10,
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cat.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: cat.withValues(alpha: 0.06),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(LucideIcons.sparkles, size: 12, color: cat),
                const SizedBox(width: 6),
                Text(
                  'QUICK SUMMARY',
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
            // [Flexible] + maxLines guards against the rare case where the
            // model returns >45 words. Without these caps, a wordy summary
            // would push the Done pill below the screen on small phones.
            Flexible(
              child: Text(
                summary,
                maxLines: 12,
                overflow: TextOverflow.fade,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  height: 1.55,
                  color: colors.text,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
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

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.article,
    required this.colors,
    required this.cat,
    required this.onSaveToggle,
    required this.onReadFull,
  });

  final Article article;
  final AppColors colors;
  final Color cat;
  final VoidCallback onSaveToggle;
  final VoidCallback onReadFull;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SaveButton(
          isSaved: article.isSaved,
          colors: colors,
          onTap: () {
            HapticFeedback.lightImpact();
            onSaveToggle();
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onReadFull,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                height: 48,
                decoration: BoxDecoration(
                  color: colors.bg2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cat.withValues(alpha: 0.32)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.bookOpen, size: 16, color: cat),
                    const SizedBox(width: 8),
                    Text(
                      'Read full article',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cat,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SaveButton extends StatefulWidget {
  const _SaveButton({
    required this.isSaved,
    required this.colors,
    required this.onTap,
  });

  final bool isSaved;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0.92,
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
      onTap: () async {
        await _ctrl.animateTo(0.92,
            duration: const Duration(milliseconds: 90));
        await _ctrl.animateTo(1.0,
            duration: const Duration(milliseconds: 130));
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.scale(scale: _ctrl.value, child: child),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: saved
                ? const Color(0x33EF4444)
                : widget.colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: saved
                  ? const Color(0xFFEF4444).withValues(alpha: 0.55)
                  : widget.colors.border,
            ),
            boxShadow: saved
                ? [
                    BoxShadow(
                      color:
                          const Color(0xFFEF4444).withValues(alpha: 0.32),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(
            saved ? LucideIcons.heart : LucideIcons.heart,
            size: 18,
            color: saved
                ? const Color(0xFFEF4444)
                : widget.colors.text2,
          ),
        ),
      ),
    );
  }
}
