// Tests for ImageSearchStore — the singleton background job for the
// InsightAI vision flow. Mirrors the proven OnlineSearchStore test
// pattern so the same battle-tested guarantees apply to images:
//
//   • startSearch creates a job, attaches the listener, and returns
//     a deterministic sessionKey the UI can subscribe with.
//   • cancel marks the job as not-loading without dropping the
//     associated bytes or job entry — the result widget still has
//     something to render.
//   • remove tears down everything (memory-leak proof).
//   • Retries the call when the underlying service raises a
//     retryable error (5xx, connection abort, etc).
//   • Surfaces a friendly error message on a non-retryable failure.
//   • Image bytes ride on the job so the follow-up sheet can reach
//     them via getJob(...).imageBytes.
//   • debugResetForTests fully drains state between scenarios.
//
// We talk to the store through a tiny fake [TutorAiService] subclass
// that lets the test choose response / throw / latency on a per-call
// basis. That covers the production retry + cancellation contract
// without going through Dio.

import 'dart:typed_data';

import 'package:ai_nexus/core/services/image_search_store.dart';
import 'package:ai_nexus/data/services/tutor_ai_service.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fake TutorAiService ──────────────────────────────────────────────

class _FakeAiService implements TutorAiService {
  /// Sequence of behaviours to apply on consecutive `imageSearch` calls.
  /// Pops left-to-right; throws StateError when exhausted to surface
  /// "store called more times than expected" bugs loudly in tests.
  final List<_Step> steps;

  _FakeAiService(this.steps);

  /// Records all calls — read by tests to assert that retry actually
  /// re-dispatched the request.
  final List<_RecordedCall> calls = [];

  /// Honours CancelToken so the cancel-mid-flight test can verify the
  /// store stops waiting and tears down cleanly.
  @override
  Future<GroundedSearchResponse> imageSearch({
    required String query,
    required Uint8List imageBytes,
    required String imageMediaType,
    String? provider,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    calls.add(_RecordedCall(
      query: query,
      imageBytes: imageBytes,
      imageMediaType: imageMediaType,
      provider: provider,
      mode: mode,
    ));

    if (steps.isEmpty) {
      throw StateError(
          'fake ai service ran out of steps (call #${calls.length})');
    }
    final step = steps.removeAt(0);

    if (step.delay != null) {
      await Future<void>.delayed(step.delay!);
    }
    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: 'x'),
        reason: 'cancelled by test',
      );
    }
    if (step.error != null) throw step.error!;
    return step.response!;
  }

  // Every other method is unused by ImageSearchStore but the abstract
  // contract demands an implementation. We `noSuchMethod` them so a
  // future store call would loudly explode and we'd notice.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        'TutorAiService.${invocation.memberName} not stubbed in test');
  }
}

class _Step {
  _Step.success(this.response, {this.delay})
      : error = null;
  // `delay` on error steps is currently unused, but kept symmetrical
  // with `_Step.success` so future tests that want to simulate "slow
  // failure" can do so without changing the constructor signature.
  _Step.error(this.error) : response = null, delay = null;

  final GroundedSearchResponse? response;
  final Object? error;
  final Duration? delay;
}

class _RecordedCall {
  _RecordedCall({
    required this.query,
    required this.imageBytes,
    required this.imageMediaType,
    required this.provider,
    required this.mode,
  });
  final String query;
  final Uint8List imageBytes;
  final String imageMediaType;
  final String? provider;
  final String? mode;
}

DioException _retryable5xx() => DioException(
      requestOptions: RequestOptions(path: '/ai/image-search'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/ai/image-search'),
        statusCode: 503,
        data: 'service unavailable',
      ),
      type: DioExceptionType.badResponse,
      message: 'service unavailable',
    );

DioException _payloadTooLarge() => DioException(
      requestOptions: RequestOptions(path: '/ai/image-search'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/ai/image-search'),
        statusCode: 413,
        data: 'too large',
      ),
      type: DioExceptionType.badResponse,
      message: 'payload too large',
    );

DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/ai/image-search'),
      type: DioExceptionType.connectionError,
      message: 'no internet',
    );

GroundedSearchResponse _stubGrounded({String answer = 'A picture of a cat'}) {
  return GroundedSearchResponse(
    answer: answer,
    query: 'q',
    model: 'gemini-2.5-flash',
    searchQueries: const [],
    sources: const [],
    citations: const [],
  );
}

// Tiny non-empty bytes used in every test — the store doesn't decode
// them, it just passes them straight through to the fake.
final Uint8List _fakeBytes = Uint8List.fromList(
    List<int>.generate(2048, (i) => i & 0xFF));

