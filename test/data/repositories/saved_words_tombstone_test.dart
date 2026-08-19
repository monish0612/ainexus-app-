// Cross-device delete sync for dictionary "saved words":
//   • apply remote deletes via the tombstone log
//   • watermark cursor (?since=) advances to the MAX deletedAt
//   • guards: re-saved-after-delete kept, empty payloads ignored, 404/empty
//     responses are no-ops.
//
// Runs the REAL [SavedWordsRepository] against a REAL in-memory Drift DB with a
// path-routing fake [ApiClient]. Nothing is mocked at the repository boundary.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/saved_words_repository.dart';

const _kWatermarkKey = 'saved_words_tombstone_watermark';

/// Path-routing fake. GET on `…/saved-words/tombstones` returns [tombstones].
class _FakeApi extends ApiClient {
  _FakeApi();

  List<String> calls = <String>[];
  Object? tombstones = <dynamic>[];
  bool tombstones404 = false;

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
      {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    calls.add('GET $path');
    if (path.contains('/saved-words/tombstones')) {
      if (tombstones404) throw _dioErr(path, 404);
      return _resp<T>(path, tombstones);
    }
    return _resp<T>(path, <dynamic>[]);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    calls.add('POST $path');
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

  String? lastTombstoneGet() {
    for (final c in calls.reversed) {
      if (c.startsWith('GET ') && c.contains('/saved-words/tombstones')) {
        return c;
      }
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  late _FakeApi api;
  late SavedWordsRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    repo = SavedWordsRepository(database, api, prefs);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedWord(String id, {required String savedAt}) async {
    await database.into(database.savedWords).insert(
          db.SavedWordsCompanion.insert(
            id: id,
            word: 'word-$id',
            definition: 'def',
            pronunciation: 'pron',
            partOfSpeech: 'noun',
            savedAt: savedAt,
            responseJson: const Value('{}'),
          ),
        );
  }

  Future<db.SavedWord?> row(String id) =>
      (database.select(database.savedWords)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  group('syncTombstones — cross-device delete sync', () {
    test('deletes a local row that was tombstoned remotely', () async {
      await seedWord('w1', savedAt: '2026-06-20T10:00:00.000Z');
      api.tombstones = [
        {'id': 'w1', 'deletedAt': '2026-06-21T10:00:00.000Z'},
      ];
      final applied = await repo.syncTombstones();
      expect(applied, 1);
      expect(await row('w1'), isNull);
      expect(prefs.getString(_kWatermarkKey), '2026-06-21T10:00:00.000Z');
    });

    test('idempotent for an id not present locally (no-op, advances cursor)',
        () async {
      api.tombstones = [
        {'id': 'ghost', 'deletedAt': '2026-06-21T10:00:00.000Z'},
      ];
      final applied = await repo.syncTombstones();
      expect(applied, 0);
      expect(prefs.getString(_kWatermarkKey), '2026-06-21T10:00:00.000Z');
    });

    test('accepts snake_case deleted_at fallback', () async {
      await seedWord('w1', savedAt: '2026-06-20T10:00:00.000Z');
      api.tombstones = [
        {'id': 'w1', 'deleted_at': '2026-06-21T10:00:00.000Z'},
      ];
      final applied = await repo.syncTombstones();
      expect(applied, 1);
      expect(await row('w1'), isNull);
    });

    test('ignores malformed tombstones (empty id or empty deletedAt)',
        () async {
      await seedWord('keep', savedAt: '2026-06-20T10:00:00.000Z');
      api.tombstones = [
        {'id': '', 'deletedAt': '2026-06-21T10:00:00.000Z'},
        {'id': 'keep', 'deletedAt': ''}, // no deletedAt → must NOT delete
        'garbage',
      ];
      final applied = await repo.syncTombstones();
      expect(applied, 0);
      expect(await row('keep'), isNotNull);
      expect(prefs.getString(_kWatermarkKey), isNull);
    });

    test('keeps a word re-saved strictly AFTER the remote delete', () async {
      // savedAt is later than the tombstone → the word was re-added; keep it.
      await seedWord('w1', savedAt: '2026-06-25T10:00:00.000Z');
      api.tombstones = [
        {'id': 'w1', 'deletedAt': '2026-06-20T10:00:00.000Z'},
      ];
      final applied = await repo.syncTombstones();
      expect(applied, 0);
      expect(await row('w1'), isNotNull);
      // Cursor still advances so we don't reprocess this tombstone forever.
      expect(prefs.getString(_kWatermarkKey), '2026-06-20T10:00:00.000Z');
    });

    test('deletes when the tombstone is newer than the local savedAt',
        () async {
      await seedWord('w1', savedAt: '2026-06-20T10:00:00.000Z');
      api.tombstones = [
        {'id': 'w1', 'deletedAt': '2026-06-25T10:00:00.000Z'},
      ];
      final applied = await repo.syncTombstones();
      expect(applied, 1);
      expect(await row('w1'), isNull);
    });

    test('advances watermark to the MAX deletedAt across a batch', () async {
      await seedWord('a', savedAt: '2026-06-01T00:00:00.000Z');
      await seedWord('b', savedAt: '2026-06-01T00:00:00.000Z');
      api.tombstones = [
        {'id': 'a', 'deletedAt': '2026-06-10T10:00:00.000Z'},
        {'id': 'b', 'deletedAt': '2026-06-12T10:00:00.000Z'},
      ];
      final applied = await repo.syncTombstones();
      expect(applied, 2);
      expect(prefs.getString(_kWatermarkKey), '2026-06-12T10:00:00.000Z');
    });

    test('sends ?since=<watermark> on the next pull', () async {
      await prefs.setString(_kWatermarkKey, '2026-06-12T10:00:00.000Z');
      api.tombstones = <dynamic>[];
      await repo.syncTombstones();
      final last = api.lastTombstoneGet();
      expect(last, isNotNull);
      expect(last!.contains('since='), isTrue);
      expect(
          last.contains(Uri.encodeQueryComponent('2026-06-12T10:00:00.000Z')),
          isTrue);
    });

    test('first pull (no watermark) omits the since param', () async {
      api.tombstones = <dynamic>[];
      await repo.syncTombstones();
      expect(api.lastTombstoneGet()!.contains('since='), isFalse);
    });

    test('404 (endpoint not deployed) is handled gracefully', () async {
      api.tombstones404 = true;
      final applied = await repo.syncTombstones();
      expect(applied, 0);
    });

    test('empty / non-list tombstone responses are no-ops', () async {
      api.tombstones = <dynamic>[];
      expect(await repo.syncTombstones(), 0);
      api.tombstones = <String, dynamic>{'oops': true};
      expect(await repo.syncTombstones(), 0);
    });
  });

  group('end-to-end: delete on web converges on the phone', () {
    test('seeded word is removed once its tombstone is pulled', () async {
      await seedWord('x', savedAt: '2026-06-20T10:00:00.000Z');
      expect(await row('x'), isNotNull);

      // Web deletes → tombstone appears → next pull removes it locally.
      api.tombstones = [
        {'id': 'x', 'deletedAt': '2026-06-22T10:00:00.000Z'},
      ];
      await repo.syncTombstones();
      expect(await row('x'), isNull);

      // A subsequent pull with an empty delta is a clean no-op.
      api.tombstones = <dynamic>[];
      expect(await repo.syncTombstones(), 0);
    });
  });
}
