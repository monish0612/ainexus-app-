import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/expense_insight.dart';

/// Calls the backend Composer (`/ai/expense-insight`) to turn pre-computed
/// [InsightFacts] into a dynamic, personalized [ResponseSpec].
///
/// Only the user's first name + the COMPUTED token map are sent — never raw
/// expense rows. Returns `null` on any failure so callers fall back to the
/// deterministic template via [InsightGrounding.template]. Grounding/validation
/// of the returned spec is the caller's responsibility (see
/// `InsightGrounding.ground`).
class ExpenseInsightService {
  ExpenseInsightService(this._api);

  final ApiClient _api;

  Future<ResponseSpec?> compose(
    InsightFacts facts, {
    String? liteModel,
  }) async {
    final question = facts.question.trim();
    if (question.isEmpty) return null;
    final sw = Stopwatch()..start();
    try {
      final body = <String, dynamic>{
        'question': question,
        'firstName': facts.firstName,
        'facts': facts.toPromptTokens(),
      };
      if (liteModel != null && liteModel.trim().isNotEmpty) {
        body['liteModel'] = liteModel.trim();
      }
      final res = await _api.post<dynamic>(
        ApiEndpoints.aiExpenseInsight,
        data: body,
      );
      final data = res.data;
      if (data is! Map) {
        TLog.w('ExpenseInsight', 'Non-map response');
        return null;
      }
      final spec = ResponseSpec.fromJson(Map<String, dynamic>.from(data));
      if (spec.isEmpty) {
        TLog.w('ExpenseInsight', 'Empty spec ${sw.elapsedMilliseconds}ms');
        return null;
      }
      TLog.i('ExpenseInsight',
          '✓ ${sw.elapsedMilliseconds}ms tone=${spec.tone.name} chips=${spec.chips.length}');
      return spec;
    } on DioException catch (e, st) {
      TLog.e('ExpenseInsight', 'Compose failed ${sw.elapsedMilliseconds}ms',
          error: e, st: st);
      return null;
    } catch (e, st) {
      TLog.e('ExpenseInsight', 'Compose error ${sw.elapsedMilliseconds}ms',
          error: e, st: st);
      return null;
    }
  }
}
