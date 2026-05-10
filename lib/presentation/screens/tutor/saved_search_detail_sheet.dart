import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/saved_search_store.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/saved_search.dart';
import '../../../domain/entities/tutor_entities.dart';
import '../../widgets/provider_picker.dart';
import '../settings/settings_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SavedSearchDetailSheet — opens a saved search's snapshot + chat history
// ─────────────────────────────────────────────────────────────────────────────
//
// Layout:
//   [grabber]
//   [header — title + share + delete]
//   [snapshot card — collapsed-by-default summary of the original result]
//   [chat list — persistent SavedSearchStore-backed message stream]
//   [input box — Lite/Deep + Provider picker + send]
//
// All chat persistence is routed via SavedSearchStore so messages survive
// app restarts and sync to the server. The retry/lifecycle logic is owned
// by the store; this widget just dispatches and listens.

class SavedSearchDetailSheet extends ConsumerStatefulWidget {
  const SavedSearchDetailSheet({super.key, required this.entryId});
  final String entryId;

  @override
  ConsumerState<SavedSearchDetailSheet> createState() =>
      _SavedSearchDetailSheetState();
}

class _SavedSearchDetailSheetState
    extends ConsumerState<SavedSearchDetailSheet> {
  static const _uuid = Uuid();

  SavedSearchEntry? _entry;
  bool _loading = true;
  bool _snapshotExpanded = false;
  bool _useDeep = false;
  bool _sending = false;
  String _provider = 'gemini'; // 'gemini' | 'xgrok'

  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _chatScroll = ScrollController();

  /// Tracks the last rendered message count so we only schedule an
  /// auto-scroll post-frame callback when it actually changes (rather
  /// than on every rebuild — e.g. theme changes, keyboard popping).
  int _lastRenderedMsgCount = -1;

  @override
  void initState() {
    super.initState();
    _loadEntry();
    // Best-effort pull of any server-side messages we don't yet have.
    Future<void>.microtask(() => ref
        .read(savedSearchStoreProvider)
        .pullMessagesFromServer(widget.entryId));
  }

  Future<void> _loadEntry() async {
    final store = ref.read(savedSearchStoreProvider);
    final entry = await store.getById(widget.entryId);
    if (!mounted) return;
    // Read global settings defensively. If the provider hasn't been
    // overridden (e.g. in widget tests where SharedPreferences isn't
    // wired) we just fall back to a sane default state so the sheet
    // still opens. Production always has a real value.
    SettingsState settings;
    try {
      settings = ref.read(settingsProvider);
    } catch (_) {
      settings = const SettingsState();
    }
    setState(() {
      _entry = entry;
      _loading = false;
      // Seed picker from the saved entry's provider, falling back to global
      // settings when blank. xGrok is auto-downgraded to gemini if the user
      // has disabled the toggle in settings.
      final raw = (entry?.provider.isNotEmpty ?? false)
          ? entry!.provider
          : settings.onlineSearchProvider;
      _provider =
          (raw == 'xgrok' && settings.xgrokEnabled) ? 'xgrok' : 'gemini';
      _useDeep = (entry?.mode ?? '') == 'deep';
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entry == null
                  ? _buildMissing(colors)
                  : _buildBody(colors, scrollController),
        ),
      ),
    );
  }

  Widget _buildMissing(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.alertTriangle, size: 32, color: colors.text4),
          const SizedBox(height: 12),
          Text('This saved search is no longer available.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: colors.text3)),
        ],
      ),
    );
  }

  Widget _buildBody(AppColors colors, ScrollController scrollController) {
    final entry = _entry!;
    return Column(
      children: [
        _buildGrabber(colors),
        _buildHeader(colors, entry),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              _buildSnapshot(colors, entry),
              const SizedBox(height: 14),
              _buildChatLabel(colors),
              const SizedBox(height: 6),
              _buildChat(colors, entry),
            ],
          ),
        ),
        _buildInputBar(colors),
      ],
    );
  }

  Widget _buildGrabber(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: colors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors, SavedSearchEntry entry) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title.isNotEmpty ? entry.title : entry.query,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _detailSubtitle(entry),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: colors.text4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(entry),
            icon: Icon(LucideIcons.trash2, size: 18, color: colors.text3),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(LucideIcons.x, size: 20, color: colors.text3),
          ),
        ],
      ),
    );
  }

  String _detailSubtitle(SavedSearchEntry entry) {
    final ts = DateTime.tryParse(entry.savedAt)?.toLocal();
    final saved = ts == null
        ? 'Saved'
        : 'Saved ${ts.day}/${ts.month}/${ts.year}';
    final t = _prettyType(entry.responseType);
    return t.isEmpty ? saved : '$saved \u00B7 $t';
  }

  static String _prettyType(String t) {
    switch (t) {
      case SavedSearchResponseType.summarizer:
        return 'Summary';
      case SavedSearchResponseType.grounded:
        return 'Grounded answer';
      case SavedSearchResponseType.tavily:
        return 'Tavily answer';
      default:
        return t;
    }
  }

  // ── Snapshot rendering ────────────────────────────────────────────────────

  Widget _buildSnapshot(AppColors colors, SavedSearchEntry entry) {
    final result = entry.decodedResult();
    String body = '';
    String? subtitle;
    List<_SnapshotSource> sources = const [];

    if (result is SummarizerResult) {
      body = result.summary;
      if (result.url.isNotEmpty) subtitle = result.url;
      if (result.keyPoints.isNotEmpty) {
        body =
            '$body\n\n**Key points**\n${result.keyPoints.map((p) => '- $p').join('\n')}';
      }
    } else if (result is GroundedSearchResponse) {
      body = result.answer;
      sources = result.sources
          .map((s) => _SnapshotSource(s.title, s.url))
          .toList();
    } else if (result is TavilySearchResponse) {
      body = result.answer;
      sources = result.results
          .map((s) => _SnapshotSource(s.title, s.url))
          .toList();
    } else {
      // Forward-compat: render the raw query if we don't recognise the type.
      body = entry.query;
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(LucideIcons.fileText,
                    size: 14, color: Color(0xFF8B5CF6)),
                const SizedBox(width: 6),
                Text(
                  'ORIGINAL RESULT',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF8B5CF6),
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                if (body.length > 320 || sources.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(
                        () => _snapshotExpanded = !_snapshotExpanded),
                    icon: Icon(
                      _snapshotExpanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 14,
                    ),
                    label: Text(
                      _snapshotExpanded ? 'Collapse' : 'Expand',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () {
                  final url = subtitle;
                  if (url != null) _openUrl(url);
                },
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4285F4),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _snapshotExpanded ? double.infinity : 200,
                ),
                child: SingleChildScrollView(
                  physics: _snapshotExpanded
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: MarkdownBody(
                    data: body.isEmpty ? '_(empty)_' : body,
                    selectable: true,
                    onTapLink: (_, href, __) {
                      if (href != null) _openUrl(href);
                    },
                  ),
                ),
              ),
            ),
          ),
          if (_snapshotExpanded && sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in sources) _sourceChip(colors, s),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceChip(AppColors colors, _SnapshotSource s) {
    return GestureDetector(
      onTap: () => _openUrl(s.url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.externalLink,
                size: 11, color: Color(0xFF4285F4)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                s.title.isNotEmpty ? s.title : s.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chat ──────────────────────────────────────────────────────────────────

  Widget _buildChatLabel(AppColors colors) {
    return Row(
      children: [
        const Icon(LucideIcons.messageSquare, size: 13, color: Color(0xFF8B5CF6)),
        const SizedBox(width: 6),
        Text(
          'FOLLOW-UP CHAT',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF8B5CF6),
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildChat(AppColors colors, SavedSearchEntry entry) {
    final store = ref.read(savedSearchStoreProvider);
    return StreamBuilder<List<PersistedChatMessage>>(
      stream: store.watchMessages(entry.id),
      builder: (context, snapshot) {
        final msgs = snapshot.data ?? const <PersistedChatMessage>[];
        if (msgs.isEmpty && !_sending) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'Ask a follow-up question to extend this search.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: colors.text4),
              ),
            ),
          );
        }
        // Only schedule auto-scroll when the rendered count actually grows.
        // Avoids redundant animations on theme/keyboard rebuilds.
        final renderedCount = msgs.length + (_sending ? 1 : 0);
        if (renderedCount != _lastRenderedMsgCount) {
          _lastRenderedMsgCount = renderedCount;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_chatScroll.hasClients) {
              _chatScroll.animateTo(
                _chatScroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
              );
            }
          });
        }
        return Column(
          children: [
            for (final m in msgs) _buildBubble(colors, m),
            if (_sending) _buildTypingBubble(colors),
          ],
        );
      },
    );
  }

  /// Animated three-dot "AI is thinking" bubble shown while a follow-up
  /// answer is in flight. Mirrors the FAB chat's typing indicator so the
  /// user gets immediate feedback even on slow networks.
  Widget _buildTypingBubble(AppColors colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _TypingDot(delay: Duration(milliseconds: i * 160)),
            ],
            const SizedBox(width: 8),
            Text(
              'Thinking\u2026',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.text4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(AppColors colors, PersistedChatMessage m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF6366F1).withValues(alpha: 0.10)
              : colors.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUser
                ? const Color(0xFF6366F1).withValues(alpha: 0.25)
                : colors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: m.text,
              selectable: true,
              onTapLink: (_, href, __) {
                if (href != null) _openUrl(href);
              },
            ),
            if (m.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in m.sources)
                    _sourceChip(
                        colors, _SnapshotSource(s.title, s.url)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────

  Widget _buildInputBar(AppColors colors) {
    // `watch` would throw at the first frame if settingsProvider hasn't
    // been overridden (tests). Fall back to a default state in that case.
    SettingsState settings;
    try {
      settings = ref.watch(settingsProvider);
    } catch (_) {
      settings = const SettingsState();
    }
    final providerOptions = settings.xgrokEnabled
        ? const <ProviderOption>[
            ProviderOption(
              id: 'gemini',
              label: 'Gemini',
              icon: LucideIcons.globe,
              color: Color(0xFF4285F4),
            ),
            ProviderOption(
              id: 'xgrok',
              label: 'xGrok',
              icon: LucideIcons.bot,
              color: Color(0xFFE8453C),
            ),
          ]
        : const <ProviderOption>[
            ProviderOption(
              id: 'gemini',
              label: 'Gemini',
              icon: LucideIcons.globe,
              color: Color(0xFF4285F4),
            ),
          ];

    final selectedId = (_provider == 'xgrok' && settings.xgrokEnabled)
        ? 'xgrok'
        : 'gemini';

    // Dynamic bottom inset: prefer the keyboard inset when the
    // soft-keyboard is open, otherwise keep a comfortable gap above the
    // gesture-nav bar. The outer `SafeArea(bottom: true)` in [build]
    // already pushes us above the system inset, so this controls the
    // visual breathing room only.
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = insets > 0 ? insets + 8 : 10;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad.toDouble()),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggles row — wrap so chips never get clipped on narrow
          // screens or in landscape; fixed 8px run/spacing keeps the
          // visual rhythm consistent with the input row below.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ProviderPicker(
                  options: providerOptions,
                  selectedId: selectedId,
                  onChanged: (id) => setState(() => _provider = id),
                  colors: colors,
                  heroTag: 'saved-search-detail',
                ),
                _buildModeToggle(colors),
                if (_sending)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  focusNode: _inputFocus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Ask a follow-up\u2026',
                    hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 14, color: colors.text5),
                    isDense: true,
                    filled: true,
                    fillColor: colors.bg1,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
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
                      borderSide: const BorderSide(
                          color: Color(0xFF8B5CF6), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _sending ? null : _send,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(LucideIcons.send,
                        size: 18, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle(AppColors colors) {
    return GestureDetector(
      onTap: () => setState(() => _useDeep = !_useDeep),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _useDeep
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.12)
              : colors.bg1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _useDeep
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.35)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _useDeep ? LucideIcons.brain : LucideIcons.zap,
              size: 12,
              color: _useDeep
                  ? const Color(0xFF8B5CF6)
                  : colors.text3,
            ),
            const SizedBox(width: 5),
            Text(
              _useDeep ? 'Deep' : 'Lite',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _useDeep ? const Color(0xFF8B5CF6) : colors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Send + persist ────────────────────────────────────────────────────────

  Future<void> _send() async {
    final entry = _entry;
    if (entry == null) return;
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    final store = ref.read(savedSearchStoreProvider);
    final aiService = ref.read(tutorAiServiceProvider);
    final settings = ref.read(settingsProvider);
    final useXGrok = _provider == 'xgrok' && settings.xgrokEnabled;
    final mode = _useDeep ? 'deep' : 'lite';

    HapticFeedback.lightImpact();
    final userMsgId = _uuid.v4();
    final userTs = DateTime.now().toUtc().toIso8601String();
    _inputCtrl.clear();
    setState(() => _sending = true);

    // Persist the user turn first.
    await store.appendMessage(
      searchId: entry.id,
      messageId: userMsgId,
      role: 'user',
      text: text,
      createdAt: userTs,
    );

    // Build conversation history from the current Drift snapshot.
    final history = await store.loadMessages(entry.id);
    final wireHistory = history
        .where((m) => m.id != userMsgId) // exclude the just-added user turn
        .map((m) => {'role': m.role, 'text': m.text})
        .toList();

    String initialAnswer = '';
    final result = entry.decodedResult();
    if (result is SummarizerResult) {
      initialAnswer = result.summary;
    } else if (result is GroundedSearchResponse) {
      initialAnswer = result.answer;
    } else if (result is TavilySearchResponse) {
      initialAnswer = result.answer;
    }

    try {
      final resp = await aiService.searchFollowUp(
        query: entry.query,
        initialAnswer: initialAnswer,
        question: text,
        history: wireHistory,
        mode: mode,
        provider: useXGrok ? 'xgrok' : null,
        deepModel: useXGrok ? null : settings.deepModel,
        liteModel: useXGrok ? null : settings.liteModel,
        xgrokLiteModel: useXGrok ? settings.xgrokLiteModel : null,
        xgrokDeepModel: useXGrok ? settings.xgrokDeepModel : null,
        xgrokThinkingModel: useXGrok ? settings.xgrokThinkingModel : null,
      );
      await store.appendMessage(
        searchId: entry.id,
        messageId: _uuid.v4(),
        role: 'assistant',
        text: resp.answer,
        model: resp.model,
        sources: resp.sources,
      );
    } on DioException catch (e) {
      TLog.w('SavedSearchDetail', 'searchFollowUp failed', error: e);
      await store.appendMessage(
        searchId: entry.id,
        messageId: _uuid.v4(),
        role: 'assistant',
        text: e.type == DioExceptionType.cancel
            ? '_(Cancelled)_'
            : '_(Could not reach the AI service. Please try again.)_',
      );
    } catch (e) {
      TLog.e('SavedSearchDetail', 'searchFollowUp unexpected error', error: e);
      await store.appendMessage(
        searchId: entry.id,
        messageId: _uuid.v4(),
        role: 'assistant',
        text: '_(Something went wrong. Please try again.)_',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Misc ──────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(SavedSearchEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved search?'),
        content: const Text(
          'This will remove it from history on every device. Follow-up '
          'messages will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    await ref.read(savedSearchStoreProvider).delete(entry.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      TLog.w('SavedSearchDetail', 'openUrl failed', error: e);
    }
  }
}

class _SnapshotSource {
  const _SnapshotSource(this.title, this.url);
  final String title;
  final String url;
}

/// Single animated dot — three of these are rendered side-by-side with
/// staggered delays to produce the "thinking" pulse used in the
/// follow-up chat while an AI request is in flight.
class _TypingDot extends StatefulWidget {
  const _TypingDot({required this.delay});
  final Duration delay;

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future<void>.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1.0).animate(_ctrl),
      child: const SizedBox(
        width: 6,
        height: 6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF8B5CF6),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
