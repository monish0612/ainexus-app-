// Deep / adversarial tests for cross-device nuke propagation.
//
// A single in-memory [_SharedBackend] models the server-side reset epoch and is
// shared by multiple "devices", each of which is a fully independent stack
// (its own Drift DB + SharedPreferences + ApiClient). This lets us prove the
// END-TO-END guarantee — a nuke driven through the REAL AppNukeService /
// ExpenseNukeService on device A is detected and applied (local wipe) on device
// B — plus the hard edges: scale, malformed responses, restart durability,
// crash-safety, monotonicity, and "an offline queue must not re-push after a
// remote reset".

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/app_nuke_service.dart';
import 'package:ai_nexus/core/services/expense_nuke_service.dart';
import 'package:ai_nexus/core/services/nuke_report.dart';
import 'package:ai_nexus/core/services/reset_sync_service.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/data/repositories/news_repository.dart';
import 'package:ai_nexus/data/repositories/salary_repository.dart';
import 'package:ai_nexus/data/repositories/saved_words_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one shared server: a mutable global reset epoch + a kill switch.
class _SharedBackend {
  int fullGen = 0;
  int expenseGen = 0;
  bool offline = false;

  /// If set, the data-reset GET returns exactly this (adversarial payloads).
  Object? Function()? resetGetOverride;

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

/// A device-scoped ApiClient over the shared backend. Serves the data-reset
/// routes plus enough of the financial/saved endpoints (empty lists on GET, OK
/// on DELETE/POST) for the real repos to complete their clear+verify path.
class _DeviceApi extends ApiClient {
  _DeviceApi(this.backend);
  final _SharedBackend backend;

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
    if (path.contains('data-reset')) {
      final o = backend.resetGetOverride;
      return _ok<T>(path, o != null ? o() : backend.state);
    }
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

/// One self-contained device: independent DB + prefs + api + full service stack.
class _Device {
  _Device(this.database, this.prefs, this.api, this.reset, this.expenseRepo,
      this.salaryRepo, this.savedWordsRepo);

  final db.AppDatabase database;
  final SharedPreferences prefs;
  final _DeviceApi api;
  final ResetSyncService reset;
  final ExpenseRepository expenseRepo;
  final SalaryRepository salaryRepo;
  final SavedWordsRepository savedWordsRepo;

  AppNukeService appNuke() => AppNukeService(
        database,
        expenseRepo,
        salaryRepo,
        savedWordsRepo,
        NewsRepository(database, api),
        reset,
        clearSavedSearches: () async => true,
      );

  ExpenseNukeService expenseNuke() =>
      ExpenseNukeService(expenseRepo, salaryRepo, reset);

  Future<void> close() async {
    try {
      await database.close();
    } catch (_) {/* already closed by a fault-injection test */}
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SharedBackend backend;
  final devices = <_Device>[];

  Future<_Device> newDevice({Map<String, Object>? prefs}) async {
    SharedPreferences.setMockInitialValues(prefs ?? <String, Object>{});
    final p = await SharedPreferences.getInstance();
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    final api = _DeviceApi(backend);
    final d = _Device(
      database,
      p,
      api,
      ResetSyncService(database, api, p),
      ExpenseRepository(database, api, p),
      SalaryRepository(database, api, p),
      SavedWordsRepository(database, api, p),
    );
    devices.add(d);
    return d;
  }

  Future<void> seedExpense(db.AppDatabase d, String id) =>
      d.into(d.expenses).insert(db.ExpensesCompanion.insert(
            id: id,
            amount: 100,
            description: 'd',
            category: 'Food',
            bank: 'HDFC',
            cardType: 'CC',
            date: '2026-06-01T00:00:00.000Z',
          ));

  Future<void> seedBudget(db.AppDatabase d, String id) =>
      d.into(d.budgetEntries).insert(db.BudgetEntriesCompanion.insert(
          id: id, amount: 5000, setAt: '2026-06-01T00:00:00.000Z'));

  Future<void> seedSalary(db.AppDatabase d, String month) =>
      d.into(d.salaryEntries).insert(db.SalaryEntriesCompanion.insert(
          id: month, month: month, amount: 9, setAt: '2026-06-01T00:00:00.000Z'));

  Future<void> seedWord(db.AppDatabase d, String id) =>
      d.into(d.savedWords).insert(db.SavedWordsCompanion.insert(
            id: id,
            word: 'w',
            definition: 'x',
            pronunciation: '',
            partOfSpeech: 'n',
            savedAt: '2026-06-01T00:00:00.000Z',
          ));

  Future<void> seedAll(db.AppDatabase d) async {
    await seedExpense(d, 'e1');
    await seedBudget(d, 'b1');
    await seedSalary(d, '2026-06');
    await seedWord(d, 'w1');
  }

  setUp(() {
    backend = _SharedBackend();
    devices.clear();
  });

  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
  });

