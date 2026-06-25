import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/on_demand_summarize_store.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/article_tts_service.dart';
import '../../../domain/entities/news_entities.dart';
import '../../widgets/wave_visualizer.dart';
import '../settings/settings_controller.dart';
import 'article_followup_sheet.dart';
import 'news_screen.dart' show newsCategoryIcon;
import 'widgets/news_summary_view.dart';

/// Which body the article detail is currently showing.
enum _ArticleView { full, summary }

/// Renders an inline article image (`![alt](src)`) from the full-content
/// markdown: cached, rounded, full-width, with a graceful placeholder and a
/// silent collapse on error so a single dead image URL never leaves an ugly
/// broken-image box in the middle of the prose.
class _MarkdownArticleImage extends StatelessWidget {
  const _MarkdownArticleImage({required this.uri, required this.colors});

  final Uri uri;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final src = uri.toString();
    if (src.isEmpty || !(src.startsWith('http://') || src.startsWith('https://'))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: src,
            // fitWidth = fill the column width and let height follow the
            // image's natural aspect ratio. No fixed height → no cropping
            // and no overflow regardless of the source image dimensions.
            fit: BoxFit.fitWidth,
            width: double.infinity,
            placeholder: (_, __) => Container(
              height: 180,
              color: colors.bg2,
              child: Center(
                child: Icon(
                  LucideIcons.image,
                  size: 28,
                  color: colors.text5,
                ),
              ),
            ),
            // A dead inline image should vanish, not show a broken-image glyph.
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

Color newsCategoryColor(String category) {
  final hex = CAT_COLOR[category] ?? '#818CF8';
  final value = hex.replaceFirst('#', '');
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return const Color(0xFF818CF8);
  return Color(parsed + 0xFF000000);
}

/// Articles in [kNoSummarizeCategories] (Movies, General) ship the FULL
/// original article body — no AI summary. We render them with a slightly
/// larger, more "article-reader" oriented typography so long-form reading
/// is comfortable on mobile. AI-summarized pieces continue to use the
/// compact dashboard styling.
bool _isFullContentArticle(Article article) =>
    kNoSummarizeCategories.contains(article.category);

/// Full-screen article detail (open with [Navigator.push]).
class ArticleDetailModal extends ConsumerStatefulWidget {
  const ArticleDetailModal({
    super.key,
    required this.article,
    required this.onToggleSave,
    required this.onMarkRead,
  });

  final Article article;
  final ValueChanged<bool> onToggleSave;
  final VoidCallback onMarkRead;

  @override
  ConsumerState<ArticleDetailModal> createState() => _ArticleDetailModalState();
}

class _ArticleDetailModalState extends ConsumerState<ArticleDetailModal> {
  late bool _saved;
  late bool _read;
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false;
  late final ArticleTtsService _tts;

  /// On-demand AI summary state. [_summaryText] is seeded from the article's
  /// cached [Article.summaryShort] (populated either by a previous tap here
  /// or by the For You batch flow) so re-opening never re-spends AI.
  _ArticleView _view = _ArticleView.full;
  String? _summaryText;
  bool _summarizing = false;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _saved = widget.article.isSaved;
    _read = widget.article.isRead;
    final cached = widget.article.summaryShort?.trim();
    _summaryText = (cached != null && cached.isNotEmpty) ? cached : null;
    _scroll.addListener(_onScroll);
    _tts = ArticleTtsService();

    // Re-attach to any background summarize already running / finished for
    // this article (e.g. the user tapped Summarize, minimised the app, and
    // re-opened the reader). The store is the source of truth across the
    // widget lifecycle, so we hydrate from it and subscribe for updates.
    OnDemandSummarizeStore.instance
        .addListener(widget.article.id, _onSummaryStoreUpdate);
    _onSummaryStoreUpdate();
  }

  /// Pulls the latest background-summarize state for this article and folds it
  /// into the local view state. Runs on every store transition (loading →
  /// ready / error) so the UI stays live even if the work finished while the
  /// modal was closed and re-opened.
  void _onSummaryStoreUpdate() {
    final s = OnDemandSummarizeStore.instance.stateOf(widget.article.id);
    switch (s.status) {
      case OnDemandStatus.loading:
        if (!mounted) return;
        setState(() {
          _summarizing = true;
          _summaryError = null;
          if (_view == _ArticleView.full && !_hasSummary) {
            _view = _ArticleView.summary;
          }
        });
        break;
      case OnDemandStatus.ready:
        final summary = s.summary?.trim();
        if (summary == null || summary.isEmpty) return;
        if (!mounted) return;
        setState(() {
          _summaryText = summary;
          _summarizing = false;
          _summaryError = null;
        });
        break;
      case OnDemandStatus.error:
        if (!mounted) return;
        setState(() {
          _summarizing = false;
          _summaryError = s.error ??
              'Could not summarize this article right now. Please try again.';
        });
        break;
      case OnDemandStatus.idle:
        break;
    }
  }

  /// `true` when this article ships the full original body and should default
  /// to the interactive reader with AI summarization offered on demand.
  /// Combines the backend-driven [Article.isFullContent] flag with the
  /// pre-existing Movies/General category check so behaviour is unchanged for
  /// articles created before the flag existed (and for the widget tests).
  bool get _showFullContent =>
      widget.article.isFullContent || _isFullContentArticle(widget.article);

  bool get _hasSummary => (_summaryText?.trim().isNotEmpty ?? false);

  /// Generates (or reveals a cached) AI summary on demand and switches the
  /// body to the summary view. Cheap path first: if we already hold a cached
  /// summary we just toggle — zero AI cost.
  /// Generates (or reveals a cached) AI summary on demand and switches the
  /// body to the summary view.
  ///
  /// Cheap path first: a cached summary just toggles (zero AI cost). Otherwise
  /// the work is handed to [OnDemandSummarizeStore], which runs it under a
  /// foreground service so it survives the app being minimised and persists
  /// the result even if this modal is closed mid-flight. UI state is driven
  /// back via [_onSummaryStoreUpdate].
  Future<void> _onSummarize() async {
    if (_summarizing) return;

    if (_hasSummary) {
      setState(() => _view = _ArticleView.summary);
      return;
    }

    setState(() {
      _summarizing = true;
      _summaryError = null;
      _view = _ArticleView.summary;
    });

    final store = OnDemandSummarizeStore.instance
      ..init(
        ref.read(newsSummarizeServiceProvider),
        ref.read(newsRepositoryProvider),
      );
    final liteModel = ref.read(settingsProvider).liteModel;
    TLog.i('ArticleDetail', 'On-demand summarize requested id=${widget.article.id}');
    store.summarize(article: widget.article, liteModel: liteModel);
  }

  void _onRetrySummarize() {
    if (_summarizing) return;
    setState(() {
      _summarizing = true;
      _summaryError = null;
      _view = _ArticleView.summary;
    });
    OnDemandSummarizeStore.instance
      ..init(
        ref.read(newsSummarizeServiceProvider),
        ref.read(newsRepositoryProvider),
      )
      ..summarize(
        article: widget.article,
        liteModel: ref.read(settingsProvider).liteModel,
      );
  }

  void _showFull() => setState(() => _view = _ArticleView.full);

  @override
  void dispose() {
    OnDemandSummarizeStore.instance
        .removeListener(widget.article.id, _onSummaryStoreUpdate);
    _tts.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final next = _scroll.offset > 140;
    if (next != _scrolled) setState(() => _scrolled = next);
  }

  Future<void> _share() async {
    final originalUrl = widget.article.originalUrl;
    final text = [
      widget.article.title,
      widget.article.excerpt,
      '— ${widget.article.source}',
      if (originalUrl != null && originalUrl.isNotEmpty) originalUrl,
    ].join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied to clipboard',
          style: GoogleFonts.plusJakartaSans(color: Colors.white),
        ),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleSave() {
    final newValue = !_saved;
    setState(() => _saved = newValue);
    widget.onToggleSave(newValue);
    if (!newValue) {
      ArticleFollowUpStore.instance.clear(widget.article.id);
    }
    if (newValue) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  void _markRead() {
    if (_read) return;
    setState(() => _read = true);
    widget.onMarkRead();
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _openOriginalLink() async {
    final rawUrl = widget.article.originalUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open source link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final cat = newsCategoryColor(widget.article.category);
    final summaryMarkdown = widget.article.summaryMarkdown?.trim();
    // Detect the server's "couldn't summarise" sentinel
    // (`<!-- summary-unavailable -->`). When present, we render a
    // single clean banner instead of trying to display the title
    // twice + an "Article Preview" header + the raw RSS excerpt —
    // that combination is what made the news tab look broken in
    // the user-reported screenshot.
    final isSummaryUnavailable = summaryMarkdown != null &&
        summaryMarkdown.contains('<!-- summary-unavailable -->');
    final hasSummaryMarkdown = summaryMarkdown != null &&
        summaryMarkdown.isNotEmpty &&
        !isSummaryUnavailable;
    final originalUrl = widget.article.originalUrl;
    final hasOriginalUrl = originalUrl != null && originalUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                  child: _HeroImage(article: widget.article, cat: cat)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _MetaRow(article: widget.article, cat: cat, colors: colors),
                    const SizedBox(height: 16),
                    Text(
                      widget.article.title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.27,
                        letterSpacing: -0.5,
                        color: colors.text,
                      ),
                    ),
                    if (widget.article.excerpt.isNotEmpty &&
                        widget.article.excerpt != 'New article available.') ...[
                      const SizedBox(height: 18),
                      Text(
                        widget.article.excerpt,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          height: 1.72,
                          color: colors.text3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Divider(height: 1, color: colors.border),
                    const SizedBox(height: 20),
                    _TtsPlayerBar(
                      ttsService: _tts,
                      article: widget.article,
                      accentColor: cat,
                      colors: colors,
                      isFullContent: _showFullContent,
                    ),
                    const SizedBox(height: 20),
                    if (_showFullContent) ...[
                      // Full-content articles render the original body in the
                      // interactive reader by default and offer AI
                      // summarization as an explicit, cached, on-demand action.
                      _SummarizeToggleBar(
                        view: _view,
                        summarizing: _summarizing,
                        hasSummary: _hasSummary,
                        cat: cat,
                        colors: colors,
                        onSummarize: _onSummarize,
                        onShowFull: _showFull,
                      ),
                      const SizedBox(height: 18),
                      if (_view == _ArticleView.summary)
                        _OnDemandSummarySection(
                          summarizing: _summarizing,
                          error: _summaryError,
                          summary: _summaryText,
                          cat: cat,
                          colors: colors,
                          onRetry: _onRetrySummarize,
                        )
                      else if (hasSummaryMarkdown)
                        _SummaryMarkdown(
                          summary: summaryMarkdown,
                          cat: cat,
                          colors: colors,
                          isFullArticle: true,
                        )
                      else
                        _BlockList(
                          blocks: widget.article.blocks,
                          cat: cat,
                          colors: colors,
                        ),
                    ] else if (hasSummaryMarkdown)
                      _SummaryMarkdown(
                        summary: summaryMarkdown,
                        cat: cat,
                        colors: colors,
                        isFullArticle: _isFullContentArticle(widget.article),
                      )
                    else if (isSummaryUnavailable)
                      _SummaryUnavailableBanner(colors: colors, cat: cat)
                    else
                      _BlockList(
                          blocks: widget.article.blocks,
                          cat: cat,
                          colors: colors),
                    const SizedBox(height: 32),
                    if (hasOriginalUrl)
                      GestureDetector(
                        onTap: _openOriginalLink,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: cat.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: cat.withValues(alpha: 0.14)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: cat.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(LucideIcons.externalLink,
                                    size: 18, color: cat),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Read Original Article',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: colors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.article.source,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: colors.text4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(LucideIcons.arrowUpRight,
                                  size: 18, color: cat),
                            ],
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          ),
          if (_scrolled)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.fromLTRB(
                    16, MediaQuery.paddingOf(context).top + 10, 16, 10),
                decoration: BoxDecoration(
                  color: colors.headerBg.withValues(alpha: 0.94),
                  border: Border(
                    bottom: BorderSide(color: colors.border),
                  ),
                ),
                child: Text(
                  widget.article.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 20,
            bottom: MediaQuery.paddingOf(context).bottom + 80,
            child: ArticleFollowUpFab(
              articleId: widget.article.id,
              articleTitle: widget.article.title,
              articleUrl: widget.article.originalUrl,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              colors: colors,
              saved: _saved,
              read: _read,
              onShare: _share,
              onToggleSave: _toggleSave,
              onMarkRead: _markRead,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean, single-card banner shown when the backend wasn't able to
/// produce an AI summary for this article (e.g. configured Gemini
/// model id doesn't exist, rate-limited, blocked by safety filter).
///
/// Replaces the previous behaviour where the fallback markdown
/// (`# title / ## Article Preview / <RSS excerpt>`) was rendered
/// verbatim — that path looked broken because the title was already
/// shown above and the "Article Preview" header had no visual
/// affordance to communicate "this is a failure state, not your
/// summary".
class _SummaryUnavailableBanner extends StatelessWidget {
  const _SummaryUnavailableBanner({required this.colors, required this.cat});

  final AppColors colors;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cat.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.fileWarning, size: 18, color: cat),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI summary unavailable',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'We couldn\'t generate a summary for this article. '
                  'Tap "Read Original Article" below to view the full piece.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.5,
                    color: colors.text3,
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

class _SummaryMarkdown extends StatelessWidget {
  const _SummaryMarkdown({
    required this.summary,
    required this.cat,
    required this.colors,
    this.isFullArticle = false,
  });

  final String summary;
  final Color cat;
  final AppColors colors;

  /// Renders with newspaper-grade typography: serif body text, larger
  /// font, generous line-height, wider paragraph spacing, and a subtle
  /// drop-cap on the very first paragraph. Used for the Movies / General
  /// categories which ship the full original article body.
  final bool isFullArticle;

  @override
  Widget build(BuildContext context) {
    if (isFullArticle) {
      return _FullArticleBody(
        markdown: summary,
        cat: cat,
        colors: colors,
      );
    }
    return SelectionArea(
      child: MarkdownBody(
        data: summary,
        selectable: false,
        sizedImageBuilder: (config) =>
            _MarkdownArticleImage(uri: config.uri, colors: colors),
        onTapLink: (text, href, title) async {
          if (href == null || href.isEmpty) return;
          final uri = Uri.tryParse(href);
          if (uri == null) return;
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (e) {
            TLog.w('ArticleDetail', 'Failed to open link: $href', error: e);
          }
        },
        styleSheet: MarkdownStyleSheet(
          p: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            height: 1.82,
            color: colors.text2,
          ),
          pPadding: const EdgeInsets.only(bottom: 8),
          h1: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.3,
            color: colors.text,
          ),
          h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
          h2: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.35,
            color: colors.text,
          ),
          h2Padding: const EdgeInsets.only(top: 20, bottom: 6),
          h3: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.4,
            color: colors.text,
          ),
          h3Padding: const EdgeInsets.only(top: 14, bottom: 4),
          strong: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
          em: GoogleFonts.plusJakartaSans(
            fontStyle: FontStyle.italic,
            color: colors.text3,
          ),
          blockquote: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontStyle: FontStyle.italic,
            height: 1.72,
            color: colors.text,
          ),
          blockquoteDecoration: BoxDecoration(
            color: cat.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(color: cat, width: 3),
            ),
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          listBullet: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: cat,
          ),
          listBulletPadding: const EdgeInsets.only(right: 8),
          listIndent: 22,
          tableHead: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
          tableBody: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            height: 1.6,
            color: colors.text2,
          ),
          tableBorder: TableBorder.all(
            color: colors.border,
            borderRadius: BorderRadius.circular(8),
          ),
          tableHeadAlign: TextAlign.left,
          tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          tableColumnWidth: const FlexColumnWidth(),
          code: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            color: cat,
            backgroundColor: colors.bg2,
          ),
          codeblockDecoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          codeblockPadding: const EdgeInsets.all(14),
          a: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: cat,
            decoration: TextDecoration.underline,
            decorationColor: cat.withValues(alpha: 0.4),
          ),
          horizontalRuleDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colors.border,
                width: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Full-article reader
//
// Renders the deep-extracted article body (used by Movies + General feeds)
// with newspaper-grade typography: serif body text, larger size, generous
// 1.78 line-height, wider paragraph spacing, and a discreet drop-cap on
// the lead paragraph. The same markdown content goes through Flutter's
// MarkdownBody — only the StyleSheet differs from the dashboard `_SummaryMarkdown`
// path.
//
// A small "Original full article" pill is shown above the body so the
// reader has an immediate signal that they're looking at the source piece
// (not an AI summary). The pill also subtly explains why the typography
// is different from the AI-summary articles in the rest of the app.
// ─────────────────────────────────────────────────────────────────────────

/// Parsed review meta block (Gizbot). Stable shape guaranteed by
/// `buildReviewMetaMarkdown` on the backend:
///
///     **⭐ Rating: 4.8 / 5**
///
///     #### ✅ Pros
///     - …
///
///     #### ❌ Cons
///     - …
///
///     ---
///
/// We strip the block from the markdown body and render it as a rich,
/// color-coded card above the prose for a much better mobile UX than
/// raw bullets. When `_ReviewMeta.tryParse` returns null, the article
/// has no structured meta and the body renders unchanged.
@immutable
class _ReviewMeta {
  const _ReviewMeta({
    required this.rating,
    required this.pros,
    required this.cons,
    required this.bodyAfter,
  });

  final String rating; // raw, may include "/ 5" or just "4.8"
  final List<String> pros;
  final List<String> cons;

  /// The markdown body with the meta block removed — what the standard
  /// `MarkdownBody` should render below the card.
  final String bodyAfter;

  bool get isEmpty => rating.isEmpty && pros.isEmpty && cons.isEmpty;

  static _ReviewMeta? tryParse(String markdown) {
    // Detection sentinel — the literal phrase the backend emits as the
    // FIRST line of the meta header. Anything else (regular article body,
    // empty-content fallback prose, etc.) leaves the markdown untouched.
    final ratingRx = RegExp(r'^\*\*⭐\s*Rating:\s*([^*]+?)\*\*');
    final firstLine = markdown.trimLeft();
    final m = ratingRx.firstMatch(firstLine);
    if (m == null) return null;

    // The meta block always ends with a standalone `---` on its own
    // line, followed by a blank line, then the body. If we can't find
    // that separator within the first ~1200 chars (the meta block is
    // small by construction), give up to avoid mis-parsing — `---` is
    // also used elsewhere as a section break.
    final searchSlice = markdown.substring(0, markdown.length.clamp(0, 1500));
    final sepRx = RegExp(r'\n\s*---\s*\n');
    final sepMatch = sepRx.firstMatch(searchSlice);
    if (sepMatch == null) return null;

    final header = markdown.substring(0, sepMatch.start);
    final bodyAfter = markdown.substring(sepMatch.end).trimLeft();

    final rating = m.group(1)?.trim() ?? '';

    List<String> collectAfterHeading(RegExp headingRx) {
      final lines = header.split('\n');
      final out = <String>[];
      var inSection = false;
      for (final raw in lines) {
        final line = raw.trimRight();
        if (headingRx.hasMatch(line)) {
          inSection = true;
          continue;
        }
        if (inSection) {
          // A new heading at any level OR a blank-then-heading boundary
          // closes the section. We treat any line starting with `####`
          // (the level the backend uses) as a new section.
          if (line.startsWith('#### ')) break;
          final bullet = RegExp(r'^\s*[-*]\s+(.*)$').firstMatch(line);
          if (bullet != null) {
            final text = bullet.group(1)?.trim();
            if (text != null && text.isNotEmpty) out.add(text);
          }
        }
      }
      return out;
    }

    final pros = collectAfterHeading(RegExp(r'^####\s*✅\s*Pros\b'));
    final cons = collectAfterHeading(RegExp(r'^####\s*❌\s*Cons\b'));

    final meta = _ReviewMeta(
      rating: rating,
      pros: pros,
      cons: cons,
      bodyAfter: bodyAfter,
    );
    if (meta.isEmpty) return null;
    return meta;
  }
}

// ---------------------------------------------------------------------------
// On-demand AI summarize controls
//
// Full-content articles show their original body by default. The user can
// tap "AI Summarize" to generate (once, then cached) a quick summary and
// toggle between the two views. This keeps AI spend explicit and minimal.
// ---------------------------------------------------------------------------

class _SummarizeToggleBar extends StatelessWidget {
  const _SummarizeToggleBar({
    required this.view,
    required this.summarizing,
    required this.hasSummary,
    required this.cat,
    required this.colors,
    required this.onSummarize,
    required this.onShowFull,
  });

  final _ArticleView view;
  final bool summarizing;
  final bool hasSummary;
  final Color cat;
  final AppColors colors;
  final VoidCallback onSummarize;
  final VoidCallback onShowFull;

  @override
  Widget build(BuildContext context) {
    // First-run call-to-action: no summary exists yet and nothing is in
    // flight — show a single prominent "AI Summarize" button.
    if (!hasSummary && !summarizing) {
      return _AiSummarizeCta(cat: cat, colors: colors, onTap: onSummarize);
    }

    // Once a summary exists (or is generating), show a segmented toggle so
    // the user can flip between the original article and its summary.
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: 'Article',
              icon: LucideIcons.fileText,
              selected: view == _ArticleView.full,
              cat: cat,
              colors: colors,
              onTap: onShowFull,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegmentButton(
              label: 'AI Summary',
              icon: LucideIcons.sparkles,
              selected: view == _ArticleView.summary,
              busy: summarizing,
              cat: cat,
              colors: colors,
              onTap: onSummarize,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSummarizeCta extends StatelessWidget {
  const _AiSummarizeCta({
    required this.cat,
    required this.colors,
    required this.onTap,
  });

  final Color cat;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.30),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.sparkles,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Summarize',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Condense this article into a quick read',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 18, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.cat,
    required this.colors,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool busy;
  final Color cat;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : colors.text2;
    return Material(
      color: selected ? cat : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: selected ? Colors.white : cat,
                  ),
                )
              else
                Icon(icon, size: 14, color: selected ? Colors.white : colors.text3),
              const SizedBox(width: 7),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnDemandSummarySection extends StatelessWidget {
  const _OnDemandSummarySection({
    required this.summarizing,
    required this.error,
    required this.summary,
    required this.cat,
    required this.colors,
    required this.onRetry,
  });

  final bool summarizing;
  final String? error;
  final String? summary;
  final Color cat;
  final AppColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (summarizing) {
      return _SummaryLoadingCard(cat: cat, colors: colors);
    }
    if (error != null) {
      return _SummaryErrorCard(
        message: error!,
        cat: cat,
        colors: colors,
        onRetry: onRetry,
      );
    }
    final s = summary?.trim();
    if (s == null || s.isEmpty) {
      return _SummaryErrorCard(
        message: 'No summary available yet. Tap to generate one.',
        cat: cat,
        colors: colors,
        onRetry: onRetry,
      );
    }
    return NewsSummaryView(summary: s, colors: colors, cat: cat);
  }
}

/// Premium, fluid loading state for an in-flight AI summary.
///
/// Replaces the old static spinner with a living card: a pulsing gradient
/// "AI orb", a status line that cycles through the phases of the work, and a
/// shimmering skeleton that previews the shape of the summary that's coming.
/// Purely cosmetic + self-contained (single [AnimationController] + one
/// [Timer]); no extra packages.
class _SummaryLoadingCard extends StatefulWidget {
  const _SummaryLoadingCard({required this.cat, required this.colors});

  final Color cat;
  final AppColors colors;

  @override
  State<_SummaryLoadingCard> createState() => _SummaryLoadingCardState();
}

class _SummaryLoadingCardState extends State<_SummaryLoadingCard>
    with SingleTickerProviderStateMixin {
  static const _gradA = Color(0xFF6366F1);
  static const _gradB = Color(0xFFA855F7);
  static const _phases = <String>[
    'Reading the article…',
    'Distilling the key points…',
    'Writing your summary…',
    'Polishing the highlights…',
  ];

  late final AnimationController _c;
  Timer? _phaseTimer;
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _phaseTimer = Timer.periodic(const Duration(milliseconds: 1900), (_) {
      if (!mounted) return;
      setState(() => _phase = (_phase + 1) % _phases.length);
    });
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gradB.withValues(alpha: 0.22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _gradA.withValues(alpha: colors.isDark ? 0.10 : 0.06),
            _gradB.withValues(alpha: colors.isDark ? 0.10 : 0.06),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulsingOrb(anim: _c),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI is summarizing',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _phases[_phase],
                        key: ValueKey<int>(_phase),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.text3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ShimmerLines(anim: _c, colors: colors),
        ],
      ),
    );
  }
}

