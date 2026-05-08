// ignore_for_file: library_private_types_in_public_api, unused_element, unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/tutor_ai_service.dart';
import '../../../domain/entities/tutor_entities.dart';
import '../../widgets/voice_input_button.dart';
import '../../screens/settings/settings_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CHAT MESSAGE (private, search-scoped)
// ═══════════════════════════════════════════════════════════════════════════════

class _ChatMessage {
  _ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.sources = const [],
    this.model = '',
    this.isLoading = false,
    this.isError = false,
  });

  final String id;
  final String role;
  String text;
  List<GroundedSource> sources;
  String model;
  bool isLoading;
  bool isError;

  String sourcesToJson() {
    if (sources.isEmpty) return '[]';
    return jsonEncode(
      sources
          .map((s) => {'index': s.index, 'title': s.title, 'url': s.url})
          .toList(),
    );
  }

  static List<GroundedSource> _sourcesFromJson(String raw) {
    if (raw.isEmpty || raw == '[]') return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => GroundedSource(
                index: (m['index'] is int) ? m['index'] as int : 0,
                title: m['title']?.toString() ?? '',
                url: m['url']?.toString() ?? '',
              ))
          .toList();
    } catch (e) {
      TLog.w('SearchChat', 'Failed to decode sources JSON: $e');
      return const [];
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RETRY CONTEXT
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchRetry {
  _SearchRetry({
    required this.query,
    required this.initialAnswer,
    required this.aiMsg,
    required this.history,
    required this.question,
    required this.aiService,
    this.mode,
    this.deepModel,
    this.liteModel,
    this.provider,
    this.xgrokLiteModel,
    this.xgrokDeepModel,
    this.xgrokThinkingModel,
  });

  final String query;
  final String initialAnswer;
  final _ChatMessage aiMsg;
  final List<Map<String, String>> history;
  final String question;
  final TutorAiService aiService;
  final String? mode;
  final String? deepModel;
  final String? liteModel;
  final String? provider;
  final String? xgrokLiteModel;
  final String? xgrokDeepModel;
  final String? xgrokThinkingModel;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PERSISTENT STORE — in-memory cache + background retry on resume
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchConversationSummary {
  _SearchConversationSummary({required this.text, required this.pairsCovered});
  final String text;
  final int pairsCovered;
}

class SearchFollowUpStore with WidgetsBindingObserver {
  SearchFollowUpStore._();
  static final instance = SearchFollowUpStore._();

  static const kSummarizeThreshold = 10;
  static const kRecentPairsToKeep = 5;

  final _cache = <String, List<_ChatMessage>>{};
  final _initialAnswers = <String, String>{};
  final _summaries = <String, _SearchConversationSummary>{};
  bool _observerBound = false;

  final _listeners = <String, VoidCallback>{};
  final _pendingAiMsgs = <String, _ChatMessage>{};
  final _retryQueue = <String, _SearchRetry>{};
  final _cancelTokens = <String, CancelToken>{};

  /// Prevents concurrent background summarizations for the same query.
  final _summarizingQueries = <String>{};

  void init() {
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  void setInitialAnswer(String query, String answer) {
    _initialAnswers[query] = answer;
  }

  String getInitialAnswer(String query) => _initialAnswers[query] ?? '';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _retryQueue.isEmpty) return;
    final entries = Map.of(_retryQueue);
    _retryQueue.clear();

    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      for (final e in entries.entries) {
        final query = e.key;
        final r = e.value;
        TLog.d('SearchStore', 'Resumed — retrying follow-up for "$query"');
        r.aiMsg
          ..text = ''
          ..isLoading = true
          ..isError = false;
        _pendingAiMsgs[query] = r.aiMsg;
        _listeners[query]?.call();
        unawaited(_executeRequest(
          query: query,
          initialAnswer: r.initialAnswer,
          aiMsg: r.aiMsg,
          history: r.history,
          question: r.question,
          aiService: r.aiService,
          mode: r.mode,
          deepModel: r.deepModel,
          liteModel: r.liteModel,
          provider: r.provider,
          xgrokLiteModel: r.xgrokLiteModel,
          xgrokDeepModel: r.xgrokDeepModel,
          xgrokThinkingModel: r.xgrokThinkingModel,
          isRetry: true,
        ));
      }
    });
  }

  static bool _isContextLimitError(Object? e) {
    if (e is! DioException) return false;
    if (e.response?.statusCode != 400) return false;
    final body = e.response?.data?.toString().toLowerCase() ?? '';
    return body.contains('context') ||
        body.contains('token limit') ||
        body.contains('token_limit') ||
        body.contains('too long') ||
        body.contains('max_tokens') ||
        body.contains('content_length') ||
        body.contains('request too large') ||
        body.contains('input_too_long');
  }

  static bool _isRetryableNetworkError(Object? e) {
    if (e == null) return false;
    if (e is DioException) {
      if (e.type == DioExceptionType.cancel) return false;
      if (e.type != DioExceptionType.badResponse) return true;
    }
    final s = e.toString().toLowerCase();
    return s.contains('connection abort') ||
        s.contains('connection reset') ||
        s.contains('broken pipe') ||
        s.contains('network is unreachable') ||
        s.contains('socket') ||
        s.contains('timed out') ||
        s.contains('connection closed');
  }

  // ── Listener management ─────────────────────────────────────────────────

  void addListener(String query, VoidCallback cb) => _listeners[query] = cb;

  void removeListener(String query, VoidCallback cb) {
    if (_listeners[query] == cb) _listeners.remove(query);
  }

  bool hasPending(String query) => _pendingAiMsgs.containsKey(query);

  List<_ChatMessage> getCached(String query) => _cache[query] ?? const [];

  // ── Fire-and-forget AI request ───────────────────────────────────────────

  void sendQuestion({
    required String query,
    required String initialAnswer,
    required _ChatMessage userMsg,
    required _ChatMessage aiMsg,
    required List<Map<String, String>> history,
    required TutorAiService aiService,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? provider,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
  }) {
    TLog.d('SearchStore', 'sendQuestion mode=${mode ?? 'deep'}, provider=${provider ?? 'gemini'}, histLen=${history.length}');
    _cache.putIfAbsent(query, () => []);
    final list = _cache[query]!;

    if (!list.any((m) => m.id == userMsg.id)) list.add(userMsg);
    if (!list.any((m) => m.id == aiMsg.id)) list.add(aiMsg);

    _pendingAiMsgs[query] = aiMsg;
    final token = CancelToken();
    _cancelTokens[query] = token;

    unawaited(_executeRequest(
      query: query,
      initialAnswer: initialAnswer,
      aiMsg: aiMsg,
      history: history,
      question: userMsg.text,
      aiService: aiService,
      mode: mode,
      deepModel: deepModel,
      liteModel: liteModel,
      provider: provider,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
      cancelToken: token,
    ));
  }

  /// Cancel the in-flight request for [query]. Returns the user's question
  /// text so the UI can restore it to the input field. Returns null if
  /// nothing was pending.
  String? cancelPending(String query) {
    _cancelTokens[query]?.cancel('User cancelled');
    _cancelTokens.remove(query);
    _retryQueue.remove(query);

    final list = _cache[query];
    if (list == null || list.isEmpty) {
      _pendingAiMsgs.remove(query);
      _listeners[query]?.call();
      return null;
    }

    String? userText;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].isLoading && list[i].role == 'assistant') {
        list.removeAt(i);
        if (i > 0 && list[i - 1].role == 'user') {
          userText = list[i - 1].text;
          list.removeAt(i - 1);
        }
        break;
      }
    }

    _pendingAiMsgs.remove(query);
    _listeners[query]?.call();
    return userText;
  }

  Future<void> _executeRequest({
    required String query,
    required String initialAnswer,
    required _ChatMessage aiMsg,
    required List<Map<String, String>> history,
    required String question,
    required TutorAiService aiService,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? provider,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
    bool isRetry = false,
  }) async {
    bool keepPending = false;

    try {
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (cancelToken?.isCancelled ?? false) return;
        try {
          final result = await aiService.searchFollowUp(
            query: query,
            initialAnswer: initialAnswer,
            question: question,
            history: history,
            mode: mode,
            deepModel: deepModel,
            liteModel: liteModel,
            provider: provider,
            xgrokLiteModel: xgrokLiteModel,
            xgrokDeepModel: xgrokDeepModel,
            xgrokThinkingModel: xgrokThinkingModel,
            cancelToken: cancelToken,
          );
          if (!_cache.containsKey(query)) return;
          if (cancelToken?.isCancelled ?? false) return;
          aiMsg
            ..text = result.answer
            ..sources = result.sources
            ..model = mode ?? 'deep'
            ..isLoading = false;
          return;
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) return;

          if (_isContextLimitError(e) && history.length > 4) {
            TLog.w('SearchFollowUp',
                'Context limit hit (400) — force-summarizing ${history.length} entries and retrying');
            try {
              const recentCount = kRecentPairsToKeep * 2;
              final splitAt = history.length > recentCount
                  ? history.length - recentCount
                  : (history.length ~/ 2);
              final oldPairs = history.sublist(0, splitAt);
              final recentPairs = history.sublist(splitAt);

              final summaryText = await aiService.summarizeHistory(
                messages: oldPairs,
                articleContext: query,
                liteModel: liteModel,
              );
              if (summaryText.isNotEmpty) {
                final existingPairs =
                    getSummary(query)?.pairsCovered ?? 0;
                final computed = oldPairs.length ~/ 2;
                final safePairsCovered =
                    existingPairs > computed ? existingPairs : computed;
                saveSummary(query, summaryText, safePairsCovered);
                final condensedHistory = <Map<String, String>>[
                  {
                    'role': 'user',
                    'text':
                        '[Summary of our earlier conversation ($safePairsCovered exchanges)]:\n$summaryText',
                  },
                  {
                    'role': 'assistant',
                    'text':
                        'I have context from our earlier discussion and will use it to answer your questions.',
                  },
                  ...recentPairs,
                ];
                if (cancelToken?.isCancelled ?? false) return;
                final retryResult = await aiService.searchFollowUp(
                  query: query,
                  initialAnswer: initialAnswer,
                  question: question,
                  history: condensedHistory,
                  mode: mode,
                  deepModel: deepModel,
                  liteModel: liteModel,
                  provider: provider,
                  xgrokLiteModel: xgrokLiteModel,
                  xgrokDeepModel: xgrokDeepModel,
                  xgrokThinkingModel: xgrokThinkingModel,
                  cancelToken: cancelToken,
                );
                if (!_cache.containsKey(query)) return;
                aiMsg
                  ..text = retryResult.answer
                  ..sources = retryResult.sources
                  ..model = mode ?? 'deep'
                  ..isLoading = false;
                TLog.i('SearchFollowUp',
                    'Context-limit recovery succeeded for "$query" ($safePairsCovered pairs summarized)');
                return;
              } else {
                TLog.w('SearchFollowUp',
                    'Summarize returned empty — cannot recover from context limit');
              }
            } catch (retryErr) {
              TLog.e('SearchFollowUp',
                  'Context-limit recovery failed for "$query"',
                  error: retryErr);
            }
          }

          lastError = e;
          if (!_isRetryableNetworkError(e) || !_cache.containsKey(query)) {
            break;
          }
          if (attempt < 2) {
            TLog.w('SearchFollowUp',
                'Network error — retry ${attempt + 1}/2 (${e.runtimeType})');
            await Future.delayed(Duration(seconds: (attempt + 1) * 5));
            if (cancelToken?.isCancelled ?? false) return;
            if (!_cache.containsKey(query)) return;
          }
        }
      }

      if (lastError != null &&
          _isRetryableNetworkError(lastError) &&
          _cache.containsKey(query)) {
        _retryQueue[query] = _SearchRetry(
          query: query,
          initialAnswer: initialAnswer,
          aiMsg: aiMsg,
          history: history,
          question: question,
          aiService: aiService,
          mode: mode,
          deepModel: deepModel,
          liteModel: liteModel,
          provider: provider,
          xgrokLiteModel: xgrokLiteModel,
          xgrokDeepModel: xgrokDeepModel,
          xgrokThinkingModel: xgrokThinkingModel,
        );
        keepPending = true;
        TLog.w('SearchFollowUp',
            'Scheduled auto-retry on resume for "$query"');
      } else if (_cache.containsKey(query)) {
        TLog.e('SearchFollowUp', 'Search follow-up failed', error: lastError);
        aiMsg
          ..text = 'Something went wrong. Please try again.'
          ..isLoading = false
          ..isError = true;
      }
    } finally {
      if (!keepPending) _pendingAiMsgs.remove(query);
      _listeners[query]?.call();
    }
  }

  // ── Conversation summaries (in-memory, session-scoped) ─────────────────

  _SearchConversationSummary? getSummary(String query) =>
      _summaries[query];

  void saveSummary(String query, String text, int pairsCovered) {
    final existing = _summaries[query];
    if (existing != null && existing.pairsCovered > pairsCovered) {
      TLog.w('SearchStore',
          'Blocked summary downgrade for "$query" (${existing.pairsCovered} > $pairsCovered)');
      return;
    }
    _summaries[query] =
        _SearchConversationSummary(text: text, pairsCovered: pairsCovered);
    TLog.d('SearchStore', 'Saved summary for "$query" ($pairsCovered pairs)');
  }

  void clear(String query) {
    _cancelTokens[query]?.cancel('Cleared');
    _cancelTokens.remove(query);
    _cache.remove(query);
    _pendingAiMsgs.remove(query);
    _retryQueue.remove(query);
    _initialAnswers.remove(query);
    _summaries.remove(query);
    _summarizingQueries.remove(query);
  }

  void clearAll() {
    for (final t in _cancelTokens.values) {
      t.cancel('Cleared');
    }
    _cancelTokens.clear();
    _cache.clear();
    _initialAnswers.clear();
    _summaries.clear();
    _pendingAiMsgs.clear();
    _retryQueue.clear();
    _summarizingQueries.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  FAB
// ═══════════════════════════════════════════════════════════════════════════════

class SearchFollowUpFab extends StatefulWidget {
  const SearchFollowUpFab({
    super.key,
    required this.query,
    required this.initialAnswer,
    required this.model,
  });

  final String query;
  final String initialAnswer;
  final String model;

  @override
  State<SearchFollowUpFab> createState() => _SearchFollowUpFabState();
}

class _SearchFollowUpFabState extends State<SearchFollowUpFab>
    with TickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    final store = SearchFollowUpStore.instance;
    store.init();
    store.setInitialAnswer(widget.query, widget.initialAnswer);
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _open() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchFollowUpChat(
        query: widget.query,
        initialAnswer: widget.initialAnswer,
        model: widget.model,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4285F4).withValues(alpha: 0.35),
              blurRadius: 16 + _pulseAnim.value,
              spreadRadius: _pulseAnim.value / 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
      child: GestureDetector(
        onTapDown: (_) => _scaleCtrl.forward(),
        onTapUp: (_) {
          _scaleCtrl.reverse();
          _open();
        },
        onTapCancel: () => _scaleCtrl.reverse(),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4285F4), Color(0xFF6366F1)],
              ),
            ),
            child: const Icon(
                LucideIcons.sparkles, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CHAT SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchFollowUpChat extends ConsumerStatefulWidget {
  const _SearchFollowUpChat({
    required this.query,
    required this.initialAnswer,
    required this.model,
  });

  final String query;
  final String initialAnswer;
  final String model;

  @override
  ConsumerState<_SearchFollowUpChat> createState() =>
      _SearchFollowUpChatState();
}

class _SearchFollowUpChatState extends ConsumerState<_SearchFollowUpChat>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  var _messages = <_ChatMessage>[];
  bool _sending = false;
  bool _useDeepModel = false;
  late bool _useXGrok;
  bool _maximized = false;
  bool _voiceListening = false;
  String _loadingPhase = '';
  Timer? _phaseTimer;
  Timer? _elapsedTimer;
  DateTime? _sendStartTime;
  String _elapsedText = '';
  int _idSeq = 0;

  late final AnimationController _entryAnim;

  String _nextId() =>
      'sf-${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  @override
  void initState() {
    super.initState();
    _useXGrok = ref.read(settingsProvider).defaultFollowUpIsXGrok;

    final store = SearchFollowUpStore.instance;
    store.init();
    store.addListener(widget.query, _onStoreUpdate);

    WidgetsBinding.instance.addObserver(this);
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _loadFromStore();
  }

  void _loadFromStore() {
    final store = SearchFollowUpStore.instance;
    final cached = store.getCached(widget.query);
    final hasPending = store.hasPending(widget.query);

    setState(() {
      _messages = List<_ChatMessage>.of(cached);
      _sending = hasPending;
    });

    if (hasPending) _startLoadingPhases();

    // Auto-retry orphaned question (app was killed mid-request)
    if (!hasPending && _messages.isNotEmpty && _messages.last.role == 'user') {
      _autoRetryOrphan(store);
    }

    if (_messages.isNotEmpty) _scrollToBottom();
  }

  void _autoRetryOrphan(SearchFollowUpStore store) {
    final providerTag = _useXGrok ? 'xGrok' : 'Gemini';
    final modeTag = _useDeepModel ? 'Deep' : 'Lite';
    TLog.i('SearchChat', 'Auto-retrying orphaned question [$providerTag/$modeTag]');
    final orphanedUserMsg = _messages.last;
    final aiMsg = _ChatMessage(
      id: _nextId(),
      role: 'assistant',
      text: '',
      isLoading: true,
    );

    final allPairs = <Map<String, String>>[];
    for (var i = 0; i < _messages.length - 1; i++) {
      final m = _messages[i];
      if (m.isLoading || m.isError) continue;
      if (m.role == 'user' && i + 1 < _messages.length - 1) {
        final next = _messages[i + 1];
        if (next.role == 'assistant' && !next.isError && !next.isLoading) {
          allPairs.add({'role': 'user', 'text': m.text});
          allPairs.add({'role': 'assistant', 'text': next.text});
          i++;
        }
      }
    }

    final history = _buildHistoryWithSummary(store, allPairs);

    setState(() {
      _messages.add(aiMsg);
      _sending = true;
    });
    _startLoadingPhases();
    _scrollToBottom();

    final settings = ref.read(settingsProvider);
    final xgrokOn = settings.xgrokEnabled && _useXGrok;

    store.sendQuestion(
      query: widget.query,
      initialAnswer: widget.initialAnswer,
      userMsg: orphanedUserMsg,
      aiMsg: aiMsg,
      history: history,
      aiService: ref.read(tutorAiServiceProvider),
      mode: _useDeepModel ? null : 'lite',
      deepModel: _useDeepModel ? settings.deepModel : null,
      liteModel: (_useDeepModel || xgrokOn) ? null : settings.liteModel,
      provider: xgrokOn ? 'xgrok' : null,
      xgrokLiteModel: xgrokOn ? settings.xgrokLiteModel : null,
      xgrokDeepModel: xgrokOn ? settings.xgrokDeepModel : null,
      xgrokThinkingModel: xgrokOn ? settings.xgrokThinkingModel : null,
    );
  }

  void _onStoreUpdate() {
    if (!mounted) return;
    final store = SearchFollowUpStore.instance;
    final cached = store.getCached(widget.query);
    final stillPending = store.hasPending(widget.query);
    if (!stillPending) _stopLoadingPhases();
    setState(() {
      _messages = List<_ChatMessage>.of(cached);
      _sending = stillPending;
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    SearchFollowUpStore.instance.removeListener(widget.query, _onStoreUpdate);
    WidgetsBinding.instance.removeObserver(this);
    _phaseTimer?.cancel();
    _elapsedTimer?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _entryAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final store = SearchFollowUpStore.instance;
      final cached = store.getCached(widget.query);
      final stillPending = store.hasPending(widget.query);
      setState(() {
        _messages = List<_ChatMessage>.of(cached);
        _sending = stillPending;
      });
      if (!stillPending) _stopLoadingPhases();
      _scrollToBottom();
    }
  }

  static const _litePhases = [
    'Searching the web\u2026',
    'Analyzing context\u2026',
    'Composing answer\u2026',
  ];

  static const _deepPhases = [
    'Searching the web\u2026',
    'Analyzing context\u2026',
    'Finding relevant info\u2026',
    'Cross-referencing sources\u2026',
    'Synthesizing insights\u2026',
    'Composing detailed answer\u2026',
  ];

  static const _extendedPhases = [
    'Deep analysis in progress\u2026',
    'Still working on it\u2026',
    'Refining the response\u2026',
    'Almost there\u2026',
  ];

  void _startLoadingPhases() {
    if (_phaseTimer != null) return;
    _sendStartTime = DateTime.now();
    _startElapsedTimer();

    final phases = _useDeepModel ? _deepPhases : _litePhases;
    int idx = 0;
    setState(() => _loadingPhase = phases[0]);

    _phaseTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      idx++;
      if (!mounted) return;
      String phase;
      if (idx < phases.length) {
        phase = phases[idx];
      } else {
        final extIdx = (idx - phases.length) % _extendedPhases.length;
        phase = _extendedPhases[extIdx];
      }
      setState(() => _loadingPhase = phase);
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedText = '';
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sendStartTime == null) return;
      final secs = DateTime.now().difference(_sendStartTime!).inSeconds;
      if (secs < 5) return;
      setState(() {
        if (secs < 60) {
          _elapsedText = '${secs}s';
        } else {
          _elapsedText = '${secs ~/ 60}m ${secs % 60}s';
        }
      });
    });
  }

  void _stopLoadingPhases() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _sendStartTime = null;
    _elapsedText = '';
  }

  void _cancel() {
    TLog.i('SearchChat', 'User cancelled follow-up for "${widget.query.length > 40 ? '${widget.query.substring(0, 40)}…' : widget.query}"');
    final store = SearchFollowUpStore.instance;
    final restoredText = store.cancelPending(widget.query);
    _stopLoadingPhases();
    if (restoredText != null && restoredText.isNotEmpty) {
      _ctrl.text = restoredText;
      _ctrl.selection =
          TextSelection.collapsed(offset: restoredText.length);
    }
    _focusNode.requestFocus();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    final providerTag = _useXGrok ? 'xGrok' : 'Gemini';
    final modeTag = _useDeepModel ? 'Deep' : 'Lite';
    TLog.i('SearchChat', 'Sending [$providerTag/$modeTag]: "${text.length > 60 ? '${text.substring(0, 60)}…' : text}"');

    _ctrl.clear();
    _focusNode.requestFocus();

    final store = SearchFollowUpStore.instance;

    final allPairs = <Map<String, String>>[];
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.isLoading || m.isError) continue;
      if (m.role == 'user' && i + 1 < _messages.length) {
        final next = _messages[i + 1];
        if (next.role == 'assistant' && !next.isError && !next.isLoading) {
          allPairs.add({'role': 'user', 'text': m.text});
          allPairs.add({'role': 'assistant', 'text': next.text});
          i++;
        }
      }
    }

    final history = _buildHistoryWithSummary(store, allPairs);

    final userMsg = _ChatMessage(id: _nextId(), role: 'user', text: text);
    final aiMsg = _ChatMessage(
        id: _nextId(), role: 'assistant', text: '', isLoading: true);

    setState(() {
      _messages.add(userMsg);
      _messages.add(aiMsg);
      _sending = true;
    });

    _startLoadingPhases();
    _scrollToBottom();

    final settings = ref.read(settingsProvider);
    final xgrokOn = settings.xgrokEnabled && _useXGrok;

    store.sendQuestion(
      query: widget.query,
      initialAnswer: widget.initialAnswer,
      userMsg: userMsg,
      aiMsg: aiMsg,
      history: history,
      aiService: ref.read(tutorAiServiceProvider),
      mode: _useDeepModel ? null : 'lite',
      deepModel: _useDeepModel ? settings.deepModel : null,
      liteModel: (_useDeepModel || xgrokOn) ? null : settings.liteModel,
      provider: xgrokOn ? 'xgrok' : null,
      xgrokLiteModel: xgrokOn ? settings.xgrokLiteModel : null,
      xgrokDeepModel: xgrokOn ? settings.xgrokDeepModel : null,
      xgrokThinkingModel: xgrokOn ? settings.xgrokThinkingModel : null,
    );
  }

  List<Map<String, String>> _buildHistoryWithSummary(
      SearchFollowUpStore store, List<Map<String, String>> allPairs) {
    final pairCount = allPairs.length ~/ 2;
    if (pairCount <= SearchFollowUpStore.kSummarizeThreshold) {
      return allPairs;
    }

    const recentCount = SearchFollowUpStore.kRecentPairsToKeep * 2;
    final recentStart = allPairs.length - recentCount;
    final oldPairs = allPairs.sublist(0, recentStart);
    final recentPairs = allPairs.sublist(recentStart);
    final oldPairCount = oldPairs.length ~/ 2;

    final summary = store.getSummary(widget.query);

    if (summary != null && summary.pairsCovered >= oldPairCount) {
      TLog.d('SearchChat',
          'Using cached summary (${summary.pairsCovered} pairs) + ${SearchFollowUpStore.kRecentPairsToKeep} recent');
      return [
        {
          'role': 'user',
          'text':
              '[Summary of our earlier conversation (${summary.pairsCovered} exchanges)]:\n${summary.text}',
        },
        {
          'role': 'assistant',
          'text':
              'I have context from our earlier discussion and will use it to answer your questions.',
        },
        ...recentPairs,
      ];
    }

    if (summary != null) {
      TLog.d('SearchChat',
          'Stale summary (${summary.pairsCovered}/$oldPairCount pairs) — using it + recent, re-summarizing in background');
      _triggerBackgroundSummarization(store, summary, oldPairs, oldPairCount);
      return [
        {
          'role': 'user',
          'text':
              '[Summary of our earlier conversation (${summary.pairsCovered} exchanges)]:\n${summary.text}',
        },
        {
          'role': 'assistant',
          'text':
              'I have context from our earlier discussion and will use it to answer your questions.',
        },
        ...recentPairs,
      ];
    }

    TLog.d('SearchChat',
        'No summary — sending ${recentPairs.length ~/ 2} recent pairs, triggering background summarization');
    _triggerBackgroundSummarization(store, null, oldPairs, oldPairCount);
    return recentPairs;
  }

  void _triggerBackgroundSummarization(
      SearchFollowUpStore store,
      _SearchConversationSummary? existingSummary,
      List<Map<String, String>> oldPairs,
      int totalOldPairCount) {
    final query = widget.query;
    if (store._summarizingQueries.contains(query)) {
      TLog.d('SearchChat',
          'Summarization already in-flight for "$query" — skipping');
      return;
    }
    store._summarizingQueries.add(query);

    final aiService = ref.read(tutorAiServiceProvider);
    final liteModel = ref.read(settingsProvider).liteModel;
    unawaited(() async {
      try {
        final messagesToSummarize = <Map<String, String>>[];

        if (existingSummary != null) {
          final alreadyCovered = existingSummary.pairsCovered * 2;
          messagesToSummarize.add({
            'role': 'user',
            'text':
                '[Previous summary covering ${existingSummary.pairsCovered} exchanges]:\n${existingSummary.text}',
          });
          messagesToSummarize.add({
            'role': 'assistant',
            'text': 'Understood.',
          });
          if (alreadyCovered < oldPairs.length) {
            messagesToSummarize.addAll(oldPairs.sublist(alreadyCovered));
          }
        } else {
          messagesToSummarize.addAll(oldPairs);
        }

        final summary = await aiService.summarizeHistory(
          messages: messagesToSummarize,
          articleContext: query,
          liteModel: liteModel,
        );
        if (summary.isNotEmpty) {
          store.saveSummary(query, summary, totalOldPairCount);
          TLog.i('SearchChat',
              'Background summarization complete for "$query" ($totalOldPairCount pairs)');
        } else {
          TLog.w('SearchChat',
              'Background summarization returned empty for "$query"');
        }
      } catch (e) {
        TLog.w('SearchChat', 'Background summarization failed', error: e);
      } finally {
        store._summarizingQueries.remove(query);
      }
    }());
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;
    final safePad = MediaQuery.viewPaddingOf(context).bottom;

    return AnimatedBuilder(
      animation: _entryAnim,
      builder: (context, child) {
        final slide = Tween<double>(begin: 40, end: 0)
            .animate(CurvedAnimation(
                parent: _entryAnim, curve: Curves.easeOutCubic))
            .value;
        return Transform.translate(
          offset: Offset(0, slide),
          child: Opacity(opacity: _entryAnim.value, child: child),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        height: _maximized
            ? MediaQuery.sizeOf(context).height
            : MediaQuery.sizeOf(context).height * 0.78,
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_maximized ? 0 : 24),
          ),
          border: _maximized
              ? null
              : Border(top: BorderSide(color: colors.border)),
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              height: _maximized
                  ? MediaQuery.viewPaddingOf(context).top + 4
                  : 0,
              color: _maximized ? colors.bg : null,
            ),
            _buildHeader(colors),
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmpty(colors)
                  : _buildChat(colors),
            ),
            _buildInput(colors, bottomPad > 0 ? bottomPad : safePad),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors) {
    final subtitle = widget.query.length > 50
        ? '${widget.query.substring(0, 50)}…'
        : widget.query;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF4285F4), Color(0xFF6366F1)],
              ),
            ),
            child: const Icon(LucideIcons.sparkles,
                size: 14, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask AI',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4285F4),
                ),
              ),
            ),
          _MaximizeButton(
            maximized: _maximized,
            colors: colors,
            onTap: () => setState(() => _maximized = !_maximized),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 18, color: colors.text3),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4285F4).withValues(alpha: 0.08),
              border: Border.all(
                color: const Color(0xFF4285F4).withValues(alpha: 0.2),
              ),
            ),
            child: const Icon(LucideIcons.messageCircle,
                size: 20, color: Color(0xFF4285F4)),
          ),
          const SizedBox(height: 12),
          Text(
            'Ask follow-up questions',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _useXGrok && ref.watch(settingsProvider).xgrokEnabled
                ? 'Powered by xGrok with real-time search.\n'
                  'Toggle Lite/Deep and Gemini/xGrok below.'
                : 'Powered by Gemini with real-time search.\n'
                  'Toggle Lite (fast) or Deep (thorough) below.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              height: 1.5,
              color: colors.text3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChat(AppColors colors) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _buildMessage(colors, _messages[i]),
    );
  }

  // ── Loading bubble with animated phases ─────────────────────────────────

  Widget _buildLoadingBubble(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiBadge(),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.bg2,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: colors.border2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _TypingDots(),
                      const SizedBox(width: 10),
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _loadingPhase,
                            key: ValueKey(_loadingPhase),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF4285F4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _modelChip(
                          colors, _useDeepModel ? 'deep' : 'lite'),
                      const SizedBox(width: 6),
                      _metaChip(
                        colors,
                        _useXGrok ? 'xGrok' : 'Gemini',
                        _useXGrok
                            ? LucideIcons.bot
                            : LucideIcons.sparkles,
                        _useXGrok
                            ? const Color(0xFFE8453C)
                            : const Color(0xFF4285F4),
                      ),
                      if (_elapsedText.isNotEmpty) ...[
                        const Spacer(),
                        Text(
                          _elapsedText,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.text4,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor:
                          const Color(0xFF4285F4).withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF4285F4)),
                    ),
                  ),
                  if (_useDeepModel) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Deep analysis may take up to a minute. '
                      'You can minimize the app.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: colors.text5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildMessage(AppColors colors, _ChatMessage msg) {
    if (msg.isLoading) return _buildLoadingBubble(colors);

    final isUser = msg.role == 'user';

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 40),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border.all(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.2),
                  ),
                ),
                child: SelectableText(
                  msg.text,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.6,
                    color: colors.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isError = msg.isError;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiBadge(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isError
                        ? const Color(0xFFFF6B6B).withValues(alpha: 0.08)
                        : colors.bg2,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: isError
                          ? const Color(0xFFFF6B6B).withValues(alpha: 0.2)
                          : colors.border2,
                    ),
                  ),
                  child: isError
                      ? SelectableText(
                          msg.text,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            height: 1.7,
                            color: const Color(0xFFFF6B6B),
                          ),
                        )
                      : SelectionArea(
                          child: MarkdownBody(
                            data: msg.text,
                            selectable: false,
                            onTapLink: (_, href, __) async {
                              if (href == null || href.isEmpty) return;
                              final uri = Uri.tryParse(href);
                              if (uri == null) return;
                              try {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              } catch (e) {
                                TLog.w('SearchChat', 'Failed to launch URL: $href', error: e);
                              }
                            },
                            styleSheet: _chatMarkdownStyle(colors),
                          ),
                        ),
                ),
                if (msg.model.isNotEmpty || msg.sources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (msg.model.isNotEmpty)
                          _modelChip(colors, msg.model),
                        if (msg.sources.isNotEmpty)
                          _metaChip(
                            colors,
                            '${msg.sources.length} sources',
                            LucideIcons.link,
                            const Color(0xFF34D399),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  MarkdownStyleSheet _chatMarkdownStyle(AppColors colors) {
    const accent = Color(0xFF4285F4);
    return MarkdownStyleSheet(
      p: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        height: 1.7,
        color: colors.text,
      ),
      pPadding: const EdgeInsets.only(bottom: 6),
      h1: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        height: 1.3,
        color: colors.text,
      ),
      h1Padding: const EdgeInsets.only(top: 6, bottom: 4),
      h2: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        height: 1.35,
        color: colors.text,
      ),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h3: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: colors.text,
      ),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 2),
      strong: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w700,
        color: colors.text,
      ),
      em: GoogleFonts.plusJakartaSans(
        fontStyle: FontStyle.italic,
        color: colors.text3,
      ),
      blockquote: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontStyle: FontStyle.italic,
        height: 1.6,
        color: colors.text2,
      ),
      blockquoteDecoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      listBullet: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: accent,
      ),
      listBulletPadding: const EdgeInsets.only(right: 6),
      listIndent: 18,
      tableHead: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: colors.text,
      ),
      tableBody: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        height: 1.5,
        color: colors.text2,
      ),
      tableBorder: TableBorder.all(
        color: colors.border,
        borderRadius: BorderRadius.circular(8),
      ),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tableColumnWidth: const FlexColumnWidth(),
      code: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        color: accent,
        backgroundColor: colors.bg3,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      a: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: accent,
        decoration: TextDecoration.underline,
        decorationColor: accent.withValues(alpha: 0.4),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border, width: 0.5),
        ),
      ),
    );
  }

  Widget _aiBadge() {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF4285F4), Color(0xFF6366F1)],
        ),
      ),
      child: const Icon(LucideIcons.sparkles, size: 12, color: Colors.white),
    );
  }

  Widget _metaChip(
      AppColors colors, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelChip(AppColors colors, String model) {
    final isLite = model.toLowerCase().contains('lite') ||
        model.toLowerCase().contains('flash');
    final color =
        isLite ? const Color(0xFF4285F4) : const Color(0xFFC084FC);
    final icon = isLite ? LucideIcons.zap : LucideIcons.brain;
    final label = isLite ? 'Lite' : 'Deep';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(AppColors colors, double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 12, bottomPad + 10),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModelToggle(colors),
              if (ref.watch(settingsProvider).xgrokEnabled) ...[
                const SizedBox(width: 6),
                _buildProviderToggle(colors),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.bg2,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: colors.border),
                      ),
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: colors.text,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ask a follow-up question…',
                          hintStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: colors.text4,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  VoiceInputButton(
                    controller: _ctrl,
                    colors: colors,
                    disabled: _sending,
                    tag: 'SearchVoice',
                    onListeningChanged: (v) {
                      if (mounted) setState(() => _voiceListening = v);
                    },
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _voiceListening
                        ? null
                        : (_sending ? _cancel : _send),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _voiceListening
                            ? colors.bg3
                            : (_sending
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF4285F4)),
                      ),
                      child: _sending
                          ? Center(
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            )
                          : Icon(
                              LucideIcons.send,
                              size: 16,
                              color: _voiceListening
                                  ? colors.text5
                                  : Colors.white,
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

  Widget _buildModelToggle(AppColors colors) {
    const liteColor = Color(0xFF4285F4);
    const deepColor = Color(0xFFC084FC);

    return GestureDetector(
      onTap: _sending
          ? null
          : () {
              HapticFeedback.selectionClick();
              setState(() => _useDeepModel = !_useDeepModel);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _toggleChip(
              label: 'Lite',
              icon: LucideIcons.zap,
              active: !_useDeepModel,
              color: liteColor,
              colors: colors,
            ),
            const SizedBox(width: 2),
            _toggleChip(
              label: 'Deep',
              icon: LucideIcons.brain,
              active: _useDeepModel,
              color: deepColor,
              colors: colors,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderToggle(AppColors colors) {
    const geminiColor = Color(0xFF4285F4);
    const xgrokColor = Color(0xFFE8453C);

    return GestureDetector(
      onTap: _sending
          ? null
          : () {
              HapticFeedback.selectionClick();
              setState(() => _useXGrok = !_useXGrok);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _toggleChip(
              label: 'Gemini',
              icon: LucideIcons.sparkles,
              active: !_useXGrok,
              color: geminiColor,
              colors: colors,
            ),
            const SizedBox(width: 2),
            _toggleChip(
              label: 'xGrok',
              icon: LucideIcons.bot,
              active: _useXGrok,
              color: xgrokColor,
              colors: colors,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color color,
    required AppColors colors,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: active ? color : colors.text5,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? color : colors.text4,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TYPING DOTS ANIMATION
// ═══════════════════════════════════════════════════════════════════════════════

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
            final y = -3.0 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Transform.translate(
              offset: Offset(0, y),
              child: Container(
                width: 6,
                height: 6,
                margin: EdgeInsets.only(right: i < 2 ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4285F4)
                      .withValues(alpha: 0.4 + 0.6 * (1 - (y.abs() / 3))),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  const _MaximizeButton({
    required this.maximized,
    required this.colors,
    required this.onTap,
  });

  final bool maximized;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.85,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.reverse(),
      onTapUp: (_) {
        _press.forward();
        widget.onTap();
      },
      onTapCancel: () => _press.forward(),
      child: ScaleTransition(
        scale: _press,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: widget.maximized
                ? const Color(0xFF4285F4).withValues(alpha: 0.14)
                : widget.colors.bg3,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.maximized
                  ? const Color(0xFF4285F4).withValues(alpha: 0.3)
                  : widget.colors.border,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            child: Icon(
              widget.maximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
              key: ValueKey(widget.maximized),
              size: 14,
              color: widget.maximized
                  ? const Color(0xFF4285F4)
                  : widget.colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}
