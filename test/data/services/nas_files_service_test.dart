// Hermetic tests for NasFilesService.
//
// A scripted HttpClientAdapter stands in for the network, so this drives the real
// Dio stack — interceptors and all — without a socket.
//
// The distinctions worth protecting here are about *honesty*. The read endpoints
// answer 200 even when the NAS is off, carrying the reason in the body, and that
// has to survive into a message the owner can act on: "it is switched off" and
// "the server has no password for it" lead to two completely different actions,
// and only one of them is something he can do from the phone.
//
// The other is that an upload must not be retried. Retry backoff is real, so a
// test that accidentally allows it takes seconds rather than milliseconds — which
// is itself a decent alarm.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/nas_files_service.dart';
import 'package:ai_nexus/domain/entities/nas_file.dart';

class _Reply {
  _Reply.json(this.status, Object body)
      : payload = jsonEncode(body),
        error = null;
  _Reply.failure(this.error)
      : status = null,
        payload = null;

  final int? status;
  final String? payload;
  final DioExceptionType? error;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<_Reply> script;
  int calls = 0;
  final List<String> paths = [];
  final List<String> methods = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    methods.add(options.method);
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    final reply = script[calls < script.length ? calls : script.length - 1];
    calls += 1;

    final type = reply.error;
    if (type != null) throw DioException(requestOptions: options, type: type);

