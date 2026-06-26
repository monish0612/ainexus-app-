// Hermetic tests for the previously-untested ExpenseRepository paths:
// budget set/get, learnings save/get, and the easter-egg clear operations
// (local-first delete + server verify + pending-retry flag on outage).
//
// Runs the REAL repository against a REAL in-memory Drift DB with a
// controllable fake ApiClient and mock SharedPreferences.

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiClient {
  _FakeApi();

  /// Methods that should throw a connection error (simulate offline backend).
  final Set<String> failMethods = <String>{};

  /// Returns response data for a GET path (used for clear verification).
  Object? Function(String path)? onGet;

  final List<String> deletes = <String>[];
  final List<({String path, Object? data})> posts = <({String path, Object? data})>[];

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  Never _throwOffline(String path) => throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        message: 'fake offline',
      );

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters}) async {
    if (failMethods.contains('GET')) _throwOffline(path);
    return _resp<T>(path, onGet?.call(path) ?? const <dynamic>[]);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    if (failMethods.contains('POST')) _throwOffline(path);
    posts.add((path: path, data: data));
    return _resp<T>(path, null);
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    if (failMethods.contains('DELETE')) _throwOffline(path);
    deletes.add(path);
    return _resp<T>(path, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _FakeApi api;
  late ExpenseRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    repo = ExpenseRepository(database, api, prefs);
  });

  tearDown(() async {
    await database.close();
  });

  group('budget', () {
    test('setBudget persists locally and getBudget returns the latest', () async {
      await repo.setBudget(5000);
      await repo.setBudget(8000);
      expect(await repo.getBudget(), 8000,
          reason: 'getBudget returns the most-recently-set entry');
    });

    test('getBudget returns 0 when no budget has ever been set', () async {
      expect(await repo.getBudget(), 0);
    });

    test('setBudget survives a backend outage (local kept, returns false)',
        () async {
      api.failMethods.add('POST');
      final ok = await repo.setBudget(3000);
      expect(ok, isFalse, reason: 'server sync failed');
      expect(await repo.getBudget(), 3000, reason: 'local write is durable');
    });
  });

  group('learnings', () {
    test('saveLearning + getLearnings round-trip', () async {
      await repo.saveLearning('swiggy', 'Food');
      await repo.saveLearning('uber', 'Transport');
      final learnings = await repo.getLearnings();
      expect(learnings['swiggy'], 'Food');
      expect(learnings['uber'], 'Transport');
    });

    test('saveLearning upserts (latest category wins for a keyword)', () async {
      await repo.saveLearning('amazon', 'Shopping');
      await repo.saveLearning('amazon', 'Electronics');
      final learnings = await repo.getLearnings();
      expect(learnings['amazon'], 'Electronics');
    });
  });

  group('clearAllExpenses', () {
    test('success: clears local + server, no pending flag', () async {
      api.onGet = (_) => const <dynamic>[]; // verify GET sees an empty server
      final ok = await repo.clearAllExpenses();
      expect(ok, isTrue);
      expect(api.deletes, isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pending_clear_expenses'), isNot(true));
    });

    test('server outage: local cleared, pending flag set, then retry resolves',
        () async {
      api.failMethods.add('DELETE');
      final ok = await repo.clearAllExpenses();
      expect(ok, isFalse, reason: 'server delete failed after retries');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pending_clear_expenses'), isTrue,
          reason: 'pending clear is flagged for later retry');

      // Backend comes back online — retryPendingClears should resolve + clear.
      api.failMethods.remove('DELETE');
      api.onGet = (_) => const <dynamic>[];
      await repo.retryPendingClears();
      expect(prefs.getBool('pending_clear_expenses'), isNot(true),
          reason: 'pending flag removed after a successful retry');
    });
  });

  group('clearBudgetHistory', () {
    test('success clears local budget entries', () async {
      await repo.setBudget(1000);
      api.onGet = (_) => const <dynamic>[];
      final ok = await repo.clearBudgetHistory();
      expect(ok, isTrue);
      expect(await repo.getBudget(), 0, reason: 'local budget wiped');
    });
  });
}
