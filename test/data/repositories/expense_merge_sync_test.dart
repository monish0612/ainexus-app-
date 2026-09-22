import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/expense_merge.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StoreApi extends ApiClient {
  _StoreApi();

  final Map<String, Map<String, dynamic>> store = {};
  final List<String> deleted = <String>[];
  final List<Map<String, dynamic>> posted = <Map<String, dynamic>>[];
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> tombstoneLog = <Map<String, dynamic>>[];
  bool failWrites = false;
  final Set<String> delete404 = <String>{};

  Response<T> _resp<T>(String path, Object? data) => Response<T>(
        requestOptions: RequestOptions(path: path),
        data: data as T?,
        statusCode: 200,
      );

  Never _offline(String path) {
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.connectionError,
      error: 'offline',
    );
  }

  String _idFromPath(String path) => path.split('/').last.split('?').first;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    calls.add('GET $path');
    if (path.contains('/expenses/tombstones')) {
      return _resp<T>(path, tombstoneLog);
    }
    return _resp<T>(path, store.values.toList());
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    calls.add('POST $path');
    if (failWrites) _offline(path);
    if (path.contains('/api/v1/expenses') && data is Map) {
      final row = Map<String, dynamic>.from(data);
      final id = row['id']?.toString() ?? '';
      posted.add(row);
      if (id.isNotEmpty) store[id] = row;
      return _resp<T>(path, <String, dynamic>{
        'ok': true,
        'id': id,
        'updatedAt': '2026-09-19T12:00:00.000Z',
      });
    }
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
    final id = _idFromPath(path);
    if (delete404.contains(id)) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    if (failWrites) _offline(path);
    deleted.add(id);
    store.remove(id);
    tombstoneLog.add({
      'id': id,
      'deletedAt': '2026-09-19T12:00:00.000Z',
    });
    return _resp<T>(path, <String, dynamic>{'ok': true});
  }
}

