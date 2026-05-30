import 'dart:async';
import 'dart:ui' as ui;

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
import '../../../core/utils/retry.dart';
import '../../../domain/entities/news_entities.dart';
import '../../widgets/compact_header.dart';
import '../../widgets/news_action_fab.dart';
import '../../widgets/swipe_to_delete.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_modal.dart';
import 'article_detail_modal.dart';
import 'article_followup_sheet.dart';
import 'news_controller.dart';
import 'summary_reader_screen.dart';

class _NewsNotif {
  const _NewsNotif({
    required this.id,
    required this.title,
    required this.time,
    required this.read,
    required this.articleId,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String time;
  final bool read;
  final String articleId;
  final IconData icon;
  final Color color;
}

/// Single source of truth for the icon used to represent a news category.
/// Shared by the notification panel, the featured card badge, and the
/// list-row badge so every surface stays in sync when a new category is
/// added in [CATEGORIES].
IconData newsCategoryIcon(String category) {
  switch (category) {
    case 'Finance':
      return LucideIcons.trendingUp;
    case 'AI News':
      return LucideIcons.cpu;
    case 'Movies':
      return LucideIcons.film;
    case 'General':
      return LucideIcons.globe;
    default:
      return LucideIcons.newspaper;
  }
}

IconData _notifIconForCategory(String category) => newsCategoryIcon(category);

Color _notifColorForCategory(String category) {
  switch (category) {
    case 'Finance':
      return const Color(0xFF34D399);
    case 'AI News':
      return const Color(0xFFF59E0B);
    case 'Movies':
      return const Color(0xFFEC4899);
    case 'General':
      return const Color(0xFF38BDF8);
    default:
      return AppColors.accent;
  }
}

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final TextEditingController _savedSearchCtrl;
  String _category = 'All';
  bool _showNotif = false;
  bool _notifSeen = false;
  String _savedSearch = '';
  final Set<String> _dismissedNotifIds = {};

  /// Listener bound to [NewsSummarizeStore] so the "Resume summary" pill
  /// rebuilds when a background session progresses or completes.
  late final VoidCallback _summarizeListener;
  StreamSubscription<String>? _payloadSub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
    _savedSearchCtrl = TextEditingController();
    _summarizeListener = () {
      if (!mounted) return;
      // The store also raises notifyListeners when [requestReaderReopen]
      // sets the pending-reopen flag — handle that here so cold-start /
      // notification-tap flows don't depend on payload-stream timing.
      if (NewsSummarizeStore.instance.consumePendingReopen()) {
        _reopenReaderForActiveSession();
      }
      setState(() {});
    };
    NewsSummarizeStore.instance.addListener(_summarizeListener);

    // Listen for the deep-link payload fired when the user taps the
    // "summary ready" notification. We pop any active route stack down to
    // the news screen and reopen the reader for the live session.
    _payloadSub = notificationPayloadStream.stream.listen((payload) {
      if (!mounted) return;
      if (payload != NewsSummarizeStore.kReopenPayload) return;
      _reopenReaderForActiveSession();
    });

    // If the user reached the news screen via the completion-notification
    // tap that fired before we had a chance to subscribe, the reopen flag
    // will already be set on the store. Drain it on the next frame so the
    // reader opens the moment the screen is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (NewsSummarizeStore.instance.consumePendingReopen()) {
        _reopenReaderForActiveSession();
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    NewsSummarizeStore.instance.removeListener(_summarizeListener);
    _payloadSub?.cancel();
    _savedSearchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_showNotif && _tabCtrl.indexIsChanging) {
      setState(() => _showNotif = false);
    }
  }

  /// Re-opens the [SummaryReaderScreen] for the current background session.
  /// Called from the "Resume summary" pill and from the completion-
  /// notification deep-link.
  Future<void> _reopenReaderForActiveSession() async {
    final store = NewsSummarizeStore.instance;
    final session = store.articles;
    if (session.isEmpty) return;
    if (!mounted) return;
    // Make sure the For You tab is in front when we navigate.
    if (_tabCtrl.index != 0) _tabCtrl.animateTo(0);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SummaryReaderScreen(articles: session),
      ),
    );
  }

  List<_NewsNotif> _buildNotifications(List<Article> articles) {
    return articles
        .where((a) =>
            !a.isRead && !a.isSaved && !_dismissedNotifIds.contains(a.id))
        .take(8)
        .map(
          (article) => _NewsNotif(
            id: 'notif-${article.id}',
            title: article.title,
            time: article.timeAgo ?? article.date,
            read: false,
            articleId: article.id,
            icon: _notifIconForCategory(article.category),
            color: _notifColorForCategory(article.category),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _handleRefresh() async {
    try {
      final newCount =
          await ref.read(newsControllerProvider.notifier).refresh();
      if (!mounted) return;
      if (newCount > 0) {
        setState(() => _notifSeen = false);
      }
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
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            duration: const Duration(seconds: 3),
            backgroundColor: newCount > 0
                ? const Color(0xFF34D399)
                : null,
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
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  Future<void> _openArticle(Article raw) async {
    final article =
        await ref.read(newsControllerProvider.notifier).loadArticle(raw.id) ??
            raw;
    if (!mounted) return;

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ArticleDetailModal(
          article: article,
          onToggleSave: (_) {
            ref.read(newsControllerProvider.notifier).toggleSaved(raw.id);
          },
          onMarkRead: () {
            ref.read(newsControllerProvider.notifier).markRead(raw.id);
          },
        ),
      ),
    );
  }

  /// Handles an action picked from the For You speed-dial FAB. The full feed
  /// list is computed once in `build()` and forwarded here so we don't redo
  /// the filter work and so we always operate on the user's current view.
  Future<void> _handleFabAction({
    required NewsFabAction action,
    required NewsFabScope scope,
    required List<Article> unfilteredFeed,
    required List<Article> filteredFeed,
  }) async {
    var target = scope == NewsFabScope.all ? unfilteredFeed : filteredFeed;

    // EDGE CASE GUARD — when the user is on a Movies/General chip and picks
    // "summarize current category", the inline scope picker still routes
    // through `filteredFeed`, which is the (full-content) Movies/General
    // articles. Those must NEVER be batch-summarized by the AI — the whole
    // point of the skip_summary feeds is to show the original body. Strip
    // them defensively here so a future scope-picker change can't sneak
    // them into the summarize pipeline. "Clear" action is unaffected:
    // marking Movies/General articles as read in bulk is still valid.
    if (action == NewsFabAction.summarize) {
      target = target
          .where((a) => !kNoSummarizeCategories.contains(a.category))
          .toList(growable: false);
    }

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

  /// Swipe-to-delete handler used by Movies/General list rows.
  ///
  /// Semantics:
  ///   • Local DB is mutated first (mark as read) so the row disappears
  ///     instantly — the Drift stream rebuilds the feed within one frame.
  ///   • Article follow-up chat state is wiped (mirrors the Saved-tab
  ///     `onRemove` contract).
  ///   • All work is wrapped in [_runWithRetry] so a transient local-DB
  ///     failure (very rare — main-thread SQLite contention) gets one quiet
  ///     retry before we surface the error to the user.
  ///   • Successes are logged at info, failures at error. Both flow through
  ///     the production [TLog] pipeline (batched + exponential-backoff
  ///     Telegram delivery). Error logs are flushed immediately.
  ///
  /// The remote leg (already-built `markRead` repo API) is best-effort and
  /// fire-and-forget — the user-visible UX never blocks on the network.
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
          await ref.read(newsControllerProvider.notifier).markRead(id);
        },
      );
      ArticleFollowUpStore.instance.clear(id);
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          duration: const Duration(milliseconds: 1600),
          backgroundColor: const Color(0xFF34D399),
        ),
      );
  }

  /// Trim noisy titles so logs stay compact (Telegram has hard limits and
  /// our batches go through the chunker — keeping each line short means
  /// more entries fit per chunk).
  String _safeTitle(String s) =>
      s.length <= 60 ? s : '${s.substring(0, 57)}…';

  Future<void> _openSummaryReader(List<Article> articles) async {
    final service = ref.read(newsSummarizeServiceProvider);
    final repo = ref.read(newsRepositoryProvider);
    final liteModel = ref.read(settingsProvider).liteModel;

    NewsSummarizeStore.instance.start(
      articles: articles,
      service: service,
      repository: repo,
      liteModel: liteModel,
    );

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SummaryReaderScreen(articles: articles),
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
    final scopeLabel =
        categories.length == 1 ? categories.first : null;

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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
    final notifications = _buildNotifications(allArticles);
    final unreadNotifCount = notifications.where((n) => !n.read).length;

    // All unread+unsaved articles regardless of category. Drives the
    // per-category chip (Movies / General etc.) and the notification panel
    // so those tabs always reflect the true article pool.
    final unreadUnsaved =
        allArticles.where((a) => !a.isRead && !a.isSaved).toList();

    // The "All" chip + FAB "summarize-all" scope deliberately EXCLUDE the
    // no-summarize categories (Movies, General). Those feeds carry the
    // FULL article body — the catch-up summarize flow is designed for
    // AI-condensed pieces, and the user explicitly asked for them to be
    // segregated from the "All" pile.
    final unfilteredFeed = unreadUnsaved
        .where((a) => !kNoSummarizeCategories.contains(a.category))
        .toList(growable: false);

    final List<Article> feed = _category == 'All'
        ? unfilteredFeed
        : unreadUnsaved.where((a) => a.category == _category).toList();
    final featured = feed.isEmpty ? null : feed.first;
    final featuredArticle = featured;
    final rest = featuredArticle == null
        ? feed
        : feed.where((a) => a.id != featuredArticle.id).toList();

    final savedArticles = allArticles.where((a) => a.isSaved).toList();
    final q = _savedSearch.trim().toLowerCase();
    final filteredSaved = q.isEmpty
        ? savedArticles
        : savedArticles
            .where(
              (a) =>
                  a.title.toLowerCase().contains(q) ||
                  a.category.toLowerCase().contains(q) ||
                  a.source.toLowerCase().contains(q),
            )
            .toList();

    return Column(
      children: [
        CompactHeader(
          title: 'News',
          actionIcon: LucideIcons.bell,
          actionBadgeCount:
              (!_notifSeen && unreadNotifCount > 0) ? unreadNotifCount : null,
          onAvatarTap: () => showSettingsModal(context, ref),
          onActionTap: () => setState(() {
            _showNotif = true;
            _notifSeen = true;
          }),
        ),
        Material(
          color: colors.headerBg,
          child: TabBar(
            controller: _tabCtrl,
            indicatorColor:
                colors.isDark ? const Color(0xFF818CF8) : AppColors.accent,
            indicatorWeight: 2,
            labelColor: colors.text,
            unselectedLabelColor: colors.text3,
            dividerColor: colors.border,
            labelStyle: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              const Tab(text: 'For You'),
              Tab(
                text: savedArticles.isEmpty
                    ? 'Saved'
                    : 'Saved (${savedArticles.length})',
              ),
            ],
          ),
        ),
        Expanded(
          child: PopScope(
            canPop: !_showNotif,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _showNotif) {
                setState(() => _showNotif = false);
              }
            },
            child: Stack(
              children: [
                ColoredBox(
                  color: colors.bg,
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _ForYouTab(
                        colors: colors,
                        category: _category,
                        onCategory: (c) => setState(() => _category = c),
                        featured: featuredArticle,
                        rest: rest,
                        loading: newsState.isLoading && allArticles.isEmpty,
                        hasError: newsState.hasError && allArticles.isEmpty,
                        feedEmpty: feed.isEmpty,
                        onRefresh: _handleRefresh,
                        onOpen: _openArticle,
                        unreadCountAll: unfilteredFeed.length,
                        unreadCountInCategory: feed.length,
                        // Movies / General chips swap to the clearOnly FAB
                        // (single "Clear All" action, no Summarize, no
                        // scope toggle) AND enable per-row swipe-delete.
                        // Driven off `kNoSummarizeCategories` so the same
                        // declarative set governs every place we treat
                        // these feeds specially.
                        clearOnly:
                            kNoSummarizeCategories.contains(_category),
                        onSwipeDelete: _deleteArticle,
                        onFabAction: (action, scope) => _handleFabAction(
                          action: action,
                          scope: scope,
                          unfilteredFeed: unfilteredFeed,
                          filteredFeed: feed,
                        ),
                        // The pill showing "Catch-up summary ready" is
                        // driven by the singleton store and rebuilt via
                        // [_summarizeListener] above. We use the
                        // RELEVANCE-aware check ([hasRelevantSession]) so
                        // the pill auto-hides if the user has marked all
                        // of the session's articles as read by some other
                        // path (article-detail modal mark-read, multi-
                        // device sync, etc.) — without that check, the
                        // pill would stay even when "No articles in this
                        // category" is showing below it.
                        activeSummaryProgress: NewsSummarizeStore.instance
                                .hasRelevantSession({
                          for (final a in unfilteredFeed) a.id,
                        })
                            ? NewsSummarizeStore.instance.progress
                            : null,
                        onResumeSummary: _reopenReaderForActiveSession,
                      ),
                      _SavedTab(
                        colors: colors,
                        searchController: _savedSearchCtrl,
                        search: _savedSearch,
                        onSearch: (s) => setState(() => _savedSearch = s),
                        savedEmpty: savedArticles.isEmpty,
                        filteredEmpty:
                            filteredSaved.isEmpty && savedArticles.isNotEmpty,
                        articles: filteredSaved,
                        onRefresh: _handleRefresh,
                        onOpen: _openArticle,
                        onRemove: (id) {
                          ref
                              .read(newsControllerProvider.notifier)
                              .toggleSaved(id);
                          ref
                              .read(newsControllerProvider.notifier)
                              .markRead(id);
                          ArticleFollowUpStore.instance.clear(id);
                        },
                      ),
                    ],
                  ),
                ),
                if (_showNotif) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _showNotif = false),
                      behavior: HitTestBehavior.opaque,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  _NotificationPanel(
                    notifications: notifications,
                    colors: colors,
                    onClose: () => setState(() => _showNotif = false),
                    onClearAll: () {
                      setState(() {
                        for (final n in notifications) {
                          _dismissedNotifIds.add(n.articleId);
                        }
                        _showNotif = false;
                      });
                    },
                    onOpenArticle: (id) {
                      Article? art;
                      for (final article in allArticles) {
                        if (article.id == id) {
                          art = article;
                          break;
                        }
                      }
                      if (art != null) {
                        _openArticle(art);
                      }
                      setState(() => _showNotif = false);
                    },
                  ),
                ],
              ],
            ),
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
    required this.onCategory,
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
    required this.clearOnly,
    required this.onSwipeDelete,
  });

  final AppColors colors;
  final String category;
  final ValueChanged<String> onCategory;
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

  /// `true` when the active chip is in `kNoSummarizeCategories` (Movies
  /// or General). Drives both the FAB layout (clear-only mode) and the
  /// per-row swipe-to-delete affordance.
  final bool clearOnly;

  /// Per-article delete handler — invoked from the swipe-to-delete
  /// affordance on Movies/General rows. Hosted by the parent screen so
  /// it can run with retry + Telegram logging + show snackbars.
  final ValueChanged<Article> onSwipeDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: onRefresh,
          color: AppColors.accent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            children: [
          if (activeSummaryProgress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _SummaryRunningPill(
                colors: colors,
                progress: activeSummaryProgress!,
                onTap: onResumeSummary,
              ),
            ),
          if (featured != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: clearOnly
                  ? SwipeToDelete(
                      key: ValueKey<String>('swipe-featured-${featured!.id}'),
                      onDelete: () => onSwipeDelete(featured!),
                      borderRadius: 24,
                      contentHeight: 280,
                      child: _FeaturedCard(
                        article: featured!,
                        colors: colors,
                        onTap: () => onOpen(featured!),
                      ),
                    )
                  : _FeaturedCard(
                      article: featured!,
                      colors: colors,
                      onTap: () => onOpen(featured!),
                    ),
            ),
          ],
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _Chip(
                  label: 'All',
                  selected: category == 'All',
                  colors: colors,
                  onTap: () => onCategory('All'),
                ),
                ...CATEGORIES.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _Chip(
                      label: c,
                      selected: category == c,
                      colors: colors,
                      onTap: () => onCategory(c),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 72),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                ),
              ),
            )
          else if (hasError)
            Padding(
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
                ],
              ),
            )
          else if (feedEmpty)
            Padding(
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
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < rest.length; i++)
                    if (clearOnly)
                      SwipeToDelete(
                        key: ValueKey<String>('swipe-row-${rest[i].id}'),
                        onDelete: () => onSwipeDelete(rest[i]),
                        child: _NewsListCard(
                          article: rest[i],
                          colors: colors,
                          onTap: () => onOpen(rest[i]),
                        ),
                      )
                    else
                      _NewsListCard(
                        article: rest[i],
                        colors: colors,
                        onTap: () => onOpen(rest[i]),
                      ),
                ],
              ),
            ),
          ],
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: NewsActionFab(
              colors: colors,
              unreadCount: unreadCountAll,
              unreadCountInCategory: unreadCountInCategory,
              activeCategory: category,
              clearOnly: clearOnly,
              onAction: onFabAction,
            ),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          height: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withValues(alpha: colors.isDark ? 0.45 : 0.2),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (article.imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: article.imageUrl,
                    fit: BoxFit.cover,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cat.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: cat.withValues(alpha: 0.3)),
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
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? (colors.isDark ? Colors.white : const Color(0xFF0F172A))
        : colors.bg2;
    final border = selected
        ? (colors.isDark ? Colors.white : const Color(0xFF0F172A))
        : colors.border;
    final fg =
        selected ? (colors.isDark ? Colors.black : Colors.white) : colors.text2;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
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
                        color: colors.text,
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
  }
}