  // ── End-to-end through the REAL nuke services ────────────────────────────

  group('cross-device end-to-end', () {
    test('AppNukeService on A → full local wipe on B', () async {
      final a = await newDevice();
      final b = await newDevice();
      await seedAll(a.database);
      await seedAll(b.database);

      final report = await a.appNuke().nuke();
      expect(report.scope, NukeScope.full);
      expect(report.fullySynced, isTrue, reason: 'cloud + epoch all confirmed');
      expect(backend.fullGen, 1, reason: 'A bumped the global epoch');
      // A already wiped itself locally and adopted the epoch.
      expect((await a.database.dataRowCounts()).values.every((c) => c == 0), isTrue);
      expect(await a.reset.applyRemoteResetIfNeeded(), isFalse,
          reason: 'initiator never re-wipes');

      // B was untouched until it checks in…
      expect((await b.database.dataRowCounts())['Expenses'], 1);
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      expect((await b.database.dataRowCounts()).values.every((c) => c == 0), isTrue,
          reason: 'B reset to match the cloud');
    });

    test('ExpenseNukeService on A → financial-only wipe on B', () async {
      final a = await newDevice();
      final b = await newDevice();
      await seedAll(a.database);
      await seedAll(b.database);

      final report = await a.expenseNuke().nuke();
      expect(report.scope, NukeScope.expense);
      expect(backend.expenseGen, 1);
      expect(backend.fullGen, 0);

      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      final c = await b.database.dataRowCounts();
      expect(c['Expenses'], 0);
      expect(c['Budget history'], 0);
      expect(c['Salary'], 0);
      expect(c['Saved words'], 1, reason: 'non-financial data untouched');
    });

    test('three devices all converge after one nuke', () async {
      final a = await newDevice();
      final b = await newDevice();
      final c = await newDevice();
      await seedAll(b.database);
      await seedAll(c.database);

      await a.appNuke().nuke();
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      expect(await c.reset.applyRemoteResetIfNeeded(), isTrue);
      expect((await b.database.dataRowCounts()).values.every((x) => x == 0), isTrue);
      expect((await c.database.dataRowCounts()).values.every((x) => x == 0), isTrue);
    });
  });

  // ── Scale ─────────────────────────────────────────────────────────────────

  group('scale', () {
    test('remote full reset wipes 50k+ rows on B quickly', () async {
      final a = await newDevice();
      final b = await newDevice();

      await b.database.batch((batch) {
        for (var i = 0; i < 50000; i++) {
          batch.insert(
            b.database.expenses,
            db.ExpensesCompanion.insert(
              id: 'e$i',
              amount: 10,
              description: 'd',
              category: 'Food',
              bank: 'HDFC',
              cardType: 'CC',
              date: '2026-06-01T00:00:00.000Z',
            ),
          );
        }
      });
      for (var i = 0; i < 2000; i++) {
        await seedWord(b.database, 'w$i');
      }
      expect((await b.database.dataRowCounts())['Expenses'], 50000);

      await a.appNuke().nuke();
      final sw = Stopwatch()..start();
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      sw.stop();
      expect((await b.database.dataRowCounts()).values.every((c) => c == 0), isTrue);
      expect(sw.elapsedMilliseconds, lessThan(5000),
          reason: 'large wipe stays fast (was ${sw.elapsedMilliseconds}ms)');
    });
  });

