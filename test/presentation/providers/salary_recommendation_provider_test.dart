// End-to-end orchestration tests for salaryRecommendationProvider — the glue
// that decides between the LLM-composed insight and the deterministic salary
// template. Wired over a REAL ProviderContainer with the composer faked so we
// can drive every branch deterministically:
//   • no salary      → template, composer NOT called (no wasted network)
//   • valid spec     → grounded, composed (real figures bound)
//   • offline (null) → SALARY template (not the generic expense template)
//   • hallucination  → SALARY template (ungrounded prose rejected)
//   • composer throws→ template (never crashes the UI)

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/expense_insight_service.dart';
import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/domain/entities/expense_insight.dart';
import 'package:ai_nexus/domain/entities/salary_entities.dart';
import 'package:ai_nexus/presentation/providers/salary_providers.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';

class _FakeApi extends ApiClient {
  _FakeApi();
  Response<T> _r<T>(String p, Object? d) => Response<T>(
      requestOptions: RequestOptions(path: p), data: d as T?, statusCode: 200);
  @override
  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters}) async =>
      _r<T>(path, <dynamic>[]);
  @override
  Future<Response<T>> post<T>(String path,
          {Object? data, Options? options, CancelToken? cancelToken}) async =>
      _r<T>(path, <String, dynamic>{'ok': true});
  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async =>
      _r<T>(path, <String, dynamic>{});
  @override
  Future<Response<T>> delete<T>(String path) async =>
      _r<T>(path, <String, dynamic>{'ok': true});
}

class _FakeInsight extends ExpenseInsightService {
  _FakeInsight(super.api, {this.spec, this.throwIt = false});
  final ResponseSpec? spec;
  final bool throwIt;
  int calls = 0;

  @override
  Future<ResponseSpec?> compose(InsightFacts facts, {String? liteModel}) async {
    calls++;
    if (throwIt) throw StateError('boom');
    return spec;
  }
}

SalaryStats _stats({double salary = 100000, double spent = 30000}) => SalaryStats(
      month: '2026-06',
      salary: salary,
      budget: 50000,
      spent: spent,
      previousSalary: 90000,
      totalRecorded: salary,
      monthsRecorded: 1,
      highestSalary: salary,
      averageSalary: salary,
      cumulativeSaved: 70000,
      avgSavingsRatePct: 70,
      avgMonthlySpend: 30000,
      dayOfMonth: 15,
      daysInMonth: 30,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    api = _FakeApi();
  });

  ProviderContainer makeContainer({
    required SalaryStats stats,
    required _FakeInsight insight,
  }) {
    return ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      sharedPreferencesProvider.overrideWithValue(prefs),
      userFirstNameProvider.overrideWithValue('Monish'),
      salaryStatsProvider.overrideWithValue(stats),
      expenseInsightServiceProvider.overrideWithValue(insight),
      settingsProvider.overrideWith(
        (ref) => SettingsController(prefs, UserPreferencesService(api)),
      ),
    ]);
  }

  test('no salary → deterministic template, composer NOT called', () async {
    final insight = _FakeInsight(api);
    final c = makeContainer(stats: SalaryStats.empty, insight: insight);
    addTearDown(c.dispose);

    final rec = await c.read(salaryRecommendationProvider.future);
    expect(rec.isTemplate, isTrue);
    expect(rec.greeting, 'Hey Monish,');
    expect(rec.headline.toLowerCase(), contains('salary'));
    expect(insight.calls, 0, reason: 'no network round-trip without a salary');
  });

  test('valid composed spec → grounded with real figures (not template)',
      () async {
    const spec = ResponseSpec(
      greeting: 'Hey {{name}},',
      headline: 'You saved {{saved}} of your {{salary}} salary.',
      tip: 'Budget used: {{budgetUsedPct}}.',
      tone: InsightTone.positive,
      chips: ['How can I save more?'],
    );
    final insight = _FakeInsight(api, spec: spec);
    final c = makeContainer(stats: _stats(), insight: insight);
    addTearDown(c.dispose);

    final rec = await c.read(salaryRecommendationProvider.future);
    expect(insight.calls, 1);
    expect(rec.isTemplate, isFalse);
    expect(rec.greeting, 'Hey Monish,');
    expect(rec.headline, contains('₹70,000'));
    expect(rec.headline, contains('₹1,00,000'));
    expect(rec.tip, contains('60%')); // 30k / 50k budget
  });

  test('offline composer (null spec) → SALARY template, not expense template',
      () async {
    final insight = _FakeInsight(api, spec: null);
    final c = makeContainer(stats: _stats(), insight: insight);
    addTearDown(c.dispose);

    final rec = await c.read(salaryRecommendationProvider.future);
    expect(insight.calls, 1);
    expect(rec.isTemplate, isTrue);
    expect(rec.greeting, 'Hey Monish,');
    // Salary-specific wording — must NOT be the generic expense fallback.
    expect(rec.headline.toLowerCase(), contains('saved'));
    expect(rec.headline.toLowerCase(), isNot(contains('expenses')));
  });

  test('hallucinated bare number → rejected, falls back to SALARY template',
      () async {
    const spec = ResponseSpec(
      greeting: 'Hey {{name}},',
      headline: 'You secretly saved ₹42000 more.', // ungrounded number
      tip: 'Trust me.',
      tone: InsightTone.positive,
      chips: [],
    );
    final insight = _FakeInsight(api, spec: spec);
    final c = makeContainer(stats: _stats(), insight: insight);
    addTearDown(c.dispose);

    final rec = await c.read(salaryRecommendationProvider.future);
    expect(rec.isTemplate, isTrue);
    expect(rec.headline, isNot(contains('42000')));
    expect(rec.headline.toLowerCase(), contains('saved'));
  });

  test('composer throws → template (never crashes)', () async {
    final insight = _FakeInsight(api, throwIt: true);
    final c = makeContainer(stats: _stats(), insight: insight);
    addTearDown(c.dispose);

    final rec = await c.read(salaryRecommendationProvider.future);
    expect(rec.isTemplate, isTrue);
    expect(rec.greeting, 'Hey Monish,');
    expect(rec.hasContent, isTrue);
  });
}
