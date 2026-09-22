import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/news_summarize_store.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/reduced_motion.dart';
import '../../../core/utils/retry.dart';
import '../../../data/services/narration_completion_store.dart';
import '../../../domain/entities/news_entities.dart';
import '../../providers/profile_photo_provider.dart';
import '../../widgets/compact_header.dart';
import '../../widgets/news_action_fab.dart';
import '../../widgets/swipe_to_delete.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_modal.dart';
import 'article_followup_sheet.dart';
import 'news_article_nav.dart';
import 'news_category_rail.dart';
import 'news_chrome.dart';
import 'news_controller.dart';
import 'news_feed_filters.dart';
import 'news_review_meta.dart';
import 'news_saved_page.dart';
import 'summary_reader_screen.dart';

export 'news_chrome.dart' show newsCategoryIcon, newsCategoryColor;

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  String _category = 'All';

  /// Listener bound to [NewsSummarizeStore] so the "Resume summary" pill
  /// rebuilds when a background session progresses or completes.
  late final VoidCallback _summarizeListener;
  StreamSubscription<String>? _payloadSub;

  @override
  void initState() {
    super.initState();
    _summarizeListener = () {
      if (!mounted) return;
      if (NewsSummarizeStore.instance.consumePendingReopen()) {
        _reopenReaderForActiveSession();
      }
      setState(() {});
    };
    NewsSummarizeStore.instance.addListener(_summarizeListener);

    _payloadSub = notificationPayloadStream.stream.listen((payload) {
      if (!mounted) return;
      if (payload != NewsSummarizeStore.kReopenPayload) return;
      _reopenReaderForActiveSession();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
          ref.read(newsControllerProvider.notifier).ensureFresh(force: true));
      if (NewsSummarizeStore.instance.consumePendingReopen()) {
        _reopenReaderForActiveSession();
      }
    });
  }

  @override
  void dispose() {
    NewsSummarizeStore.instance.removeListener(_summarizeListener);
    _payloadSub?.cancel();
    super.dispose();
  }

  /// Re-opens the [SummaryReaderScreen] for the current background session.
  /// Called from the "Resume summary" pill and from the completion-
  /// notification deep-link.
  Future<void> _reopenReaderForActiveSession() async {
    final store = NewsSummarizeStore.instance;
    final session = store.articles;
    if (session.isEmpty) return;
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SummaryReaderScreen(articles: session),
      ),
    );
  }

  /// Manual pull-to-refresh. Auto-load via [NewsController.ensureFresh] is
  /// the primary path; this still POSTs `/news/refresh` so the user can
  /// force a fetch as a secondary option (not throttled by the auto window).
  Future<void> _handleRefresh() async {
    try {
      final newCount =
          await ref.read(newsControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              newCount > 0
                  ? '$newCount new article${newCount > 1 ? 's' : ''} fetched'
                  : 'All caught up — no new articles',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: kNewsSnackBarMargin,
            duration: const Duration(seconds: 3),
            backgroundColor: newCount > 0 ? const Color(0xFF34D399) : null,
          ),
        );
    } catch (e) {
      TLog.e('News', 'Refresh failed', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Unable to refresh news right now',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: kNewsSnackBarMargin,
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  Future<void> _openArticle(Article raw) {
    return openNewsArticle(context: context, ref: ref, raw: raw);
  }

  /// Handles an action picked from the speed-dial FAB. All + current-category
  /// scopes both include Movies and General — Summarize All covers the
  /// entire unread pile and skips articles that already have summaryShort.
  Future<void> _handleFabAction({
    required NewsFabAction action,
    required NewsFabScope scope,
    required List<Article> unfilteredFeed,
    required List<Article> filteredFeed,
  }) async {
    final target = scope == NewsFabScope.all ? unfilteredFeed : filteredFeed;
    if (target.isEmpty) return;

    switch (action) {
      case NewsFabAction.summarize:
        await _openSummaryReader(target);
        break;
      case NewsFabAction.clearAll:
        await _confirmClearAll(target);
        break;
    }
  }

  /// Swipe-to-delete handler used by every For You list row (All, AI
  /// News, Finance, Movies, General).
  ///
  /// Semantics:
  ///   • The article is permanently removed — the local DB row is deleted
  ///     first so it disappears instantly (the Drift stream rebuilds the feed
  ///     within one frame), then the server is told to delete + tombstone it
  ///     so the RSS sync never re-imports it and it leaves the website too.
  ///   • Article follow-up chat state is wiped (handled inside
  ///     `deleteArticle`, mirrored by the Saved-tab `onRemove` contract).
  ///   • All work is wrapped in [runWithRetry] so a transient local-DB
  ///     failure (very rare — main-thread SQLite contention) gets one quiet
  ///     retry before we surface the error to the user.
  ///   • Successes are logged at info, failures at error. Both flow through
  ///     the production [TLog] pipeline (batched + exponential-backoff
  ///     Telegram delivery). Error logs are flushed immediately.
  Future<void> _deleteArticle(Article article) async {
    final id = article.id;
    final category = article.category;

    TLog.d('News', 'Swipe-delete requested id=$id category=$category');

    try {
      await runWithRetry<void>(
        tag: 'News',
        operation: 'swipe-delete[$category]',
        attempts: 3,
        action: () async {
          await ref.read(newsControllerProvider.notifier).deleteArticle(id);
        },
      );
      TLog.i('News',
          'Swipe-delete ✓ id=$id category=$category title="${_safeTitle(article.title)}"');
    } catch (e, st) {
      TLog.e(
        'News',
        'Swipe-delete failed id=$id category=$category',
        error: e,
        st: st,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not remove article. Please try again.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: kNewsSnackBarMargin,
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Removed from $category',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: kNewsSnackBarMargin,
          duration: const Duration(milliseconds: 1600),
          backgroundColor: const Color(0xFF34D399),
        ),
      );
  }

  /// Trim noisy titles so logs stay compact (Telegram has hard limits and
  /// our batches go through the chunker — keeping each line short means
  /// more entries fit per chunk).
  String _safeTitle(String s) => s.length <= 60 ? s : '${s.substring(0, 57)}…';

  Future<void> _openSummaryReader(List<Article> articles) async {
    final service = ref.read(newsSummarizeServiceProvider);
    final repo = ref.read(newsRepositoryProvider);
    final liteModel = ref.read(settingsProvider).liteModel;

    List<Article> hydrated = articles;
    try {
      hydrated = await repo.mergeCachedSummaries(articles);
    } catch (e) {
      TLog.w('News', 'Could not hydrate cached summaries: $e', error: e);
    }

    NewsSummarizeStore.instance.start(
      articles: hydrated,
      service: service,
      repository: repo,
      liteModel: liteModel,
    );

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SummaryReaderScreen(articles: hydrated),
      ),
    );
  }

  Future<void> _confirmClearAll(List<Article> articles) async {
    final colors = Theme.of(context).extension<AppColors>()!;
    // Category scope label drives the confirm sheet copy. When every
    // article in the batch belongs to the same category (the Movies /
    // General clearOnly path always does), we surface that category name
    // so the user sees exactly which pile they're about to nuke. Mixed
    // batches keep the original "all unread" wording.
    final categories = <String>{for (final a in articles) a.category};
    final scopeLabel = categories.length == 1 ? categories.first : null;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ClearAllConfirmSheet(
        colors: colors,
        count: articles.length,
        scopeLabel: scopeLabel,
      ),
    );
    if (confirmed != true || !mounted) return;

    final ids = articles.map((a) => a.id).toList(growable: false);
    final logScope = scopeLabel ?? 'mixed';

    var updated = 0;
    try {
      updated = await runWithRetry<int>(
        tag: 'News',
        operation: 'clearAll[$logScope]',
        attempts: 3,
        action: () =>
            ref.read(newsControllerProvider.notifier).markManyRead(ids),
      );
      for (final id in ids) {
        ArticleFollowUpStore.instance.clear(id);
      }
      TLog.i(
        'News',
        'Clear All ✓ scope=$logScope requested=${ids.length} updated=$updated',
      );
    } catch (e, st) {
      TLog.e(
        'News',
        'Clear All failed scope=$logScope requested=${ids.length}',
        error: e,
        st: st,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not clear articles. Please try again.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: kNewsSnackBarMargin,
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      return;
    }

    if (!mounted) return;

    final shownCount = updated > 0 ? updated : ids.length;
    final successMsg = scopeLabel != null
        ? 'Cleared $shownCount from $scopeLabel'
        : 'Cleared $shownCount article${shownCount == 1 ? '' : 's'}';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            successMsg,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: kNewsSnackBarMargin,
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF34D399),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final newsState = ref.watch(newsControllerProvider);
    final allArticles = newsState.valueOrNull ?? const <Article>[];
    final unreadUnsaved = unreadUnsavedArticles(allArticles);
    final unfilteredFeed = unreadUnsaved;
    final feed = newsFeedForCategory(unreadUnsaved, _category);
    final featuredArticle = feed.isEmpty ? null : feed.first;
    final rest = featuredArticle == null
        ? feed
        : feed.where((a) => a.id != featuredArticle.id).toList();
    final savedCount = allArticles.where((a) => a.isSaved).length;
    final railCounts = {
      for (final label in kNewsCategoryRailLabels)
        label: newsCategoryCount(unreadUnsaved, label),
    };

    return Column(
      children: [
        CompactHeader(
          title: 'News',
          photoPath: ref.watch(profilePhotoPathProvider),
          actionIcon: LucideIcons.bookmark,
          actionTooltip: 'Saved',
          actionBadgeCount: savedCount > 0 ? savedCount : null,
          onAvatarTap: () => showSettingsModal(context, ref),
          onActionTap: () => NewsSavedPage.open(context),
        ),
        Expanded(
          child: Stack(
            children: [
              ColoredBox(
                color: colors.bg,
                child: _ForYouTab(
                  colors: colors,
                  category: _category,
                  featured: featuredArticle,
                  rest: rest,
                  loading: newsState.isLoading && allArticles.isEmpty,
                  hasError: newsState.hasError && allArticles.isEmpty,
                  feedEmpty: feed.isEmpty,
                  onRefresh: _handleRefresh,
                  onOpen: _openArticle,
                  unreadCountAll: unfilteredFeed.length,
                  unreadCountInCategory: feed.length,
                  onSwipeDelete: _deleteArticle,
                  onFabAction: (action, scope) => _handleFabAction(
                    action: action,
                    scope: scope,
                    unfilteredFeed: unfilteredFeed,
                    filteredFeed: feed,
                  ),
                  activeSummaryProgress:
                      NewsSummarizeStore.instance.hasRelevantSession({
                    for (final a in unfilteredFeed) a.id,
                  })
                          ? NewsSummarizeStore.instance.progress
                          : null,
                  onResumeSummary: _reopenReaderForActiveSession,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: NewsCategoryRail(
                  colors: colors,
                  selected: _category,
                  counts: railCounts,
                  onSelected: (c) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    setState(() => _category = c);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ForYouTab extends StatelessWidget {
  const _ForYouTab({
    required this.colors,
    required this.category,
    required this.featured,
    required this.rest,
    required this.loading,
    required this.hasError,
    required this.feedEmpty,
    required this.onRefresh,
    required this.onOpen,
    required this.unreadCountAll,
    required this.unreadCountInCategory,
    required this.onFabAction,
    required this.activeSummaryProgress,
    required this.onResumeSummary,
    required this.onSwipeDelete,
  });

  final AppColors colors;
  final String category;
  final Article? featured;
  final List<Article> rest;
  final bool loading;
  final bool hasError;
  final bool feedEmpty;
  final Future<void> Function() onRefresh;
  final ValueChanged<Article> onOpen;

  /// Total unread+unsaved across all categories (used by the FAB sheet).
  final int unreadCountAll;

  /// Unread+unsaved in the currently-active category chip.
  final int unreadCountInCategory;

  /// Fired when the user picks an action from the speed-dial FAB.
  final void Function(NewsFabAction action, NewsFabScope scope) onFabAction;

  /// Snapshot of progress from a still-running background summarize
  /// session, or `null` if no session is active.
  final SummaryProgress? activeSummaryProgress;

  /// Re-opens the reader bound to the live session.
  final VoidCallback onResumeSummary;

  /// Per-article delete handler — invoked from the swipe-to-delete
  /// affordance on every feed row (All, AI News, Finance, Movies, General).
  final ValueChanged<Article> onSwipeDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        RefreshIndicator(
          key: const Key('news-feed-refresh'),
          onRefresh: onRefresh,
          color: AppColors.accent,
          backgroundColor: colors.bg1,
          displacement: 48,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: kNewsFeedBottomInset),
            itemCount: () {
              var n = 0;
              if (activeSummaryProgress != null) n++;
              if (featured != null) n++;
              if (loading || hasError || feedEmpty) return n + 1;
              return n + rest.length;
            }(),
            itemBuilder: (context, i) {
              var cursor = i;
              if (activeSummaryProgress != null) {
                if (cursor == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _SummaryRunningPill(
                      colors: colors,
                      progress: activeSummaryProgress!,
                      onTap: onResumeSummary,
                    ),
                  );
                }
                cursor--;
              }
              if (featured != null) {
                if (cursor == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: SwipeToDelete(
                      key: ValueKey<String>('swipe-featured-${featured!.id}'),
                      onDelete: () => onSwipeDelete(featured!),
                      headline: 'Delete this article?',
                      title: featured!.title,
                      message:
                          'Remove from ${featured!.category}. It will not come back on refresh.',
                      borderRadius: 24,
                      contentHeight: 280,
                      child: _FeaturedCard(
                        article: featured!,
                        colors: colors,
                        onTap: () => onOpen(featured!),
                      ),
                    ),
                  );
                }
                cursor--;
              }
              if (loading) {
                return const Padding(
                  padding: EdgeInsets.only(top: 72),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
                    ),
                  ),
                );
              }
              if (hasError) {
                return Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Column(
                    children: [
                      Icon(LucideIcons.wifiOff, size: 36, color: colors.text4),
                      const SizedBox(height: 12),
                      Text(
                        'Could not load news right now',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.text4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pull down to try again',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: colors.text4,
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (feedEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Column(
                    children: [
                      const Text('📰', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      Text(
                        'No articles in this category',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.text4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pull down to refresh',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: colors.text4,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final article = rest[cursor];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SwipeToDelete(
                  key: ValueKey<String>('swipe-row-${article.id}'),
                  onDelete: () => onSwipeDelete(article),
                  headline: 'Delete this article?',
                  title: article.title,
                  message:
                      'Remove from ${article.category}. It will not come back on refresh.',
                  borderRadius: 14,
                  child: _NewsListCard(
                    article: article,
                    colors: colors,
                    onTap: () => onOpen(article),
                  ),
                ),
              );
            },
          ),
        ),
        // Overlay only: empty space must not swallow vertical overscroll
        // so pull-to-refresh stays usable as a secondary fetch.
        Positioned.fill(
          child: NewsActionFab(
            colors: colors,
            unreadCount: unreadCountAll,
            unreadCountInCategory: unreadCountInCategory,
            activeCategory: category,
            dockInset: kNewsCategoryRailHeight,
            onAction: onFabAction,
          ),
        ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.article,
    required this.colors,
    required this.onTap,
  });

  final Article article;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cat = newsCategoryColor(article.category);
    final rating = NewsReviewMeta.ratingLabelOf(article.summaryMarkdown);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.shadowColor,
            blurRadius: colors.isDark ? 32 : 18,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (article.imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: article.imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: ((MediaQuery.sizeOf(context).width - 32) *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      memCacheHeight:
                          (280 * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      placeholder: (_, __) => Container(
                        color: cat.withValues(alpha: 0.06),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: cat.withValues(alpha: 0.06),
                        child: Center(
                          child: Icon(LucideIcons.newspaper,
                              size: 40, color: cat.withValues(alpha: 0.2)),
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cat.withValues(alpha: 0.12),
                            cat.withValues(alpha: 0.04),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Icon(LucideIcons.newspaper,
                            size: 40, color: cat.withValues(alpha: 0.2)),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.08),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                          Colors.black.withValues(alpha: 0.98),
                        ],
                        stops: const [0, 0.32, 0.64, 1],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.bottomCenter,
                        radius: 1,
                        colors: [
                          cat.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: cat.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: cat.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    newsCategoryIcon(article.category),
                                    size: 10,
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
                            if (rating != null)
                              NewsRatingBadge(
                                rating: rating,
                                onDark: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          article.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                            letterSpacing: -0.3,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          article.excerpt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              article.source,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                            Text(
                              ' · ',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            Icon(
                              LucideIcons.clock,
                              size: 11,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${article.readTime} min',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                            Text(
                              ' · ',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                article.date,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsListCard extends StatelessWidget {
  const _NewsListCard({
    required this.article,
    required this.colors,
    required this.onTap,
  });

  final Article article;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cat = newsCategoryColor(article.category);
    final rating = NewsReviewMeta.ratingLabelOf(article.summaryMarkdown);

    return ListenableBuilder(
      listenable: NarrationCompletionStore.instance,
      builder: (context, _) {
        final done = NarrationCompletionStore.instance.isCompleted(article.id);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (article.imageUrl.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: article.imageUrl,
                              fit: BoxFit.cover,
                              memCacheWidth:
                                  (88 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                              memCacheHeight:
                                  (88 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                              placeholder: (_, __) => Container(
                                color: cat.withValues(alpha: 0.08),
                                child: Center(
                                  child: Icon(
                                    newsCategoryIcon(article.category),
                                    size: 24,
                                    color: cat.withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: cat.withValues(alpha: 0.08),
                                child: Center(
                                  child: Icon(
                                    newsCategoryIcon(article.category),
                                    size: 24,
                                    color: cat.withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    cat.withValues(alpha: 0.12),
                                    cat.withValues(alpha: 0.04),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  newsCategoryIcon(article.category),
                                  size: 24,
                                  color: cat.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cat.withValues(alpha: 0.12),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          if (rating != null)
                            Positioned(
                              left: 4,
                              bottom: 4,
                              child: NewsRatingBadge(
                                rating: rating,
                                onDark: true,
                                compact: true,
                              ),
                            ),
                          if (done)
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Icon(
                                LucideIcons.checkCircle2,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            letterSpacing: -0.1,
                            color: done
                                ? colors.text.withValues(alpha: 0.5)
                                : colors.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          article.excerpt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            height: 1.35,
                            color: colors.text3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cat.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    newsCategoryIcon(article.category),
                                    size: 9,
                                    color: cat,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    article.category,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 9,
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
                                '${article.source} · ${article.date}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: colors.text4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClearAllConfirmSheet extends StatelessWidget {
  const _ClearAllConfirmSheet({
    required this.colors,
    required this.count,
    this.scopeLabel,
  });

  final AppColors colors;
  final int count;

  /// Optional category name to show in the title + body — set when every
  /// article in the about-to-be-cleared batch shares a single category
  /// (e.g. Movies/General `clearOnly` flow). `null` falls back to the
  /// legacy "Clear all unread?" copy used by the mixed-feed path.
  final String? scopeLabel;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final titleText = scopeLabel != null
        ? 'Clear all from $scopeLabel?'
        : 'Clear all unread?';
    final bodyText = scopeLabel != null
        ? '$count article${count == 1 ? '' : 's'} from $scopeLabel will be removed from your feed. Saved articles are not affected.'
        : '$count article${count == 1 ? '' : 's'} will be removed from your News feed. Saved articles are not affected.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        margin: EdgeInsets.only(bottom: 16 + bottomInset),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadowColor,
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0x1AEF4444),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x33EF4444)),
              ),
              child: const Icon(
                LucideIcons.eraser,
                size: 24,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              titleText,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.text,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              bodyText,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.4,
                color: colors.text3,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(false),
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.bg2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.border),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.text2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(true),
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFEF4444),
                              Color(0xFFDC2626),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Clear $count',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// "Summary running in background" pill
//
// Shows up at the top of the For You feed any time the user has a live
// summarize session in flight (after closing the reader before all batches
// finished, or after coming back to the app from the completion notification).
// One-tap re-opens the reader on the current state — every cached summary
// is already in the local DB, so no work is duplicated.
// ─────────────────────────────────────────────────────────────────────────

class _SummaryRunningPill extends StatefulWidget {
  const _SummaryRunningPill({
    required this.colors,
    required this.progress,
    required this.onTap,
  });

  final AppColors colors;
  final SummaryProgress progress;
  final VoidCallback onTap;

  @override
  State<_SummaryRunningPill> createState() => _SummaryRunningPillState();
}

class _SummaryRunningPillState extends State<_SummaryRunningPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    } else if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final isComplete = p.isComplete;
    final pct = (p.fraction * 100).clamp(0, 100).round();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isComplete
                    ? const [Color(0xFF10B981), Color(0xFF059669)]
                    : const [Color(0xFF6366F1), Color(0xFFA855F7)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (isComplete
                          ? const Color(0xFF10B981)
                          : const Color(0xFF8B5CF6))
                      .withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final t = isComplete ? 1.0 : (0.7 + _pulseCtrl.value * 0.3);
                    return Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: t),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isComplete ? LucideIcons.check : LucideIcons.sparkles,
                        size: 14,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isComplete
                            ? 'Catch-up summary ready'
                            : 'Summarizing in background',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isComplete
                            ? 'Tap to read ${p.ready} quick summaries'
                            : '${p.ready} / ${p.total} ready · $pct%',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
