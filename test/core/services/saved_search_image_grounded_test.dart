// End-to-end tests for image-grounded saved searches.
//
// These tests are the production safety net for cross-device sync of
// the new InsightAI image flow. We exercise the SavedSearchStore APIs
// with [ImageGroundedResult] inputs — the same path the tutor screen
// takes when an image search lands — and prove:
//
//   1.  Local save: an image result inserts a Drift row with the
//       canonical `image-grounded` response type, `image` kind, and a
//       responseJson that carries the cross-device thumbnail + media
//       type + question.
//   2.  Cross-device pull: a row saved on Device A reaches Device B
//       through the fake backend with identical responseJson + a fully
//       decodable thumbnail data URL.
//   3.  Delete + undelete still work for image-grounded rows (no
//       regression of the existing soft-delete contract).
//   4.  Chat-mirror: text-only follow-up turns persisted under the
//       image entry round-trip across devices through the existing
//       /chat endpoints (proves the "text-only fallback on non-
//       uploading devices" UX).
//   5.  Tombstone protection: a tombstoned image-grounded row is not
//       resurrected by a later index pull.
//   6.  Forward-compat: the existing SavedSearchEntry helpers (
//       imageThumbDataUrl / imageMediaType / imageQuestion) crack
//       open the responseJson without leaking the schema into UI code.
//
// The fake backend used here is the same one as the canonical sync
// E2E test — kept inline to dodge dart-test discovery quirks while
// still mirroring the real Express routes exactly.

import 'dart:convert';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fake backend ──────────────────────────────────────────────────────

class _Row {
  _Row({
    required this.id,
    required this.kind,
    required this.query,
    required this.title,
    required this.responseType,
    required this.responseJson,
    required this.model,
    required this.provider,
    required this.mode,
    required this.pinned,
    required this.savedAt,
    required this.updatedAt,
  });

  String id;
  String kind;
  String query;
  String title;
  String responseType;
  String responseJson;
  String model;
  String provider;
  String mode;
  bool pinned;
  String savedAt;
  String updatedAt;

  Map<String, dynamic> toJson() {
    Object decoded;
    try {
      decoded = jsonDecode(responseJson);
    } catch (_) {
      decoded = responseJson;
    }
    return {
      'id': id,
      'kind': kind,
      'query': query,
      'title': title,
      'responseType': responseType,
      'responseJson': decoded,
      'model': model,
      'provider': provider,
      'mode': mode,
      'pinned': pinned,
      'savedAt': savedAt,
      'updatedAt': updatedAt,
    };
  }
}

class _ChatRow {
  _ChatRow({
    required this.id,
    required this.searchId,
    required this.role,
    required this.text,
    required this.model,
    required this.sourcesJson,
    required this.createdAt,
  });
  String id;
  String searchId;
  String role;
  String text;
  String model;
  String sourcesJson;
  String createdAt;
}

class _Backend {
  final Map<String, _Row> rows = {};
  final Map<String, _ChatRow> chats = {};
  final Map<String, String> tombstones = {};
  final List<String> calls = [];

