// Exhaustive tests for the cross-device expense sync upgrade:
//   • Last-write-wins MERGE on pull (insert new, apply newer remote edits,
//     keep newer local edits, skip identical content, ignore malformed rows).
//   • Server-clock adoption on push (clock-skew-proof LWW).
//   • Tombstone delete sync (apply remote deletes, watermark cursor, guards for
//     newer-local-edit / empty payloads / 404 / empty list).
//
// Runs the REAL [ExpenseRepository] against a REAL in-memory Drift DB with a
// path-routing fake [ApiClient]. Nothing is mocked at the repository boundary.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';

const _kWatermarkKey = 'expenseRepo.lastTombstonePullAt';

/// Path-routing fake. GET on `…/expenses/tombstones` returns [tombstones];
/// any other GET returns [expenses]. POST returns a body built by
/// [postUpdatedAt] (so tests can simulate the server-assigned timestamp).
class _FakeApi extends ApiClient {
  _FakeApi();

  List<String> calls = <String>[];
  Object? expenses = <dynamic>[];
  Object? tombstones = <dynamic>[];

  /// When set, POST /expenses echoes `{ ok, id, updatedAt }` with this value.
  String? Function(String id)? postUpdatedAt;

  bool tombstones404 = false;
  bool expensesGetThrows = false;

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  DioException _dioErr(String path, int status) => DioException(
        requestOptions: RequestOptions(path: path),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: status,
        ),
        type: DioExceptionType.badResponse,
      );

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters}) async {
    calls.add('GET $path');
    if (path.contains('/expenses/tombstones')) {
      if (tombstones404) throw _dioErr(path, 404);
      return _resp<T>(path, tombstones);
    }
    if (expensesGetThrows) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }
    return _resp<T>(path, expenses);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    calls.add('POST $path');
    final id = (data is Map) ? (data['id']?.toString() ?? '') : '';
    final body = <String, dynamic>{'ok': true, 'id': id};
    final ua = postUpdatedAt?.call(id);
    if (ua != null) body['updatedAt'] = ua;
    return _resp<T>(path, body);
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

  int get tombstoneGets =>
      calls.where((c) => c.contains('/expenses/tombstones')).length;

  String? lastTombstoneGet() {
    for (final c in calls.reversed) {
      if (c.startsWith('GET ') && c.contains('/expenses/tombstones')) return c;
    }
    return null;
  }
}

