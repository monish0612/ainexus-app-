import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/online_search_store.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/tutor_entities.dart';
import '../../screens/settings/settings_controller.dart';
import 'search_followup_sheet.dart';

/// Standalone grounded-search screen that can be pushed on any navigation stack.
/// Tries grounded search first, falls back to Tavily.
class SearchLookupScreen extends ConsumerStatefulWidget {
  const SearchLookupScreen({super.key, required this.query});

  final String query;

  @override
  ConsumerState<SearchLookupScreen> createState() =>
      _SearchLookupScreenState();
}

class _SearchLookupScreenState extends ConsumerState<SearchLookupScreen>
    with WidgetsBindingObserver {
  static const _accent = Color(0xFF34D399);

  bool _loading = true;
  String? _error;

  GroundedSearchResponse? _groundedResult;
  TavilySearchResponse? _tavilyResult;

  String? _searchKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search();
  }

  @override
  void dispose() {
    if (_searchKey != null) {
      OnlineSearchStore.instance.removeListener(_searchKey!, _onStoreUpdate);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _searchKey != null) {
      _syncFromStore();
    }
  }

  void _onStoreUpdate() {
    if (!mounted) return;
    _syncFromStore();
  }

  void _syncFromStore() {
    final job = OnlineSearchStore.instance.getJob(_searchKey ?? '');
    if (job == null) return;
    setState(() {
      _loading = job.loading;
      _groundedResult = job.groundedResult;
      _tavilyResult = job.tavilyResult;
      _error = job.error;
    });
  }

  void _search() {
    setState(() {
      _loading = true;
      _error = null;
      _groundedResult = null;
      _tavilyResult = null;
    });

    if (_searchKey != null) {
      OnlineSearchStore.instance.removeListener(_searchKey!, _onStoreUpdate);
    }

    final service = ref.read(tutorAiServiceProvider);
    final settings = ref.read(settingsProvider);
    final useXGrok = settings.xgrokEnabled &&
        settings.onlineSearchProvider == 'xgrok';

    TLog.d('SearchLookup', 'Search \u2192 "${widget.query}" [provider=${useXGrok ? 'xGrok' : 'Gemini'}]');

    final store = OnlineSearchStore.instance;
    _searchKey = store.startSearch(
      query: widget.query,
      service: service,
      useXGrok: useXGrok,
      xgrokLiteModel: useXGrok ? settings.xgrokLiteModel : null,
    );
    store.addListener(_searchKey!, _onStoreUpdate);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied',
          style: GoogleFonts.plusJakartaSans(color: Colors.white),
        ),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.headerBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.text, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Search',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: Stack(
        children: [
          _loading
              ? _buildLoading(colors)
              : _error != null
                  ? _buildError(colors)
                  : _groundedResult != null
                      ? _buildGroundedResult(colors, _groundedResult!)
                      : _tavilyResult != null
                          ? _buildTavilyResult(colors, _tavilyResult!)
                          : const SizedBox.shrink(),
          if (_groundedResult != null)
            Positioned(
              right: 20,
              bottom: 24,
              child: SearchFollowUpFab(
                query: widget.query,
                initialAnswer: _groundedResult!.answer,
                model: _groundedResult!.model,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoading(AppColors colors) {
    final settings = ref.watch(settingsProvider);
    final isXGrok = settings.xgrokEnabled &&
        settings.onlineSearchProvider == 'xgrok';
    final providerLabel = isXGrok ? 'xGrok' : 'Gemini';
    final providerColor =
        isXGrok ? const Color(0xFFE8453C) : const Color(0xFF4285F4);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Searching the web…',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '"${widget.query.length > 60 ? '${widget.query.substring(0, 57)}…' : widget.query}"',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: colors.text4,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: providerColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: providerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isXGrok ? LucideIcons.bot : LucideIcons.globe,
                    size: 10,
                    color: providerColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    providerLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: providerColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle, size: 40, color: colors.text4),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                color: colors.text2,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _search,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Service badge ────────────────────────────────────────────────────────

  Widget _serviceBadge(AppColors colors, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Grounded search result ──────────────────────────────────────────────

  Widget _buildGroundedResult(AppColors colors, GroundedSearchResponse r) {
    final isXGrokResult = r.model.toLowerCase().contains('grok');
    final badgeLabel = isXGrokResult
        ? 'xGrok · ${r.model}'
        : 'Google · ${r.model.isNotEmpty ? r.model : "Gemini"}';
    final badgeColor = isXGrokResult
        ? const Color(0xFFE8453C)
        : const Color(0xFF4285F4);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _serviceBadge(
                colors,
                badgeLabel,
                isXGrokResult ? LucideIcons.bot : LucideIcons.globe,
                badgeColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (r.searchQueries.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: r.searchQueries
                  .map((q) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.bg3,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.search,
                                size: 10, color: colors.text4),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                q,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: colors.text3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            decoration: BoxDecoration(
              color: colors.bg1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.06),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(
                      bottom: BorderSide(color: colors.border2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.globe, size: 14, color: _accent),
                      const SizedBox(width: 8),
                      Text(
                        'ANSWER',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _copy(r.answer),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.copy,
                                size: 13, color: colors.text4),
                            const SizedBox(width: 4),
                            Text(
                              'Copy',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: colors.text4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectionArea(
                    child: MarkdownBody(
                      data: r.answer,
                      selectable: false,
                      onTapLink: (_, href, __) {
                        if (href != null) _openUrl(href);
                      },
                      styleSheet: _answerMarkdownStyle(colors),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (r.sources.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sourcesSection(colors, r.sources),
          ],
        ],
      ),
    );
  }

  // ── Tavily fallback result ──────────────────────────────────────────────

  Widget _buildTavilyResult(AppColors colors, TavilySearchResponse r) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _serviceBadge(
                colors,
                'Tavily Search',
                LucideIcons.sparkles,
                const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (r.answer.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: colors.bg1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.06),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                      border: Border(
                        bottom: BorderSide(color: colors.border2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.sparkles,
                            size: 14, color: _accent),
                        const SizedBox(width: 8),
                        Text(
                          'AI ANSWER',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _copy(r.answer),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.copy,
                                  size: 13, color: colors.text4),
                              const SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: colors.text4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectionArea(
                      child: MarkdownBody(
                        data: r.answer,
                        selectable: false,
                        onTapLink: (_, href, __) {
                          if (href != null) _openUrl(href);
                        },
                        styleSheet: _answerMarkdownStyle(colors),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (r.results.isNotEmpty) ...[
            const SizedBox(height: 20),
            _tavilySourcesSection(colors, r.results),
          ],
        ],
      ),
    );
  }

  // ── Shared source widgets ───────────────────────────────────────────────

  Widget _sourcesSection(AppColors colors, List<GroundedSource> sources) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(LucideIcons.link, size: 13, color: _accent),
          const SizedBox(width: 6),
          Text(
            'SOURCES',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _accent,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${sources.length}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ...sources.map((src) => _sourceCard(colors, src.title, src.url)),
      ],
    );
  }

  Widget _tavilySourcesSection(
      AppColors colors, List<TavilyResultItem> results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(LucideIcons.link, size: 13, color: _accent),
          const SizedBox(width: 6),
          Text(
            'SOURCES',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _accent,
              letterSpacing: 1.2,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ...results.map((r) => _sourceCard(colors, r.title, r.url)),
      ],
    );
  }

  MarkdownStyleSheet _answerMarkdownStyle(AppColors colors) {
    return MarkdownStyleSheet(
      p: GoogleFonts.plusJakartaSans(
          fontSize: 14, height: 1.75, color: colors.text),
      pPadding: const EdgeInsets.only(bottom: 6),
      h1: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.3,
          color: colors.text),
      h1Padding: const EdgeInsets.only(top: 6, bottom: 4),
      h2: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          height: 1.35,
          color: colors.text),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h3: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.4,
          color: colors.text),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 2),
      strong: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700, color: colors.text),
      em: GoogleFonts.plusJakartaSans(
          fontStyle: FontStyle.italic, color: colors.text3),
      blockquote: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          height: 1.6,
          color: colors.text2),
      blockquoteDecoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: _accent, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      listBullet: GoogleFonts.plusJakartaSans(
          fontSize: 13, fontWeight: FontWeight.w700, color: _accent),
      listBulletPadding: const EdgeInsets.only(right: 6),
      listIndent: 18,
      tableHead: GoogleFonts.plusJakartaSans(
          fontSize: 11, fontWeight: FontWeight.w700, color: colors.text),
      tableBody: GoogleFonts.plusJakartaSans(
          fontSize: 11, height: 1.5, color: colors.text2),
      tableBorder: TableBorder.all(
          color: colors.border, borderRadius: BorderRadius.circular(8)),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tableColumnWidth: const FlexColumnWidth(),
      code: GoogleFonts.jetBrainsMono(
          fontSize: 12, color: _accent, backgroundColor: colors.bg3),
      codeblockDecoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      a: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _accent,
        decoration: TextDecoration.underline,
        decorationColor: _accent.withValues(alpha: 0.4),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border, width: 0.5)),
      ),
    );
  }

  Widget _sourceCard(AppColors colors, String title, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openUrl(url),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty ? title : url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: colors.text4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.externalLink, size: 14, color: colors.text4),
            ],
          ),
        ),
      ),
    );
  }
}