Expense _e({
  required String id,
  required double amount,
  required String description,
  String category = 'Others',
  String bank = 'HDFC',
  String cardType = 'CC',
  required String date,
  String comments = '',
}) =>
    Expense(
      id: id,
      amount: amount,
      description: description,
      category: category,
      bank: bank,
      cardType: cardType,
      date: date,
      isManualCategory: false,
      comments: comments,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.ainexus.ai_nexus/expense_widget');
  late db.AppDatabase database;
  late _StoreApi api;
  late ExpenseRepository repo;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _StoreApi();
    repo = ExpenseRepository(database, api, prefs);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await database.close();
  });

  Future<db.Expense?> row(String id) =>
      (database.select(database.expenses)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  test('online merge tombstones sources then posts only the replacement',
      () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 60,
      description: 'paytmqr16ii90sd2y@paytm',
      date: '2026-09-19T11:18:00.000',
      comments: 'Auto Detected · 19 Sep 2026, 11:18 AM',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 37,
      description: '99440213809@okbizaxis',
      date: '2026-09-19T10:18:00.000',
      comments: 'Auto Detected · 19 Sep 2026, 10:18 AM',
    ));
    api.posted.clear();
    api.deleted.clear();
    api.calls.clear();

    final merged = composeMergedExpense(
      plan: planExpenseMerge([
        _e(
          id: 'a',
          amount: 60,
          description: 'paytmqr16ii90sd2y@paytm',
          date: '2026-09-19T11:18:00.000',
        ),
        _e(
          id: 'b',
          amount: 37,
          description: '99440213809@okbizaxis',
          date: '2026-09-19T10:18:00.000',
        ),
      ]),
      id: 'merged',
      description: 'Danalashmi Flower Shop',
      category: 'Personal',
    );

    final synced = await repo.mergeExpenses(
      sourceIds: const ['a', 'b'],
      merged: merged.copyWith(amount: 1),
    );
    expect(synced, isTrue);

    expect(await row('a'), isNull);
    expect(await row('b'), isNull);
    final kept = await row('merged');
    expect(kept, isNotNull);
    expect(kept!.amount, 97);
    expect(kept.description, 'Danalashmi Flower Shop');
    expect(kept.category, 'Personal');
    expect(kept.comments, isEmpty);
    expect(kept.isManualCategory, isTrue);

    expect(api.store.keys, ['merged']);
    expect(api.deleted, containsAll(['a', 'b']));
    expect(api.posted.last['id'], 'merged');
    expect(api.posted.last['amount'], 97);
    expect(api.posted.last['comments'], '');
    expect(api.posted.last['description'], 'Danalashmi Flower Shop');

    final deleteIdx = api.calls.indexWhere((c) => c.startsWith('DELETE'));
    final postIdx = api.calls.lastIndexWhere((c) => c.startsWith('POST'));
    expect(deleteIdx, lessThan(postIdx));

    expect(await database.pendingSyncItems('expense'), isEmpty);
  });

  test('offline merge keeps originals queued as deletes, never upserts them',
      () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 80,
      description: 'gpay-12198000736@okbizaxi',
      date: '2026-09-19T10:15:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 30,
      description: 'Paytm',
      date: '2026-09-19T10:13:00.000',
    ));
    api.failWrites = true;
    api.store.addAll({
      'a': {'id': 'a', 'amount': 80, 'description': 'gpay-12198000736@okbizaxi'},
      'b': {'id': 'b', 'amount': 30, 'description': 'Paytm'},
    });

    final merged = composeMergedExpense(
      plan: planExpenseMerge([
        _e(
          id: 'a',
          amount: 80,
          description: 'gpay',
          date: '2026-09-19T10:15:00.000',
        ),
        _e(
          id: 'b',
          amount: 30,
          description: 'Paytm',
          date: '2026-09-19T10:13:00.000',
        ),
      ]),
      id: 'flower',
      description: 'Flower shop',
      category: 'Personal',
    );

    final synced = await repo.mergeExpenses(
      sourceIds: const ['a', 'b'],
      merged: merged,
    );
    expect(synced, isFalse);
    expect(await row('a'), isNull);
    expect(await row('b'), isNull);
    expect(await row('flower'), isNotNull);

    // Pull must not resurrect doomed UPI rows while deletes are queued.
    api.failWrites = false;
    await repo.syncFromServer();
    expect(await row('a'), isNull);
    expect(await row('b'), isNull);
    expect(await row('flower'), isNotNull);

    final queued = await database.pendingSyncItems('expense');
    expect(queued.map((q) => q.action).toList(), ['delete', 'delete', 'upsert']);
    expect(queued.map((q) => q.entityId).toList(), ['a', 'b', 'flower']);

    api.deleted.clear();
    api.posted.clear();
    final drained = await repo.drainSyncQueue();
    expect(drained, 3);
    expect(api.deleted, containsAll(['a', 'b']));
    expect(api.store.keys, ['flower']);
    expect(api.posted.single['id'], 'flower');
    expect(api.posted.single['description'], 'Flower shop');
    expect(api.store.containsKey('a'), isFalse);
    expect(await database.pendingSyncItems('expense'), isEmpty);
  });

  test('missing source aborts and leaves the other row untouched', () async {
    await repo.addExpense(_e(
      id: 'alive',
      amount: 50,
      description: 'keep me',
      date: '2026-09-19T10:11:00.000',
    ));
    expect(
      () => repo.mergeExpenses(
        sourceIds: const ['alive', 'ghost'],
        merged: _e(
          id: 'merged',
          amount: 50,
          description: 'nope',
          date: '2026-09-19T10:11:00.000',
        ),
      ),
      throwsA(isA<ExpenseMergeException>()),
    );
    expect(await row('alive'), isNotNull);
    expect(await row('merged'), isNull);
  });

  test('one id cannot merge', () async {
    await repo.addExpense(_e(
      id: 'solo',
      amount: 10,
      description: 'alone',
      date: '2026-09-19T10:00:00.000',
    ));
    expect(
      () => repo.mergeExpenses(
        sourceIds: const ['solo'],
        merged: _e(
          id: 'm',
          amount: 10,
          description: 'x',
          date: '2026-09-19T10:00:00.000',
        ),
      ),
      throwsA(isA<ExpenseMergeException>()),
    );
    expect(await row('solo'), isNotNull);
  });

  test('drain converts a stale source upsert into a cloud delete', () async {
    await repo.addExpense(_e(
      id: 'stale',
      amount: 10,
      description: 'paytmqr6p24ts@ptys',
      date: '2026-09-19T10:10:00.000',
    ));
    await database.enqueueSync(
      entityType: 'expense',
      entityId: 'stale',
      action: 'upsert',
      payload:
          '{"id":"stale","amount":10,"description":"paytmqr6p24ts@ptys","category":"Others","bank":"HDFC","cardType":"CC","date":"2026-09-19T10:10:00.000","isManualCategory":false,"comments":"vpa"}',
    );
    await (database.delete(database.expenses)
          ..where((t) => t.id.equals('stale')))
        .go();

    api.store['stale'] = {
      'id': 'stale',
      'description': 'paytmqr6p24ts@ptys',
    };
    api.posted.clear();
    api.deleted.clear();

    await repo.drainSyncQueue();
    expect(api.posted, isEmpty);
    expect(api.deleted, ['stale']);
    expect(api.store.containsKey('stale'), isFalse);
  });

  test('six UPI rows merge to one local+cloud row; leftover spend stays',
      () async {
    final rows = <({String id, double amount, String desc})>[
      (id: 'u1', amount: 60, desc: 'paytmqr16ii90sd2y@paytm'),
      (id: 'u2', amount: 37, desc: '99440213809@okbizaxis'),
      (id: 'u3', amount: 80, desc: 'gpay-12198000736@okbizaxi'),
      (id: 'u4', amount: 30, desc: 'Paytm'),
      (id: 'u5', amount: 50, desc: 'paytmqr5wi4xc@ptys'),
      (id: 'u6', amount: 10, desc: 'paytmqr6p24ts@ptys'),
    ];
    for (final r in rows) {
      await repo.addExpense(_e(
        id: r.id,
        amount: r.amount,
        description: r.desc,
        date: '2026-09-19T10:00:00.000',
        comments: 'Auto Detected · 19 Sep 2026, 10:10 AM',
      ));
    }
    await repo.addExpense(_e(
      id: 'keep',
      amount: 20,
      description: 'Danalashmi Flower Shop',
      category: 'Personal',
      date: '2026-09-19T09:00:00.000',
    ));
    api.posted.clear();
    api.deleted.clear();

    final sources = [
      for (final r in rows)
        _e(
          id: r.id,
          amount: r.amount,
          description: r.desc,
          date: '2026-09-19T10:00:00.000',
        ),
    ];
    final synced = await repo.mergeExpenses(
      sourceIds: rows.map((r) => r.id).toList(),
      merged: composeMergedExpense(
        plan: planExpenseMerge(sources),
        id: 'flower',
        description: 'Danalashmi Flower Shop',
        category: 'Personal',
      ),
    );
    expect(synced, isTrue);
    for (final r in rows) {
      expect(await row(r.id), isNull);
    }
    expect(await row('keep'), isNotNull);
    expect((await row('flower'))!.amount, 267);
    expect((await row('flower'))!.comments, isEmpty);
    expect(api.store.keys.toSet(), {'keep', 'flower'});
    expect(api.deleted.toSet(), {'u1', 'u2', 'u3', 'u4', 'u5', 'u6'});
    expect(api.posted.last['amount'], 267);
    expect(api.posted.last['comments'], '');
    expect(api.posted.last['description'], isNot(contains('@')));
  });

  test('duplicate source ids still merge two unique rows', () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 10,
      description: 'a',
      date: '2026-09-19T10:00:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 15,
      description: 'b',
      date: '2026-09-19T10:01:00.000',
    ));
    final synced = await repo.mergeExpenses(
      sourceIds: const ['a', 'a', 'b', 'b'],
      merged: composeMergedExpense(
        plan: planExpenseMerge([
          _e(id: 'a', amount: 10, description: 'a', date: '2026-09-19T10:00:00.000'),
          _e(id: 'b', amount: 15, description: 'b', date: '2026-09-19T10:01:00.000'),
        ]),
        id: 'm',
        description: 'combined',
        category: 'Others',
      ),
    );
    expect(synced, isTrue);
    expect(await row('a'), isNull);
    expect(await row('b'), isNull);
    expect((await row('m'))!.amount, 25);
  });

  test('existing merged id aborts and leaves sources in place', () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 10,
      description: 'a',
      date: '2026-09-19T10:00:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 10,
      description: 'b',
      date: '2026-09-19T10:01:00.000',
    ));
    await repo.addExpense(_e(
      id: 'taken',
      amount: 1,
      description: 'already here',
      date: '2026-09-19T09:00:00.000',
    ));
    expect(
      () => repo.mergeExpenses(
        sourceIds: const ['a', 'b'],
        merged: _e(
          id: 'taken',
          amount: 20,
          description: 'nope',
          date: '2026-09-19T10:01:00.000',
        ),
      ),
      throwsA(isA<ExpenseMergeException>()),
    );
    expect(await row('a'), isNotNull);
    expect(await row('b'), isNotNull);
    expect((await row('taken'))!.description, 'already here');
  });

  test('blank description aborts before deleting anything', () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 10,
      description: 'a',
      date: '2026-09-19T10:00:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 10,
      description: 'b',
      date: '2026-09-19T10:01:00.000',
    ));
    expect(
      () => repo.mergeExpenses(
        sourceIds: const ['a', 'b'],
        merged: _e(
          id: 'm',
          amount: 20,
          description: '   ',
          date: '2026-09-19T10:01:00.000',
        ),
      ),
      throwsA(isA<ExpenseMergeException>()),
    );
    expect(await row('a'), isNotNull);
    expect(await row('b'), isNotNull);
    expect(await row('m'), isNull);
  });

  test('404 on source DELETE is already-gone, merge still posts replacement',
      () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 12,
      description: 'a',
      date: '2026-09-19T10:00:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 8,
      description: 'b',
      date: '2026-09-19T10:01:00.000',
    ));
    api.delete404.add('a');
    api.posted.clear();
    final synced = await repo.mergeExpenses(
      sourceIds: const ['a', 'b'],
      merged: composeMergedExpense(
        plan: planExpenseMerge([
          _e(id: 'a', amount: 12, description: 'a', date: '2026-09-19T10:00:00.000'),
          _e(id: 'b', amount: 8, description: 'b', date: '2026-09-19T10:01:00.000'),
        ]),
        id: 'm',
        description: 'done',
        category: 'Others',
      ),
    );
    expect(synced, isTrue);
    expect(await row('a'), isNull);
    expect(await row('b'), isNull);
    expect(await row('m'), isNotNull);
    expect(api.posted.last['id'], 'm');
    expect(await database.pendingSyncItems('expense'), isEmpty);
  });

  test('pending upsert of a source is replaced by a tombstone during merge',
      () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 10,
      description: 'paytmqr6p24ts@ptys',
      date: '2026-09-19T10:00:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 10,
      description: 'Paytm',
      date: '2026-09-19T10:01:00.000',
    ));
    await database.enqueueSync(
      entityType: 'expense',
      entityId: 'a',
      action: 'upsert',
      payload:
          '{"id":"a","amount":10,"description":"paytmqr6p24ts@ptys","category":"Others","bank":"HDFC","cardType":"CC","date":"2026-09-19T10:00:00.000","isManualCategory":false,"comments":"vpa"}',
    );
    api.failWrites = true;
    await repo.mergeExpenses(
      sourceIds: const ['a', 'b'],
      merged: composeMergedExpense(
        plan: planExpenseMerge([
          _e(id: 'a', amount: 10, description: 'a', date: '2026-09-19T10:00:00.000'),
          _e(id: 'b', amount: 10, description: 'b', date: '2026-09-19T10:01:00.000'),
        ]),
        id: 'm',
        description: 'shop',
        category: 'Others',
      ),
    );
    final queued = await database.pendingSyncItems('expense');
    expect(queued.where((q) => q.entityId == 'a').map((q) => q.action), ['delete']);
    expect(queued.where((q) => q.action == 'upsert').map((q) => q.entityId), ['m']);
  });

  test('add, edit, and delete still work after a merge', () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 10,
      description: 'a',
      date: '2026-09-19T10:00:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 10,
      description: 'b',
      date: '2026-09-19T10:01:00.000',
    ));
    await repo.mergeExpenses(
      sourceIds: const ['a', 'b'],
      merged: composeMergedExpense(
        plan: planExpenseMerge([
          _e(id: 'a', amount: 10, description: 'a', date: '2026-09-19T10:00:00.000'),
          _e(id: 'b', amount: 10, description: 'b', date: '2026-09-19T10:01:00.000'),
        ]),
        id: 'm',
        description: 'shop',
        category: 'Others',
      ),
    );
    await repo.addExpense(_e(
      id: 'c',
      amount: 5,
      description: 'coffee',
      date: '2026-09-19T12:00:00.000',
    ));
    await repo.updateExpense(_e(
      id: 'c',
      amount: 6,
      description: 'coffee',
      category: 'Food',
      date: '2026-09-19T12:00:00.000',
    ));
    expect((await row('c'))!.amount, 6);
    expect((await row('c'))!.category, 'Food');
    await repo.deleteExpense('c');
    expect(await row('c'), isNull);
    expect(await row('m'), isNotNull);
    final live = await repo.watchExpenses().first;
    expect(live.map((e) => e.id), ['m']);
  });

  test('stale GET of a merged source is wiped by the tombstone log', () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 10,
      description: 'paytmqr6p24ts@ptys',
      date: '2026-09-19T10:00:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 10,
      description: 'Paytm',
      date: '2026-09-19T10:01:00.000',
    ));
    await repo.mergeExpenses(
      sourceIds: const ['a', 'b'],
      merged: composeMergedExpense(
        plan: planExpenseMerge([
          _e(id: 'a', amount: 10, description: 'a', date: '2026-09-19T10:00:00.000'),
          _e(id: 'b', amount: 10, description: 'b', date: '2026-09-19T10:01:00.000'),
        ]),
        id: 'm',
        description: 'shop',
        category: 'Others',
      ),
    );
    expect(await row('a'), isNull);

    api.store['a'] = {
      'id': 'a',
      'amount': 10,
      'description': 'paytmqr6p24ts@ptys',
      'category': 'Others',
      'bank': 'HDFC',
      'cardType': 'CC',
      'date': '2026-09-19T10:00:00.000',
      'updatedAt': '2026-09-19T10:00:00.000Z',
    };

    await repo.syncFromServer();
    expect(await row('a'), isNull);
    expect(await row('b'), isNull);
    expect(await row('m'), isNotNull);
    expect((await row('m'))!.description, 'shop');
  });

  test('merge refuses a replacement that reuses a source id', () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 10,
      description: 'a',
      date: '2026-09-19T10:00:00.000',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 10,
      description: 'b',
      date: '2026-09-19T10:01:00.000',
    ));
    expect(
      () => repo.mergeExpenses(
        sourceIds: const ['a', 'b'],
        merged: _e(
          id: 'a',
          amount: 20,
          description: 'nope',
          date: '2026-09-19T10:01:00.000',
        ),
      ),
      throwsA(isA<ExpenseMergeException>()),
    );
    expect(await row('a'), isNotNull);
    expect(await row('b'), isNotNull);
  });

  test('user comments and bank on the merged row persist', () async {
    await repo.addExpense(_e(
      id: 'a',
      amount: 10,
      description: 'paytmqr6p24ts@ptys',
      date: '2026-09-19T10:00:00.000',
      comments: 'Auto Detected · 19 Sep 2026, 10:10 AM',
    ));
    await repo.addExpense(_e(
      id: 'b',
      amount: 10,
      description: 'Paytm',
      date: '2026-09-19T10:01:00.000',
    ));
    await repo.mergeExpenses(
      sourceIds: const ['a', 'b'],
      merged: composeMergedExpense(
        plan: planExpenseMerge([
          _e(
            id: 'a',
            amount: 10,
            description: 'a',
            date: '2026-09-19T10:00:00.000',
            comments: 'Auto Detected · 19 Sep 2026, 10:10 AM',
          ),
          _e(id: 'b', amount: 10, description: 'b', date: '2026-09-19T10:01:00.000'),
        ]),
        id: 'm',
        description: 'shop',
        category: 'Personal',
        bank: 'AXIS',
        cardType: 'DB',
        comments: 'split with Riya',
      ),
    );
    final kept = await row('m');
    expect(kept, isNotNull);
    expect(kept!.comments, 'split with Riya');
    expect(kept.bank, 'AXIS');
    expect(kept.cardType, 'DB');
    expect(kept.category, 'Personal');
    expect(api.posted.last['comments'], 'split with Riya');
    expect(api.posted.last['bank'], 'AXIS');
  });
}