Map<String, dynamic> _serverRow(
  String id, {
  required double amount,
  String description = 'desc',
  String category = 'Food',
  String bank = 'HDFC',
  String cardType = 'CC',
  String date = '2026-06-20T08:00:00.000',
  bool isManualCategory = false,
  String comments = '',
  String? updatedAt,
}) =>
    <String, dynamic>{
      'id': id,
      'amount': amount,
      'description': description,
      'category': category,
      'bank': bank,
      'cardType': cardType,
      'date': date,
      'isManualCategory': isManualCategory,
      'comments': comments,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _FakeApi api;
  late ExpenseRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    repo = ExpenseRepository(database, api, prefs);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedLocal(
    String id, {
    required double amount,
    String description = 'desc',
    String category = 'Food',
    String bank = 'HDFC',
    String cardType = 'CC',
    String date = '2026-06-20T08:00:00.000',
    bool manual = false,
    String comments = '',
    String? updatedAt,
  }) async {
    await database.into(database.expenses).insert(
          db.ExpensesCompanion.insert(
            id: id,
            amount: amount,
            description: description,
            category: category,
            bank: bank,
            cardType: cardType,
            date: date,
            isManualCategory: Value(manual),
            comments: Value(comments),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<db.Expense?> row(String id) =>
      (database.select(database.expenses)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  // ─────────────────────────────────────────────────────────────────────────
  group('syncFromServer — last-write-wins merge', () {
    test('inserts a server row not present locally', () async {
      api.expenses = [
        _serverRow('s1',
            amount: 99, comments: 'new', updatedAt: '2026-06-20T10:00:00.000Z'),
      ];
      final changed = await repo.syncFromServer();
      expect(changed, 1);
      final r = await row('s1');
      expect(r, isNotNull);
      expect(r!.comments, 'new');
      expect(r.updatedAt, '2026-06-20T10:00:00.000Z');
    });

    test('skips identical content even when the server timestamp is newer',
        () async {
      await seedLocal('e1',
          amount: 50, comments: 'same', updatedAt: '2026-06-20T10:00:00.000Z');
      api.expenses = [
        _serverRow('e1',
            amount: 50,
            comments: 'same',
            updatedAt: '2026-06-25T10:00:00.000Z'), // newer ts, same content
      ];
      final changed = await repo.syncFromServer();
      expect(changed, 0); // no write
      final r = await row('e1');
      // local updatedAt must NOT be clobbered (proves the row was untouched).
      expect(r!.updatedAt, '2026-06-20T10:00:00.000Z');
    });

    test('applies a remote EDIT when the server copy is newer (web wins)',
        () async {
      await seedLocal('e1',
          amount: 50,
          category: 'Food',
          comments: 'old',
          updatedAt: '2026-06-20T10:00:00.000Z');
      api.expenses = [
        _serverRow('e1',
            amount: 250,
            category: 'Shopping',
            comments: 'edited on web',
            updatedAt: '2026-06-21T10:00:00.000Z'),
      ];
      final changed = await repo.syncFromServer();
      expect(changed, 1);
      final r = await row('e1');
      expect(r!.amount, 250);
      expect(r.category, 'Shopping');
      expect(r.comments, 'edited on web');
      expect(r.updatedAt, '2026-06-21T10:00:00.000Z');
    });

    test('keeps the LOCAL edit when it is newer than the server copy',
        () async {
      await seedLocal('e1',
          amount: 500,
          comments: 'fresh local edit',
          updatedAt: '2026-06-25T10:00:00.000Z');
      api.expenses = [
        _serverRow('e1',
            amount: 100,
            comments: 'stale server',
            updatedAt: '2026-06-20T10:00:00.000Z'),
      ];
      final changed = await repo.syncFromServer();
      expect(changed, 0);
      final r = await row('e1');
      expect(r!.amount, 500);
      expect(r.comments, 'fresh local edit');
    });

    test('never overwrites when the server omits updatedAt (older backend)',
        () async {
      await seedLocal('e1',
          amount: 500, comments: 'local', updatedAt: '2026-06-20T10:00:00.000Z');
      api.expenses = [
        _serverRow('e1', amount: 100, comments: 'server no-ts'), // no updatedAt
      ];
      final changed = await repo.syncFromServer();
      expect(changed, 0);
      final r = await row('e1');
      expect(r!.amount, 500);
    });

    test('server wins for a legacy local row with NULL updatedAt', () async {
      await seedLocal('e1',
          amount: 100, comments: 'legacy', updatedAt: null); // pre-migration
      api.expenses = [
        _serverRow('e1',
            amount: 175,
            comments: 'server refresh',
            updatedAt: '2026-06-20T10:00:00.000Z'),
      ];
      final changed = await repo.syncFromServer();
      expect(changed, 1);
      final r = await row('e1');
      expect(r!.amount, 175);
      expect(r.comments, 'server refresh');
    });

    test('ignores malformed server rows (non-map / empty id)', () async {
      api.expenses = [
        'not-a-map',
        <String, dynamic>{'amount': 10}, // no id
        _serverRow('ok', amount: 5, updatedAt: '2026-06-20T10:00:00.000Z'),
      ];
      final changed = await repo.syncFromServer();
      expect(changed, 1);
      expect(await row('ok'), isNotNull);
    });

    test('parses snake_case card_type / is_manual_category fallbacks',
        () async {
      api.expenses = [
        <String, dynamic>{
          'id': 's1',
          'amount': 12,
          'description': 'd',
          'category': 'Food',
          'bank': 'HDFC',
          'card_type': 'DC',
          'date': '2026-06-20T08:00:00.000',
          'is_manual_category': true,
          'comments': '',
          'updated_at': '2026-06-20T10:00:00.000Z',
        },
      ];
      final changed = await repo.syncFromServer();
      expect(changed, 1);
      final r = await row('s1');
      expect(r!.cardType, 'DC');
      expect(r.isManualCategory, isTrue);
      expect(r.updatedAt, '2026-06-20T10:00:00.000Z');
    });

    test('a non-list index response does not crash and still pulls tombstones',
        () async {
      api.expenses = <String, dynamic>{'unexpected': 'shape'};
      final changed = await repo.syncFromServer();
      expect(changed, 0);
      expect(api.tombstoneGets, 1); // tombstone pull still attempted
    });

    test('offline index GET is swallowed; tombstones still attempted',
        () async {
      api.expensesGetThrows = true;
      final changed = await repo.syncFromServer();
      expect(changed, 0);
      expect(api.tombstoneGets, 1);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('syncExpenseTombstones — cross-device delete sync', () {
    test('deletes a local row that was tombstoned remotely', () async {
      await seedLocal('e1',
          amount: 10, updatedAt: '2026-06-20T10:00:00.000Z');
      api.tombstones = [
        {'id': 'e1', 'deletedAt': '2026-06-21T10:00:00.000Z'},
      ];
      final applied = await repo.syncExpenseTombstones();
      expect(applied, 1);
      expect(await row('e1'), isNull);
      expect(prefs.getString(_kWatermarkKey), '2026-06-21T10:00:00.000Z');
    });

    test('is idempotent for an id not present locally (no-op, advances cursor)',
        () async {
      api.tombstones = [
        {'id': 'ghost', 'deletedAt': '2026-06-21T10:00:00.000Z'},
      ];
      final applied = await repo.syncExpenseTombstones();
      expect(applied, 0);
      expect(prefs.getString(_kWatermarkKey), '2026-06-21T10:00:00.000Z');
    });

    test('ignores malformed tombstones (empty id or empty deletedAt)',
        () async {
      await seedLocal('keep',
          amount: 10, updatedAt: '2026-06-20T10:00:00.000Z');
      api.tombstones = [
        {'id': '', 'deletedAt': '2026-06-21T10:00:00.000Z'},
        {'id': 'keep', 'deletedAt': ''}, // no deletedAt → must NOT delete
        'garbage',
      ];
      final applied = await repo.syncExpenseTombstones();
      expect(applied, 0);
      expect(await row('keep'), isNotNull);
      // No valid tombstone seen → watermark stays unset.
      expect(prefs.getString(_kWatermarkKey), isNull);
    });

    test('keeps a local edit that is strictly newer than the remote delete',
        () async {
      await seedLocal('e1',
          amount: 999,
          comments: 'edited after the delete',
          updatedAt: '2026-06-25T10:00:00.000Z');
      api.tombstones = [
        {'id': 'e1', 'deletedAt': '2026-06-20T10:00:00.000Z'}, // older delete
      ];
      final applied = await repo.syncExpenseTombstones();
      expect(applied, 0);
      expect(await row('e1'), isNotNull); // local edit preserved
      // Cursor still advances so we don't re-process this tombstone forever.
      expect(prefs.getString(_kWatermarkKey), '2026-06-20T10:00:00.000Z');
    });

    test('advances watermark to the MAX deletedAt across a batch', () async {
      await seedLocal('a', amount: 1, updatedAt: '2026-06-01T00:00:00.000Z');
      await seedLocal('b', amount: 2, updatedAt: '2026-06-01T00:00:00.000Z');
      api.tombstones = [
        {'id': 'a', 'deletedAt': '2026-06-10T10:00:00.000Z'},
        {'id': 'b', 'deletedAt': '2026-06-12T10:00:00.000Z'},
      ];
      final applied = await repo.syncExpenseTombstones();
      expect(applied, 2);
      expect(prefs.getString(_kWatermarkKey), '2026-06-12T10:00:00.000Z');
    });

    test('sends ?since=<watermark> on the next pull', () async {
      await prefs.setString(_kWatermarkKey, '2026-06-12T10:00:00.000Z');
      api.tombstones = <dynamic>[];
      await repo.syncExpenseTombstones();
      final last = api.lastTombstoneGet();
      expect(last, isNotNull);
      expect(last!.contains('since='), isTrue);
      expect(
          last.contains(Uri.encodeQueryComponent('2026-06-12T10:00:00.000Z')),
          isTrue);
    });

    test('first pull (no watermark) omits the since param', () async {
      api.tombstones = <dynamic>[];
      await repo.syncExpenseTombstones();
      expect(api.lastTombstoneGet()!.contains('since='), isFalse);
    });

    test('404 (endpoint not deployed) is handled gracefully', () async {
      api.tombstones404 = true;
      final applied = await repo.syncExpenseTombstones();
      expect(applied, 0);
    });

    test('empty / non-list tombstone responses are no-ops', () async {
      api.tombstones = <dynamic>[];
      expect(await repo.syncExpenseTombstones(), 0);
      api.tombstones = <String, dynamic>{'oops': true};
      expect(await repo.syncExpenseTombstones(), 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('write paths stamp + adopt updatedAt', () {
    test('addExpense stamps a local updatedAt', () async {
      api.postUpdatedAt = null; // server returns no ts
      await repo.addExpense(_e('a1', 10));
      final r = await row('a1');
      expect(r!.updatedAt, isNotNull);
      expect(DateTime.tryParse(r.updatedAt!), isNotNull);
    });

    test('addExpense ADOPTS the server-assigned updatedAt (clock-skew proof)',
        () async {
      api.postUpdatedAt = (_) => '2026-06-27T04:00:00.000Z';
      await repo.addExpense(_e('a1', 10));
      final r = await row('a1');
      expect(r!.updatedAt, '2026-06-27T04:00:00.000Z');
    });

    test('updateExpense adopts the server-assigned updatedAt', () async {
      api.postUpdatedAt = (_) => '2026-06-27T05:00:00.000Z';
      await repo.addExpense(_e('a1', 10));
      api.postUpdatedAt = (_) => '2026-06-27T06:00:00.000Z';
      await repo.updateExpense(_e('a1', 20));
      final r = await row('a1');
      expect(r!.amount, 20);
      expect(r.updatedAt, '2026-06-27T06:00:00.000Z');
    });

    test('add succeeds locally even if server omits updatedAt', () async {
      api.postUpdatedAt = (_) => null;
      final ok = await repo.addExpense(_e('a1', 10));
      expect(ok, isTrue);
      expect((await row('a1'))!.updatedAt, isNotNull); // local stamp retained
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('end-to-end cross-device scenario', () {
    test('add → remote edit → remote delete all converge', () async {
      // Device A adds (server assigns t1).
      api.postUpdatedAt = (_) => '2026-06-20T10:00:00.000Z';
      await repo.addExpense(_e('x', 100, comments: 'v1'));
      expect((await row('x'))!.comments, 'v1');

      // Web edits the row later (t2 > t1) → pull applies it.
      api.expenses = [
        _serverRow('x',
            amount: 100,
            comments: 'v2 from web',
            updatedAt: '2026-06-21T10:00:00.000Z'),
      ];
      await repo.syncFromServer();
      expect((await row('x'))!.comments, 'v2 from web');

      // Web deletes the row (t3) → tombstone pull removes it locally.
      api.expenses = <dynamic>[]; // gone from index
      api.tombstones = [
        {'id': 'x', 'deletedAt': '2026-06-22T10:00:00.000Z'},
      ];
      await repo.syncFromServer();
      expect(await row('x'), isNull);
    });
  });
}

Expense _e(String id, double amount, {String comments = ''}) => Expense(
      id: id,
      amount: amount,
      description: 'desc',
      category: 'Food',
      bank: 'HDFC',
      cardType: 'CC',
      date: '2026-06-20T08:00:00.000',
      isManualCategory: false,
      comments: comments,
    );
