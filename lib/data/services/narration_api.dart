import 'package:dio/dio.dart';

import '../../core/auth/app_token_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../domain/entities/news_entities.dart';
import 'article_tts_service.dart';
import 'narration_models.dart';

class NarrationApi {
  NarrationApi(this._client);

  final ApiClient _client;

  Future<NarrationJob> status(String articleId) async {
    try {
      final res = await _client.get(ApiEndpoints.narrationStatus(articleId));
      return NarrationJob.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const NarrationJob(status: NarrationJobStatus.unknown);
      }
      // Unreachable / 5xx / 401: keep trying ensure + poll. Do NOT mark
      // configured:false — that used to skip ensure and latch on-device TTS.
      return const NarrationJob(
        status: NarrationJobStatus.unknown,
        reason: 'unreachable',
      );
    }
  }

  Future<NarrationJob> ensure(Article article) async {
    try {
      final text = ArticleTtsService.extractSpeakableText(article);
      final res = await _client.post(
        ApiEndpoints.narrationEnsure(article.id),
        data: {
          'title': article.title,
          'category': article.category,
          'source': article.source,
          'text': text,
        },
      );
      return NarrationJob.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on DioException {
      return const NarrationJob(
        status: NarrationJobStatus.unknown,
        reason: 'unreachable',
      );
    }
  }

  Future<void> complete(String articleId, {String? cacheKey}) async {
    try {
      await _client.post(
        ApiEndpoints.narrationComplete(articleId),
        data: {'cacheKey': cacheKey, 'cache_key': cacheKey},
      );
    } on DioException {
      // Reaper is the backstop. Never throw into the player.
    }
  }

  String audioUrl(String articleId) => ApiEndpoints.narrationAudio(articleId);

  Map<String, String> audioHeaders() {
    final token = AppTokenStore.instance.token;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }
}
