import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../repositories/expense_repository.dart';

/// Structured query the backend (Gemini) distills from a free-text question.
///
/// The app executes this spec against the LOCAL Drift DB — exact, complete,
/// editable and instant even for very large histories. No expense data leaves
/// the device; only the question + schema hints are sent.
class ExpenseQuerySpec {
  const ExpenseQuerySpec({
    required this.title,
    required this.answer,
    required this.startIso,
    required this.endIso,
    required this.category,
    required this.search,
    required this.searchTerms,
    required this.sort,
    required this.limit,
    required this.isSummary,
    required this.chart,
    this.isSalaryTopic = false,
    this.model,
  });

  final String title;
  final String answer;
  final String? startIso;
  final String? endIso;
  final String? category;
  final String? search;

  /// Semantic OR-group from query expansion — a row matches ANY of these terms.
  final List<String> searchTerms;
  final ExpenseSort sort;
  final int limit;
  final bool isSummary;
  final ExpenseChart chart;

  /// True when the question is about salary/income — the app routes to the
  /// dedicated salary stats screen (which holds the real numbers) instead of
  /// running an expense list/summary query.
  final bool isSalaryTopic;
  final String? model;

  static ExpenseSort _parseSort(Object? raw) {
    switch (raw?.toString()) {
      case 'date_asc':
        return ExpenseSort.dateAsc;
      case 'amount_desc':
        return ExpenseSort.amountDesc;
      case 'amount_asc':
        return ExpenseSort.amountAsc;
      case 'date_desc':
      default:
        return ExpenseSort.dateDesc;
    }
  }

  static ExpenseChart _parseChart(Object? mode, Object? type) {
    if (mode?.toString() != 'chart') return ExpenseChart.none;
    switch (type?.toString()) {
      case 'daily':
        return ExpenseChart.daily;
      case 'monthly':
        return ExpenseChart.monthly;
      case 'category':
        return ExpenseChart.category;
      default:
        return ExpenseChart.category; // chart requested but type unclear
    }
  }

  static String? _str(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// Sanitize the AI's expanded keyword list: keep non-empty trimmed strings,
  /// cap length, dedupe (case-insensitively), and cap the count. Defensive so a
  /// noisy model response can never blow up the query or the UI.
  static List<String> _terms(Object? v) {
    if (v is! List) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final e in v) {
      if (e is! String) continue;
      final t = e.trim();
      if (t.isEmpty || t.length > 40) continue;
      if (seen.add(t.toLowerCase())) out.add(t);
      if (out.length >= 12) break;
    }
    return out;
  }

  factory ExpenseQuerySpec.fromJson(Map<String, dynamic> m) {
    final rawLimit = m['limit'];
    final limit = (rawLimit is num)
        ? rawLimit.toInt().clamp(1, 500)
        : int.tryParse('${rawLimit ?? ''}')?.clamp(1, 500) ?? 500;
    return ExpenseQuerySpec(
      title: _str(m['title']) ?? 'Results',
      answer: _str(m['answer']) ?? '',
      startIso: _str(m['startIso']),
      endIso: _str(m['endIso']),
      category: _str(m['category']),
      search: _str(m['search']),
      searchTerms: _terms(m['searchAny']),
      sort: _parseSort(m['sort']),
      limit: limit,
      isSummary: m['mode']?.toString() == 'summary',
      chart: _parseChart(m['mode'], m['chartType']),
      isSalaryTopic: m['topic']?.toString() == 'salary',
      model: _str(m['model']),
    );
  }
}

/// Translates a natural-language expense question into an [ExpenseQuerySpec]
/// via the backend → LiteLLM (Gemini) gateway. Returns `null` on any failure
/// so callers can gracefully fall back to a plain keyword search.
class ExpenseAiSearchService {
  ExpenseAiSearchService(this._api);

  final ApiClient _api;

  Future<ExpenseQuerySpec?> query(
    String question, {
    List<String> categories = const [],
    String? liteModel,
  }) async {
    final q = question.trim();
    if (q.isEmpty) return null;
    final sw = Stopwatch()..start();
    try {
      final body = <String, dynamic>{
        'question': q,
        // Naive local wall-clock (matches how expense timestamps are stored).
        'now': DateTime.now().toIso8601String().split('.').first,
        if (categories.isNotEmpty) 'categories': categories,
      };
      if (liteModel != null && liteModel.trim().isNotEmpty) {
        body['liteModel'] = liteModel.trim();
      }
      final res = await _api.post<dynamic>(
        ApiEndpoints.aiExpenseQuery,
        data: body,
      );
      final data = res.data;
      if (data is! Map) {
        TLog.w('ExpenseAiSearch', 'Non-map response');
        return null;
      }
      final spec = ExpenseQuerySpec.fromJson(Map<String, dynamic>.from(data));
      TLog.i('ExpenseAiSearch',
          '✓ ${sw.elapsedMilliseconds}ms model=${spec.model} sort=${spec.sort.name} '
          'cat=${spec.category ?? '-'} search=${spec.search ?? '-'} '
          'terms=${spec.searchTerms.length} chart=${spec.chart.name}');
      return spec;
    } on DioException catch (e, st) {
      TLog.e('ExpenseAiSearch', 'Query failed ${sw.elapsedMilliseconds}ms',
          error: e, st: st);
      return null;
    } catch (e, st) {
      TLog.e('ExpenseAiSearch', 'Query error ${sw.elapsedMilliseconds}ms',
          error: e, st: st);
      return null;
    }
  }
}