  Object? handle(String method, String path, {Object? body}) {
    final key = '$method $path';
    calls.add(key);

    if (method == 'GET' && path == '/api/v1/saved-searches') {
      return rows.values
          .where((r) => r.pinned)
          .map((r) => r.toJson())
          .toList();
    }
    const tsBase = '/api/v1/saved-searches/tombstones';
    if (method == 'GET' &&
        (path == tsBase || path.startsWith('$tsBase?'))) {
      return tombstones.entries
          .map((e) => {'id': e.key, 'deletedAt': e.value})
          .toList();
    }
    if (method == 'POST' && path == '/api/v1/saved-searches') {
      final m = (body as Map).cast<String, Object?>();
      final id = m['id']!.toString();
      final rj = m['responseJson'];
      final rjStr = rj is String
          ? rj
          : rj is Map || rj is List
              ? jsonEncode(rj)
              : '{}';
      rows[id] = _Row(
        id: id,
        kind: m['kind']?.toString() ?? '',
        query: m['query']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        responseType: m['responseType']?.toString() ?? '',
        responseJson: rjStr,
        model: m['model']?.toString() ?? '',
        provider: m['provider']?.toString() ?? '',
        mode: m['mode']?.toString() ?? '',
        pinned: m['pinned'] is bool ? m['pinned'] as bool : true,
        savedAt: m['savedAt']?.toString() ?? '',
        updatedAt: m['updatedAt']?.toString() ?? '',
      );
      tombstones.remove(id);
      return {'ok': true, 'id': id};
    }

    final idMatch =
        RegExp(r'^/api/v1/saved-searches/([^/]+)$').firstMatch(path);
    if (idMatch != null) {
      final id = idMatch.group(1)!;
      if (method == 'GET') {
        final r = rows[id];
        if (r == null) throw _err(404, path, 'not found');
        return r.toJson();
      }
      if (method == 'DELETE') {
        tombstones[id] = DateTime.now().toUtc().toIso8601String();
        rows.remove(id);
        chats.removeWhere((_, c) => c.searchId == id);
        return {'ok': true, 'deleted': 1};
      }
    }

    final chatMatch =
        RegExp(r'^/api/v1/saved-searches/([^/]+)/chat$').firstMatch(path);
    if (chatMatch != null) {
      final searchId = chatMatch.group(1)!;
      if (method == 'GET') {
        final list = chats.values
            .where((c) => c.searchId == searchId)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return list
            .map((c) => {
                  'id': c.id,
                  'searchId': c.searchId,
                  'role': c.role,
                  'text': c.text,
                  'model': c.model,
                  'sourcesJson': c.sourcesJson,
                  'createdAt': c.createdAt,
                })
            .toList();
      }
      if (method == 'POST') {
        final m = (body as Map).cast<String, Object?>();
        final id = m['id']!.toString();
        chats[id] = _ChatRow(
          id: id,
          searchId: searchId,
          role: m['role']?.toString() ?? '',
          text: m['text']?.toString() ?? '',
          model: m['model']?.toString() ?? '',
          sourcesJson: m['sourcesJson']?.toString() ?? '[]',
          createdAt: m['createdAt']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        );
        return {'ok': true, 'id': id};
      }
    }

    throw _err(404, path, 'no route');
  }

  static DioException _err(int code, String path, String msg) {
    final r = RequestOptions(path: path);
    return DioException(
      requestOptions: r,
      response: Response<dynamic>(
          requestOptions: r, statusCode: code, data: msg),
      type: DioExceptionType.badResponse,
      message: msg,
    );
  }
}

class _BackedApi extends ApiClient {
  _BackedApi(this._b);
  final _Backend _b;

  static String _strip(String p) {
    final i = p.indexOf('/api/v1');
    return i >= 0 ? p.substring(i) : p;
  }

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters}) async {
    return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: _b.handle('GET', _strip(path)) as T?);
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: _b.handle('POST', _strip(path), body: data) as T?);
  }

  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async {
    return Response<T>(
        requestOptions: RequestOptions(path: path), statusCode: 200);
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: _b.handle('DELETE', _strip(path)) as T?);
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────