/// Pulsing, glowing gradient circle with a sparkles glyph. Scale + glow are
/// driven off a sine of the shared controller so the motion feels organic.
class _PulsingOrb extends StatelessWidget {
  const _PulsingOrb({required this.anim});

  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final wave = (math.sin(anim.value * 2 * math.pi) + 1) / 2; // 0..1
        final scale = 1.0 + wave * 0.10;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  _SummaryLoadingCardState._gradA,
                  _SummaryLoadingCardState._gradB,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _SummaryLoadingCardState._gradB
                      .withValues(alpha: 0.25 + wave * 0.30),
                  blurRadius: 14 + wave * 10,
                  spreadRadius: wave * 2,
                ),
              ],
            ),
            child: const Icon(LucideIcons.sparkles,
                size: 20, color: Colors.white),
          ),
        );
      },
    );
  }
}

/// Three skeleton bars with a left-to-right shimmer sweep, previewing the
/// summary layout while it streams in.
class _ShimmerLines extends StatelessWidget {
  const _ShimmerLines({required this.anim, required this.colors});

  final Animation<double> anim;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final base = colors.isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);
    final highlight = colors.isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.13);

    Widget bar(double widthFactor) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: 11,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final pos = anim.value * 2 - 1; // -1 → 1 sweep
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(pos - 0.35, 0),
              end: Alignment(pos + 0.35, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect);
          },
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(1.0),
          const SizedBox(height: 9),
          bar(0.94),
          const SizedBox(height: 9),
          bar(0.66),
        ],
      ),
    );
  }
}