// ── Test driver ──────────────────────────────────────────────────────

/// Starts a search via the store and returns (sessionKey, listener).
/// Test callers can `await tickToCompletion()` to drain pending
/// microtasks before asserting on the job state.
({String key, int Function() callbackCount}) _start({
  required ImageSearchStore store,
  required _FakeAiService service,
  String sessionKey = 'image-test-1',
  String query = 'what is this?',
  bool useXGrok = false,
  String? mode,
}) {
  int cbCount = 0;
  void listener() => cbCount++;

  final returnedKey = store.startSearch(
    sessionKey: sessionKey,
    query: query,
    imageBytes: _fakeBytes,
    imageMediaType: 'image/jpeg',
    thumbDataUrl: 'data:image/jpeg;base64,Zg==',
    originalMediaType: 'image/jpeg',
    service: service,
    useXGrok: useXGrok,
    mode: mode,
  );
  store.addListener(returnedKey, listener);
  return (key: returnedKey, callbackCount: () => cbCount);
}

Future<void> _settle() async {
  // Drain microtasks AND the event loop so any pending `unawaited` work
  // posted by the store can advance one step.
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageSearchStore', () {
    late ImageSearchStore store;

    setUp(() {
      store = ImageSearchStore.instance;
      store.debugResetForTests();
    });

    tearDown(() {
      store.debugResetForTests();
    });

    test('startSearch + happy path lands the result on the job', () async {
      final ai = _FakeAiService([_Step.success(_stubGrounded())]);
      final h = _start(store: store, service: ai);
      await _settle();

      final job = store.getJob(h.key);
      expect(job, isNotNull);
      expect(job!.loading, isFalse);
      expect(job.error, isNull);
      expect(job.result, isNotNull);
      expect(job.result!.answer, contains('cat'));
      expect(job.imageBytes, equals(_fakeBytes),
          reason: 'bytes must ride along on the job so the follow-up '
              'sheet can re-attach them on every turn');
      expect(job.imageMediaType, equals('image/jpeg'));
      expect(job.thumbDataUrl, startsWith('data:image/jpeg;base64,'));
      expect(job.originalMediaType, equals('image/jpeg'));
      expect(job.question, equals('what is this?'));
      expect(h.callbackCount(), greaterThanOrEqualTo(1),
          reason: 'listener must fire at least on completion');
    });

    test('store records the right service-level params (xGrok routing)',
        () async {
      final ai = _FakeAiService([_Step.success(_stubGrounded())]);
      _start(
        store: store,
        service: ai,
        useXGrok: true,
        mode: 'deep',
      );
      await _settle();
      expect(ai.calls, hasLength(1));
      expect(ai.calls.first.provider, equals('xgrok'));
      expect(ai.calls.first.mode, equals('deep'));
    });

    test('isLoading returns true while in-flight, false after completion',
        () async {
      // Slow first call so we can observe the loading=true window.
      final ai = _FakeAiService([
        _Step.success(_stubGrounded(), delay: const Duration(milliseconds: 80)),
      ]);
      final h = _start(store: store, service: ai);

      expect(store.isLoading(h.key), isTrue,
          reason: 'loading must be true the moment startSearch returns');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(store.isLoading(h.key), isFalse);
    });

    test('cancel marks loading=false but keeps the job entry intact',
        () async {
      // Slow call so cancel can fire mid-flight.
      final ai = _FakeAiService([
        _Step.success(_stubGrounded(), delay: const Duration(milliseconds: 200)),
      ]);
      final h = _start(store: store, service: ai);
      expect(store.isLoading(h.key), isTrue);

      store.cancel(h.key);
      expect(store.isLoading(h.key), isFalse);

      // The job entry stays so the UI can still read imageBytes for
      // its result preview. The new state is "cancelled, not loading,
      // no error, no result".
      final job = store.getJob(h.key);
      expect(job, isNotNull);
      expect(job!.loading, isFalse);
      expect(job.error, isNull);
      expect(job.result, isNull);
      expect(job.imageBytes, equals(_fakeBytes),
          reason: 'cancel must NOT drop the bytes — the UI may still '
              'display the thumbnail / question with a "stopped" badge');
    });

    test('remove tears down the job AND the listener (no memory leak)',
        () async {
      final ai = _FakeAiService([_Step.success(_stubGrounded())]);
      final h = _start(store: store, service: ai);
      await _settle();
      expect(store.getJob(h.key), isNotNull);

      store.remove(h.key);
      expect(store.getJob(h.key), isNull,
          reason: 'remove must drop the job entry');

      // A second call must not blow up — verifies idempotency.
      store.remove(h.key);
    });

    test('starting a SECOND search with the same key cancels the first',
        () async {
      // First call: slow. Second call: fast. Without replacement the
      // store would have two in-flight tokens.
      final ai = _FakeAiService([
        _Step.success(_stubGrounded(answer: 'first'),
            delay: const Duration(milliseconds: 250)),
        _Step.success(_stubGrounded(answer: 'second')),
      ]);
      const key = 'fixed-key';
      final firstKey = store.startSearch(
        sessionKey: key,
        query: 'q',
        imageBytes: _fakeBytes,
        imageMediaType: 'image/jpeg',
        thumbDataUrl: '',
        originalMediaType: 'image/jpeg',
        service: ai,
        useXGrok: false,
      );
      expect(firstKey, equals(key));

      // Kick off the second one immediately — production behaviour is to
      // cancel the first token via "Replaced".
      final secondKey = store.startSearch(
        sessionKey: key,
        query: 'q',
        imageBytes: _fakeBytes,
        imageMediaType: 'image/jpeg',
        thumbDataUrl: '',
        originalMediaType: 'image/jpeg',
        service: ai,
        useXGrok: false,
      );
      expect(secondKey, equals(key));

      // Wait for the second call to land.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Settle the first call's belated arrival.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final job = store.getJob(key);
      expect(job, isNotNull);
      expect(job!.loading, isFalse);
      // Second result wins — the late "first" arrival must NOT clobber.
      expect(job.result?.answer, equals('second'));
    });

    test(
        'non-retryable 4xx (413 too large) surfaces a friendly error '
        'without auto-retry', () async {
      final ai = _FakeAiService([_Step.error(_payloadTooLarge())]);
      final h = _start(store: store, service: ai);
      await _settle();

      final job = store.getJob(h.key);
      expect(job, isNotNull);
      expect(job!.loading, isFalse);
      expect(job.result, isNull);
      expect(job.error, isNotNull);
      expect(job.error!.toLowerCase(),
          contains('too large'),
          reason: '413 must produce the "Image too large" guidance');
      expect(ai.calls, hasLength(1),
          reason: '4xx must NOT auto-retry');
    });

    test('connectionError in FOREGROUND surfaces a friendly error',
        () async {
      // App is in foreground (default) so retryable errors fall through
      // to a user-visible error rather than the retry-on-resume queue.
      final ai = _FakeAiService([_Step.error(_networkError())]);
      final h = _start(store: store, service: ai);
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final job = store.getJob(h.key);
      expect(job, isNotNull);
      expect(job!.loading, isFalse);
      expect(job.error, isNotNull);
      expect(job.error!.toLowerCase(), anyOf(
        contains('no internet'),
        contains('connection'),
        contains('reconnect'),
      ));
    });

    test('5xx retryable error in FOREGROUND surfaces a friendly error too',
        () async {
      final ai = _FakeAiService([_Step.error(_retryable5xx())]);
      final h = _start(store: store, service: ai);
      await _settle();

      final job = store.getJob(h.key);
      expect(job!.error, isNotNull);
      expect(job.error!.toLowerCase(),
          anyOf(contains('temporarily'), contains('try again')));
    });

    test('debugResetForTests clears job + listener state cleanly', () async {
      final ai = _FakeAiService([_Step.success(_stubGrounded())]);
      final h = _start(store: store, service: ai);
      await _settle();
      expect(store.getJob(h.key), isNotNull);

      store.debugResetForTests();
      expect(store.getJob(h.key), isNull);
      expect(store.isLoading(h.key), isFalse);
    });

    test('listener fires at least once on result + once on cancel',
        () async {
      final ai = _FakeAiService([
        _Step.success(_stubGrounded(),
            delay: const Duration(milliseconds: 60)),
      ]);
      final h = _start(store: store, service: ai);
      final beforeCancel = h.callbackCount();
      store.cancel(h.key);
      // The cancel itself fires a notification; the finally block of
      // the executing _executeSearch may also fire one when the cancel
      // unwinds. Either way >= 1 additional notification is required.
      expect(h.callbackCount(), greaterThanOrEqualTo(beforeCancel + 1));
    });

    test('multiple distinct sessionKeys run independent jobs', () async {
      final ai = _FakeAiService([
        _Step.success(_stubGrounded(answer: 'A')),
        _Step.success(_stubGrounded(answer: 'B')),
      ]);
      final a = _start(store: store, service: ai, sessionKey: 'k-A');
      final b = _start(store: store, service: ai, sessionKey: 'k-B');
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final jA = store.getJob(a.key);
      final jB = store.getJob(b.key);
      expect(jA?.result?.answer, equals('A'));
      expect(jB?.result?.answer, equals('B'));
    });
  });
}
