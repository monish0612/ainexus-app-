import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/services/tutor_ai_service.dart';
import '../../../domain/entities/tutor_entities.dart';
import '../../widgets/voice_input_button.dart';
import '../settings/settings_controller.dart';

class _ChatMessage {
  _ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.sources = const [],
    this.model = '',
    this.isLoading = false,
    this.isError = false,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc().toIso8601String();

  final String id;
  final String role;
  final String createdAt;
  String text;
  List<GroundedSource> sources;
  String model;
  bool isLoading;
  bool isError;

  String _sourcesToJson() {
    if (sources.isEmpty) return '[]';
    return jsonEncode(sources
        .map((s) => {'index': s.index, 'title': s.title, 'url': s.url})
        .toList());
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
    } catch (_) {
      return const [];
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PERSISTENT STORE — in-memory cache backed by Drift + background server sync
// ═══════════════════════════════════════════════════════════════════════════════

class _ArticleRetry {
  _ArticleRetry({
    required this.articleTitle,
    required this.articleUrl,
    required this.aiMsg,
    required this.history,
    required this.question,
    required this.aiService,
    this.mode,
    this.deepModel,
    this.provider,
    this.xgrokLiteModel,
    this.xgrokDeepModel,
    this.xgrokThinkingModel,
  });

  final String articleTitle;
  final String articleUrl;
  final _ChatMessage aiMsg;
  final List<Map<String, String>> history;
  final String question;
  final TutorAiService aiService;
  final String? mode;
  final String? deepModel;
  final String? provider;
  final String? xgrokLiteModel;
  final String? xgrokDeepModel;
  final String? xgrokThinkingModel;
}

class _ConversationSummary {
  _ConversationSummary({required this.text, required this.pairsCovered});
  final String text;
  final int pairsCovered;
}

class ArticleFollowUpStore with WidgetsBindingObserver {
  ArticleFollowUpStore._();
  static final instance = ArticleFollowUpStore._();

  static const kSummarizeThreshold = 10;
  static const kRecentPairsToKeep = 5;

  final _cache = <String, List<_ChatMessage>>{};
  final _summaries = <String, _ConversationSummary>{};
  AppDatabase? _db;
  ApiClient? _api;
  bool _observerBound = false;

  /// Per-article UI refresh callbacks (registered by the chat sheet widget).
  final _listeners = <String, VoidCallback>{};

  /// In-flight AI messages keyed by articleId — survives widget disposal.
  final _pendingAiMsgs = <String, _ChatMessage>{};

  /// Per-article retry queue for connection-abort recovery on app resume.
  final _retryQueue = <String, _ArticleRetry>{};

  /// Per-article Dio cancel tokens for user-initiated stop.
  final _cancelTokens = <String, CancelToken>{};

  /// Prevents concurrent background summarizations for the same article.
  final _summarizingArticleIds = <String>{};

  /// Human-readable title for each pending article (used in notifications).
  final _pendingTitles = <String, String>{};

  /// Whether the host app is currently in the background.
  bool _appInBackground = false;

  // ── Background notification helpers ──────────────────────────────────────

  static const _kAiChannelId = 'nexus_ai_processing';
  static const _kAiChannelName = 'AI Processing';
  static const _kAiChannelDesc =
      'Shows progress when AI generates answers in the background';
  static const _kProcessingNotifId = 9200;
  static const _kCompletionNotifId = 9201;

  static FlutterLocalNotificationsPlugin? _notifPlugin;

  static Future<FlutterLocalNotificationsPlugin> _ensureNotifPlugin() async {
    if (_notifPlugin != null) return _notifPlugin!;
    _notifPlugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifPlugin!
        .initialize(const InitializationSettings(android: android));
    return _notifPlugin!;
  }

  Future<void> _showProcessingNotification(String articleTitle) async {
    try {
      final fln = await _ensureNotifPlugin();
      final title = articleTitle.length > 50
          ? '${articleTitle.substring(0, 50)}…'
          : articleTitle;
      const details = AndroidNotificationDetails(
        _kAiChannelId,
        _kAiChannelName,
        channelDescription: _kAiChannelDesc,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showProgress: true,
        indeterminate: true,
        category: AndroidNotificationCategory.progress,
        color: ui.Color(0xFF0D59F2),
      );
      await fln.show(
        _kProcessingNotifId,
        '\u2728 AI is thinking\u2026',
        'Generating answer for "$title"',
        const NotificationDetails(android: details),
      );
    } catch (e) {
      TLog.w('ChatStore', 'Failed to show processing notification', error: e);
    }
  }

  Future<void> _showCompletionNotification(String articleTitle) async {
    try {
      final fln = await _ensureNotifPlugin();
      await fln.cancel(_kProcessingNotifId);
      final title = articleTitle.length > 50
          ? '${articleTitle.substring(0, 50)}…'
          : articleTitle;
      const details = AndroidNotificationDetails(
        _kAiChannelId,
        _kAiChannelName,
        channelDescription: _kAiChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        color: ui.Color(0xFF0D59F2),
      );
      await fln.show(
        _kCompletionNotifId,
        '\u2705 Answer ready',
        'Your question about "$title" has been answered',
        const NotificationDetails(android: details),
        payload: 'news_tab',
      );
    } catch (e) {
      TLog.w('ChatStore', 'Failed to show completion notification', error: e);
    }
  }

  Future<void> _cancelProcessingNotification() async {
    try {
      final fln = await _ensureNotifPlugin();
      await fln.cancel(_kProcessingNotifId);
    } catch (_) {}
  }

  void init(AppDatabase db, ApiClient api) {
    _db = db;
    _api = api;
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ── Going to background ──────────────────────────────────────────────
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_appInBackground && _pendingAiMsgs.isNotEmpty) {
        _appInBackground = true;
        final title =
            _pendingTitles.values.firstOrNull ?? 'your article';
        unawaited(_showProcessingNotification(title));
      }
      return;
    }

    // ── Returning to foreground ──────────────────────────────────────────
    if (state != AppLifecycleState.resumed) return;

    final wasInBackground = _appInBackground;
    _appInBackground = false;
    if (wasInBackground) {
      unawaited(_cancelProcessingNotification());
    }

    if (_retryQueue.isEmpty) return;
    final entries = Map.of(_retryQueue);
    _retryQueue.clear();

    // Let the OS fully restore network connectivity before retrying.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      for (final e in entries.entries) {
        final articleId = e.key;
        final r = e.value;
        TLog.d('ChatStore', 'Resumed — retrying follow-up for $articleId');
        r.aiMsg
          ..text = ''
          ..isLoading = true
          ..isError = false;
        _pendingAiMsgs[articleId] = r.aiMsg;
        _listeners[articleId]?.call();
        unawaited(_executeRequest(
          articleId: articleId,
          articleTitle: r.articleTitle,
          articleUrl: r.articleUrl,
          aiMsg: r.aiMsg,
          history: r.history,
          question: r.question,
          aiService: r.aiService,
          mode: r.mode,
          deepModel: r.deepModel,
          provider: r.provider,
          xgrokLiteModel: r.xgrokLiteModel,
          xgrokDeepModel: r.xgrokDeepModel,
          xgrokThinkingModel: r.xgrokThinkingModel,
          isRetry: true,
        ));
      }
    });
  }

  /// Returns true when the backend responds 400 due to context/token overflow.
  /// Intentionally avoids matching bare 'token' to prevent false positives
  /// on authentication errors ("invalid token").
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

  /// Returns true for ANY Dio transport-level error (timeout, socket kill,
  /// connection reset, etc.) — all of which are retryable after resume.
  /// Only HTTP response errors (4xx/5xx) are considered non-retryable.
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

  void addListener(String articleId, VoidCallback cb) =>
      _listeners[articleId] = cb;

  /// Only removes the listener if [cb] matches the currently registered one,
  /// preventing a stale dispose from removing a freshly registered listener.
  void removeListener(String articleId, VoidCallback cb) {
    if (_listeners[articleId] == cb) _listeners.remove(articleId);
  }

  bool hasPending(String articleId) =>
      _pendingAiMsgs.containsKey(articleId);

  List<_ChatMessage> getCached(String articleId) =>
      _cache[articleId] ?? const [];

  // ── Load ─────────────────────────────────────────────────────────────────

  /// Load messages for [articleId] from local DB (fast), then merge from server.
  Future<List<_ChatMessage>> load(String articleId) async {
    final cached = _cache[articleId];
    if (cached != null && cached.isNotEmpty) {
      TLog.d('ChatStore', 'Cache hit for $articleId → ${cached.length} msgs');
      return cached;
    }

    final messages = <_ChatMessage>[];
    try {
      final db = _db;
      if (db == null) {
        TLog.w('ChatStore', 'DB null during load for $articleId — cannot read persisted chats');
      } else {
        final rows = await (db.select(db.articleChatMessages)
              ..where((t) => t.articleId.equals(articleId))
              ..orderBy([(t) => drift.OrderingTerm.asc(t.createdAt)]))
            .get();
        for (final r in rows) {
          messages.add(_ChatMessage(
            id: r.id,
            role: r.role,
            text: r.msgText,
            model: r.model,
            sources: _ChatMessage._sourcesFromJson(r.sourcesJson),
            createdAt: r.createdAt,
          ));
        }
        TLog.d('ChatStore', 'DB load for $articleId → ${messages.length} msgs');
      }
    } catch (e) {
      TLog.e('ChatStore', 'Local load failed for $articleId', error: e);
    }

    _cache[articleId] = messages;
    unawaited(_syncFromServer(articleId));
    return messages;
  }

  // ── Persist ──────────────────────────────────────────────────────────────

  /// Persist a message locally and queue server sync.
  Future<void> persist(String articleId, _ChatMessage msg) async {
    final list = _cache[articleId];
    if (list != null && !list.any((m) => m.id == msg.id)) {
      list.add(msg);
    }

    try {
      final db = _db;
      if (db == null) {
        TLog.w('ChatStore',
            'DB null during persist — message ${msg.id} cached only (will not survive restart)');
      } else {
        await db.into(db.articleChatMessages).insertOnConflictUpdate(
          ArticleChatMessagesCompanion.insert(
            id: msg.id,
            articleId: articleId,
            role: msg.role,
            msgText: msg.text,
            model: drift.Value(msg.model),
            sourcesJson: drift.Value(msg._sourcesToJson()),
            createdAt: msg.createdAt,
          ),
        );
        TLog.d('ChatStore', 'Persisted ${msg.role} msg ${msg.id} for $articleId');
      }
    } catch (e) {
      TLog.e('ChatStore', 'Local persist failed: ${msg.id}', error: e);
    }

    unawaited(_syncMessageToServer(articleId, msg));
  }

  // ── Fire-and-forget AI request ───────────────────────────────────────────

  /// Start an AI request that survives widget disposal.
  /// Adds both messages to cache immediately and runs the API call in background.
  void sendQuestion({
    required String articleId,
    required String articleTitle,
    required String articleUrl,
    required _ChatMessage userMsg,
    required _ChatMessage aiMsg,
    required List<Map<String, String>> history,
    required TutorAiService aiService,
    String? mode,
    String? deepModel,
    String? provider,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
  }) {
    TLog.d('ChatStore', 'sendQuestion mode=${mode ?? 'deep'}, provider=${provider ?? 'gemini'}, histLen=${history.length}');
    _cache.putIfAbsent(articleId, () => []);
    final list = _cache[articleId]!;

    if (!list.any((m) => m.id == userMsg.id)) list.add(userMsg);
    if (!list.any((m) => m.id == aiMsg.id)) list.add(aiMsg);

    _pendingAiMsgs[articleId] = aiMsg;
    _pendingTitles[articleId] = articleTitle;
    final token = CancelToken();
    _cancelTokens[articleId] = token;

    unawaited(_executeRequest(
      articleId: articleId,
      articleTitle: articleTitle,
      articleUrl: articleUrl,
      aiMsg: aiMsg,
      history: history,
      question: userMsg.text,
      aiService: aiService,
      mode: mode,
      deepModel: deepModel,
      provider: provider,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
      cancelToken: token,
    ));
  }

  /// Cancel the in-flight request for [articleId]. Returns the user's question
  /// text so the UI can restore it to the input field.
  String? cancelPending(String articleId) {
    _cancelTokens[articleId]?.cancel('User cancelled');
    _cancelTokens.remove(articleId);
    _retryQueue.remove(articleId);

    final list = _cache[articleId];
    if (list == null || list.isEmpty) {
      _pendingAiMsgs.remove(articleId);
      _listeners[articleId]?.call();
      return null;
    }

    String? userText;
    String? cancelledUserMsgId;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].isLoading && list[i].role == 'assistant') {
        list.removeAt(i);
        if (i > 0 && list[i - 1].role == 'user') {
          cancelledUserMsgId = list[i - 1].id;
          userText = list[i - 1].text;
          list.removeAt(i - 1);
        }
        break;
      }
    }

    _pendingAiMsgs.remove(articleId);
    _pendingTitles.remove(articleId);
    _listeners[articleId]?.call();

    if (cancelledUserMsgId != null) {
      _deleteCancelledMsg(cancelledUserMsgId);
    }

    return userText;
  }

  /// Fire-and-forget cleanup of a cancelled user message from the local DB
  /// to prevent orphan auto-retry on next sheet open.
  void _deleteCancelledMsg(String msgId) {
    final db = _db;
    if (db == null) return;
    unawaited(
      (db.delete(db.articleChatMessages)
            ..where((t) => t.id.equals(msgId)))
          .go()
          .catchError((_) => 0),
    );
  }

  Future<void> _executeRequest({
    required String articleId,
    required String articleTitle,
    required String articleUrl,
    required _ChatMessage aiMsg,
    required List<Map<String, String>> history,
    required String question,
    required TutorAiService aiService,
    String? mode,
    String? deepModel,
    String? provider,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
    bool isRetry = false,
  }) async {
    if (!isRetry && !(cancelToken?.isCancelled ?? false)) {
      final list = _cache[articleId];
      if (list != null) {
        final aiIdx = list.indexOf(aiMsg);
        if (aiIdx > 0) {
          await persist(articleId, list[aiIdx - 1]);
        }
      }
    }
    if (cancelToken?.isCancelled ?? false) return;

    bool keepPending = false;

    try {
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (cancelToken?.isCancelled ?? false) return;
        try {
          final result = await aiService.articleFollowUp(
            question: question,
            articleUrl: articleUrl,
            articleTitle: articleTitle,
            history: history,
            mode: mode,
            deepModel: deepModel,
            provider: provider,
            xgrokLiteModel: xgrokLiteModel,
            xgrokDeepModel: xgrokDeepModel,
            xgrokThinkingModel: xgrokThinkingModel,
            cancelToken: cancelToken,
          );
          if (!_cache.containsKey(articleId)) return;
          if (cancelToken?.isCancelled ?? false) return;
          aiMsg
            ..text = result.answer
            ..sources = result.sources
            ..model = mode ?? 'deep'
            ..isLoading = false;
          await persist(articleId, aiMsg);
          return;
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) return;
          if (e is DioException && e.response?.statusCode == 404) {
            TLog.w('FollowUp', 'Endpoint not deployed — using mock response');
            await Future<void>.delayed(const Duration(seconds: 3));
            if (!_cache.containsKey(articleId)) return;
            final mock = _mockAnswer(question, articleTitle);
            aiMsg
              ..text = mock
              ..sources = [
                GroundedSource(
                    index: 0, title: articleTitle, url: articleUrl),
                const GroundedSource(
                    index: 1,
                    title: 'Google Search',
                    url: 'https://google.com'),
              ]
              ..model = mode ?? 'deep'
              ..isLoading = false;
            await persist(articleId, aiMsg);
            return; // mock success
          }

          if (_isContextLimitError(e) && history.length > 4) {
            TLog.w('FollowUp',
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
                articleContext: articleTitle,
              );
              if (summaryText.isNotEmpty) {
                final existingPairs =
                    getSummary(articleId)?.pairsCovered ?? 0;
                final computed = oldPairs.length ~/ 2;
                final safePairsCovered =
                    existingPairs > computed ? existingPairs : computed;
                await saveSummary(
                    articleId, summaryText, safePairsCovered);
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
                final retryResult = await aiService.articleFollowUp(
                  question: question,
                  articleUrl: articleUrl,
                  articleTitle: articleTitle,
                  history: condensedHistory,
                  mode: mode,
                  deepModel: deepModel,
                  provider: provider,
                  xgrokLiteModel: xgrokLiteModel,
                  xgrokDeepModel: xgrokDeepModel,
                  xgrokThinkingModel: xgrokThinkingModel,
                  cancelToken: cancelToken,
                );
                if (!_cache.containsKey(articleId)) return;
                aiMsg
                  ..text = retryResult.answer
                  ..sources = retryResult.sources
                  ..model = mode ?? 'deep'
                  ..isLoading = false;
                await persist(articleId, aiMsg);
                TLog.i('FollowUp',
                    'Context-limit recovery succeeded for $articleId ($safePairsCovered pairs summarized)');
                return;
              } else {
                TLog.w('FollowUp',
                    'Summarize returned empty — cannot recover from context limit');
              }
            } catch (retryErr) {
              TLog.e('FollowUp',
                  'Context-limit recovery failed for $articleId',
                  error: retryErr);
            }
          }

          lastError = e;
          if (!_isRetryableNetworkError(e) ||
              !_cache.containsKey(articleId)) break;
          if (attempt < 2) {
            TLog.w('FollowUp',
                'Network error — retry ${attempt + 1}/2 (${e.runtimeType})');
            await Future.delayed(Duration(seconds: (attempt + 1) * 5));
            if (cancelToken?.isCancelled ?? false) return;
            if (!_cache.containsKey(articleId)) return;
          }
        }
      }

      // Inline retries exhausted
      if (lastError != null &&
          _isRetryableNetworkError(lastError) &&
          _cache.containsKey(articleId)) {
        _retryQueue[articleId] = _ArticleRetry(
          articleTitle: articleTitle,
          articleUrl: articleUrl,
          aiMsg: aiMsg,
          history: history,
          question: question,
          aiService: aiService,
          mode: mode,
          deepModel: deepModel,
          provider: provider,
          xgrokLiteModel: xgrokLiteModel,
          xgrokDeepModel: xgrokDeepModel,
          xgrokThinkingModel: xgrokThinkingModel,
        );
        keepPending = true;
        TLog.w('FollowUp', 'Scheduled auto-retry on resume for $articleId');
      } else if (_cache.containsKey(articleId)) {
        TLog.e('FollowUp', 'Article follow-up failed', error: lastError);
        aiMsg
          ..text = 'Something went wrong. Please try again.'
          ..isLoading = false
          ..isError = true;
      }
    } finally {
      final title = _pendingTitles[articleId];
      if (!keepPending) {
        _pendingAiMsgs.remove(articleId);
        _pendingTitles.remove(articleId);
      }
      _listeners[articleId]?.call();

      if (_appInBackground && !keepPending) {
        unawaited(_cancelProcessingNotification());
        if (!aiMsg.isError && aiMsg.text.isNotEmpty) {
          unawaited(_showCompletionNotification(title ?? 'your article'));
        }
      }
    }
  }

  static String _mockAnswer(String question, String title) {
    final q = question.toLowerCase();
    if (q.contains('summar') || q.contains('about')) {
      return 'Based on the original source article "$title", this piece covers several '
          'key developments:\n\n'
          '1. **Main topic** — The article discusses recent changes and their broader '
          'implications on the industry.\n\n'
          '2. **Key findings** — Multiple experts were quoted highlighting both opportunities '
          'and challenges ahead.\n\n'
          '3. **What\'s next** — The article concludes with upcoming milestones to watch.\n\n'
          '_Note: This is a mock response for UI testing. Deploy the backend to get real '
          'AI-powered answers from the original source article._';
    }
    if (q.contains('who') || q.contains('author')) {
      return 'The article "$title" was published by the original source outlet. '
          'The specific author details would be available from the source URL.\n\n'
          '_Mock response — deploy backend for real answers._';
    }
    if (q.contains('why') || q.contains('reason')) {
      return 'According to the original source for "$title", the primary reasons cited '
          'include:\n\n'
          '• **Economic factors** — Market dynamics and shifting consumer preferences\n'
          '• **Policy changes** — Recent regulatory updates affecting the sector\n'
          '• **Technology** — New innovations driving adoption\n\n'
          '_Mock response — deploy backend for real answers._';
    }
    return 'Great question about "$title"!\n\n'
        'In a real scenario, Gemini 3.1 Pro would:\n'
        '1. Search the web for the original article at the source URL\n'
        '2. Read and analyze the full article content\n'
        '3. Use Google Search grounding for real-time information\n'
        '4. Provide a detailed, cited answer based on the actual source\n\n'
        'Your question: "$question"\n\n'
        'The conversation history is maintained — ask follow-up questions and '
        'the AI will remember this entire chat context.\n\n'
        '_Mock response — deploy backend for real answers._';
  }

  // ── Clear ────────────────────────────────────────────────────────────────

  /// Delete all messages for [articleId] from DB and server.
  Future<void> clear(String articleId) async {
    _cancelTokens[articleId]?.cancel('Cleared');
    _cancelTokens.remove(articleId);
    _cache.remove(articleId);
    _pendingAiMsgs.remove(articleId);
    _pendingTitles.remove(articleId);
    _retryQueue.remove(articleId);

    try {
      final db = _db;
      if (db != null) {
        await (db.delete(db.articleChatMessages)
              ..where((t) => t.articleId.equals(articleId)))
            .go();
      }
    } catch (e) {
      TLog.e('ChatStore', 'Local clear failed: $articleId', error: e);
    }

    unawaited(_clearSummary(articleId));

    try {
      await _api?.delete<Object?>(ApiEndpoints.articleChats(articleId));
    } catch (e) {
      TLog.w('ChatStore', 'Server clear failed: $articleId', error: e);
    }
  }

  void clearAll() {
    for (final t in _cancelTokens.values) {
      t.cancel('Cleared');
    }
    _cancelTokens.clear();
    _cache.clear();
    _summaries.clear();
    _summarizingArticleIds.clear();
    _pendingTitles.clear();
  }

  // ── Conversation summaries ──────────────────────────────────────────────

  _ConversationSummary? getSummary(String articleId) =>
      _summaries[articleId];

  Future<void> loadSummary(String articleId) async {
    if (_summaries.containsKey(articleId)) return;
    try {
      final db = _db;
      if (db != null) {
        final row = await (db.select(db.articleChatSummaries)
              ..where((t) => t.articleId.equals(articleId)))
            .getSingleOrNull();
        if (row != null && row.summaryText.isNotEmpty) {
          _summaries[articleId] = _ConversationSummary(
            text: row.summaryText,
            pairsCovered: row.pairsCovered,
          );
          TLog.d('ChatStore',
              'Loaded summary for $articleId (${row.pairsCovered} pairs)');
        }
      }
    } catch (e) {
      TLog.w('ChatStore', 'Summary load failed: $articleId', error: e);
    }
    unawaited(_loadSummaryFromServer(articleId));
  }

  Future<void> saveSummary(
      String articleId, String text, int pairsCovered) async {
    final existing = _summaries[articleId];
    if (existing != null && existing.pairsCovered > pairsCovered) {
      TLog.w('ChatStore',
          'Blocked summary downgrade for $articleId (${existing.pairsCovered} > $pairsCovered)');
      return;
    }
    _summaries[articleId] =
        _ConversationSummary(text: text, pairsCovered: pairsCovered);
    try {
      final db = _db;
      if (db == null) return;
      await db.into(db.articleChatSummaries).insertOnConflictUpdate(
        ArticleChatSummariesCompanion.insert(
          articleId: articleId,
          summaryText: text,
          pairsCovered: pairsCovered,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      TLog.d('ChatStore',
          'Saved summary for $articleId ($pairsCovered pairs)');
    } catch (e) {
      TLog.w('ChatStore', 'Summary persist failed: $articleId', error: e);
    }
    unawaited(_syncSummaryToServer(articleId, text, pairsCovered));
  }

  Future<void> _syncSummaryToServer(
      String articleId, String text, int pairsCovered) async {
    try {
      await _api?.put<Object?>(
        ApiEndpoints.articleChatSummary(articleId),
        data: <String, dynamic>{
          'summaryText': text,
          'pairsCovered': pairsCovered,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      TLog.d('ChatStore', 'Synced summary to server for $articleId');
    } catch (e) {
      TLog.w('ChatStore', 'Summary server sync failed: $articleId', error: e);
    }
  }

  Future<void> _loadSummaryFromServer(String articleId) async {
    try {
      final response =
          await _api?.get<Object?>(ApiEndpoints.articleChatSummary(articleId));
      final data = response?.data;
      if (data is! Map || data.isEmpty) return;

      final text = data['summaryText']?.toString() ?? '';
      final pairs = data['pairsCovered'];
      final pairsCovered = pairs is int ? pairs : int.tryParse('$pairs') ?? 0;
      if (text.isEmpty || pairsCovered == 0) return;

      final existing = _summaries[articleId];
      if (existing != null && existing.pairsCovered >= pairsCovered) return;

      _summaries[articleId] =
          _ConversationSummary(text: text, pairsCovered: pairsCovered);

      final db = _db;
      if (db != null) {
        await db.into(db.articleChatSummaries).insertOnConflictUpdate(
          ArticleChatSummariesCompanion.insert(
            articleId: articleId,
            summaryText: text,
            pairsCovered: pairsCovered,
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
      }
      TLog.d('ChatStore',
          'Loaded summary from server for $articleId ($pairsCovered pairs)');
    } catch (e) {
      TLog.w('ChatStore',
          'Summary server load failed: $articleId', error: e);
    }
  }

  Future<void> _clearSummary(String articleId) async {
    _summaries.remove(articleId);
    _summarizingArticleIds.remove(articleId);
    try {
      final db = _db;
      if (db != null) {
        await (db.delete(db.articleChatSummaries)
              ..where((t) => t.articleId.equals(articleId)))
            .go();
      }
    } catch (e) {
      TLog.w('ChatStore', 'Local summary clear failed: $articleId', error: e);
    }
    try {
      await _api?.delete<Object?>(ApiEndpoints.articleChatSummary(articleId));
    } catch (e) {
      TLog.w('ChatStore', 'Server summary clear failed: $articleId', error: e);
    }
  }

  // ── Background sync helpers ──────────────────────────────────────────────

  Future<void> _syncFromServer(String articleId) async {
    try {
      final response =
          await _api?.get<Object?>(ApiEndpoints.articleChats(articleId));
      final data = response?.data;
      if (data is! List || data.isEmpty) return;

      final db = _db;
      if (db == null) return;

      final localIds =
          _cache[articleId]?.map((m) => m.id).toSet() ?? <String>{};
      var inserted = 0;

      for (final raw in data) {
        if (raw is! Map) continue;
        final id = raw['id']?.toString() ?? '';
        if (id.isEmpty || localIds.contains(id)) continue;

        final msg = _ChatMessage(
          id: id,
          role: raw['role']?.toString() ?? 'assistant',
          text: raw['text']?.toString() ?? '',
          model: raw['model']?.toString() ?? '',
          sources: _ChatMessage._sourcesFromJson(
              raw['sources_json']?.toString() ?? '[]'),
          createdAt: raw['created_at']?.toString() ?? '',
        );

        await db.into(db.articleChatMessages).insertOnConflictUpdate(
          ArticleChatMessagesCompanion.insert(
            id: msg.id,
            articleId: articleId,
            role: msg.role,
            msgText: msg.text,
            model: drift.Value(msg.model),
            sourcesJson: drift.Value(msg._sourcesToJson()),
            createdAt: msg.createdAt,
          ),
        );

        _cache[articleId]?.add(msg);
        inserted++;
      }

      if (inserted > 0) {
        TLog.d('ChatStore',
            'Merged $inserted server messages for $articleId');
        _listeners[articleId]?.call();
      }
    } catch (e) {
      TLog.w('ChatStore', 'Sync from server failed for $articleId: $e');
    }
  }

  Future<void> _syncMessageToServer(
      String articleId, _ChatMessage msg) async {
    try {
      await _api?.post<Object?>(
        ApiEndpoints.articleChats(articleId),
        data: <String, dynamic>{
          'id': msg.id,
          'role': msg.role,
          'text': msg.text,
          'model': msg.model,
          'sourcesJson': msg._sourcesToJson(),
          'createdAt': msg.createdAt,
        },
      );
    } catch (e) {
      TLog.w('ChatStore', 'Server sync failed for ${msg.id}', error: e);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  FAB
// ═══════════════════════════════════════════════════════════════════════════════

class ArticleFollowUpFab extends StatefulWidget {
  const ArticleFollowUpFab({
    super.key,
    required this.articleId,
    required this.articleTitle,
    required this.articleUrl,
  });

  final String articleId;
  final String articleTitle;
  final String? articleUrl;

  @override
  State<ArticleFollowUpFab> createState() => _ArticleFollowUpFabState();
}

class _ArticleFollowUpFabState extends State<ArticleFollowUpFab>
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
      builder: (_) => _ArticleFollowUpChat(
        articleId: widget.articleId,
        articleTitle: widget.articleTitle,
        articleUrl: widget.articleUrl ?? '',
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

class _ArticleFollowUpChat extends ConsumerStatefulWidget {
  const _ArticleFollowUpChat({
    required this.articleId,
    required this.articleTitle,
    required this.articleUrl,
  });

  final String articleId;
  final String articleTitle;
  final String articleUrl;

  @override
  ConsumerState<_ArticleFollowUpChat> createState() =>
      _ArticleFollowUpChatState();
}

class _ArticleFollowUpChatState extends ConsumerState<_ArticleFollowUpChat>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  var _messages = <_ChatMessage>[];
  bool _sending = false;
  bool _loading = true;
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
      'cm-${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  @override
  void initState() {
    super.initState();
    _useXGrok = ref.read(settingsProvider).defaultFollowUpIsXGrok;

    final store = ArticleFollowUpStore.instance;
    store.init(ref.read(appDatabaseProvider), ref.read(apiClientProvider));
    store.addListener(widget.articleId, _onStoreUpdate);

    WidgetsBinding.instance.addObserver(this);
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _loadFromStore();
  }

  Future<void> _loadFromStore() async {
    final store = ArticleFollowUpStore.instance;
    final results = await Future.wait([
      store.load(widget.articleId),
      store.loadSummary(widget.articleId),
    ]);
    final cached = results[0] as List<_ChatMessage>;
    if (!mounted) return;

    final hasPending = store.hasPending(widget.articleId);
    setState(() {
      _messages = List<_ChatMessage>.of(cached);
      _loading = false;
      _sending = hasPending;
    });

    // Restart loading phases if a background request is still in-flight
    if (hasPending) _startLoadingPhases();

    // Auto-retry orphaned question: if the last message is from the user with
    // no AI response, the app was likely killed before the answer arrived.
    // Re-send — the backend DB cache will return instantly if Gemini finished.
    if (!hasPending && _messages.isNotEmpty && _messages.last.role == 'user') {
      _autoRetryOrphan(store);
    }

    if (_messages.isNotEmpty) _scrollToBottom();
  }

  void _autoRetryOrphan(ArticleFollowUpStore store) {
    final providerTag = _useXGrok ? 'xGrok' : 'Gemini';
    final modeTag = _useDeepModel ? 'Deep' : 'Lite';
    TLog.i('ArticleChat', 'Auto-retrying orphaned question [$providerTag/$modeTag]');
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
      articleId: widget.articleId,
      articleTitle: widget.articleTitle,
      articleUrl: widget.articleUrl,
      userMsg: orphanedUserMsg,
      aiMsg: aiMsg,
      history: history,
      aiService: ref.read(tutorAiServiceProvider),
      mode: _useDeepModel ? null : 'lite',
      deepModel: _useDeepModel ? settings.deepModel : null,
      provider: xgrokOn ? 'xgrok' : null,
      xgrokLiteModel: xgrokOn ? settings.xgrokLiteModel : null,
      xgrokDeepModel: xgrokOn ? settings.xgrokDeepModel : null,
      xgrokThinkingModel: xgrokOn ? settings.xgrokThinkingModel : null,
    );
  }

  /// Called by the store when a background request completes for this article.
  void _onStoreUpdate() {
    if (!mounted) return;
    final store = ArticleFollowUpStore.instance;
    final cached = store.getCached(widget.articleId);
    final stillPending = store.hasPending(widget.articleId);
    if (!stillPending) _stopLoadingPhases();
    setState(() {
      _messages = List<_ChatMessage>.of(cached);
      _sending = stillPending;
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    ArticleFollowUpStore.instance
        .removeListener(widget.articleId, _onStoreUpdate);
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
      // Refresh from cache in case the request completed while backgrounded
      final store = ArticleFollowUpStore.instance;
      final cached = store.getCached(widget.articleId);
      final stillPending = store.hasPending(widget.articleId);
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
    'Reading sources\u2026',
    'Composing answer\u2026',
  ];

  static const _deepPhases = [
    'Searching the web\u2026',
    'Reading original article\u2026',
    'Analyzing sources\u2026',
    'Cross-referencing data\u2026',
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
    TLog.i('ArticleChat', 'User cancelled follow-up for "${widget.articleTitle.length > 40 ? '${widget.articleTitle.substring(0, 40)}…' : widget.articleTitle}"');
    final store = ArticleFollowUpStore.instance;
    final restoredText = store.cancelPending(widget.articleId);
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
    TLog.i('ArticleChat', 'Sending [$providerTag/$modeTag]: "${text.length > 60 ? '${text.substring(0, 60)}…' : text}"');

    _ctrl.clear();
    _focusNode.requestFocus();

    final store = ArticleFollowUpStore.instance;

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
      articleId: widget.articleId,
      articleTitle: widget.articleTitle,
      articleUrl: widget.articleUrl,
      userMsg: userMsg,
      aiMsg: aiMsg,
      history: history,
      aiService: ref.read(tutorAiServiceProvider),
      mode: _useDeepModel ? null : 'lite',
      deepModel: _useDeepModel ? settings.deepModel : null,
      provider: xgrokOn ? 'xgrok' : null,
      xgrokLiteModel: xgrokOn ? settings.xgrokLiteModel : null,
      xgrokDeepModel: xgrokOn ? settings.xgrokDeepModel : null,
      xgrokThinkingModel: xgrokOn ? settings.xgrokThinkingModel : null,
    );
  }

  /// Builds the history payload, using a cached summary for older pairs when
  /// the conversation exceeds [ArticleFollowUpStore.kSummarizeThreshold].
  ///
  /// Layout sent to API:
  ///   [summary-context pair]  ← condensed digest of pairs 1…(N-K)
  ///   [recent K full pairs]   ← verbatim for conversational coherence
  ///   [new user question]     ← appended by the caller
  ///
  /// The summary always covers ALL old pairs (cumulative). When the old-pair
  /// count grows beyond what the cached summary covers, a background
  /// re-summarization is triggered that includes the previous summary text
  /// plus the new "graduated" pairs — so context is never lost.
  List<Map<String, String>> _buildHistoryWithSummary(
      ArticleFollowUpStore store, List<Map<String, String>> allPairs) {
    final pairCount = allPairs.length ~/ 2;
    if (pairCount <= ArticleFollowUpStore.kSummarizeThreshold) {
      return allPairs;
    }

    const recentCount = ArticleFollowUpStore.kRecentPairsToKeep * 2;
    final recentStart = allPairs.length - recentCount;
    final oldPairs = allPairs.sublist(0, recentStart);
    final recentPairs = allPairs.sublist(recentStart);
    final oldPairCount = oldPairs.length ~/ 2;

    final summary = store.getSummary(widget.articleId);

    if (summary != null && summary.pairsCovered >= oldPairCount) {
      TLog.d('ArticleChat',
          'Using cached summary (${summary.pairsCovered} pairs) + ${ArticleFollowUpStore.kRecentPairsToKeep} recent');
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
      TLog.d('ArticleChat',
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

    TLog.d('ArticleChat',
        'No summary — sending ${recentPairs.length ~/ 2} recent pairs, triggering background summarization');
    _triggerBackgroundSummarization(store, null, oldPairs, oldPairCount);
    return recentPairs;
  }

  /// Summarizes old conversation pairs in the background.
  /// If [existingSummary] is provided, it is prepended to the new pairs so
  /// the resulting summary is cumulative (covers everything from pair 1).
  /// Debounced per article — concurrent calls for the same article are skipped.
  void _triggerBackgroundSummarization(
      ArticleFollowUpStore store,
      _ConversationSummary? existingSummary,
      List<Map<String, String>> oldPairs,
      int totalOldPairCount) {
    final articleId = widget.articleId;
    if (store._summarizingArticleIds.contains(articleId)) {
      TLog.d('ArticleChat',
          'Summarization already in-flight for $articleId — skipping');
      return;
    }
    store._summarizingArticleIds.add(articleId);

    final aiService = ref.read(tutorAiServiceProvider);
    final articleTitle = widget.articleTitle;
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
          articleContext: articleTitle,
        );
        if (summary.isNotEmpty) {
          await store.saveSummary(articleId, summary, totalOldPairCount);
          TLog.i('ArticleChat',
              'Background summarization complete for $articleId ($totalOldPairCount pairs)');
        } else {
          TLog.w('ArticleChat',
              'Background summarization returned empty for $articleId');
        }
      } catch (e) {
        TLog.w('ArticleChat', 'Background summarization failed', error: e);
      } finally {
        store._summarizingArticleIds.remove(articleId);
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
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: const Color(0xFF4285F4),
                        ),
                      ),
                    )
                  : _messages.isEmpty
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
    final title = widget.articleTitle.length > 50
        ? '${widget.articleTitle.substring(0, 50)}…'
        : widget.articleTitle;

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
            child:
                const Icon(LucideIcons.sparkles, size: 14, color: Colors.white),
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
                  title,
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
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: const Color(0xFF4285F4),
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
            'Ask anything about this article',
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
                      'You can minimize the app \u2014 '
                      'we\u2019ll notify you when it\u2019s ready.',
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
                                TLog.w('FollowUp', 'Failed to launch URL: $href', error: e);
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
                          hintText: 'Ask about this article…',
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
                    tag: 'ArticleVoice',
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