class _SummaryErrorCard extends StatelessWidget {
  const _SummaryErrorCard({
    required this.message,
    required this.cat,
    required this.colors,
    required this.onRetry,
  });

  final String message;
  final Color cat;
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
          const Icon(LucideIcons.alertTriangle,
              size: 16, color: Color(0xFFEF4444)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.refreshCw,
                        size: 11, color: Colors.white),
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

class _FullArticleBody extends StatelessWidget {
  const _FullArticleBody({
    required this.markdown,
    required this.cat,
    required this.colors,
  });

  final String markdown;
  final Color cat;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    // If the article opens with a Gizbot review meta block, strip it out
    // and render it as a rich card above the prose.
    final meta = _ReviewMeta.tryParse(markdown);
    final effectiveMarkdown = meta?.bodyAfter ?? markdown;

    final styleSheet = MarkdownStyleSheet(
      p: GoogleFonts.lora(
        fontSize: 17,
        height: 1.78,
        color: colors.text,
        letterSpacing: 0.1,
      ),
      pPadding: const EdgeInsets.only(bottom: 16),
      h1: GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: -0.4,
        color: colors.text,
      ),
      h1Padding: const EdgeInsets.only(top: 12, bottom: 8),
      h2: GoogleFonts.plusJakartaSans(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: -0.3,
        color: colors.text,
      ),
      h2Padding: const EdgeInsets.only(top: 24, bottom: 10),
      h3: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.35,
        color: colors.text,
      ),
      h3Padding: const EdgeInsets.only(top: 18, bottom: 6),
      strong: GoogleFonts.lora(
        fontWeight: FontWeight.w700,
        color: colors.text,
      ),
      em: GoogleFonts.lora(
        fontStyle: FontStyle.italic,
        color: colors.text2,
      ),
      blockquote: GoogleFonts.lora(
        fontSize: 17,
        fontStyle: FontStyle.italic,
        height: 1.7,
        color: colors.text,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cat.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: cat, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      listBullet: GoogleFonts.lora(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: cat,
      ),
      listBulletPadding: const EdgeInsets.only(right: 8),
      listIndent: 22,
      code: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: cat,
        backgroundColor: colors.bg2,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      a: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: cat,
        decoration: TextDecoration.underline,
        decorationColor: cat.withValues(alpha: 0.45),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border, width: 0.5),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FullArticlePill(cat: cat, colors: colors),
        const SizedBox(height: 18),
        if (meta != null) ...[
          _ReviewMetaCard(meta: meta, cat: cat, colors: colors),
          const SizedBox(height: 22),
        ],
        SelectionArea(
          child: MarkdownBody(
            data: effectiveMarkdown,
            selectable: false,
            sizedImageBuilder: (config) =>
                _MarkdownArticleImage(uri: config.uri, colors: colors),
            onTapLink: (text, href, title) async {
              if (href == null || href.isEmpty) return;
              final uri = Uri.tryParse(href);
              if (uri == null) return;
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                TLog.w('ArticleDetail', 'Failed to open link: $href', error: e);
              }
            },
            styleSheet: styleSheet,
          ),
        ),
      ],
    );
  }
}