class _SavedTab extends StatelessWidget {
  const _SavedTab({
    required this.colors,
    required this.searchController,
    required this.search,
    required this.onSearch,
    required this.savedEmpty,
    required this.filteredEmpty,
    required this.articles,
    required this.onRefresh,
    required this.onOpen,
    required this.onRemove,
  });

  final AppColors colors;
  final TextEditingController searchController;
  final String search;
  final ValueChanged<String> onSearch;
  final bool savedEmpty;
  final bool filteredEmpty;
  final List<Article> articles;
  final Future<void> Function() onRefresh;
  final ValueChanged<Article> onOpen;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SavedSearchField(
            colors: colors,
            controller: searchController,
            value: search,
            onChanged: onSearch,
          ),
          const SizedBox(height: 12),
          if (savedEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  Icon(LucideIcons.bookmark, size: 42, color: colors.text5),
                  const SizedBox(height: 12),
                  Text(
                    'No saved articles yet',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.text4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Open an article and tap Save to read it later',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: colors.text5,
                    ),
                  ),
                ],
              ),
            )
          else if (filteredEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Column(
                children: [
                  Icon(LucideIcons.search, size: 28, color: colors.text5),
                  const SizedBox(height: 8),
                  Text(
                    'No results for "$search"',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: colors.text4,
                    ),
                  ),
                ],
              ),
            )
          else
            ...articles.map(
              (a) => _SavedRow(
                article: a,
                colors: colors,
                query: search.trim(),
                onOpen: () => onOpen(a),
                onRemove: () => onRemove(a.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _SavedSearchField extends StatelessWidget {
  const _SavedSearchField({
    required this.colors,
    required this.controller,
    required this.value,
    required this.onChanged,
  });

  final AppColors colors;
  final TextEditingController controller;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = value.isNotEmpty;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? const Color(0xFFA78BFA).withValues(alpha: 0.55)
              : colors.border,
          width: 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.search,
            size: 15,
            color: active ? const Color(0xFFA78BFA) : colors.text4,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 14, color: colors.text),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search saved articles…',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: colors.text4,
                ),
              ),
            ),
          ),
          if (active)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
              icon: Icon(LucideIcons.x, size: 15, color: colors.text4),
            ),
        ],
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.article,
    required this.colors,
    required this.query,
    required this.onOpen,
    required this.onRemove,
  });

  final Article article;
  final AppColors colors;
  final String query;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cat = newsCategoryColor(article.category);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: CachedNetworkImage(
                    imageUrl: article.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: colors.bg2),
                    errorWidget: (_, __, ___) => Container(color: colors.bg2),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _HighlightTitle(
                            text: article.title,
                            query: query,
                            cat: cat,
                            colors: colors,
                          ),
                        ),
                        Material(
                          color: const Color(0x1AEF4444),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: onRemove,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0x33EF4444),
                                ),
                              ),
                              child: const Icon(
                                LucideIcons.trash2,
                                size: 12,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cat.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            article.category,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: cat,
                            ),
                          ),
                        ),
                        Text(
                          '${article.source} · ${article.date}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: colors.text4,
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
  }
}

