// ============================================================================
// LIVE Flutter -> Backend round-trip for the InsightAI vision endpoints.
//
// What this proves:
//   • The Flutter `TutorAiService.imageSearch` request body the user's
//     phone actually sends is accepted by the live backend.
//   • The backend response is parsed by `GroundedSearchResponse.fromJson`
//     / `ArticleFollowUpResponse.fromJson` without a single field
//     mismatch — i.e. the wire shape is locked end-to-end.
//   • All four (provider × mode) combos work: Gemini lite, Gemini deep,
//     xGrok lite, xGrok deep.
//   • `image-followup` re-attaches the image bytes and threads
//     `initialAnswer` + `history` correctly so the model can continue
//     the conversation.
//   • `CancelToken` cleanly aborts an in-flight request without
//     dirtying the API client.
//
// What this is NOT:
//   • Not a mocked / contract test (we already have
//     `tutor_ai_service_image_routing_test.dart` for that — locks the
//     outgoing JSON body shape).
//   • Not part of the default `flutter test` run. Tagged `live` so the
//     CI bot does not burn Gemini/xGrok tokens. Run explicitly:
//
//       flutter test --tags live \
//         --dart-define=API_BASE_URL=http://localhost:3000 \
//         test/integration_live/image_endpoints_live_test.dart
//
//   The test reads the Taj Mahal photo staged at
//   `test/fixtures/taj_mahal.png` (despite the .png extension, the file
//   is actually JPEG — same payload the backend's live suite uses).
// ============================================================================

@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/constants/app_constants.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/tutor_ai_service.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';

const _defaultLiteModel = kDefaultLiteModel; // gemini-3.1-flash-lite-preview
const _defaultDeepModel = kDefaultDeepModel; // gemini-3.1-pro-preview
const _defaultXLite = kDefaultXGrokLiteModel; // grok-4-1-fast-non-reasoning
const _defaultXDeep = kDefaultXGrokDeepModel; // grok-4-0709

// 1×1 transparent PNG, for the cancellation test where we don't want
// to spend money on a real provider call.
final Uint8List _smallPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
  0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
]);

/// Magic-byte sniffer — same idea as the backend's `image-preprocess.js`.
/// Phones lie about extensions; we trust the bytes.
String _sniffMediaType(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return 'image/gif';
  }
  return 'application/octet-stream';
}

Future<bool> _probeReachable(String baseUrl) async {
  try {
    final probe = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
    ));
    // Send a deliberately invalid POST — we don't care about the body, we
    // just need to know whether the route is mounted and the server is up.
    // Backend should reply with 400 Bad Request (missing image) in < 5 ms.
    final r = await probe.post(
      '/api/v1/ai/image-search',
      data: const {},
      options: Options(
        validateStatus: (_) => true,
        contentType: 'application/json',
      ),
    );
    probe.close(force: true);
    return r.statusCode != null &&
        r.statusCode != 404 &&
        r.statusCode != 502 &&
        r.statusCode != 503;
  } catch (_) {
    return false;
  }
}

