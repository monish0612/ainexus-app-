import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/article_tts_service.dart';
import '../../../domain/entities/news_entities.dart';
import '../../widgets/wave_visualizer.dart';
import 'article_followup_sheet.dart';

Color newsCategoryColor(String category) {
  final hex = CAT_COLOR[category] ?? '#818CF8';
  final value = hex.replaceFirst('#', '');
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return const Color(0xFF818CF8);
  return Color(parsed + 0xFF000000);
}

/// Full-screen article detail (open with [Navigator.push]).
class ArticleDetailModal extends StatefulWidget {
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
  State<ArticleDetailModal> createState() => _ArticleDetailModalState();
}

class _ArticleDetailModalState extends State<ArticleDetailModal> {
  late bool _saved;
  late bool _read;
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false;
  late final ArticleTtsService _tts;

  @override
  void initState() {
    super.initState();
    _saved = widget.article.isSaved;
    _read = widget.article.isRead;
    _scroll.addListener(_onScroll);
    _tts = ArticleTtsService();
  }

  @override
  void dispose() {
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
    final hasSummaryMarkdown =
        summaryMarkdown != null && summaryMarkdown.isNotEmpty;
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
                    ),
                    const SizedBox(height: 20),
                    if (hasSummaryMarkdown)
                      _SummaryMarkdown(
                        summary: summaryMarkdown,
                        cat: cat,
                        colors: colors,
                      )
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

class _SummaryMarkdown extends StatelessWidget {
  const _SummaryMarkdown({
    required this.summary,
    required this.cat,
    required this.colors,
  });

  final String summary;
  final Color cat;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: MarkdownBody(
        data: summary,
        selectable: false,
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
                    article.category == 'Finance'
                        ? LucideIcons.trendingUp
                        : article.category == 'AI News'
                            ? LucideIcons.cpu
                            : LucideIcons.newspaper,
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
            children: [
              Icon(
                icon,
                size: 16,
                color: filled ? accent : colors.text2,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: filled ? accent : colors.text2,
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
  });

  final ArticleTtsService ttsService;
  final Article article;
  final Color accentColor;
  final AppColors colors;

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
                      'Listen to Summary',
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