class _HighlightTitle extends StatelessWidget {
  const _HighlightTitle({
    required this.text,
    required this.query,
    required this.cat,
    required this.colors,
  });

  final String text;
  final String query;
  final Color cat;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: colors.text,
        ),
      );
    }
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      return Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: colors.text,
        ),
      );
    }
    return Text.rich(
      TextSpan(
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: colors.text,
        ),
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: TextStyle(
              backgroundColor: cat.withValues(alpha: 0.22),
              color: cat,
            ),
          ),
          TextSpan(text: text.substring(idx + query.length)),
        ],
      ),
    );
  }
}

class _NotificationPanel extends StatefulWidget {
  const _NotificationPanel({
    required this.notifications,
    required this.colors,
    required this.onClose,
    required this.onClearAll,
    required this.onOpenArticle,
  });

  final List<_NewsNotif> notifications;
  final AppColors colors;
  final VoidCallback onClose;
  final VoidCallback onClearAll;
  final ValueChanged<String> onOpenArticle;

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _slide;

  List<_NewsNotif> get notifications => widget.notifications;
  AppColors get colors => widget.colors;
  VoidCallback get onClose => widget.onClose;
  VoidCallback get onClearAll => widget.onClearAll;
  ValueChanged<String> get onOpenArticle => widget.onOpenArticle;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: colors.isDark ? const Color(0xFF080808) : colors.bg1,
          elevation: 8,
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.65,
            ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border2)),
                ),
                child: Row(
                  children: [
                    Text(
                      'Notifications',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                      ),
                    ),
                    const Spacer(),
                    if (notifications.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: onClearAll,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: Text(
                                'Clear all',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Material(
                      color: colors.bg3,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: onClose,
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: Icon(LucideIcons.x,
                              size: 14, color: colors.text3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: notifications.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 40,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  LucideIcons.bellOff,
                                  size: 34,
                                  color: colors.text4,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No new article alerts yet',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: colors.text4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]
                      : [
                          for (final n in notifications)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => onOpenArticle(n.articleId),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                        bottom:
                                            BorderSide(color: colors.border2)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        margin: const EdgeInsets.only(top: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              n.color.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: n.color
                                                  .withValues(alpha: 0.18)),
                                        ),
                                        child: Icon(n.icon,
                                            size: 15, color: n.color),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              n.title,
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                fontSize: 13,
                                                fontWeight: n.read
                                                    ? FontWeight.w500
                                                    : FontWeight.w700,
                                                height: 1.4,
                                                color: n.read
                                                    ? colors.text3
                                                    : colors.text,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              n.time,
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                fontSize: 11,
                                                color: colors.text5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!n.read)
                                        Container(
                                          width: 7,
                                          height: 7,
                                          margin: const EdgeInsets.only(top: 6),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: n.color,
                                            boxShadow: [
                                              BoxShadow(
                                                color: n.color
                                                    .withValues(alpha: 0.6),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
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
// Clear-All confirmation bottom sheet
// ─────────────────────────────────────────────────────────────────────────

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
        : '$count article${count == 1 ? '' : 's'} will be marked as read and disappear from For You. Saved articles are not affected.';
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
              color: Colors.black.withValues(alpha: 0.4),
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
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
                          isComplete
                              ? LucideIcons.check
                              : LucideIcons.sparkles,
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
      ),
    );
  }
}