  // ── Adversarial / malformed server responses ───────────────────────────────

  group('malformed epoch responses are survived', () {
    test('null body → no wipe, no throw', () async {
      final b = await newDevice();
      await seedAll(b.database);
      backend.resetGetOverride = () => null;
      expect(await b.reset.applyRemoteResetIfNeeded(), isFalse);
      expect((await b.database.dataRowCounts())['Expenses'], 1);
    });

    test('missing fields default to 0 → no wipe', () async {
      final b = await newDevice();
      await seedAll(b.database);
      backend.resetGetOverride = () => <String, dynamic>{'resetAt': 'now'};
      expect(await b.reset.applyRemoteResetIfNeeded(), isFalse);
      expect((await b.database.dataRowCounts())['Expenses'], 1);
    });

    test('string-typed generations are parsed and applied', () async {
      final b = await newDevice();
      await seedAll(b.database);
      backend.resetGetOverride =
          () => <String, dynamic>{'fullGen': '7', 'expenseGen': '0'};
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      expect((await b.database.dataRowCounts()).values.every((c) => c == 0), isTrue);
      expect(b.prefs.getInt('reset_full_gen_applied'), 7);
    });

    test('garbage generation values fall back to 0 (no crash)', () async {
      final b = await newDevice();
      await seedAll(b.database);
      backend.resetGetOverride =
          () => <String, dynamic>{'fullGen': 'abc', 'expenseGen': null};
      expect(await b.reset.applyRemoteResetIfNeeded(), isFalse);
      expect((await b.database.dataRowCounts())['Expenses'], 1);
    });

    test('non-map body (list) → no wipe, no throw', () async {
      final b = await newDevice();
      await seedAll(b.database);
      backend.resetGetOverride = () => const <dynamic>[];
      expect(await b.reset.applyRemoteResetIfNeeded(), isFalse);
      expect((await b.database.dataRowCounts())['Expenses'], 1);
    });
  });

  // ── Durability across an app restart ───────────────────────────────────────

  group('restart durability', () {
    test('adopted epoch persists — fresh service instance does not re-wipe',
        () async {
      final a = await newDevice();
      final b = await newDevice();
      await seedAll(b.database);
      await a.appNuke().nuke();

      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);

      // Simulate relaunch: brand-new ResetSyncService over the SAME prefs + DB.
      final reset2 = ResetSyncService(b.database, b.api, b.prefs);
      await seedExpense(b.database, 'late1'); // user adds data after the reset
      expect(await reset2.applyRemoteResetIfNeeded(), isFalse,
          reason: 'epoch already applied — must not wipe fresh local data');
      expect((await b.database.dataRowCounts())['Expenses'], 1);
    });
  });

  // ── Crash safety ────────────────────────────────────────────────────────────

  group('crash safety', () {
    test('local wipe failure does NOT advance the applied epoch', () async {
      final a = await newDevice();
      final b = await newDevice();
      await seedAll(b.database);
      await a.appNuke().nuke();

      await b.database.close(); // force wipeAllRows() to throw inside apply
      expect(await b.reset.applyRemoteResetIfNeeded(), isFalse,
          reason: 'failure is swallowed, not propagated');
      expect(b.prefs.getInt('reset_full_gen_applied') ?? 0, 0,
          reason: 'epoch not adopted, so the wipe retries next launch');
    });
  });

  // ── The offline-queue-must-not-re-push guarantee ────────────────────────────

