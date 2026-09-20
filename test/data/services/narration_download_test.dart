import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_nexus/core/services/telegram_logger.dart';
import 'package:ai_nexus/data/services/narration_download.dart';
import 'package:ai_nexus/data/services/narration_download_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _ogg({int extra = 300}) =>
    Uint8List.fromList(<int>[0x4F, 0x67, 0x67, 0x53, ...List<int>.filled(extra, 1)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('download helpers', () {
    test('basename sanitizes traversal and empty ids', () {
      expect(narrationDownloadBasename(''), '');
      expect(narrationDownloadBasename('../x'), matches(RegExp(r'^a\.\._x-[0-9a-f]+\.opus$')));
      expect(narrationDownloadBasename('news-1'), matches(RegExp(r'^news-1-[0-9a-f]+\.opus$')));
      expect(narrationDownloadBasename('a b/c'), matches(RegExp(r'^a_b_c-[0-9a-f]+\.opus$')));
      expect(narrationDownloadBasename('x' * 200).endsWith('.opus'), isTrue);
      expect(narrationDownloadBasename('x' * 200).length, lessThanOrEqualTo(96));
      expect(
        narrationDownloadBasename('news-1'),
        isNot(narrationDownloadBasename('news-2')),
      );
    });

    test('opus magic + min size', () {
      expect(
        isValidDownloadedOpus(exists: false, length: 400, header: kOggMagic),
        isFalse,
      );
      expect(
        isValidDownloadedOpus(exists: true, length: 10, header: kOggMagic),
        isFalse,
      );
      expect(
        isValidDownloadedOpus(
          exists: true,
          length: 400,
          header: const [1, 2, 3, 4],
        ),
        isFalse,
      );
      expect(
        isValidDownloadedOpus(
          exists: true,
          length: 400,
          header: kOggMagic,
        ),
        isTrue,
      );
    });

    test('retry backoff and status policy', () {
      expect(narrationDownloadBackoff(0).inMilliseconds, 250);
      expect(narrationDownloadBackoff(1).inMilliseconds, 500);
      expect(narrationDownloadBackoff(8).inMilliseconds, 4000);
      expect(isRetryableDownloadStatus(null), isTrue);
      expect(isRetryableDownloadStatus(404), isTrue);
      expect(isRetryableDownloadStatus(503), isTrue);
      expect(isRetryableDownloadStatus(401), isFalse);
      expect(isRetryableDownloadStatus(403), isFalse);
      expect(isRetryableDownloadStatus(400), isFalse);
      expect(isRetryableDownloadStatus(408), isTrue);
      expect(isRetryableDownloadStatus(429), isTrue);
    });

    test('prefer local and reload when download finishes mid-session', () {
      expect(shouldPreferLocalAudio(fileExists: true, bytes: 256), isTrue);
      expect(shouldPreferLocalAudio(fileExists: false, bytes: 4000), isFalse);
      expect(shouldPreferLocalAudio(fileExists: true, bytes: 10), isFalse);
      expect(
        shouldReloadForLocalFile(localReady: true, currentIsLocal: false),
        isTrue,
      );
      expect(
        shouldReloadForLocalFile(localReady: true, currentIsLocal: true),
        isFalse,
      );
      expect(
        shouldReloadForLocalFile(localReady: false, currentIsLocal: false),
        isFalse,
      );
      expect(shouldWipeLocalOnArticleGone(false), isTrue);
      expect(shouldWipeLocalOnArticleGone(true), isFalse);
      expect(shouldWipeLocalOnMarkRead(), isTrue);
      expect(shouldAllowDownloadTap(NarrationDownloadPhase.idle), isTrue);
      expect(shouldAllowDownloadTap(NarrationDownloadPhase.error), isTrue);
      expect(shouldAllowDownloadTap(NarrationDownloadPhase.ready), isTrue);
      expect(
        shouldAllowDownloadTap(NarrationDownloadPhase.downloading),
        isFalse,
      );
      expect(shouldSkipNetworkDownload(localPlayable: true), isTrue);
      expect(shouldSkipNetworkDownload(localPlayable: false), isFalse);
    });

    test('progress fraction clamps and treats unknown totals as zero', () {
      expect(
        const NarrationDownloadProgress(
          phase: NarrationDownloadPhase.downloading,
          received: 50,
          total: 100,
        ).fraction,
        0.5,
      );
      expect(
        const NarrationDownloadProgress(
          phase: NarrationDownloadPhase.downloading,
          received: 150,
          total: 100,
        ).fraction,
        1.0,
      );
      expect(
        const NarrationDownloadProgress(
          phase: NarrationDownloadPhase.downloading,
          received: 10,
        ).fraction,
        0,
      );
      expect(
        const NarrationDownloadProgress(
          phase: NarrationDownloadPhase.downloading,
          received: 10,
          total: 0,
        ).fraction,
        0,
      );
      expect(const NarrationDownloadProgress.idle().isBusy, isFalse);
      expect(const NarrationDownloadProgress.ready().isReady, isTrue);
      expect(
        const NarrationDownloadProgress(
          phase: NarrationDownloadPhase.downloading,
        ).isBusy,
        isTrue,
      );
    });

    test('opus rejects short headers and exact undersize even with magic', () {
      expect(
        isValidDownloadedOpus(
          exists: true,
          length: 256,
          header: kOggMagic,
        ),
        isTrue,
      );
      expect(
        isValidDownloadedOpus(
          exists: true,
          length: 255,
          header: kOggMagic,
        ),
        isFalse,
      );
      expect(
        isValidDownloadedOpus(
          exists: true,
          length: 400,
          header: const [0x4F, 0x67, 0x67],
        ),
        isFalse,
      );
      expect(
        isValidDownloadedOpus(
          exists: true,
          length: 400,
          header: const [0x4F, 0x67, 0x67, 0x54],
        ),
        isFalse,
      );
    });

    test('basename keeps uuid ids unique and rejects traversal', () {
      expect(
        narrationDownloadBasename('news-550e8400-e29b-41d4-a716-446655440000'),
        matches(
          RegExp(r'^news-550e8400-e29b-41d4-a716-446655440000-[0-9a-f]+\.opus$'),
        ),
      );
      expect(narrationDownloadBasename('.'), matches(RegExp(r'^article-[0-9a-f]+\.opus$')));
      expect(narrationDownloadBasename('..'), matches(RegExp(r'^article-[0-9a-f]+\.opus$')));
      expect(
        narrationDownloadBasename('.hidden'),
        matches(RegExp(r'^a\.hidden-[0-9a-f]+\.opus$')),
      );
      expect(
        narrationDownloadBasename('你好'),
        isNot(narrationDownloadBasename('世界')),
      );
    });

    test('retry policy covers 409/422/5xx and backoff steps', () {
      expect(isRetryableDownloadStatus(409), isFalse);
      expect(isRetryableDownloadStatus(422), isFalse);
      expect(isRetryableDownloadStatus(500), isTrue);
      expect(isRetryableDownloadStatus(502), isTrue);
      expect(isRetryableDownloadStatus(504), isTrue);
      expect(narrationDownloadBackoff(2).inMilliseconds, 1000);
      expect(narrationDownloadBackoff(3).inMilliseconds, 2000);
      expect(narrationDownloadBackoff(-1).inMilliseconds, 250);
    });

    test('semantics labels cover every phase', () {
      expect(
        narrationDownloadSemantics(NarrationDownloadPhase.idle),
        'Download audio',
      );
      expect(
        narrationDownloadSemantics(NarrationDownloadPhase.downloading),
        'Downloading audio',
      );
      expect(
        narrationDownloadSemantics(NarrationDownloadPhase.ready),
        'Audio downloaded',
      );
      expect(
        narrationDownloadSemantics(NarrationDownloadPhase.error),
        'Retry download',
      );
    });
  });

  group('NarrationDownloadStore', () {
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tmp = await Directory.systemTemp.createTemp('nar-dl-');
      NarrationDownloadStore.debugRootOverride = tmp;
      NarrationDownloadStore.debugGetBytes = null;
      NarrationDownloadStore.instance.resetForTest();
      await NarrationDownloadStore.instance.hydrate();
    });

    tearDown(() async {
      NarrationDownloadStore.debugGetBytes = null;
      NarrationDownloadStore.debugRootOverride = null;
      NarrationDownloadStore.instance.resetForTest();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('happy path writes opus and isReady', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        expect(url, contains('/audio'));
        expect(resume, 0);
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('news-1');
      expect(NarrationDownloadStore.instance.isReady('news-1'), isTrue);
      expect(await NarrationDownloadStore.instance.hasPlayableFile('news-1'), isTrue);
      expect(
        NarrationDownloadStore.instance.progressOf('news-1').phase,
        NarrationDownloadPhase.ready,
      );
    });

    test('invalid payload is not marked ready', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: Uint8List.fromList(List<int>.filled(400, 9)));
      };
      await NarrationDownloadStore.instance.download('bad-1');
      expect(NarrationDownloadStore.instance.isReady('bad-1'), isFalse);
      expect(
        NarrationDownloadStore.instance.progressOf('bad-1').phase,
        NarrationDownloadPhase.error,
      );
    });

    test('retries 503 then succeeds', () async {
      var n = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        if (n == 1) return (status: 503, body: <int>[]);
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('news-retry');
      expect(n, 2);
      expect(NarrationDownloadStore.instance.isReady('news-retry'), isTrue);
    });

    test('401 is not retried', () async {
      var n = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        return (status: 401, body: <int>[]);
      };
      await NarrationDownloadStore.instance.download('news-401');
      expect(n, 1);
      expect(NarrationDownloadStore.instance.isReady('news-401'), isFalse);
    });

    test('resume appends 206 body onto the part file', () async {
      final part = File(
        '${NarrationDownloadStore.instance.localFile('news-resume')!.path}.part',
      );
      await part.writeAsBytes(_ogg(extra: 40));
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        expect(resume, greaterThan(0));
        return (status: 206, body: List<int>.filled(300, 2));
      };
      await NarrationDownloadStore.instance.download('news-resume');
      expect(NarrationDownloadStore.instance.isReady('news-resume'), isTrue);
      final dest = NarrationDownloadStore.instance.localFile('news-resume')!;
      expect(await dest.length(), greaterThan(300));
      expect(await part.exists(), isFalse);
    });

    test('wipe deletes file and index even mid-id', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('keep-me');
      await NarrationDownloadStore.instance.download('drop-me');
      await NarrationDownloadStore.instance.wipe(['drop-me', '']);
      expect(NarrationDownloadStore.instance.isReady('keep-me'), isTrue);
      expect(NarrationDownloadStore.instance.isReady('drop-me'), isFalse);
      expect(
        await NarrationDownloadStore.instance.localFile('drop-me')!.exists(),
        isFalse,
      );
    });

    test('download and wipe emit confirmation logs', () async {
      final logs = <String>[];
      TLog.debugOnLog = (level, tag, message, {error}) {
        if (tag == 'NarrationDL') logs.add('$level $message');
      };
      addTearDown(() => TLog.debugOnLog = null);
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('news-log');
      expect(
        logs.any((m) => m.contains('offline audio saved') && m.contains('news-log')),
        isTrue,
      );
      logs.clear();
      await NarrationDownloadStore.instance.wipe(['news-log']);
      expect(
        logs.any((m) => m.contains('deleted local audio') && m.contains('files=1')),
        isTrue,
      );
      expect(await NarrationDownloadStore.instance.localFile('news-log')!.exists(), isFalse);
    });

    test('pruneTo drops orphans not in the live set', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('live');
      await NarrationDownloadStore.instance.download('orphan');
      await NarrationDownloadStore.instance.pruneTo({'live'});
      expect(NarrationDownloadStore.instance.isReady('live'), isTrue);
      expect(NarrationDownloadStore.instance.isReady('orphan'), isFalse);
    });

    test('single-flight does not start two network gets', () async {
      var n = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return (status: 200, body: _ogg());
      };
      await Future.wait([
        NarrationDownloadStore.instance.download('same'),
        NarrationDownloadStore.instance.download('same'),
      ]);
      expect(n, 1);
    });

    test('empty id is a no-op', () async {
      await NarrationDownloadStore.instance.download('  ');
      expect(NarrationDownloadStore.instance.isReady(''), isFalse);
    });

    test('hydrate drops index entries whose files vanished', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('ghost');
      final file = NarrationDownloadStore.instance.localFile('ghost')!;
      await file.delete();
      NarrationDownloadStore.instance.resetForTest();
      NarrationDownloadStore.debugRootOverride = tmp;
      await NarrationDownloadStore.instance.hydrate();
      expect(NarrationDownloadStore.instance.isReady('ghost'), isFalse);
    });

    test('already-ready download does not hit the network', () async {
      var n = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('news-cached');
      await NarrationDownloadStore.instance.download('news-cached');
      expect(n, 1);
    });

    test('waitUntilReady false surfaces a retryable error and writes nothing',
        () async {
      var n = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download(
        'news-wait',
        waitUntilReady: () async => false,
      );
      expect(n, 0);
      expect(NarrationDownloadStore.instance.isReady('news-wait'), isFalse);
      expect(
        NarrationDownloadStore.instance.progressOf('news-wait').phase,
        NarrationDownloadPhase.error,
      );
    });

    test('tiny payload is rejected like a corrupt opus', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: Uint8List.fromList(kOggMagic));
      };
      await NarrationDownloadStore.instance.download('tiny');
      expect(NarrationDownloadStore.instance.isReady('tiny'), isFalse);
      expect(
        await NarrationDownloadStore.instance.localFile('tiny')!.exists(),
        isFalse,
      );
    });

    test('400 is not retried; 429 then succeeds', () async {
      var n400 = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n400 += 1;
        return (status: 400, body: <int>[]);
      };
      await NarrationDownloadStore.instance.download('news-400');
      expect(n400, 1);

      var n429 = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n429 += 1;
        if (n429 == 1) return (status: 429, body: <int>[]);
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('news-429');
      expect(n429, 2);
      expect(NarrationDownloadStore.instance.isReady('news-429'), isTrue);
    });

    test('full 200 on resume replaces the part instead of appending', () async {
      final part = File(
        '${NarrationDownloadStore.instance.localFile('news-full')!.path}.part',
      );
      await part.writeAsBytes(List<int>.filled(80, 9));
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        expect(resume, greaterThan(0));
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('news-full');
      expect(NarrationDownloadStore.instance.isReady('news-full'), isTrue);
      expect(
        await NarrationDownloadStore.instance.localFile('news-full')!.length(),
        _ogg().length,
      );
    });

    test('wipe during an in-flight get never leaves a ready file', () async {
      final started = Completer<void>();
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        started.complete();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return (status: 200, body: _ogg());
      };
      final pending = NarrationDownloadStore.instance.download('race-1');
      await started.future;
      await NarrationDownloadStore.instance.wipe(['race-1']);
      await pending;
      expect(NarrationDownloadStore.instance.isReady('race-1'), isFalse);
      expect(
        await NarrationDownloadStore.instance.localFile('race-1')!.exists(),
        isFalse,
      );
      expect(
        NarrationDownloadStore.instance.progressOf('race-1').phase,
        NarrationDownloadPhase.idle,
      );
    });

    test('download after wipe fetches a fresh copy', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('again');
      await NarrationDownloadStore.instance.wipe(['again']);
      expect(NarrationDownloadStore.instance.isReady('again'), isFalse);
      await NarrationDownloadStore.instance.download('again');
      expect(NarrationDownloadStore.instance.isReady('again'), isTrue);
      expect(
        await NarrationDownloadStore.instance.hasPlayableFile('again'),
        isTrue,
      );
    });

    test('transient throw is retried then succeeds', () async {
      var n = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        if (n == 1) throw Exception('socket reset');
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('news-throw');
      expect(n, 2);
      expect(NarrationDownloadStore.instance.isReady('news-throw'), isTrue);
    });

    test('403 and 409 are not retried; 404 exhausts max attempts', () async {
      var n403 = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n403 += 1;
        return (status: 403, body: <int>[]);
      };
      await NarrationDownloadStore.instance.download('news-403');
      expect(n403, 1);

      var n409 = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n409 += 1;
        return (status: 409, body: <int>[]);
      };
      await NarrationDownloadStore.instance.download('news-409');
      expect(n409, 1);

      var n404 = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n404 += 1;
        return (status: 404, body: <int>[]);
      };
      await NarrationDownloadStore.instance.download('news-404');
      expect(n404, kNarrationDownloadMaxAttempts);
      expect(NarrationDownloadStore.instance.isReady('news-404'), isFalse);
      expect(
        NarrationDownloadStore.instance.progressOf('news-404').phase,
        NarrationDownloadPhase.error,
      );
    });

    test('waitUntilReady true then fetches; wipe during wait writes nothing',
        () async {
      var n = 0;
      final started = Completer<void>();
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download(
        'news-wait-ok',
        waitUntilReady: () async => true,
      );
      expect(n, 1);
      expect(NarrationDownloadStore.instance.isReady('news-wait-ok'), isTrue);

      n = 0;
      final pending = NarrationDownloadStore.instance.download(
        'news-wait-wipe',
        waitUntilReady: () async {
          started.complete();
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return true;
        },
      );
      await started.future;
      await NarrationDownloadStore.instance.wipe(['news-wait-wipe']);
      await pending;
      expect(n, 0);
      expect(NarrationDownloadStore.instance.isReady('news-wait-wipe'), isFalse);
    });

    test('wipe during 503 backoff does not retry', () async {
      var n = 0;
      final first = Completer<void>();
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        if (n == 1) {
          first.complete();
          return (status: 503, body: <int>[]);
        }
        return (status: 200, body: _ogg());
      };
      final pending = NarrationDownloadStore.instance.download('news-bo');
      await first.future;
      await NarrationDownloadStore.instance.wipe(['news-bo']);
      await pending;
      expect(n, 1);
      expect(NarrationDownloadStore.instance.isReady('news-bo'), isFalse);
    });

    test('trims ids, persists index, and rehydrates ready files', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        expect(url, contains(Uri.encodeComponent('news-ws')));
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('  news-ws  ');
      expect(NarrationDownloadStore.instance.isReady('news-ws'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('narration.downloaded_ids'),
        contains('news-ws'),
      );
      NarrationDownloadStore.instance.resetForTest();
      NarrationDownloadStore.debugRootOverride = tmp;
      await NarrationDownloadStore.instance.hydrate();
      expect(NarrationDownloadStore.instance.isReady('news-ws'), isTrue);
      expect(
        await NarrationDownloadStore.instance.hasPlayableFile('news-ws'),
        isTrue,
      );
    });

    test('hydrate drops corrupt on-disk opus and re-download replaces it',
        () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('corrupt');
      final file = NarrationDownloadStore.instance.localFile('corrupt')!;
      await file.writeAsBytes(List<int>.filled(400, 9), flush: true);
      NarrationDownloadStore.instance.resetForTest();
      NarrationDownloadStore.debugRootOverride = tmp;
      await NarrationDownloadStore.instance.hydrate();
      expect(NarrationDownloadStore.instance.isReady('corrupt'), isFalse);
      await NarrationDownloadStore.instance.download('corrupt');
      expect(NarrationDownloadStore.instance.isReady('corrupt'), isTrue);
    });

    test('index-ready but truncated file is not playable and re-fetches',
        () async {
      var n = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('trunc');
      expect(n, 1);
      final file = NarrationDownloadStore.instance.localFile('trunc')!;
      await file.writeAsBytes(_ogg(extra: 10), flush: true);
      expect(NarrationDownloadStore.instance.isReady('trunc'), isTrue);
      expect(
        await NarrationDownloadStore.instance.hasPlayableFile('trunc'),
        isFalse,
      );
      await NarrationDownloadStore.instance.download('trunc');
      expect(n, 2);
      expect(
        await NarrationDownloadStore.instance.hasPlayableFile('trunc'),
        isTrue,
      );
    });

    test('parallel downloads of different ids both complete', () async {
      var n = 0;
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        n += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return (status: 200, body: _ogg());
      };
      await Future.wait([
        NarrationDownloadStore.instance.download('alpha'),
        NarrationDownloadStore.instance.download('beta'),
      ]);
      expect(n, 2);
      expect(NarrationDownloadStore.instance.isReady('alpha'), isTrue);
      expect(NarrationDownloadStore.instance.isReady('beta'), isTrue);
    });

    test('pruneTo empty live set wipes all; pruneTo all live is a no-op',
        () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg());
      };
      await NarrationDownloadStore.instance.download('keep-a');
      await NarrationDownloadStore.instance.download('keep-b');
      await NarrationDownloadStore.instance.pruneTo({'keep-a', 'keep-b'});
      expect(NarrationDownloadStore.instance.isReady('keep-a'), isTrue);
      expect(NarrationDownloadStore.instance.isReady('keep-b'), isTrue);
      await NarrationDownloadStore.instance.pruneTo(<String>{});
      expect(NarrationDownloadStore.instance.isReady('keep-a'), isFalse);
      expect(NarrationDownloadStore.instance.isReady('keep-b'), isFalse);
    });

    test('wipe unknown or empty ids does not throw', () async {
      await NarrationDownloadStore.instance.wipe(const <String>[]);
      await NarrationDownloadStore.instance.wipe(['never-there', '  ']);
      expect(NarrationDownloadStore.instance.isReady('never-there'), isFalse);
    });

    test('widget-test binding skips network without debugGetBytes', () async {
      NarrationDownloadStore.debugGetBytes = null;
      await NarrationDownloadStore.instance.download('no-net');
      expect(NarrationDownloadStore.instance.isReady('no-net'), isFalse);
    });

    test('exact min-size ogg is accepted; empty 200 is rejected', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg(extra: 252));
      };
      await NarrationDownloadStore.instance.download('min-ok');
      expect(NarrationDownloadStore.instance.isReady('min-ok'), isTrue);

      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: <int>[]);
      };
      await NarrationDownloadStore.instance.download('empty-body');
      expect(NarrationDownloadStore.instance.isReady('empty-body'), isFalse);
    });

    test('localFile is null for empty id and hasPlayableFile is false',
        () async {
      expect(NarrationDownloadStore.instance.localFile(''), isNull);
      expect(NarrationDownloadStore.instance.localFile('   '), isNull);
      expect(
        await NarrationDownloadStore.instance.hasPlayableFile('missing'),
        isFalse,
      );
      expect(
        NarrationDownloadStore.instance.progressOf('unknown').phase,
        NarrationDownloadPhase.idle,
      );
    });

    test('uuid article ids stay unique on disk', () async {
      NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
        return (status: 200, body: _ogg());
      };
      const a = 'news-550e8400-e29b-41d4-a716-446655440000';
      const b = 'news-550e8400-e29b-41d4-a716-446655440001';
      await NarrationDownloadStore.instance.download(a);
      await NarrationDownloadStore.instance.download(b);
      expect(
        NarrationDownloadStore.instance.localFile(a)!.path,
        isNot(NarrationDownloadStore.instance.localFile(b)!.path),
      );
      expect(await NarrationDownloadStore.instance.hasPlayableFile(a), isTrue);
      expect(await NarrationDownloadStore.instance.hasPlayableFile(b), isTrue);
    });
  });
}