    if (reply.status! >= 400) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: reply.status,
          data: jsonDecode(reply.payload!),
        ),
      );
    }

    return ResponseBody.fromString(
      reply.payload!,
      reply.status!,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({NasFilesService service, _ScriptedAdapter adapter}) build(
    List<_Reply> script,
  ) {
    final api = ApiClient();
    final adapter = _ScriptedAdapter(script);
    api.dio.httpClientAdapter = adapter;
    return (service: NasFilesService(api), adapter: adapter);
  }

  Map<String, dynamic> filesOk(List<Map<String, dynamic>> files) => {
        'ok': true,
        'reason': null,
        'message': null,
        'files': files,
      };

  // ── status ────────────────────────────────────────────────────

  group('status', () {
    test('a configured, answering NAS is ready and names its folder', () async {
      final h = build([
        _Reply.json(200, {
          'configured': true,
          'reachable': true,
          'reason': null,
          'root': 'Code/Cloud Storage',
        }),
      ]);

      final s = await h.service.status();
      expect(s.state, NasStorageState.ready);
      expect(s.isReady, isTrue);
      // The owner should be told where on the share it lands, not just "NAS".
      expect(s.root, 'Code/Cloud Storage');
      expect(s.explanation, contains('Code/Cloud Storage'));
    });

    test('no password on the server is a distinct, unselectable state',
        () async {
      final h = build([
        _Reply.json(200, {
          'configured': false,
          'reachable': false,
          'reason': 'not_configured',
          'root': 'Code/Cloud Storage',
        }),
      ]);

      final s = await h.service.status();
      expect(s.state, NasStorageState.notConfigured);
      expect(s.selectable, isFalse,
          reason: 'nothing he does on the phone can make this work, so the '
              'option must not accept a tap');
      expect(s.explanation, contains('Not set up'));
    });

    test('a switched-off NAS is still selectable — he may go and switch it on',
        () async {
      final h = build([
        _Reply.json(200, {
          'configured': true,
          'reachable': false,
          'reason': 'unreachable',
          'root': 'Code/Cloud Storage',
        }),
      ]);

      final s = await h.service.status();
      expect(s.state, NasStorageState.unreachable);
      expect(s.selectable, isTrue);
      expect(s.explanation, contains('switched off'));
    });

    test('a rejected credential is not confused with an absent one', () async {
      final h = build([
        _Reply.json(200, {
          'configured': true,
          'reachable': false,
          'reason': 'auth',
          'root': 'Code/Cloud Storage',
        }),
      ]);

      final s = await h.service.status();
      expect(s.state, NasStorageState.badCredential);
      expect(s.explanation, contains('rejected'));
    });

    test('a phone with no signal reports unknown rather than guessing',
        () async {
      final h = build([_Reply.failure(DioExceptionType.connectionError)]);

      final s = await h.service.status();
      expect(s.state, NasStorageState.unknown,
          reason: 'the phone cannot tell a dead server from a dead NAS, and '
              'inventing an answer would be worse than admitting that');
      expect(s.selectable, isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ── listing ───────────────────────────────────────────────────

  group('listing', () {
    test('files parse with their size, date and type', () async {
      final h = build([
        _Reply.json(
          200,
          filesOk([
            {
              'name': 'holiday photo.jpg',
              'size': 2048576,
              'modified': '2026-08-19T09:24:11.000Z',
              'mimeType': 'image/jpeg',
              'etag': 'abc123',
            },
          ]),
        ),
      ]);

      final files = await h.service.listFiles();
      expect(files, hasLength(1));
      expect(files.single.name, 'holiday photo.jpg');
      expect(files.single.sizeBytes, 2048576);
      expect(files.single.ext, 'jpg');
      expect(files.single.modified, isNotNull);
    });

    test('an empty folder is an empty list, not an error', () async {
      final h = build([_Reply.json(200, filesOk([]))]);
      expect(await h.service.listFiles(), isEmpty);
    });

    test('a 200 carrying ok:false throws with the server\'s own sentence',
        () async {
      final h = build([
        _Reply.json(200, {
          'ok': false,
          'reason': 'unreachable',
          'message': 'Your NAS is not reachable — it may be switched off.',
          'files': <dynamic>[],
        }),
      ]);

      await expectLater(
        h.service.listFiles(),
        throwsA(isA<NasUnavailable>()
            .having((e) => e.message, 'message', contains('switched off'))
            .having((e) => e.reason, 'reason', 'unreachable')),
      );
    });

    test('not_configured is tagged so the UI can offer the right fix',
        () async {
      final h = build([
        _Reply.json(200, {
          'ok': false,
          'reason': 'not_configured',
          'message': 'NAS storage is not set up on the server yet.',
          'files': <dynamic>[],
        }),
      ]);

      try {
        await h.service.listFiles();
        fail('should have thrown');
      } on NasUnavailable catch (e) {
        expect(e.isNotConfigured, isTrue);
      }
    });

    test('a nameless entry is dropped rather than rendered as a blank row',
        () async {
      final h = build([
        _Reply.json(
          200,
          filesOk([
            {'name': '', 'size': 1},
            {'name': 'real.txt', 'size': 2},
          ]),
        ),
      ]);

      final files = await h.service.listFiles();
      expect(files.map((f) => f.name), ['real.txt']);
    });

    test('a missing timestamp survives as null instead of becoming now',
        () async {
      final h = build([
        _Reply.json(
          200,
          filesOk([
            {'name': 'undated.txt', 'size': 5, 'modified': null},
          ]),
        ),
      ]);

      final files = await h.service.listFiles();
      expect(files.single.modified, isNull,
          reason: 'dating it to now would sort it as a fresh upload');
    });
  });

  // ── mutations do not retry ────────────────────────────────────

  group('no retry on mutations', () {
    test('a 503 delete is reported at once, not after three backoffs',
        () async {
      final h = build([
        _Reply.json(503, {
          'error': 'Your NAS is not reachable — it may be switched off.',
          'reason': 'unreachable',
        }),
      ]);

      final sw = Stopwatch()..start();
      await expectLater(
        h.service.deleteFile('a.txt'),
        throwsA(isA<NasUnavailable>()
            .having((e) => e.message, 'message', contains('switched off'))),
      );
      sw.stop();

      expect(h.adapter.calls, 1,
          reason: 'the shared interceptor retries 503, and this endpoint '
              'returns 503 for a NAS that is switched off — which will not '
              'have changed by the end of a backoff');
      expect(sw.elapsed.inSeconds, lessThan(3));
    });

    test('the delete is aimed at the encoded name', () async {
      final h = build([_Reply.json(200, {'ok': true})]);
      await h.service.deleteFile('holiday photo.jpg');
      expect(h.adapter.methods.single, 'DELETE');
      expect(h.adapter.paths.single, contains('holiday%20photo.jpg'));
    });

    test('the server\'s wording is preferred over a generic line', () async {
      final h = build([
        _Reply.json(507, {
          'error': 'There is not enough free space on the NAS.',
          'reason': 'insufficient_storage',
        }),
      ]);

      await expectLater(
        h.service.deleteFile('a.txt'),
        throwsA(isA<NasUnavailable>().having(
            (e) => e.message, 'message', contains('not enough free space'))),
      );
    });
  });

  // ── the reading of a listing ──────────────────────────────────

  group('NasFile', () {
    test('the extension is taken from the name, lowercased', () {
      expect(const NasFile(name: 'REPORT.PDF', sizeBytes: 1).ext, 'pdf');
      expect(const NasFile(name: 'archive.tar.gz', sizeBytes: 1).ext, 'gz');
    });

    test('a name with no extension does not invent one', () {
      expect(const NasFile(name: 'Makefile', sizeBytes: 1).ext, '');
      expect(const NasFile(name: '.', sizeBytes: 1).ext, '');
      expect(const NasFile(name: 'trailing.', sizeBytes: 1).ext, '');
    });
  });

  group('upload routing', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('nas-up-'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    File _file(String name, int bytes) {
      final f = File('${tmp.path}${Platform.pathSeparator}$name');
      f.writeAsBytesSync(List<int>.filled(bytes, 7));
      return f;
    }

    test('a small file is a single multipart POST', () async {
      final h = build([
        _Reply.json(201, {
          'file': {'name': 'note.txt'},
        }),
      ]);
      final out = await h.service.uploadFile(_file('note.txt', 128));
      expect(out.name, 'note.txt');
      expect(h.adapter.methods, ['POST']);
      expect(h.adapter.paths.single, contains('/nas/upload'));
      expect(h.adapter.paths.single, isNot(contains('resumable')));
    });

    test('a file over 5 MB is sent in chunks, not as one 30-minute PUT',
        () async {
      final h = build([
        _Reply.json(201, {
          'uploadId': 'abc123',
          'chunkSize': NasFilesService.chunkSize,
        }),
        _Reply.json(201, {
          'done': true,
          'file': {'name': 'clip.bin'},
        }),
      ]);
      final size = NasFilesService.simpleThreshold;
      final out = await h.service.uploadFile(_file('clip.bin', size));
      expect(out.name, 'clip.bin');
      expect(h.adapter.methods, ['POST', 'PUT']);
      expect(h.adapter.paths[0], contains('/nas/upload/resumable/start'));
      expect(h.adapter.paths[1], contains('/nas/upload/resumable/abc123'));
    });

    test('a two-chunk file puts twice and finishes on the second reply',
        () async {
      final h = build([
        _Reply.json(201, {
          'uploadId': 'id9',
          'chunkSize': NasFilesService.chunkSize,
        }),
        _Reply.json(200, {'done': false, 'received': NasFilesService.chunkSize}),
        _Reply.json(201, {
          'done': true,
          'file': {'name': 'film.mkv'},
        }),
      ]);
      final size = NasFilesService.chunkSize + 1024;
      final out = await h.service.uploadFile(_file('film.mkv', size));
      expect(out.name, 'film.mkv');
      expect(h.adapter.methods, ['POST', 'PUT', 'PUT']);
    });
  });
}
