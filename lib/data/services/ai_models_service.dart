import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/ai_error.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';

/// Single Gemini model entry returned by the backend's `/api/v1/ai/models`
/// endpoint. The list is the result of asking Google's
/// `/v1beta/models?key=…` what the configured server-side API key can
/// actually invoke — so what the user sees in Settings is always
/// in lock-step with reality (no hard-coded enums).
class GeminiModel {
  const GeminiModel({
    required this.id,
    required this.displayName,
    this.description = '',
    this.inputTokenLimit,
    this.outputTokenLimit,
  });

  /// Bare model id consumed by `gemini-direct.js` on the backend
  /// (e.g. `gemini-3.1-flash-lite-preview`, `gemini-2.5-flash`).
  final String id;

  /// Human-friendly label from Google's catalogue (e.g. "Gemini 1.5
  /// Flash"). Used for the primary line in the picker.
  final String displayName;

  /// Vendor description — long, free-form text. Shown as a tooltip
  /// or secondary line.
  final String description;

  final int? inputTokenLimit;
  final int? outputTokenLimit;

  factory GeminiModel.fromJson(Map<String, dynamic> json) => GeminiModel(
        id: (json['id'] ?? '').toString(),
        displayName: (json['displayName'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        inputTokenLimit: (json['inputTokenLimit'] as num?)?.toInt(),
        outputTokenLimit: (json['outputTokenLimit'] as num?)?.toInt(),
      );
}

/// Result envelope from `/api/v1/ai/models`.
class GeminiModelList {
  const GeminiModelList({
    required this.models,
    this.primary,
    this.cachedAt,
  });

  /// All models sorted server-side: non-experimental first, newer
  /// versions ahead of older ones, lite variants demoted.
  final List<GeminiModel> models;

  /// Server's pick for "if the user hasn't chosen, use this". Mirrors
  /// what news ingestion falls back to.
  final String? primary;

  /// Server-side cache timestamp — useful in QA to confirm a refresh
  /// went through.
  final String? cachedAt;

  bool get isEmpty => models.isEmpty;
  bool get isNotEmpty => models.isNotEmpty;
}

class AiModelsService {
  AiModelsService(this._dio);
  final Dio _dio;

  /// Pass `force: true` to bust the server-side cache via
  /// `?refresh=1`. The Settings sheet uses this when the user taps
  /// the refresh icon next to the picker.
  Future<GeminiModelList> list({bool force = false}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        ApiEndpoints.aiModels,
        queryParameters: force ? {'refresh': '1'} : null,
      );
      final data = res.data ?? const {};
      final raw = (data['models'] as List?) ?? const [];
      final models = raw
          .whereType<Map>()
          .map((m) => GeminiModel.fromJson(Map<String, dynamic>.from(m)))
          .where((m) => m.id.isNotEmpty)
          .toList(growable: false);
      return GeminiModelList(
        models: models,
        primary: (data['primary'] as String?)?.trim().isEmpty ?? true
            ? null
            : data['primary'] as String,
        cachedAt: data['cachedAt'] as String?,
      );
    } on DioException catch (e) {
      // Convert into the same envelope the toast layer already
      // understands so the Settings sheet can show a meaningful
      // message ("API key not configured", "rate-limited", …) instead
      // of an opaque "failed to load models".
      final err = AiError.fromDio(e, fallbackMessage: 'Could not load Gemini models');
      TLog.w('AIModels', 'list failed → ${err.code}: ${err.userMessage}');
      throw err;
    } catch (e) {
      TLog.w('AIModels', 'list failed: $e');
      throw AiError.fromAny(e, fallbackMessage: 'Could not load Gemini models');
    }
  }
}

final aiModelsServiceProvider = Provider<AiModelsService>(
  (ref) => AiModelsService(ref.read(apiClientProvider).dio),
);