  group('offline queue safety', () {
    test('queued salary upsert is purged by a remote expense reset', () async {
      final a = await newDevice();
      final b = await newDevice();
      await seedAll(b.database);
      // B has an unsynced salary write sitting in its durable queue.
      await b.database.enqueueSync(
        entityType: 'salary',
        entityId: '2026-06',
        action: 'upsert',
        payload: '{"month":"2026-06","amount":9}',
      );
      expect((await b.database.pendingSyncItems('salary')).length, 1);

      await a.expenseNuke().nuke();
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      expect((await b.database.pendingSyncItems('salary')), isEmpty,
          reason: 'stale queued write cannot re-populate the cloud post-reset');
    });

    test('full reset purges every table including the sync queue', () async {
      final a = await newDevice();
      final b = await newDevice();
      await seedAll(b.database);
      await b.database.enqueueSync(
        entityType: 'salary',
        entityId: 'x',
        action: 'upsert',
        payload: '{}',
      );
      await a.appNuke().nuke();
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      expect((await b.database.pendingSyncItems('salary')), isEmpty);
    });
  });

  // ── Monotonicity & ordering ─────────────────────────────────────────────────

  group('monotonicity', () {
    test('an older/stale epoch never downgrades an up-to-date device', () async {
      final b = await newDevice(prefs: <String, Object>{
        'reset_full_gen_applied': 9,
        'reset_expense_gen_applied': 4,
      });
      await seedAll(b.database);
      backend.fullGen = 3; // server BEHIND this device (impossible IRL, but safe)
      backend.expenseGen = 1;
      expect(await b.reset.applyRemoteResetIfNeeded(), isFalse);
      expect((await b.database.dataRowCounts())['Expenses'], 1);
    });

    test('repeated nukes keep incrementing and each propagates once', () async {
      final a = await newDevice();
      final b = await newDevice();

      await seedAll(b.database);
      await a.appNuke().nuke(); // gen 1
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);

      await seedAll(b.database); // B re-accumulates data
      await a.appNuke().nuke(); // gen 2
      expect(backend.fullGen, 2);
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue,
          reason: 'a second nuke propagates again');
      expect((await b.database.dataRowCounts()).values.every((c) => c == 0), isTrue);

      // No third nuke → no wipe.
      await seedAll(b.database);
      expect(await b.reset.applyRemoteResetIfNeeded(), isFalse);
    });

    test('full reset received while behind on expense adopts BOTH counters',
        () async {
      final b = await newDevice();
      await seedAll(b.database);
      backend.expenseGen = 5;
      backend.fullGen = 2;
      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      expect(b.prefs.getInt('reset_full_gen_applied'), 2);
      expect(b.prefs.getInt('reset_expense_gen_applied'), 5,
          reason: 'full subsumes expense so a later expense apply is a no-op');
      // Re-accumulate; no further wipe since both counters were adopted.
      await seedExpense(b.database, 'z1');
      expect(await b.reset.applyRemoteResetIfNeeded(), isFalse);
    });
  });

  // ── Offline self-heal (initiator) ────────────────────────────────────────────

  group('offline initiator self-heal', () {
    test('nuke while offline still propagates after reconnect', () async {
      final a = await newDevice();
      final b = await newDevice();
      await seedAll(b.database);

      backend.offline = true;
      final report = await a.appNuke().nuke();
      expect(report.fullySynced, isFalse, reason: 'cloud + epoch were offline');
      expect(a.prefs.getBool('reset_pending_bump_full'), isTrue);
      expect(backend.fullGen, 0);

      backend.offline = false;
      await a.reset.applyRemoteResetIfNeeded(); // flushes the queued bump
      expect(backend.fullGen, 1);
      expect(a.prefs.getBool('reset_pending_bump_full'), isNot(true));

      expect(await b.reset.applyRemoteResetIfNeeded(), isTrue);
      expect((await b.database.dataRowCounts()).values.every((c) => c == 0), isTrue);
    });
  });
}
