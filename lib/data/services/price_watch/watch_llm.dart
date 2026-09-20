import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/services/telegram_logger.dart';
import 'price_models.dart';
import 'price_parse.dart';

/// Last-resort product extract when store adapters miss. Droplert still
/// parks 35% jumps — this only fills name/price when HTML had no structured
/// Offer. Background WorkManager may omit this (no JWT in that isolate).
abstract class WatchLlmPort {
  Future<WatchLlmHit?> extract({
    required String url,
    required String excerpt,
    String? liteModel,
  });
}

class WatchLlmHit {
  const WatchLlmHit({
    required this.price,
    required this.name,
    this.imageUrl = '',
    this.availability,
    this.confidence = 0,
  });

  final double price;
  final String name;
  final String imageUrl;
  final String? availability;
  final double confidence;

  ScrapeHit toHit() {
    final score = confidence >= 0.75
        ? 58
        : confidence >= 0.55
            ? 52
            : 48;
    return ScrapeHit(
      price: price,
      source: 'gemini',
      name: name,
      imageUrl: imageUrl,
      availability: availability,
      score: score,
    );
  }
}

class NoopWatchLlm implements WatchLlmPort {
  const NoopWatchLlm();

  @override
  Future<WatchLlmHit?> extract({
    required String url,
    required String excerpt,
    String? liteModel,
  }) async =>
      null;
}

/// Pins Settings → Gemini Lite (`liteModel`) through `/ai/watch-extract`.
class GeminiWatchLlm implements WatchLlmPort {
  GeminiWatchLlm(this._api);

  final ApiClient _api;

  @override
  Future<WatchLlmHit?> extract({
    required String url,
    required String excerpt,
    String? liteModel,
  }) async {
    final clip = excerpt.trim();
    if (clip.length < 40) return null;
    try {
      final body = <String, dynamic>{
        'url': url,
        'excerpt': clip.length > 6000 ? clip.substring(0, 6000) : clip,
      };
      final model = liteModel?.trim();
      if (model != null && model.isNotEmpty) body['liteModel'] = model;
      final res = await _api.post<Object?>(
        ApiEndpoints.aiWatchExtract,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      return parseWatchLlmResponse(res.data);
    } catch (e) {
      TLog.w('Watch', 'Gemini extract skipped: $e', error: e);
      return null;
    }
  }
}

/// Accepts the API envelope or a bare model JSON object.
WatchLlmHit? parseWatchLlmResponse(Object? data) {
  if (data is! Map) return null;
  final map = Map<String, dynamic>.from(data);
  final nested = map['extract'];
  if (nested is Map) {
    return _hitFromMap(Map<String, dynamic>.from(nested));
  }
  return _hitFromMap(map);
}

WatchLlmHit? _hitFromMap(Map<String, dynamic> map) {
  final isProduct = map['isProduct'] == true || map['is_product'] == true;
  if (!isProduct) return null;
  final price = parsePrice(map['price']?.toString());
  if (price == null || price <= 0) return null;
  final name = (map['name'] ?? map['title'] ?? '').toString().trim();
  if (name.isEmpty) return null;
  var conf = 0.0;
  final rawConf = map['confidence'];
  if (rawConf is num) conf = rawConf.toDouble();
  if (rawConf is String) conf = double.tryParse(rawConf) ?? 0;
  if (conf > 1 && conf <= 100) conf = conf / 100;
  final avail = (map['availability'] ?? '').toString().trim();
  return WatchLlmHit(
    price: price,
    name: name,
    imageUrl: (map['imageUrl'] ?? map['image_url'] ?? '').toString().trim(),
    availability: avail.isEmpty ? null : avail,
    confidence: conf.clamp(0, 1),
  );
}