/// Color-coded card that fronts a Gizbot review with its overall rating,
/// pros, and cons. Designed to be visually distinct from the surrounding
/// prose so users can size up a review at a glance.
///
/// Layout:
///   • Top-left rating pill (gold accent).
///   • Two-column pros / cons block on tablets / wide screens; stacks
///     vertically on phones (typical case).
///   • Pros card uses an emerald tint with check icons; cons card uses
///     a coral tint with X icons. Both clamp at 8 visible bullets — the
///     backend already enforces the same cap.
class _ReviewMetaCard extends StatelessWidget {
  const _ReviewMetaCard({
    required this.meta,
    required this.cat,
    required this.colors,
  });

  final _ReviewMeta meta;
  final Color cat;
  final AppColors colors;

  static const Color _prosColor = Color(0xFF10B981); // emerald-500
  static const Color _consColor = Color(0xFFEF4444); // red-500

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colors.bg1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (meta.rating.isNotEmpty) _RatingPill(rating: meta.rating, colors: colors),
          if (meta.rating.isNotEmpty &&
              (meta.pros.isNotEmpty || meta.cons.isNotEmpty))
            const SizedBox(height: 14),
          if (meta.pros.isNotEmpty)
            _ProsConsList(
              title: 'Pros',
              items: meta.pros,
              accent: _prosColor,
              icon: LucideIcons.check,
              colors: colors,
            ),
          if (meta.pros.isNotEmpty && meta.cons.isNotEmpty)
            const SizedBox(height: 12),
          if (meta.cons.isNotEmpty)
            _ProsConsList(
              title: 'Cons',
              items: meta.cons,
              accent: _consColor,
              icon: LucideIcons.x,
              colors: colors,
            ),
        ],
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating, required this.colors});

  final String rating;
  final AppColors colors;

  static const Color _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    // Normalise: "4.8" → "4.8 / 5", but keep "4.8 / 5" or text verdicts
    // ("Good", "Excellent") verbatim.
    final hasScale = RegExp(r'/\s*\d').hasMatch(rating);
    final display = hasScale ? rating : '$rating / 5';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _amber.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.star, size: 14, color: _amber),
            const SizedBox(width: 6),
            Text(
              'Rating',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _amber,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              display,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: colors.text,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProsConsList extends StatelessWidget {
  const _ProsConsList({
    required this.title,
    required this.items,
    required this.accent,
    required this.icon,
    required this.colors,
  });

  final String title;
  final List<String> items;
  final Color accent;
  final IconData icon;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          ...items.take(8).map(
                (text) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Icon(icon, size: 11, color: accent),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          text,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            height: 1.5,
                            color: colors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _FullArticlePill extends StatelessWidget {
  const _FullArticlePill({required this.cat, required this.colors});

  final Color cat;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cat.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cat.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bookOpen, size: 12, color: cat),
            const SizedBox(width: 6),
            Text(
              'Original full article',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cat,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.article, required this.cat});

  final Article article;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      width: double.infinity,
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cat.withValues(alpha: 0.15),
                      cat.withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(LucideIcons.newspaper,
                      size: 48, color: cat.withValues(alpha: 0.3)),
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
                    cat.withValues(alpha: 0.15),
                    cat.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Center(
                child: Icon(LucideIcons.newspaper,
                    size: 48, color: cat.withValues(alpha: 0.3)),
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x47000000),
                  Color(0x00000000),
                  Color(0xD1000000),
                  Color(0xFF000000),
                ],
                stops: [0, 0.38, 0.78, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.bottomCenter,
                radius: 1.2,
                colors: [
                  cat.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cat.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cat.withValues(alpha: 0.32)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    newsCategoryIcon(article.category),
                    size: 12,
                    color: cat,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    article.category,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cat,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: cat.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            article.source,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cat,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.clock, size: 12, color: colors.text5),
            const SizedBox(width: 4),
            Text(
              '${article.readTime} min',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.text4,
              ),
            ),
          ],
        ),
        Text('·', style: TextStyle(color: colors.text5)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.calendar, size: 12, color: colors.text5),
            const SizedBox(width: 4),
            Text(
              article.date,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.text4,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BlockList extends StatelessWidget {
  const _BlockList({
    required this.blocks,
    required this.cat,
    required this.colors,
  });

  final List<ArticleBlock> blocks;
  final Color cat;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var i = 0;
    while (i < blocks.length) {
      final b = blocks[i];
      if (b.type == 'stat') {
        final stats = <ArticleBlock>[];
        while (i < blocks.length && blocks[i].type == 'stat') {
          stats.add(blocks[i]);
          i++;
        }
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            children: [
              for (var j = 0; j < stats.length; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                Expanded(
                    child:
                        _StatCard(block: stats[j], cat: cat, colors: colors)),
              ],
            ],
          ),
        ));
      } else {
        children.add(_buildBlock(b));
        i++;
      }
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _buildBlock(ArticleBlock b) {
    switch (b.type) {
      case 'paragraph':
        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Text(
            b.content,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              height: 1.88,
              color: colors.text2,
            ),
          ),
        );
      case 'heading':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text(
            b.content,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.3,
              letterSpacing: -0.3,
              color: colors.text,
            ),
          ),
        );
      case 'quote':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: cat, width: 3)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"${b.content}"',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontStyle: FontStyle.italic,
                      height: 1.68,
                      color: colors.text,
                    ),
                  ),
                  if (b.label != null && b.label!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '— ${b.label}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cat,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.block,
    required this.cat,
    required this.colors,
  });

  final ArticleBlock block;
  final Color cat;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cat.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cat.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Text(
            block.content,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: cat,
            ),
          ),
          if (block.label != null && block.label!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              block.label!.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                letterSpacing: 0.5,
                color: colors.text4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.colors,
    required this.saved,
    required this.read,
    required this.onShare,
    required this.onToggleSave,
    required this.onMarkRead,
  });

  final AppColors colors;
  final bool saved;
  final bool read;
  final VoidCallback onShare;
  final VoidCallback onToggleSave;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              16, 14, 16, MediaQuery.paddingOf(context).bottom + 14),
          decoration: BoxDecoration(
            color: colors.bg.withValues(alpha: 0.82),
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              _BarAction(
                icon: LucideIcons.share2,
                label: 'Share',
                color: colors.text2,
                bgColor: colors.bg2,
                borderColor: colors.border,
                onTap: onShare,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BarPill(
                  icon: saved ? LucideIcons.bookmarkMinus : LucideIcons.bookmark,
                  label: saved ? 'Saved' : 'Save',
                  accent: AppColors.accent,
                  filled: saved,
                  colors: colors,
                  onTap: onToggleSave,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BarPill(
                  icon: read ? LucideIcons.checkCircle : LucideIcons.circle,
                  label: read ? 'Done' : 'Mark read',
                  accent: const Color(0xFF34D399),
                  filled: read,
                  colors: colors,
                  onTap: onMarkRead,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarPill extends StatelessWidget {
  const _BarPill({
    required this.icon,
    required this.label,
    required this.accent,
    required this.filled,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool filled;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? accent.withValues(alpha: 0.16) : colors.bg2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: filled
                  ? accent.withValues(alpha: 0.35)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: filled ? accent : colors.text2,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: filled ? accent : colors.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TTS Player Bar — inline player for on-device article narration
// ---------------------------------------------------------------------------

class _TtsPlayerBar extends StatelessWidget {
  const _TtsPlayerBar({
    required this.ttsService,
    required this.article,
    required this.accentColor,
    required this.colors,
    this.isFullContent = false,
  });

  final ArticleTtsService ttsService;
  final Article article;
  final Color accentColor;
  final AppColors colors;

  /// When the article ships the full original body, the player narrates the
  /// article itself (not an AI summary), so the label reflects that.
  final bool isFullContent;

  @override
  Widget build(BuildContext context) {
    final text = ArticleTtsService.extractSpeakableText(article);
    if (text.isEmpty) return const SizedBox.shrink();

    return ValueListenableBuilder<TtsState>(
      valueListenable: ttsService.stateNotifier,
      builder: (context, state, _) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: state == TtsState.idle
              ? _buildIdle(text)
              : _buildActive(state, text),
        );
      },
    );
  }

  Widget _buildIdle(String text) {
    return Material(
      color: accentColor.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => ttsService.speak(text),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(LucideIcons.headphones, size: 16, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFullContent ? 'Listen to Article' : 'Listen to Summary',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'On-device AI narration',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: colors.text4,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.play, size: 14, color: accentColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActive(TtsState state, String text) {
    final isSpeaking = state == TtsState.speaking;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          WaveVisualizer(
            isActive: isSpeaking,
            color: accentColor,
            height: 36,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TtsProgress>(
            valueListenable: ttsService.progressNotifier,
            builder: (context, progress, _) {
              final word = progress.word.trim();
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 100),
                child: Text(
                  isSpeaking
                      ? (word.isNotEmpty ? word : 'Speaking...')
                      : 'Paused',
                  key: ValueKey(isSpeaking ? word : 'paused'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: accentColor.withValues(alpha: 0.55),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PlayerButton(
                icon: isSpeaking ? LucideIcons.pause : LucideIcons.play,
                label: isSpeaking ? 'Pause' : 'Resume',
                accentColor: accentColor,
                colors: colors,
                isPrimary: true,
                onTap: () =>
                    isSpeaking ? ttsService.pause() : ttsService.resume(),
              ),
              const SizedBox(width: 10),
              _PlayerButton(
                icon: LucideIcons.square,
                label: 'Stop',
                accentColor: accentColor,
                colors: colors,
                isPrimary: false,
                onTap: () => ttsService.stop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerButton extends StatelessWidget {
  const _PlayerButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.colors,
    required this.isPrimary,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final AppColors colors;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          isPrimary ? accentColor.withValues(alpha: 0.12) : colors.bg3,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPrimary
                  ? accentColor.withValues(alpha: 0.25)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isPrimary ? accentColor : colors.text2,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isPrimary ? accentColor : colors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
