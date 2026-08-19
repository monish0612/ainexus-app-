// Screen-level integration test for the AI recommendation card inside the REAL
// ExpenseTimeframeScreen. Guards against the regression where the card grew to
// occupy the whole page and pushed the summary + transaction table off-screen.
//
// Renders at a typical phone size with the AI insight enabled and asserts that
// the card, the Total-Spent summary, AND a transaction row all coexist with
// zero overflow — and that the card stays height-bounded.

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:ai_nexus/presentation/screens/expense/expense_timeframe_screen.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/ai_recommendation_card.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiClient {
  _FakeApi();
  Response<T> _r<T>(String p, Object? d) => Response<T>(
      requestOptions: RequestOptions(path: p), data: d as T?, statusCode: 200);
  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async =>
      _r<T>(path, const <dynamic>[]);
  @override
  Future<Response<T>> post<T>(String path, {Object? data, Options? options, CancelToken? cancelToken}) async =>
      _r<T>(path, <String, dynamic>{'ok': true});
  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async => _r<T>(path, <String, dynamic>{});
  @override
  Future<Response<T>> delete<T>(String path) async => _r<T>(path, <String, dynamic>{'ok': true});
}

ThemeData _theme() => ThemeData(
      extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;

  setUp(() => database = db.AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => database.close());

  testWidgets(
      'AI card, summary and table coexist with no overflow (card stays bounded)',
      (tester) async {
    // Typical phone viewport.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final repo = ExpenseRepository(database, _FakeApi(), prefs);

    // Seed enough data that the engine produces a rich recommendation.
    await repo.addExpense(const Expense(
      id: 'b1', amount: 8421, description: 'Apartment bills',
      category: 'Bills', bank: 'HDFC', cardType: 'CC',
      date: '2026-06-25T11:00:00.000', isManualCategory: false,
    ));
    await repo.addExpense(const Expense(
      id: 'f1', amount: 220, description: 'Coffee',
      category: 'Food', bank: 'CASH', cardType: 'Cash',
      date: '2026-06-24T09:00:00.000', isManualCategory: false,
    ));

    await tester.pumpWidget(
      ProviderScope(
        // No settings/composer override: the composer path short-circuits and
        // the always-grounded deterministic template renders — exactly the
        // offline/degraded path the user must never see break.
        overrides: [
          expenseRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: _theme(),
          home: const ExpenseTimeframeScreen(
            timeframe: ExpenseTimeframe(
              label: 'Spending Breakdown',
              startIso: null,
              aiInsight: true,
              aiQuestion: 'recommendations to minimize my expenses',
            ),
          ),
        ),
      ),
    );
    // The card's shimmer animates forever, so pumpAndSettle would hang — pump
    // bounded frames to let the async load + grounding complete instead.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // No RenderFlex / overflow anywhere.
    expect(tester.takeException(), isNull);

    // The card rendered with its grounded template content.
    expect(find.byType(AiRecommendationCard), findsOneWidget);
    expect(find.textContaining('Hey'), findsOneWidget);

    // CRITICAL: the summary AND a transaction row are still visible — the card
    // did NOT take over the page.
    expect(find.textContaining('transaction'), findsOneWidget);
    expect(find.text('Apartment bills'), findsOneWidget);

    // The card must occupy only a fraction of the 780px viewport.
    final cardH = tester.getSize(find.byType(AiRecommendationCard)).height;
    expect(cardH, lessThan(360),
        reason: 'AI card must stay bounded, not fill the screen');
  });
}
