import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/llm/model_hints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/tutor_entities.dart';

class TutorAiService {
  TutorAiService(this._apiClient);

  final ApiClient _apiClient;

  Future<RephraseResult> rephrase({
    required String text,
    required String platform,
    String? intent,
    String? liteModel,
  }) async {
    TLog.d('TutorAI', 'Rephrase → platform=$platform${intent != null && intent.isNotEmpty ? ' intent="${intent.length > 60 ? '${intent.substring(0, 60)}…' : intent}"' : ''}');
    try {
      final body = <String, dynamic>{'text': text, 'platform': platform};
      if (intent != null && intent.isNotEmpty) {
        body['intent'] = intent;
      }
      _addLiteModel(body, liteModel);
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiRephrase,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty rephrase response body');
        throw StateError('Empty rephrase response');
      }
      TLog.i('TutorAI', 'Rephrase ✓ model=${data['model']} platform=$platform');
      return RephraseResult.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Rephrase failed', error: e);
      rethrow;
    }
  }

  Future<CoachResult> coach({
    required String text,
    String? liteModel,
  }) async {
    TLog.d('TutorAI', 'Coach → ${text.length} chars');
    try {
      final body = <String, dynamic>{'text': text};
      _addLiteModel(body, liteModel);
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiCorrect,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty coach response body');
        throw StateError('Empty coach response');
      }
      TLog.i('TutorAI', 'Coach ✓ model=${data['model']}');
      return CoachResult.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Coach failed', error: e);
      rethrow;
    }
  }

  Future<DictionaryResult> define({
    required String word,
    String? liteModel,
  }) async {
    TLog.d('TutorAI', 'Define → "$word"');
    try {
      final body = <String, dynamic>{'word': word};
      _addLiteModel(body, liteModel);
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiDefine,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 45)),
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty dictionary response body');
        throw StateError('Empty dictionary response');
      }
      TLog.i('TutorAI', 'Define ✓ model=${data['model']} word=${data['word']}');
      return DictionaryResult.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Define failed', error: e);
      rethrow;
    }
  }

  Future<SummarizerResult> summarize({
    required String url,
    String? provider,
    String? xgrokModel,
    String? liteModel,
    CancelToken? cancelToken,
  }) async {
    TLog.d('TutorAI', 'Summarize → $url [provider=${provider ?? 'gemini'}]');
    try {
      final body = <String, dynamic>{'url': url};
      if (provider != null && provider.isNotEmpty) body['provider'] = provider;
      if (xgrokModel != null && xgrokModel.isNotEmpty) body['xgrokModel'] = xgrokModel;
      _addLiteModel(body, liteModel);
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiSummarize,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 90)),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty summarizer response body');
        throw StateError('Empty summarizer response');
      }
      TLog.i('TutorAI', 'Summarize ✓ provider=${data['providerUsed']} model=${data['model']} method=${data['extractionMethod']} fallback=${data['fallback']}');
      return SummarizerResult.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Summarize failed', error: e);
      rethrow;
    }
  }

  /// Adds a `liteModel` field to [body] when [model] is non-empty. Used by
  /// every fast/lite endpoint so the user-configured Gemini Lite model from
  /// Settings (synced cross-device via user_preferences) flows through to
  /// the backend's LiteLLM gateway. The backend is responsible for
  /// `gemini/`-prefix normalisation; the Flutter setting holds the bare
  /// model id, matching the Deep Research convention.
  void _addLiteModel(Map<String, dynamic> body, String? model) {
    if (model == null) return;
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    body['liteModel'] = trimmed;
  }

  Future<TavilySearchResponse> search({
    required String query,
    CancelToken? cancelToken,
  }) async {
    TLog.d('TutorAI', 'Tavily search → "$query"');
    try {
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiSearch,
        data: <String, dynamic>{'query': query},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty search response body');
        throw StateError('Empty search response');
      }
      TLog.i('TutorAI', 'Search ✓ results=${(data['results'] as List?)?.length ?? 0}');
      return TavilySearchResponse.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Tavily search failed', error: e);
      rethrow;
    }
  }

  /// Grounded search with automatic retry (up to 2 attempts) and exponential
  /// backoff. The backend already has internal retries & cross-provider
  /// fallback, so we keep client-side retries limited to transient network
  /// errors only to avoid amplifying load.
  ///
  /// Model routing fields are funneled through [ModelHints.build] so the
  /// wire body only ever carries the model id matching the active
  /// (provider, mode) pair. This is the safety net that prevents a
  /// permissive backend resolver from routing a "lite" request to a "deep"
  /// (non-grounded) model — the regression that previously broke real-time
  /// answers in InsightAI Lite.
  ///
  /// [mode] selects depth — 'lite' (fast, default), 'deep' (thorough), or
  /// 'thinking' (xGrok-only). When omitted the backend defaults to 'lite'
  /// for backward compatibility.
  ///
  /// [xgrokModel] is the legacy single-slot xGrok override; it is honoured
  /// only when [mode] is lite and [xgrokLiteModel] is absent.
  Future<GroundedSearchResponse> groundedSearch({
    required String query,
    String? provider,
    String? xgrokModel,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    final hints = ModelHints.build(
      provider: provider,
      mode: mode,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
      legacyXgrokModel: xgrokModel,
    );
    final resolvedProvider = hints['provider'] as String;
    final resolvedMode = hints['mode'] as String;
    final isDeep = resolvedMode == ModelHints.modeDeep ||
        resolvedMode == ModelHints.modeThinking;
    // Client-side timeouts are deliberately a few seconds longer than the
    // backend's per-call timeouts (gemini=30s/75s, xgrok=75s/120s) so the
    // backend gets a chance to surface its own error / fallback response
    // before the client tears down the socket. We do NOT wait through full
    // backend retry storms — the OnlineSearchStore queues a resume retry
    // when the app is in the background, and the user can tap "Retry" in
    // foreground.
    final timeout = resolvedProvider == ModelHints.providerXGrok
        ? Duration(seconds: isDeep ? 135 : 85)
        : Duration(seconds: isDeep ? 90 : 60);
    final qPreview =
        query.length > 80 ? '${query.substring(0, 77)}\u2026' : query;
    TLog.d('TutorAI',
        'GroundedSearch → "$qPreview" [provider=$resolvedProvider mode=$resolvedMode timeout=${timeout.inSeconds}s]');
    final sw = Stopwatch()..start();

    Object? lastError;
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException(requestOptions: RequestOptions(), type: DioExceptionType.cancel);
      }
      try {
        if (attempt > 1) {
          final delay = Duration(milliseconds: _baseDelayMs * (1 << (attempt - 2)));
          TLog.w('TutorAI', 'GroundedSearch retry $attempt/$_maxRetries in ${delay.inMilliseconds}ms');
          await Future<void>.delayed(delay);
        }
        final body = <String, dynamic>{'query': query, ...hints};
        final response = await _apiClient.post<Object?>(
          ApiEndpoints.aiGroundedSearch,
          data: body,
          options: Options(receiveTimeout: timeout),
          cancelToken: cancelToken,
        );
        final data = _asMap(response.data);
        if (data == null) {
          TLog.w('TutorAI', 'Empty grounded search response body (attempt $attempt)');
          throw StateError('Empty grounded search response');
        }
        sw.stop();
        TLog.i('TutorAI',
            'GroundedSearch ✓ provider=$resolvedProvider mode=${data['mode'] ?? resolvedMode} '
            'model=${data['model']} sources=${(data['sources'] as List?)?.length ?? 0} '
            '${sw.elapsedMilliseconds}ms (attempt $attempt)');
        return GroundedSearchResponse.fromJson(data);
      } on DioException catch (e) {
        lastError = e;
        if (e.type == DioExceptionType.cancel) rethrow;
        final isRetryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.unknown ||
            (e.response?.statusCode != null && e.response!.statusCode! >= 500);
        if (!isRetryable || attempt >= _maxRetries) break;
        TLog.w('TutorAI', 'GroundedSearch attempt $attempt failed (${e.type}), will retry');
      } catch (e) {
        lastError = e;
        if (attempt >= _maxRetries) break;
      }
    }
    sw.stop();
    TLog.e('TutorAI',
        'GroundedSearch FAILED after $_maxRetries attempts [provider=$resolvedProvider mode=$resolvedMode] '
        '${sw.elapsedMilliseconds}ms',
        error: lastError);
    throw lastError ?? StateError('Grounded search failed');
  }

  // ── Article Follow-Up (Gemini + Grounding) ─────────────────────────────

  Future<ArticleFollowUpResponse> articleFollowUp({
    required String question,
    required String articleUrl,
    required String articleTitle,
    List<Map<String, String>> history = const [],
    String? mode,
    String? deepModel,
    String? liteModel,
    String? provider,
    bool searchRequired = true,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    // Article follow-up defaults to deep mode (legacy behaviour) when the
    // caller omits [mode]. We resolve the default before going through the
    // hint builder so the wire body always carries an explicit mode.
    final hints = ModelHints.build(
      provider: provider,
      mode: mode ?? ModelHints.modeDeep,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
    );
    final resolvedProvider = hints['provider'] as String;
    final resolvedMode = hints['mode'] as String;
    TLog.d('TutorAI',
        'Article follow-up → "${question.length > 60 ? '${question.substring(0, 60)}…' : question}" '
        '[mode=$resolvedMode, provider=$resolvedProvider, searchRequired=$searchRequired]');
    try {
      final body = <String, dynamic>{
        'question': question,
        'articleUrl': articleUrl,
        'articleTitle': articleTitle,
        'history': history,
        'searchRequired': searchRequired,
        ...hints,
      };
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiArticleFollowup,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 90)),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty article follow-up response body');
        throw StateError('Empty article follow-up response');
      }
      TLog.i('TutorAI',
          'ArticleFollowUp ✓ model=${data['model']} '
          'sources=${(data['sources'] as List?)?.length ?? 0} '
          '[mode=$resolvedMode, provider=$resolvedProvider]');
      return ArticleFollowUpResponse.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Article follow-up failed', error: e);
      rethrow;
    }
  }

  // ── Deep Research (Gemini 3.1 Pro + Grounding) ──────────────────────────

  Future<ArticleFollowUpResponse> deepResearch({
    required String url,
    String question = '',
    List<Map<String, String>> history = const [],
    String? deepModel,
    String? provider,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    // Deep research is always deep-mode by definition. We pin the mode here
    // so the hint builder strips any cross-mode fields a future caller
    // might forward, and so the wire body always reflects the actual depth.
    final hints = ModelHints.build(
      provider: provider,
      mode: ModelHints.modeDeep,
      deepModel: deepModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
    );
    final resolvedProvider = hints['provider'] as String;
    TLog.d('TutorAI',
        'Deep research → ${url.length > 60 ? '${url.substring(0, 60)}…' : url} '
        '[provider=$resolvedProvider]');
    try {
      final body = <String, dynamic>{
        'url': url,
        'question': question,
        'history': history,
        ...hints,
      };
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiDeepResearch,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 120)),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty deep research response body');
        throw StateError('Empty deep research response');
      }
      TLog.i('TutorAI',
          'DeepResearch ✓ model=${data['model']} '
          'sources=${(data['sources'] as List?)?.length ?? 0} '
          '[provider=$resolvedProvider]');
      return ArticleFollowUpResponse.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Deep research failed', error: e);
      rethrow;
    }
  }

  // ── Image Search (InsightAI vision) ──────────────────────────────────────

  /// Single-shot image analysis. Sends a base64-encoded JPEG (the
  /// pipeline-compressed bytes — never the raw 50 MB source) plus an
  /// optional text query and returns the same [GroundedSearchResponse]
  /// shape as the text path, so [OnlineSearchStore] / SaveSearchStore
  /// can reuse all existing rendering + persistence plumbing.
  ///
  /// Routing follows the exact same provider / mode / model-hint
  /// contract as [groundedSearch] — the backend is expected to
  /// dispatch the request to the vision-capable variant of the
  /// resolved (provider, mode) pair.
  ///
  /// We do NOT add client-side multi-attempt retry here. The Dio
  /// interceptor already retries on 5xx + transient connection
  /// errors, and the resume-retry queue in [ImageSearchStore] handles
  /// network-loss recovery on app resume. Stacking another retry
  /// loop would amplify backend load on a 1-2 MB upload.
  ///
  /// Timeouts are deliberately longer than the text path because a
  /// 1-2 MB JPEG upload on a slow cellular link can take 30+ seconds
  /// just to send — 90 s send + 90 s receive gives a comfortable
  /// budget without leaving the user staring at a dead progress bar
  /// for minutes.
  Future<GroundedSearchResponse> imageSearch({
    required String query,
    required Uint8List imageBytes,
    required String imageMediaType,
    String? provider,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    final hints = ModelHints.build(
      provider: provider,
      mode: mode,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
    );
    final resolvedProvider = hints['provider'] as String;
    final resolvedMode = hints['mode'] as String;
    final qPreview =
        query.length > 80 ? '${query.substring(0, 77)}\u2026' : query;
    final sizeKB = (imageBytes.lengthInBytes / 1024).toStringAsFixed(0);
    TLog.d('TutorAI',
        'ImageSearch \u2192 "$qPreview" [provider=$resolvedProvider mode=$resolvedMode '
        'imageBytes=${sizeKB}KB type=$imageMediaType]');
    final sw = Stopwatch()..start();

    try {
      final body = <String, dynamic>{
        'query': query,
        'image': base64Encode(imageBytes),
        'imageMediaType': imageMediaType,
        ...hints,
      };
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiImageSearch,
        data: body,
        options: Options(
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 120),
        ),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty image search response body');
        throw StateError('Empty image search response');
      }
      sw.stop();
      TLog.i('TutorAI',
          'ImageSearch \u2713 provider=$resolvedProvider mode=${data['mode'] ?? resolvedMode} '
          'model=${data['model']} sources=${(data['sources'] as List?)?.length ?? 0} '
          'image=${sizeKB}KB ${sw.elapsedMilliseconds}ms');
      return GroundedSearchResponse.fromJson(data);
    } catch (e) {
      sw.stop();
      TLog.e('TutorAI',
          'ImageSearch FAILED [provider=$resolvedProvider mode=$resolvedMode] '
          '${sw.elapsedMilliseconds}ms',
          error: e);
      rethrow;
    }
  }

  /// Follow-up turn for an active image-search session. The image
  /// bytes are re-attached on EVERY call so the backend (stateless)
  /// always has full vision context — this is the same pattern as
  /// the Anthropic sample at cursor_ai_image_chat_prompt.md and is
  /// what makes mid-chat Lite\u2194Deep / Gemini\u2194xGrok switching
  /// stay accurate without a session-aware backend.
  Future<ArticleFollowUpResponse> imageFollowUp({
    required String query,
    required String question,
    required Uint8List imageBytes,
    required String imageMediaType,
    // The original answer the user got back from `/ai/image-search`.
    // Forwarded verbatim so the backend can ground the conversation
    // in that response even on turn #1 when `history` is still
    // empty. Optional so older callers still compile; default empty
    // string is the legacy no-context behaviour.
    String initialAnswer = '',
    List<Map<String, String>> history = const [],
    String? provider,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    final hints = ModelHints.build(
      provider: provider,
      mode: mode,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
    );
    final resolvedProvider = hints['provider'] as String;
    final resolvedMode = hints['mode'] as String;
    final sizeKB = (imageBytes.lengthInBytes / 1024).toStringAsFixed(0);
    TLog.d('TutorAI',
        'ImageFollowUp \u2192 "${question.length > 60 ? '${question.substring(0, 60)}\u2026' : question}" '
        '[provider=$resolvedProvider mode=$resolvedMode history=${history.length} '
        'image=${sizeKB}KB]');
    final sw = Stopwatch()..start();

    try {
      final body = <String, dynamic>{
        'query': query,
        if (initialAnswer.isNotEmpty) 'initialAnswer': initialAnswer,
        'question': question,
        'history': history,
        'image': base64Encode(imageBytes),
        'imageMediaType': imageMediaType,
        ...hints,
      };
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiImageFollowup,
        data: body,
        options: Options(
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 120),
        ),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty image follow-up response body');
        throw StateError('Empty image follow-up response');
      }
      sw.stop();
      TLog.i('TutorAI',
          'ImageFollowUp \u2713 model=${data['model']} '
          'sources=${(data['sources'] as List?)?.length ?? 0} '
          '[provider=$resolvedProvider mode=$resolvedMode] '
          '${sw.elapsedMilliseconds}ms');
      return ArticleFollowUpResponse.fromJson(data);
    } catch (e) {
      sw.stop();
      TLog.e('TutorAI',
          'ImageFollowUp FAILED [provider=$resolvedProvider mode=$resolvedMode] '
          '${sw.elapsedMilliseconds}ms',
          error: e);
      rethrow;
    }
  }

  // ── Search Follow-Up (Gemini + Grounding) ────────────────────────────────

  Future<ArticleFollowUpResponse> searchFollowUp({
    required String query,
    required String initialAnswer,
    required String question,
    List<Map<String, String>> history = const [],
    String? mode,
    String? deepModel,
    String? liteModel,
    String? provider,
    bool searchRequired = true,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    // Same defaulting rule as articleFollowUp: deep is the legacy default
    // when the caller doesn't specify [mode].
    final hints = ModelHints.build(
      provider: provider,
      mode: mode ?? ModelHints.modeDeep,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
    );
    final resolvedProvider = hints['provider'] as String;
    final resolvedMode = hints['mode'] as String;
    TLog.d('TutorAI',
        'Search follow-up → "${question.length > 60 ? '${question.substring(0, 60)}…' : question}" '
        '[mode=$resolvedMode, provider=$resolvedProvider, searchRequired=$searchRequired]');
    try {
      final body = <String, dynamic>{
        'query': query,
        'initialAnswer': initialAnswer,
        'question': question,
        'history': history,
        'searchRequired': searchRequired,
        ...hints,
      };
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiSearchFollowup,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 90)),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      if (data == null) {
        TLog.w('TutorAI', 'Empty search follow-up response body');
        throw StateError('Empty search follow-up response');
      }
      TLog.i('TutorAI',
          'SearchFollowUp ✓ model=${data['model']} '
          'sources=${(data['sources'] as List?)?.length ?? 0} '
          '[mode=$resolvedMode, provider=$resolvedProvider]');
      return ArticleFollowUpResponse.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Search follow-up failed', error: e);
      rethrow;
    }
  }

  // ── Conversation History Summarization ───────────────────────────────────

  /// Summarize prior chat history into a compact memory blob.
  ///
  /// Backwards-compatible model selection:
  ///   • [liteModel]    — the historical "summarizer model" slot. Backend
  ///                      reads this as the model id to invoke. Always
  ///                      passed through when set.
  ///   • [summaryModel] — forward-looking explicit override. When set, the
  ///                      same id is also written to `summaryModel` on the
  ///                      wire so a backend that prefers an explicit field
  ///                      can pick it up; the legacy `liteModel` slot is
  ///                      simultaneously upgraded to this id so today's
  ///                      backend (which reads `liteModel`) actually uses
  ///                      the deep model when the caller asks for it. This
  ///                      is how long-conversation memory consolidation
  ///                      gets a deep-grade summary without requiring a
  ///                      backend change.
  Future<String> summarizeHistory({
    required List<Map<String, String>> messages,
    String? articleContext,
    String? liteModel,
    String? summaryModel,
    CancelToken? cancelToken,
  }) async {
    final summaryModelTrimmed = summaryModel?.trim();
    final hasSummaryOverride =
        summaryModelTrimmed != null && summaryModelTrimmed.isNotEmpty;
    final modelTag = hasSummaryOverride ? summaryModelTrimmed : (liteModel ?? '');
    TLog.d(
      'TutorAI',
      'Summarize history → ${messages.length} msgs, ctx="${articleContext ?? ''}", '
          'model="$modelTag"${hasSummaryOverride ? ' (deep)' : ''}',
    );
    try {
      final body = <String, dynamic>{
        'messages': messages,
      };
      if (articleContext != null && articleContext.isNotEmpty) {
        body['articleContext'] = articleContext;
      }
      // When a summary-specific model is provided, route both the new
      // explicit field AND the legacy liteModel slot to it so old + new
      // backends both honour the upgrade. Otherwise behave exactly as
      // before — liteModel-only.
      if (hasSummaryOverride) {
        body['summaryModel'] = summaryModelTrimmed;
        body['liteModel'] = summaryModelTrimmed;
      } else {
        _addLiteModel(body, liteModel);
      }
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiSummarizeHistory,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      final summary = data?['summary']?.toString() ?? '';
      if (summary.isEmpty) {
        TLog.w('TutorAI', 'Empty summarize-history response');
      } else {
        TLog.i(
          'TutorAI',
          'SummarizeHistory ✓ model=${data?['model']} ${summary.length} chars'
              '${hasSummaryOverride ? ' [deep-override]' : ''}',
        );
      }
      return summary;
    } catch (e) {
      TLog.e('TutorAI', 'Summarize history failed', error: e);
      rethrow;
    }
  }

  // ── Saved Words Sync ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSavedWords() async {
    TLog.d('TutorAI', 'Fetching saved words from server');
    try {
      final response = await _apiClient.get<Object?>(ApiEndpoints.savedWords);
      if (response.data is List) {
        return (response.data as List)
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
      return [];
    } catch (e) {
      TLog.e('TutorAI', 'fetchSavedWords failed', error: e);
      return [];
    }
  }

  Future<void> syncSavedWord({
    required String id,
    required String word,
    required String definition,
    required String pronunciation,
    required String partOfSpeech,
    required String savedAt,
    required String responseJson,
  }) async {
    TLog.d('TutorAI', 'Syncing saved word → $word');
    try {
      await _apiClient.post<Object?>(
        ApiEndpoints.savedWords,
        data: <String, dynamic>{
          'id': id,
          'word': word,
          'definition': definition,
          'pronunciation': pronunciation,
          'partOfSpeech': partOfSpeech,
          'savedAt': savedAt,
          'responseJson': responseJson,
        },
      );
    } catch (e) {
      TLog.e('TutorAI', 'syncSavedWord failed for "$word"', error: e);
      rethrow;
    }
  }

  Future<void> deleteSavedWord(String id) async {
    TLog.d('TutorAI', 'Deleting saved word → $id');
    try {
      await _apiClient.delete<Object?>(ApiEndpoints.savedWord(id));
    } catch (e) {
      TLog.e('TutorAI', 'deleteSavedWord failed for $id', error: e);
      rethrow;
    }
  }

  // ── App Settings (server-side key-value store) ──────────────────

  static const _maxRetries = 3;
  static const _baseDelayMs = 500;

  Future<void> pushAppSetting(String key, String value) async {
    TLog.d('TutorAI', 'pushAppSetting → $key=$value');
    Object? lastError;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          final delay = _baseDelayMs * (1 << (attempt - 1));
          TLog.w(
            'TutorAI',
            'pushAppSetting retry ${attempt + 1}/$_maxRetries in ${delay}ms',
          );
          await Future<void>.delayed(Duration(milliseconds: delay));
        }
        await _apiClient.put<Object?>(
          ApiEndpoints.appSettings,
          data: {'key': key, 'value': value},
        );
        TLog.i('TutorAI', 'pushAppSetting ✓ $key=$value (attempt ${attempt + 1})');
        return;
      } on DioException catch (e) {
        lastError = e;
        final isRetryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            (e.response?.statusCode != null &&
                e.response!.statusCode! >= 500);
        if (!isRetryable || attempt >= _maxRetries - 1) break;
      } catch (e) {
        lastError = e;
        if (attempt >= _maxRetries - 1) break;
      }
    }
    TLog.e(
      'TutorAI',
      'pushAppSetting FAILED after $_maxRetries attempts for $key',
      error: lastError,
    );
  }

  Future<Map<String, String>> fetchAppSettings() async {
    TLog.d('TutorAI', 'fetchAppSettings');
    try {
      final response = await _apiClient.get<Object?>(
        ApiEndpoints.appSettings,
      );
      final data = _asMap(response.data);
      if (data == null) return {};
      final result = data.map((k, v) => MapEntry(k, v.toString()));
      TLog.i('TutorAI', 'fetchAppSettings ✓ ${result.length} keys');
      return result;
    } catch (e) {
      TLog.e('TutorAI', 'fetchAppSettings failed', error: e);
      return {};
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
