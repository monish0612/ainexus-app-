// Widget/integration test for the salary entry bottom sheet. Runs the REAL
// modal + REAL SalaryRepository over an in-memory Drift DB. Proves: the field
// digits-only filters, a hike preview vs the previous month appears, and saving
// persists the month's salary (which then syncs).

import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/domain/entities/salary_entities.dart';
import 'package:ai_nexus/presentation/screens/expense/modals/salary_entry_modal.dart';

class _FakeApi extends ApiClient {
  _FakeApi();
  Response<T> _r<T>(String p, Object? d) => Response<T>(
      requestOptions: RequestOptions(path: p), data: d as T?, statusCode: 200);
  @override
  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async =>
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

ThemeData _theme() => ThemeData(
      extensions: const <ThemeExtension<dynamic>>[
        AppColors(
          shadowColor: Color(0x66000000),
          glassFill: Color(0x0DFFFFFF),
          scrim: Color(0x99000000),
          cardGradientTop: Color(0xFF0B0B0F),
          cardGradientBottom: Color(0xFF060608),
          shimmerBase: Color(0x14FFFFFF),
          shimmerHighlight: Color(0x2EFFFFFF),
          bg: Color(0xFF000000),
          bg1: Color(0xFF060608),
          bg2: Color(0xFF131316),
          bg3: Color(0xFF1B1B1F),
          bg4: Color(0xFF26262B),
          text: Color(0xFFF1F5F9),
          text2: Color(0xFF94A3B8),
          text3: Color(0xFF6B7280),
          text4: Color(0xFF4B5563),
          text5: Color(0xFF374151),
          border: Color(0xFF1F2937),
          border2: Color(0xFF111827),
          headerBg: Color(0xFF000000),
          navBg: Color(0xFF000000),
          isDark: true,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showSalaryEntryModal(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('entering a salary saves it for the current month',
      (tester) async {
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), '95000');
    await tester.pump();
    await tester.tap(find.text('Save salary'));
    await tester.pumpAndSettle();

    final cur = monthKeyOf(DateTime.now());
    final saved =
        await container.read(salaryRepositoryProvider).getSalaryForMonth(cur);
    expect(saved, isNotNull);
    expect(saved!.amount, 95000);
  });

  testWidgets('shows a hike preview vs the previous recorded month',
      (tester) async {
    final now = DateTime.now();
    final prev = monthKeyOf(DateTime(now.year, now.month - 1, 1));
    await container.read(salaryRepositoryProvider).setSalaryForMonth(prev, 80000);

    await openSheet(tester);
    // Previous month context row renders.
    expect(find.text('Previous month'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '88000');
    await tester.pump();
    // +10% hike badge.
    expect(find.textContaining('+10.0%'), findsOneWidget);
  });

  testWidgets('digits-only filter strips non-numeric input', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), '9a9b0c0d0');
    await tester.pump();
    expect(find.text('99000'), findsOneWidget);
  });
}
