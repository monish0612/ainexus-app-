// Cross-device "nuke" propagation tests for ResetSyncService.
//
// A single fake backend holds the global reset epoch (full_gen / expense_gen).
// Two ResetSyncService instances with SEPARATE local Drift DBs + prefs play the
// role of two devices sharing that one backend, so we can prove that a reset
// recorded on device A is detected and applied (locally wiped) on device B.

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/nuke_report.dart';
import 'package:ai_nexus/core/services/reset_sync_service.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One shared fake backend: a mutable global epoch + the data-reset routes.
class _FakeBackend {
  int fullGen = 0;
  int expenseGen = 0;
  bool offline = false;

  Map<String, dynamic> get state =>
      {'fullGen': fullGen, 'expenseGen': expenseGen, 'resetAt': 'now'};

  void bump(String scope) {
    if (scope == 'expense') {
      expenseGen++;
    } else {
      fullGen++;
    }
  }
}

/// A device-scoped ApiClient backed by the shared [_FakeBackend].
class _DeviceApi extends ApiClient {
  _DeviceApi(this.backend);
  final _FakeBackend backend;

  Response<T> _ok<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  Never _offline(String path) => throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        message: 'offline',
      );

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    if (backend.offline) _offline(path);
    if (path.contains('data-reset')) return _ok<T>(path, backend.state);
    return _ok<T>(path, const <dynamic>[]);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    if (backend.offline) _offline(path);
    if (path.contains('data-reset')) {
      final scope = (data is Map ? data['scope']?.toString() : null) ?? 'full';
      backend.bump(scope);
      return _ok<T>(path, backend.state);
    }
    return _ok<T>(path, null);
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    if (backend.offline) _offline(path);
    return _ok<T>(path, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBackend backend;

  // Build an independent "device": its own DB + prefs + api → reset service.
  Future<({db.AppDatabase db, SharedPreferences prefs, ResetSyncService svc})>
      newDevice({Map<String, Object>? initialPrefs}) async {
    SharedPreferences.setMockInitialValues(initialPrefs ?? <String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    final svc = ResetSyncService(database, _DeviceApi(backend), prefs);
    return (db: database, prefs: prefs, svc: svc);
  }

  Future<void> seedFinancial(db.AppDatabase database) async {
    await database.into(database.expenses).insert(db.ExpensesCompanion.insert(
        id: 'e1', amount: 100, description: 'd', category: 'Food', bank: 'H', cardType: 'CC', date: '2026-06-01T00:00:00.000Z'));
    await database.into(database.budgetEntries).insert(
        db.BudgetEntriesCompanion.insert(id: 'b1', amount: 5000, setAt: '2026-06-01T00:00:00.000Z'));
    await database.into(database.salaryEntries).insert(
        db.SalaryEntriesCompanion.insert(id: 's1', month: '2026-06', amount: 9, setAt: '2026-06-01T00:00:00.000Z'));
  }

  Future<void> seedSavedWord(db.AppDatabase database) async {
    await database.into(database.savedWords).insert(db.SavedWordsCompanion.insert(
        id: 'w1', word: 'w', definition: 'd', pronunciation: '', partOfSpeech: 'n', savedAt: '2026-06-01T00:00:00.000Z'));
  }

  setUp(() => backend = _FakeBackend());

  test('FULL reset on device A wipes ALL local data on device B', () async {
    final a = await newDevice();
    final b = await newDevice();
    await seedFinancial(b.db);
    await seedSavedWord(b.db);

    // Device A nukes → records a full reset (bumps server epoch).
    expect(await a.svc.recordReset(NukeScope.full), isTrue);
    expect(backend.fullGen, 1);

    // Device B, on next launch, detects the newer epoch and wipes itself.
    final wiped = await b.svc.applyRemoteResetIfNeeded();
    expect(wiped, isTrue);
    final counts = await b.db.dataRowCounts();
    expect(counts.values.every((c) => c == 0), isTrue,
        reason: 'device B fully reset to match the cloud');

    await a.db.close();
    await b.db.close();
  });

  test('EXPENSE reset clears ONLY financial data on the other device', () async {
    final a = await newDevice();
    final b = await newDevice();
    await seedFinancial(b.db);
    await seedSavedWord(b.db);

    expect(await a.svc.recordReset(NukeScope.expense), isTrue);
    expect(backend.expenseGen, 1);

    expect(await b.svc.applyRemoteResetIfNeeded(), isTrue);
    final counts = await b.db.dataRowCounts();
    expect(counts['Expenses'], 0);
    expect(counts['Budget history'], 0);
    expect(counts['Salary'], 0);
    expect(counts['Saved words'], 1,
        reason: 'an expense reset must NOT touch non-financial data');

    await a.db.close();
    await b.db.close();
  });

  test('initiating device adopts the epoch and never re-wipes itself', () async {
    final a = await newDevice();
    await seedFinancial(a.db);

    await a.svc.recordReset(NukeScope.full); // A already wiped its own rows IRL
    // A's local data here is just the seed; the apply pass must be a NO-OP
    // because A adopted the generation it just bumped.
    final wiped = await a.svc.applyRemoteResetIfNeeded();
    expect(wiped, isFalse, reason: 'no re-wipe on the device that initiated it');
    final counts = await a.db.dataRowCounts();
    expect(counts['Expenses'], 1, reason: 'apply was a no-op for the initiator');

    await a.db.close();
  });

  test('apply is idempotent — a second pass at the same epoch is a no-op',
      () async {
    final a = await newDevice();
    final b = await newDevice();
    await seedFinancial(b.db);

    await a.svc.recordReset(NukeScope.full);
    expect(await b.svc.applyRemoteResetIfNeeded(), isTrue);
    // Re-seed locally; a second apply at the SAME epoch must not wipe again.
    await seedFinancial(b.db);
    expect(await b.svc.applyRemoteResetIfNeeded(), isFalse);
    expect((await b.db.dataRowCounts())['Expenses'], 1);

    await a.db.close();
    await b.db.close();
  });

  test('full reset subsumes a prior expense reset (mixed ordering)', () async {
    final a = await newDevice();
    final b = await newDevice();
    await seedFinancial(b.db);
    await seedSavedWord(b.db);

    // Expense reset then full reset on A.
    await a.svc.recordReset(NukeScope.expense);
    await a.svc.recordReset(NukeScope.full);
    expect(backend.expenseGen, 1);
    expect(backend.fullGen, 1);

    // B applies once and ends fully wiped + adopts BOTH generations.
    expect(await b.svc.applyRemoteResetIfNeeded(), isTrue);
    expect((await b.db.dataRowCounts()).values.every((c) => c == 0), isTrue);
    // No second wipe — both gens were adopted.
    await seedSavedWord(b.db);
    expect(await b.svc.applyRemoteResetIfNeeded(), isFalse);

    await a.db.close();
    await b.db.close();
  });

  test('offline reset is queued and self-heals on the next online apply',
      () async {
    final a = await newDevice();
    final b = await newDevice();
    await seedFinancial(b.db);

    // Device A nukes while offline — the bump can't reach the server yet.
    backend.offline = true;
    expect(await a.svc.recordReset(NukeScope.full), isFalse);
    expect(a.prefs.getBool('reset_pending_bump_full'), isTrue);
    expect(backend.fullGen, 0, reason: 'server not yet bumped while offline');

    // A reconnects → the next apply pass flushes the queued bump.
    backend.offline = false;
    await a.svc.applyRemoteResetIfNeeded();
    expect(a.prefs.getBool('reset_pending_bump_full'), isNot(true));
    expect(backend.fullGen, 1, reason: 'queued bump reached the server');

    // …and now device B sees it and wipes.
    expect(await b.svc.applyRemoteResetIfNeeded(), isTrue);
    expect((await b.db.dataRowCounts()).values.every((c) => c == 0), isTrue);

    await a.db.close();
    await b.db.close();
  });

  test('device offline during apply does nothing and retries cleanly', () async {
    final a = await newDevice();
    final b = await newDevice();
    await seedFinancial(b.db);
    await a.svc.recordReset(NukeScope.full);

    backend.offline = true;
    expect(await b.svc.applyRemoteResetIfNeeded(), isFalse,
        reason: 'no epoch fetch while offline → no wipe');
    expect((await b.db.dataRowCounts())['Expenses'], 1);

    backend.offline = false;
    expect(await b.svc.applyRemoteResetIfNeeded(), isTrue);
    expect((await b.db.dataRowCounts())['Expenses'], 0);

    await a.db.close();
    await b.db.close();
  });

  test('concurrent apply calls coalesce into a single wipe', () async {
    final a = await newDevice();
    final b = await newDevice();
    await seedFinancial(b.db);
    await a.svc.recordReset(NukeScope.full);

    final results = await Future.wait([
      b.svc.applyRemoteResetIfNeeded(),
      b.svc.applyRemoteResetIfNeeded(),
      b.svc.applyRemoteResetIfNeeded(),
    ]);
    // Exactly one caller performed the wipe; the rest joined the in-flight pass.
    expect(results.where((r) => r).length, 1);
    expect((await b.db.dataRowCounts()).values.every((c) => c == 0), isTrue);

    await a.db.close();
    await b.db.close();
  });
}