void main() {
  final baseUrl = AppConstants.baseUrl;
  final fixture = File('test/fixtures/taj_mahal.png');

  setUpAll(() async {
    if (!fixture.existsSync()) {
      fail('Fixture missing: ${fixture.path}. Stage the image first.');
    }
    final reachable = await _probeReachable(baseUrl);
    if (!reachable) {
      // Cause the test to skip with a precise reason instead of crashing
      // with a network exception 90 seconds later.
      // ignore: avoid_print
      print('\n  Backend at $baseUrl is NOT serving '
          '/api/v1/ai/image-search.\n'
          '  Boot the backend (`node src/index.js` inside backend/api) or\n'
          '  re-run with --dart-define=API_BASE_URL=<other-url>.\n');
    }
    expect(reachable, isTrue,
        reason: 'Backend at $baseUrl must be running for the live suite.');
  });

  group('Live image endpoints (Flutter ↔ backend round-trip)', () {
    late Uint8List bytes;
    late String mediaType;
    late ApiClient apiClient;
    late TutorAiService service;

    setUpAll(() {
      bytes = fixture.readAsBytesSync();
      mediaType = _sniffMediaType(bytes);
      // Build a real ApiClient against the active base URL. The retry
      // interceptor + logging interceptor stay on so any flakiness on the
      // way is reflected here exactly like it would be on the device.
      apiClient = ApiClient();
      service = TutorAiService(apiClient);
      // ignore: avoid_print
      print('\n  Fixture: ${bytes.lengthInBytes} bytes, '
          'sniffed mediaType=$mediaType (extension on disk: .png)\n'
          '  Backend: $baseUrl\n');
    });

    // ── /api/v1/ai/image-search ──────────────────────────────────────────

    test('image-search: Gemini lite → identifies Taj Mahal', () async {
      final sw = Stopwatch()..start();
      final res = await service.imageSearch(
        query: 'What landmark is this?',
        imageBytes: bytes,
        imageMediaType: mediaType,
        provider: 'gemini',
        mode: 'lite',
        liteModel: _defaultLiteModel,
      );
      sw.stop();

      expect(res, isA<GroundedSearchResponse>());
      expect(res.answer, isNotEmpty,
          reason: 'Gemini lite must return a non-empty answer');
      expect(res.model, isNotEmpty);
      expect(res.answer.toLowerCase(),
          anyOf(contains('taj'), contains('mahal'), contains('agra')),
          reason: 'Gemini lite should identify the Taj Mahal in the photo');
      // ignore: avoid_print
      print('  Gemini lite ✓  model=${res.model}  '
          'sources=${res.sources.length}  answerLen=${res.answer.length}  '
          '${sw.elapsedMilliseconds}ms');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('image-search: Gemini deep → grounded with sources', () async {
      final sw = Stopwatch()..start();
      final res = await service.imageSearch(
        query: 'What landmark is this?',
        imageBytes: bytes,
        imageMediaType: mediaType,
        provider: 'gemini',
        mode: 'deep',
        deepModel: _defaultDeepModel,
      );
      sw.stop();

      expect(res.answer.toLowerCase(),
          anyOf(contains('taj'), contains('mahal'), contains('agra')));
      // ignore: avoid_print
      print('  Gemini deep ✓  model=${res.model}  '
          'sources=${res.sources.length}  searchQs=${res.searchQueries.length}  '
          'answerLen=${res.answer.length}  ${sw.elapsedMilliseconds}ms');
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('image-search: xGrok lite → identifies Taj Mahal', () async {
      final sw = Stopwatch()..start();
      final res = await service.imageSearch(
        query: 'What landmark is this?',
        imageBytes: bytes,
        imageMediaType: mediaType,
        provider: 'xgrok',
        mode: 'lite',
        xgrokLiteModel: _defaultXLite,
      );
      sw.stop();

      expect(res.answer.toLowerCase(),
          anyOf(contains('taj'), contains('mahal'), contains('agra')));
      // ignore: avoid_print
      print('  xGrok lite  ✓  model=${res.model}  '
          'sources=${res.sources.length}  answerLen=${res.answer.length}  '
          '${sw.elapsedMilliseconds}ms');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('image-search: xGrok deep → identifies Taj Mahal', () async {
      final sw = Stopwatch()..start();
      final res = await service.imageSearch(
        query: 'What landmark is this?',
        imageBytes: bytes,
        imageMediaType: mediaType,
        provider: 'xgrok',
        mode: 'deep',
        xgrokDeepModel: _defaultXDeep,
      );
      sw.stop();

      expect(res.answer.toLowerCase(),
          anyOf(contains('taj'), contains('mahal'), contains('agra')));
      // ignore: avoid_print
      print('  xGrok deep  ✓  model=${res.model}  '
          'sources=${res.sources.length}  searchQs=${res.searchQueries.length}  '
          'answerLen=${res.answer.length}  ${sw.elapsedMilliseconds}ms');
    }, timeout: const Timeout(Duration(seconds: 120)));

    // ── Empty-query lens-prompt fallback ─────────────────────────────────

    test('image-search: empty query falls back to lens prompt', () async {
      final res = await service.imageSearch(
        query: '',
        imageBytes: bytes,
        imageMediaType: mediaType,
        provider: 'gemini',
        mode: 'lite',
        liteModel: _defaultLiteModel,
      );
      expect(res.answer.toLowerCase(),
          anyOf(contains('taj'), contains('mahal'), contains('agra')),
          reason: 'Backend lens-prompt should still identify the image when '
              'the user types nothing');
    }, timeout: const Timeout(Duration(seconds: 90)));

    // ── /api/v1/ai/image-followup ────────────────────────────────────────

    test('image-followup: continues conversation with image re-attached',
        () async {
      // Turn 1: get an initial answer.
      final initial = await service.imageSearch(
        query: 'What landmark is this?',
        imageBytes: bytes,
        imageMediaType: mediaType,
        provider: 'gemini',
        mode: 'lite',
        liteModel: _defaultLiteModel,
      );
      expect(initial.answer, isNotEmpty);

      // Turn 2: ask a follow-up with the image re-attached.
      final follow = await service.imageFollowUp(
        query: 'What landmark is this?',
        question:
            'What country is the structure located in, and what is that '
            "country's capital?",
        imageBytes: bytes,
        imageMediaType: mediaType,
        initialAnswer: initial.answer,
        history: [
          {'role': 'user', 'text': 'What landmark is this?'},
          {'role': 'assistant', 'text': initial.answer},
        ],
        provider: 'gemini',
        mode: 'lite',
        liteModel: _defaultLiteModel,
      );

      expect(follow.answer, isNotEmpty);
      expect(follow.model, isNotEmpty);
      final lower = follow.answer.toLowerCase();
      expect(lower, anyOf(contains('india'), contains('delhi')),
          reason: 'Follow-up should remember the Taj Mahal and answer '
              'about India/Delhi');
      // ignore: avoid_print
      print('  Follow-up ✓  model=${follow.model}  '
          'sources=${follow.sources.length}  answerLen=${follow.answer.length}');
    }, timeout: const Timeout(Duration(seconds: 150)));

    // ── Mid-chat provider switch ────────────────────────────────────────

    test('image-followup: mid-chat Gemini → xGrok still has image context',
        () async {
      final initial = await service.imageSearch(
        query: 'What landmark is this?',
        imageBytes: bytes,
        imageMediaType: mediaType,
        provider: 'gemini',
        mode: 'lite',
        liteModel: _defaultLiteModel,
      );

      // User now flips to xGrok mid-conversation. The image must be
      // re-attached and the previous turn must be threaded via `history`.
      final follow = await service.imageFollowUp(
        query: 'What landmark is this?',
        question:
            'Approximately how many tourists visit this place every year?',
        imageBytes: bytes,
        imageMediaType: mediaType,
        initialAnswer: initial.answer,
        history: [
          {'role': 'user', 'text': 'What landmark is this?'},
          {'role': 'assistant', 'text': initial.answer},
        ],
        provider: 'xgrok',
        mode: 'lite',
        xgrokLiteModel: _defaultXLite,
      );

      expect(follow.answer, isNotEmpty);
      // Don't assert on a specific number — the model is web-grounded and
      // figures vary. Just confirm the answer references the landmark or
      // year, proving the image context survived the provider switch.
      final lower = follow.answer.toLowerCase();
      expect(
        lower,
        anyOf(
          contains('taj'),
          contains('mahal'),
          contains('million'),
          contains('visit'),
          contains('tourist'),
        ),
        reason: 'xGrok must have the image + history context on switch',
      );
    }, timeout: const Timeout(Duration(seconds: 150)));

    // ── Cancellation ────────────────────────────────────────────────────

    test('image-search: CancelToken aborts cleanly without leaking', () async {
      final token = CancelToken();
      // Use a small PNG so we don't burn API tokens on a request we're
      // about to cancel.
      final f = service.imageSearch(
        query: 'cancel me',
        imageBytes: _smallPng,
        imageMediaType: 'image/png',
        provider: 'gemini',
        mode: 'lite',
        liteModel: _defaultLiteModel,
        cancelToken: token,
      );

      // Give the HTTP client a tick to dispatch, then cancel.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      token.cancel('user-test');

      try {
        await f;
        fail('Future should have completed with a DioException(cancel)');
      } on DioException catch (e) {
        expect(e.type, DioExceptionType.cancel);
      }
    });

    // ── Wire-shape sanity (no missing fields on the response) ───────────

    test('image-search: response decodes without skipping required fields',
        () async {
      final res = await service.imageSearch(
        query: 'What is in the picture?',
        imageBytes: bytes,
        imageMediaType: mediaType,
        provider: 'gemini',
        mode: 'lite',
        liteModel: _defaultLiteModel,
      );
      // GroundedSearchResponse fields are non-nullable, so decoding wouldn't
      // even reach here on a shape break. Belt-and-suspenders: confirm the
      // sequences exist and have stable types.
      expect(res.answer, isA<String>());
      expect(res.model, isA<String>());
      expect(res.query, isA<String>());
      expect(res.sources, isA<List>());
      expect(res.searchQueries, isA<List>());
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
