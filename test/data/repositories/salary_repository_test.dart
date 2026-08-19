// Deep integration tests for [SalaryRepository] against a REAL in-memory Drift
// DB with a controllable fake [ApiClient]. Covers month upsert/"reset"
// semantics, ordering, server merge (last-write-wins) and clears.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/salary_repository.dart';
import 'package:ai_nexus/domain/entities/salary_entities.dart';

class _FakeApi extends ApiClient {
  _FakeApi();

  final List<String> calls = <String>[];
  final List<Object?> postBodies = <Object?>[];
  Object? getResponse;
  bool failPost = false;

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    calls.add('GET $path');
    return _resp<T>(path, getResponse ?? <dynamic>[]);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    calls.add('POST $path');
    postBodies.add(data);
    if (failPost) throw DioException(requestOptions: RequestOptions(path: path));
    return _resp<T>(path, <String, dynamic>{'ok': true});
  }

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async {
    calls.add('PUT $path');
    return _resp<T>(path, <String, dynamic>{});
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    calls.add('DELETE $path');
    return _resp<T>(path, <String, dynamic>{'ok': true});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _FakeApi api;
  late SalaryRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    repo = SalaryRepository(database, api, prefs);
  });

  tearDown(() async {
    await database.close();
  });

  group('setSalaryForMonth', () {
    test('stores locally and posts month + amount', () async {
      final ok = await repo.setSalaryForMonth('2026-06', 85000);
      expect(ok, isTrue);

      final rows = await database.select(database.salaryEntries).get();
      expect(rows.length, 1);
      expect(rows.single.month, '2026-06');
      expect(rows.single.amount, 85000);

      final body = api.postBodies.single as Map<String, dynamic>;
      expect(body['month'], '2026-06');
      expect(body['amount'], 85000);
      expect(body['id'], isNotEmpty);
    });

    test('re-entering the same month upserts (reset) and keeps id stable',
        () async {
      await repo.setSalaryForMonth('2026-06', 80000);
      final firstId =
          (await database.select(database.salaryEntries).getSingle()).id;

      await repo.setSalaryForMonth('2026-06', 92000);
      final rows = await database.select(database.salaryEntries).get();
      expect(rows.length, 1, reason: 'one row per month');
      expect(rows.single.amount, 92000);
      expect(rows.single.id, firstId, reason: 'id stays stable across edits');
    });

    test('different months create distinct rows', () async {
      await repo.setSalaryForMonth('2026-05', 80000);
      await repo.setSalaryForMonth('2026-06', 85000);
      await repo.setSalaryForMonth('2026-07', 90000);
      final rows = await database.select(database.salaryEntries).get();
      expect(rows.length, 3);
    });

    test('returns false but still persists when sync fails', () async {
      api.failPost = true;
      final ok = await repo.setSalaryForMonth('2026-06', 70000);
      expect(ok, isFalse);
      final rows = await database.select(database.salaryEntries).get();
      expect(rows.single.amount, 70000);
    });
  });

  group('reads', () {
    test('watchSalaries emits newest month first', () async {
      await repo.setSalaryForMonth('2026-04', 70000);
      await repo.setSalaryForMonth('2026-06', 80000);
      await repo.setSalaryForMonth('2026-05', 75000);

      final list = await repo.watchSalaries().first;
      expect(list.map((e) => e.month).toList(),
          ['2026-06', '2026-05', '2026-04']);
    });

    test('getSalaryForMonth returns null when missing', () async {
      expect(await repo.getSalaryForMonth('2099-01'), isNull);
    });

    test('getCurrentMonthSalary reads the current month', () async {
      final key = monthKeyOf(DateTime.now());
      await repo.setSalaryForMonth(key, 123456);
      final cur = await repo.getCurrentMonthSalary();
      expect(cur, isNotNull);
      expect(cur!.amount, 123456);
    });
  });

  group('syncSalaryFromServer', () {
    test('inserts new months from server', () async {
      api.getResponse = <Map<String, dynamic>>[
        {'id': 'a', 'month': '2026-06', 'amount': 88000, 'setAt': '2026-06-01T00:00:00Z'},
        {'id': 'b', 'month': '2026-05', 'amount': 80000, 'setAt': '2026-05-01T00:00:00Z'},
      ];
      final merged = await repo.syncSalaryFromServer();
      expect(merged, 2);
      final rows = await database.select(database.salaryEntries).get();
      expect(rows.length, 2);
    });

    test('server wins only when its setAt is newer (last-write-wins)', () async {
      // Local entered now (newest).
      await repo.setSalaryForMonth('2026-06', 90000);
      // Server has an OLDER timestamp → must NOT override the fresh local edit.
      api.getResponse = <Map<String, dynamic>>[
        {'id': 'srv', 'month': '2026-06', 'amount': 1, 'setAt': '2000-01-01T00:00:00Z'},
      ];
      final merged = await repo.syncSalaryFromServer();
      expect(merged, 0);
      final row =
          await (database.select(database.salaryEntries)).getSingle();
      expect(row.amount, 90000);
    });

    test('server overrides when newer', () async {
      await repo.setSalaryForMonth('2026-06', 90000);
      api.getResponse = <Map<String, dynamic>>[
        {'id': 'srv', 'month': '2026-06', 'amount': 95000, 'setAt': '2999-01-01T00:00:00Z'},
      ];
      final merged = await repo.syncSalaryFromServer();
      expect(merged, 1);
      final row = await database.select(database.salaryEntries).getSingle();
      expect(row.amount, 95000);
    });

    test('handles {history:[...]} envelope shape', () async {
      api.getResponse = <String, dynamic>{
        'history': <Map<String, dynamic>>[
          {'id': 'a', 'month': '2026-06', 'amount': 50000, 'setAt': '2026-06-01T00:00:00Z'},
        ],
      };
      final merged = await repo.syncSalaryFromServer();
      expect(merged, 1);
    });

    test('skips malformed rows without throwing', () async {
      api.getResponse = <dynamic>[
        'not-a-map',
        {'id': 'a', 'amount': 50000, 'setAt': '2026-06-01T00:00:00Z'}, // no month
        {'id': 'b', 'month': '2026-07', 'amount': 60000}, // no setAt
        {'id': 'c', 'month': '2026-08', 'amount': 'NaN', 'setAt': '2026-08-01T00:00:00Z'},
        {'id': 'd', 'month': '2026-09', 'amount': 70000, 'setAt': '2026-09-01T00:00:00Z'},
      ];
      final merged = await repo.syncSalaryFromServer();
      // Only the fully-valid row 'd' (2026-09) merges. The string, the
      // month-less row, the setAt-less row and the NaN-amount row are all
      // skipped — crucially nothing throws and the good row still lands.
      final rows = await database.select(database.salaryEntries).get();
      final months = rows.map((r) => r.month).toSet();
      expect(months, {'2026-09'});
      expect(merged, 1);
    });

    test('non-list / unexpected payload yields zero merges, no throw', () async {
      api.getResponse = <String, dynamic>{'unexpected': true};
      expect(await repo.syncSalaryFromServer(), 0);
    });

    test('decimal amounts are preserved', () async {
      await repo.setSalaryForMonth('2026-06', 87654.5);
      final row = await database.select(database.salaryEntries).getSingle();
      expect(row.amount, 87654.5);
    });
  });

  group('clearSalaryHistory', () {
    test('wipes local rows and calls server delete', () async {
      await repo.setSalaryForMonth('2026-06', 80000);
      final ok = await repo.clearSalaryHistory();
      expect(ok, isTrue);
      final rows = await database.select(database.salaryEntries).get();
      expect(rows, isEmpty);
      expect(api.calls.any((c) => c.startsWith('DELETE')), isTrue);
    });
  });
}
