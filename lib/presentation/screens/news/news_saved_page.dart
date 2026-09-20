import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/nuke_report.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/news_entities.dart';
import '../expense/widgets/nuke_easter_egg.dart';
import 'article_followup_sheet.dart';
import 'news_article_nav.dart';
import 'news_chrome.dart';
import 'news_controller.dart';

/// Full-screen Saved library. Same rows, search, nuke, follow-up, and
/// delete contracts as the old in-tab Saved pane — only the entry point
/// changed (header bookmark instead of a sibling tab).
class NewsSavedPage extends ConsumerStatefulWidget {
  const NewsSavedPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const NewsSavedPage(),
      ),
    );
  }

  @override
  ConsumerState<NewsSavedPage> createState() => _NewsSavedPageState();
}

class _NewsSavedPageState extends ConsumerState<NewsSavedPage> {
  late final TextEditingController _searchCtrl;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    if (value.trim().toLowerCase() == 'nuke') {
      _searchCtrl.clear();
      setState(() => _search = '');
      unawaited(_handleNewsNuke());
      return;
    }
    setState(() => _search = value);
  }

  Future<void> _handleNewsNuke() async {
    final confirmed = await NukeEasterEgg.confirm(context, NukeScope.news);
    if (!mounted || !confirmed) return;

    TLog.w('News', '☢️ News nuke confirmed — wiping ALL articles incl. saved');
    final report = await ref.read(newsNukeServiceProvider).nuke();
    if (!mounted) return;
    await NukeEasterEgg.showReport(context, report);
  }

  Future<void> _handleRefresh() async {
    try {
      await ref.read(newsControllerProvider.notifier).refresh();
    } catch (e) {
      TLog.e('News', 'Saved refresh failed', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final allArticles =
        ref.watch(newsControllerProvider).valueOrNull ?? const <Article>[];
    final savedArticles = allArticles.where((a) => a.isSaved).toList();
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? savedArticles
        : savedArticles
            .where(
              (a) =>
                  a.title.toLowerCase().contains(q) ||
                  a.category.toLowerCase().contains(q) ||
                  a.source.toLowerCase().contains(q),
            )
            .toList();

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: AppConstants.headerHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(LucideIcons.arrowLeft, color: colors.text2),
                    ),
                    Expanded(
                      child: Text(
                        savedArticles.isEmpty
                            ? 'Saved'
                            : 'Saved (${savedArticles.length})',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                key: const Key('news-saved-refresh'),
                onRefresh: _handleRefresh,
                color: AppColors.accent,
                backgroundColor: colors.bg1,
                displacement: 48,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _SavedSearchField(
                      colors: colors,
                      controller: _searchCtrl,
                      value: _search,
                      onChanged: _onSearch,
                    ),
                    const SizedBox(height: 12),
                    if (savedArticles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Column(
                          children: [
                            Icon(LucideIcons.bookmark,
                                size: 42, color: colors.text5),
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
                    else if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Column(
                          children: [
                            Icon(LucideIcons.search,
                                size: 28, color: colors.text5),
                            const SizedBox(height: 8),
                            Text(
                              'No results for "$_search"',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: colors.text4,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...filtered.map(
                        (a) => _SavedRow(
                          article: a,
                          colors: colors,
                          query: _search.trim(),
                          onOpen: () => openNewsArticle(
                            context: context,
                            ref: ref,
                            raw: a,
                          ),
                          onRemove: () {
                            ArticleFollowUpStore.instance.clear(a.id);
                            ref
                                .read(newsControllerProvider.notifier)
                                .deleteArticle(a.id);
                          },
                        ),
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
                  child: article.imageUrl.isEmpty
                      ? ColoredBox(color: colors.bg2)
                      : CachedNetworkImage(
                          imageUrl: article.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              ColoredBox(color: colors.bg2),
                          errorWidget: (_, __, ___) =>
                              ColoredBox(color: colors.bg2),
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
