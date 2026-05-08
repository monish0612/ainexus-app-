import 'package:dio/dio.dart';

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
  }) async {
    TLog.d('TutorAI', 'Rephrase → platform=$platform${intent != null && intent.isNotEmpty ? ' intent="${intent.length > 60 ? '${intent.substring(0, 60)}…' : intent}"' : ''}');
    try {
      final body = <String, dynamic>{'text': text, 'platform': platform};
      if (intent != null && intent.isNotEmpty) {
        body['intent'] = intent;
      }
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

  Future<CoachResult> coach({required String text}) async {
    TLog.d('TutorAI', 'Coach → ${text.length} chars');
    try {
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiCorrect,
        data: <String, dynamic>{'text': text},
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

  Future<DictionaryResult> define({required String word}) async {
    TLog.d('TutorAI', 'Define → "$word"');
    try {
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiDefine,
        data: <String, dynamic>{'word': word},
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
    CancelToken? cancelToken,
  }) async {
    TLog.d('TutorAI', 'Summarize → $url [provider=${provider ?? 'gemini'}]');
    try {
      final body = <String, dynamic>{'url': url};
      if (provider != null && provider.isNotEmpty) body['provider'] = provider;
      if (xgrokModel != null && xgrokModel.isNotEmpty) body['xgrokModel'] = xgrokModel;
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
  /// [mode] selects depth — 'lite' (fast, default) or 'deep' (thorough). The
  /// backend resolves the actual model from the corresponding provider-specific
  /// hints below. Legacy callers that omit [mode] continue to behave as before
  /// (the backend defaults to 'lite' for backward compatibility).
  ///
  /// [deepModel] is the Gemini deep model (only used when mode='deep').
  /// [xgrokModel] is a legacy raw override for xGrok (treated as the lite
  /// slot if [xgrokLiteModel] is absent — kept for backward compatibility).
  Future<GroundedSearchResponse> groundedSearch({
    required String query,
    String? provider,
    String? xgrokModel,
    String? mode,
    String? deepModel,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    final tag = provider ?? 'gemini';
    final isDeep = mode == 'deep' || mode == 'thinking';
    // Client-side timeouts are deliberately a few seconds longer than the
    // backend's per-call timeouts (gemini=30s/75s, xgrok=75s/120s) so the
    // backend gets a chance to surface its own error / fallback response
    // before the client tears down the socket. We do NOT wait through full
    // backend retry storms — the OnlineSearchStore queues a resume retry
    // when the app is in the background, and the user can tap "Retry" in
    // foreground.
    final timeout = provider == 'xgrok'
        ? Duration(seconds: isDeep ? 135 : 85)
        : Duration(seconds: isDeep ? 90 : 60);
    final qPreview =
        query.length > 80 ? '${query.substring(0, 77)}\u2026' : query;
    TLog.d('TutorAI',
        'GroundedSearch → "$qPreview" [provider=$tag mode=${mode ?? 'lite'} timeout=${timeout.inSeconds}s]');
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
        final body = <String, dynamic>{'query': query};
        if (provider != null && provider.isNotEmpty) body['provider'] = provider;
        if (mode != null && mode.isNotEmpty) body['mode'] = mode;
        if (deepModel != null && deepModel.isNotEmpty) body['deepModel'] = deepModel;
        if (xgrokModel != null && xgrokModel.isNotEmpty) body['xgrokModel'] = xgrokModel;
        if (xgrokLiteModel != null && xgrokLiteModel.isNotEmpty) {
          body['xgrokLiteModel'] = xgrokLiteModel;
        }
        if (xgrokDeepModel != null && xgrokDeepModel.isNotEmpty) {
          body['xgrokDeepModel'] = xgrokDeepModel;
        }
        if (xgrokThinkingModel != null && xgrokThinkingModel.isNotEmpty) {
          body['xgrokThinkingModel'] = xgrokThinkingModel;
        }
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
            'GroundedSearch ✓ provider=$tag mode=${data['mode'] ?? mode ?? 'lite'} '
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
        'GroundedSearch FAILED after $_maxRetries attempts [provider=$tag mode=${mode ?? 'lite'}] '
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
    String? provider,
    bool searchRequired = true,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    TLog.d('TutorAI', 'Article follow-up → "${question.length > 60 ? '${question.substring(0, 60)}…' : question}" [mode=${mode ?? 'deep'}, provider=${provider ?? 'gemini'}, searchRequired=$searchRequired]');
    try {
      final body = <String, dynamic>{
        'question': question,
        'articleUrl': articleUrl,
        'articleTitle': articleTitle,
        'history': history,
        'searchRequired': searchRequired,
      };
      if (mode != null && mode.isNotEmpty) body['mode'] = mode;
      if (deepModel != null && deepModel.isNotEmpty) body['deepModel'] = deepModel;
      if (provider != null && provider.isNotEmpty) body['provider'] = provider;
      if (xgrokLiteModel != null && xgrokLiteModel.isNotEmpty) body['xgrokLiteModel'] = xgrokLiteModel;
      if (xgrokDeepModel != null && xgrokDeepModel.isNotEmpty) body['xgrokDeepModel'] = xgrokDeepModel;
      if (xgrokThinkingModel != null && xgrokThinkingModel.isNotEmpty) body['xgrokThinkingModel'] = xgrokThinkingModel;
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
      TLog.i('TutorAI', 'ArticleFollowUp ✓ model=${data['model']} sources=${(data['sources'] as List?)?.length ?? 0} [mode=${mode ?? 'deep'}, provider=${provider ?? 'gemini'}]');
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
    TLog.d('TutorAI', 'Deep research → ${url.length > 60 ? '${url.substring(0, 60)}…' : url} [provider=${provider ?? 'gemini'}]');
    try {
      final body = <String, dynamic>{
        'url': url,
        'question': question,
        'history': history,
      };
      if (deepModel != null && deepModel.isNotEmpty) body['deepModel'] = deepModel;
      if (provider != null && provider.isNotEmpty) body['provider'] = provider;
      if (xgrokDeepModel != null && xgrokDeepModel.isNotEmpty) body['xgrokDeepModel'] = xgrokDeepModel;
      if (xgrokThinkingModel != null && xgrokThinkingModel.isNotEmpty) body['xgrokThinkingModel'] = xgrokThinkingModel;
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
      TLog.i('TutorAI', 'DeepResearch ✓ model=${data['model']} sources=${(data['sources'] as List?)?.length ?? 0} [provider=${provider ?? 'gemini'}]');
      return ArticleFollowUpResponse.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Deep research failed', error: e);
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
    String? provider,
    bool searchRequired = true,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    TLog.d('TutorAI', 'Search follow-up → "${question.length > 60 ? '${question.substring(0, 60)}…' : question}" [mode=${mode ?? 'deep'}, provider=${provider ?? 'gemini'}, searchRequired=$searchRequired]');
    try {
      final body = <String, dynamic>{
        'query': query,
        'initialAnswer': initialAnswer,
        'question': question,
        'history': history,
        'searchRequired': searchRequired,
      };
      if (mode != null && mode.isNotEmpty) body['mode'] = mode;
      if (deepModel != null && deepModel.isNotEmpty) body['deepModel'] = deepModel;
      if (provider != null && provider.isNotEmpty) body['provider'] = provider;
      if (xgrokLiteModel != null && xgrokLiteModel.isNotEmpty) body['xgrokLiteModel'] = xgrokLiteModel;
      if (xgrokDeepModel != null && xgrokDeepModel.isNotEmpty) body['xgrokDeepModel'] = xgrokDeepModel;
      if (xgrokThinkingModel != null && xgrokThinkingModel.isNotEmpty) body['xgrokThinkingModel'] = xgrokThinkingModel;
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
      TLog.i('TutorAI', 'SearchFollowUp ✓ model=${data['model']} sources=${(data['sources'] as List?)?.length ?? 0} [mode=${mode ?? 'deep'}, provider=${provider ?? 'gemini'}]');
      return ArticleFollowUpResponse.fromJson(data);
    } catch (e) {
      TLog.e('TutorAI', 'Search follow-up failed', error: e);
      rethrow;
    }
  }

  // ── Conversation History Summarization ───────────────────────────────────

  Future<String> summarizeHistory({
    required List<Map<String, String>> messages,
    String? articleContext,
    CancelToken? cancelToken,
  }) async {
    TLog.d('TutorAI', 'Summarize history → ${messages.length} msgs, ctx="${articleContext ?? ''}"');
    try {
      final body = <String, dynamic>{
        'messages': messages,
      };
      if (articleContext != null && articleContext.isNotEmpty) {
        body['articleContext'] = articleContext;
      }
      final response = await _apiClient.post<Object?>(
        ApiEndpoints.aiSummarizeHistory,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 45)),
        cancelToken: cancelToken,
      );
      final data = _asMap(response.data);
      final summary = data?['summary']?.toString() ?? '';
      if (summary.isEmpty) {
        TLog.w('TutorAI', 'Empty summarize-history response');
      } else {
        TLog.i('TutorAI', 'SummarizeHistory ✓ model=${data?['model']} ${summary.length} chars');
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
