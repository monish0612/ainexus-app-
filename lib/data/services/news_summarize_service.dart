import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/news_entities.dart';

/// Thin Dio wrapper for the batch quick-summary endpoint used by the News >
/// For You "Summarize" flow. The orchestration (batching, concurrency, retry,
/// lifecycle) lives in [NewsSummarizeStore]; this layer is intentionally
/// dumb — pack the request, parse the response, throw on non-200.
class NewsSummarizeService {
  NewsSummarizeService(this._apiClient);

  final ApiClient _apiClient;

  /// Per-article content cap on the wire. Matches the server-side Zod limit
  /// (4000 chars). Trimming happens here so callers don't have to worry.
  static const int maxContentChars = 4000;

  /// Sends [articles] to the backend and returns a `Map<id, summary>`.
  ///
  /// The request body never includes more than [maxContentChars] of content
  /// per article (the title alone usually carries the gist). The server is
  /// guaranteed to echo every requested id (with a "Headline: ..." fallback
  /// if the model dropped one), so the returned map has the same length as
  /// [articles] on success.
  ///
  /// [liteModel] forwards the user-configured Gemini Lite model from
  /// Settings (synced cross-device). When provided, the backend pins the
  /// LiteLLM call to that exact model. When omitted, the backend falls back
  /// to its auto-discovered model priority list. [model] is the legacy raw
  /// override and takes precedence — keep it for diagnostics or A/B work.
  ///
  /// Throws on transport errors, non-2xx responses, or malformed payloads —
  /// caller (the store) handles retry + per-batch error state.
  Future<Map<String, String>> summarizeBatch({
    required List<Article> articles,
    String? model,
    String? liteModel,
    CancelToken? cancelToken,
  }) async {
    if (articles.isEmpty) return const <String, String>{};

    final payload = <String, dynamic>{
      'articles': [
        for (final a in articles)
          <String, dynamic>{
            'id': a.id,
            'title': a.title,
            'source': a.source,
            'category': a.category,
            'content': _composeContent(a),
            // Lets the backend deep-extract the real body when our local
            // copy is thin (feed ingested without full content). Older
            // backends simply strip the unknown key, so this is safe to
            // send unconditionally.
            if ((a.originalUrl ?? '').trim().isNotEmpty)
              'url': a.originalUrl!.trim(),
          },
      ],
    };
    final modelOverride = model?.trim();
    if (modelOverride != null && modelOverride.isNotEmpty) {
      payload['model'] = modelOverride;
    }
    final liteOverride = liteModel?.trim();
    if (liteOverride != null && liteOverride.isNotEmpty) {
      payload['liteModel'] = liteOverride;
    }

    final sw = Stopwatch()..start();
    TLog.d('NewsSummarize',
        '→ batch size=${articles.length} model=${payload['model'] ?? payload['liteModel'] ?? '(backend default)'}');

    // 90 s headroom: Android Doze can throttle a backgrounded socket for
    // ~60 s before killing it. With the foreground service running we keep
    // the process alive, but a single TCP read can still stall — bumping the
    // ceiling here means the store's per-batch retry loop is the one that
    // decides when to give up, not Dio.
    final response = await _apiClient.post<Object?>(
      ApiEndpoints.aiSummarizeArticlesBatch,
      data: payload,
      options: Options(
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 30),
      ),
      cancelToken: cancelToken,
    );

    final data = _asMap(response.data);
    if (data == null) {
      TLog.w('NewsSummarize', 'Empty response body for batch of ${articles.length}');
      throw StateError('Empty summarize-articles-batch response');
    }

    final raw = data['summaries'];
    final list = raw is List ? raw : const <Object?>[];
    final out = <String, String>{};
    for (final item in list) {
      final m = _asMap(item);
      if (m == null) continue;
      final id = (m['id'] ?? '').toString();
      final summary = (m['summary'] ?? '').toString().trim();
      if (id.isEmpty || summary.isEmpty) continue;
      out[id] = summary;
    }

    sw.stop();
    TLog.i('NewsSummarize',
        '✓ batch=${articles.length} mapped=${out.length} '
        'model=${data['model']} ${sw.elapsedMilliseconds}ms');
    return out;
  }

  /// Builds the per-article content string we send to the model. We use
  /// title + excerpt + paragraph/heading blocks (skipping stat blocks which
  /// are noisy without their visual layout). Capped to [maxContentChars] so
  /// we never blow the server-side schema limit even on long features.
  static String _composeContent(Article a) {
    final buf = StringBuffer();
    if (a.excerpt.trim().isNotEmpty) {
      buf.writeln(a.excerpt.trim());
    }
    for (final block in a.blocks) {
      final t = block.type;
      if (t == 'paragraph' || t == 'heading' || t == 'quote') {
        final c = block.content.trim();
        if (c.isEmpty) continue;
        buf.writeln();
        buf.writeln(c);
      }
      if (buf.length >= maxContentChars) break;
    }
    var text = buf.toString().trim();
    if (text.length > maxContentChars) {
      text = text.substring(0, maxContentChars);
    }
    if (text.isEmpty) {
      text = a.title;
    }
    return text;
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