/// Build a believable ImageGroundedResult with a non-empty thumbnail
/// (4-byte JPEG header — enough to keep the data URL > 0 length).
///
/// `answer` and `model` are deliberately part of the signature even
/// though current tests only flex the defaults: future tests can
/// override them without touching call sites.
ImageGroundedResult _buildImageResult({
  String question = 'what is in this picture?',
  String mediaType = 'image/jpeg',
}) {
  const grounded = GroundedSearchResponse(
    answer: 'This is a cat sitting on a mat.',
    query: 'what is in this picture?',
    model: 'gemini-2.5-flash',
    searchQueries: [],
    sources: [
      GroundedSource(
          index: 1, title: 'Wikipedia: Cat', url: 'https://en.wikipedia.org/wiki/Cat'),
    ],
    citations: [],
  );
  // 4-byte synthetic "JPEG" (just FF D8 FF E0) base64-encoded.
  const thumbDataUrl = 'data:image/jpeg;base64,/9j/4A==';
  return ImageGroundedResult(
    response: grounded,
    thumbDataUrl: thumbDataUrl,
    originalMediaType: mediaType,
    question: question,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('SavedSearchStore — image-grounded local persistence', () {
    late AppDatabase db;
    late SavedSearchStore store;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      store = SavedSearchStore.instance;
      store.debugResetForTests();
      store.init(db, null);
    });

    tearDown(() async {
      store.debugResetForTests();
      await db.close();
    });

    test('saveResult with ImageGroundedResult inserts an image-grounded row',
        () async {
      final entry = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'what is in this picture?',
        result: _buildImageResult(),
      );

      expect(entry.id, isNotEmpty);
      expect(entry.kind, equals(SavedSearchKind.image));
      expect(entry.responseType,
          equals(SavedSearchResponseType.imageGrounded));
      expect(entry.model, equals('gemini-2.5-flash'),
          reason: '_modelOf must extract model from the wrapper');
      // The Drift row should hold the merged JSON (grounded + image extras).
      final parsed = jsonDecode(entry.responseJson) as Map;
      expect(parsed['answer'], contains('cat'));
      expect(parsed['imageThumb'], startsWith('data:image/jpeg;base64,'));
      expect(parsed['imageMediaType'], equals('image/jpeg'));
      expect(parsed['question'], equals('what is in this picture?'));
    });

    test(
        'decodedResult returns a GroundedSearchResponse (shape-compatible) '
        'for image-grounded entries', () async {
      final entry = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'q',
        result: _buildImageResult(),
      );
      final decoded = entry.decodedResult();
      expect(decoded, isA<GroundedSearchResponse>(),
          reason: 'detail sheet relies on this — it dispatches via '
              '`is GroundedSearchResponse` and includes image-grounded '
              'rows in the same branch');
      final g = decoded as GroundedSearchResponse;
      expect(g.answer, contains('cat'));
      expect(g.sources, hasLength(1));
    });

    test(
        'image accessors (imageThumbDataUrl / imageMediaType / imageQuestion) '
        'crack open the responseJson cleanly', () async {
      final entry = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'what is in this picture?',
        result: _buildImageResult(mediaType: 'image/png'),
      );
      expect(entry.imageThumbDataUrl,
          startsWith('data:image/jpeg;base64,'));
      expect(entry.imageMediaType, equals('image/png'));
      expect(entry.imageQuestion, equals('what is in this picture?'));
    });

    test('non-image entries return null for the image accessors', () async {
      const tavily = TavilySearchResponse(
          answer: 'x', query: 'q', results: <TavilyResultItem>[]);
      final entry = await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'q',
        result: tavily,
      );
      expect(entry.imageThumbDataUrl, isNull);
      expect(entry.imageMediaType, isNull);
      expect(entry.imageQuestion, isNull);
    });

    test('delete + undelete still work for image-grounded entries',
        () async {
      final entry = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'q',
        result: _buildImageResult(),
      );
      expect(await store.isSaved(entry.id), isTrue);

      await store.delete(entry.id);
      expect(await store.isSaved(entry.id), isFalse,
          reason: 'image rows must honour the same soft-delete contract');

      await store.undelete(entry.id);
      expect(await store.isSaved(entry.id), isTrue);
    });

    test(
        'image-grounded rows appear in listAll alongside text rows '
        '— History sheet shows a mixed feed without filtering', () async {
      await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'pic',
        result: _buildImageResult(),
      );
      await store.saveResult(
        kind: SavedSearchKind.query,
        query: 'text',
        result: const TavilySearchResponse(
            answer: 'x', query: 'q', results: <TavilyResultItem>[]),
      );
      final all = await store.listAll();
      expect(all, hasLength(2));
      final kinds = all.map((e) => e.kind).toSet();
      expect(kinds, containsAll(<String>{
        SavedSearchKind.image,
        SavedSearchKind.query,
      }));
    });

    test('saveResult is idempotent on a fixed id for image entries too',
        () async {
      final a = await store.saveResult(
        id: 'fixed-id',
        kind: SavedSearchKind.image,
        query: 'q',
        result: _buildImageResult(),
      );
      final b = await store.saveResult(
        id: 'fixed-id',
        kind: SavedSearchKind.image,
        query: 'q',
        result: _buildImageResult(),
      );
      expect(a.id, equals(b.id));
      final all = await store.listAll();
      expect(all, hasLength(1));
    });

    test('promoteToSaved works on an image-grounded draft', () async {
      final draft = await store.startDraft(
        kind: SavedSearchKind.image,
        query: 'photo',
        result: _buildImageResult(),
      );
      expect(await store.isSaved(draft.id), isFalse,
          reason: 'drafts are unpinned by default');

      await store.promoteToSaved(draft.id);
      expect(await store.isSaved(draft.id), isTrue);

      final saved = await store.getById(draft.id);
      expect(saved!.responseType,
          equals(SavedSearchResponseType.imageGrounded));
    });
  });

  group('SavedSearchStore — image-grounded cross-device sync', () {
    late _Backend backend;
    late _BackedApi api;
    late AppDatabase deviceA;
    late SavedSearchStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      backend = _Backend();
      api = _BackedApi(backend);
      deviceA = AppDatabase.forTesting(NativeDatabase.memory());
      store = SavedSearchStore.instance;
      store.debugResetForTests();
      store.init(deviceA, api);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      backend.calls.clear();
    });

    tearDown(() async {
      store.debugResetForTests();
      await deviceA.close();
    });

    test(
        'image-grounded saves POST the responseJson with full image extras '
        'preserved end-to-end', () async {
      final entry = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'what is this?',
        result: _buildImageResult(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Server received the row.
      expect(backend.calls, contains('POST /api/v1/saved-searches'));
      expect(backend.rows[entry.id], isNotNull);
      final wire = backend.rows[entry.id]!.toJson();
      expect(wire['kind'], equals(SavedSearchKind.image));
      expect(wire['responseType'],
          equals(SavedSearchResponseType.imageGrounded));

      // The responseJson must contain the image extras — this is what
      // makes the cross-device thumbnail work on Device B.
      final rj = wire['responseJson'];
      expect(rj, isA<Map>(),
          reason: 'server returns the responseJson as a structured map');
      final rjMap = (rj as Map).cast<String, Object?>();
      expect(rjMap['imageThumb'].toString(),
          startsWith('data:image/jpeg;base64,'));
      expect(rjMap['imageMediaType'], equals('image/jpeg'));
      expect(rjMap['question'], equals('what is in this picture?'));
    });

    test(
        'Device A saves image → Device B pulls it → thumbnail + question '
        'arrive intact', () async {
      final saved = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'q on device A',
        result: _buildImageResult(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Device B comes online with a fresh Drift db pointed at the same
      // backend.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      store.debugResetForTests();
      store.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final mirrored = await store.listAll();
      expect(mirrored, hasLength(1),
          reason: 'Device B must see the row that Device A saved');
      final row = mirrored.single;
      expect(row.id, equals(saved.id));
      expect(row.kind, equals(SavedSearchKind.image));
      expect(row.responseType,
          equals(SavedSearchResponseType.imageGrounded));

      // The thumbnail data URL survives the round-trip unchanged.
      expect(row.imageThumbDataUrl,
          startsWith('data:image/jpeg;base64,'));
      expect(row.imageMediaType, equals('image/jpeg'));
      expect(row.imageQuestion, equals('what is in this picture?'));

      // And the underlying GroundedSearchResponse decodes cleanly.
      final decoded = row.decodedResult() as GroundedSearchResponse;
      expect(decoded.answer, contains('cat'));
      expect(decoded.sources, hasLength(1));

      await deviceB.close();
    });

    test(
        'delete on Device A propagates to the backend → Device B no '
        'longer sees the image row after the next pull', () async {
      final saved = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'q',
        result: _buildImageResult(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await store.delete(saved.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Server has a tombstone now.
      expect(backend.tombstones.containsKey(saved.id), isTrue);
      expect(backend.rows[saved.id], isNull);

      // Device B comes online — index pull should NOT bring the row back.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      store.debugResetForTests();
      store.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(await store.listAll(), isEmpty,
          reason: 'deleted rows must not resurrect on Device B');

      await deviceB.close();
    });

    test(
        'chat-mirror: text-only follow-up turns persisted under an image '
        'entry round-trip across devices (proves the cross-device '
        'fallback flow)', () async {
      final entry = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'what is in this picture?',
        result: _buildImageResult(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final t0 = DateTime.now().toUtc();
      await store.appendMessage(
        searchId: entry.id,
        messageId: 'u1',
        role: 'user',
        text: 'are you sure it\'s a cat?',
        createdAt: t0.toIso8601String(),
      );
      await store.appendMessage(
        searchId: entry.id,
        messageId: 'a1',
        role: 'assistant',
        text: 'Yes — the ear shape and whiskers confirm it.',
        model: 'gemini-2.5-flash',
        createdAt: t0.add(const Duration(seconds: 1)).toIso8601String(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Server received both POSTs to /:id/chat.
      final chatPosts = backend.calls
          .where((c) =>
              c.startsWith('POST /api/v1/saved-searches/') &&
              c.endsWith('/chat'))
          .toList();
      expect(chatPosts, hasLength(2),
          reason: 'chat mirror must POST both turns');

      // Device B reads the chat history.
      final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
      store.debugResetForTests();
      store.init(deviceB, api);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await store.pullMessagesFromServer(entry.id);

      final pulled = await store.loadMessages(entry.id);
      expect(pulled.map((m) => m.id), equals(<String>['u1', 'a1']));
      expect(pulled.first.text, contains('cat'));
      expect(pulled.last.model, equals('gemini-2.5-flash'));

      await deviceB.close();
    });

    test(
        'pinned flag stays true after a save — image rows show up in '
        'the History list immediately',
        () async {
      final saved = await store.saveResult(
        kind: SavedSearchKind.image,
        query: 'q',
        result: _buildImageResult(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(saved.pinned, isTrue);
      expect(backend.rows[saved.id]!.pinned, isTrue);
      // listAll filters on pinned=true.
      final list = await store.listAll();
      expect(list.map((e) => e.id), contains(saved.id));
    });
  });
}
