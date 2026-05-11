// Wire-shape lockdown for `TutorAiService.imageSearch` and
// `TutorAiService.imageFollowUp`.
//
// The InsightAI image flow lets the user freely combine:
//   • mode      — Lite | Deep
//   • provider  — Gemini | xGrok
// and switch them mid-chat. The backend is stateless, so we re-attach
// the image bytes + full chat history to EVERY request. This file
// drives the production `TutorAiService` (not a fake) through every
// cell of the 2×2 matrix and captures the actual outgoing JSON via a
// recording HTTP adapter — the strongest possible "this is what gets
// sent" guarantee.
//
// What this locks down:
//
//   1.  Lite + Gemini  → mode=lite,  provider=gemini, liteModel kept,
//                        xgrok* dropped.
//   2.  Deep + Gemini  → mode=deep,  provider=gemini, deepModel kept,
//                        liteModel + xgrok* dropped.
//   3.  Lite + xGrok   → mode=lite,  provider=xgrok,  xgrokLiteModel
//                        kept, gemini-side fields dropped.
//   4.  Deep + xGrok   → mode=deep,  provider=xgrok,  xgrokDeepModel
//                        kept, gemini-side fields dropped.
//   5.  Image bytes + media type ride on EVERY request.
//   6.  Chat history accumulates across consecutive follow-ups.
//   7.  Mid-chat model switching produces correctly-shaped wire bodies
//       on every turn — verifying the user can flip Lite↔Deep and
//       Gemini↔xGrok mid-conversation without losing grounding.
//   8.  initialAnswer is forwarded verbatim on the first follow-up and
//       OMITTED when empty (legacy compatibility).
//
// The recording adapter NEVER hits the network; every test is fully
// hermetic and runs in <100 ms.

import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/tutor_ai_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Recording adapter ────────────────────────────────────────────────

class _RecordedRequest {
  _RecordedRequest({
    required this.path,
    required this.body,
  });
  final String path;
  final Map<String, dynamic> body;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.responseJson);

  /// Body sent back to the client for EVERY request. Tests are about
  /// what we put on the wire, not about reading the response.
  final Map<String, dynamic> responseJson;

  final List<_RecordedRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw = options.data;
    Map<String, dynamic> decoded;
    if (raw is Map) {
      decoded = raw.cast<String, dynamic>();
    } else if (raw is String) {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } else {
      decoded = const <String, dynamic>{};
    }
    requests.add(_RecordedRequest(
      path: options.path,
      body: decoded,
    ));
    final bytes = utf8.encode(jsonEncode(responseJson));
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ── Test fixtures ────────────────────────────────────────────────────

/// Tiny non-empty bytes used as the upload image in every test. The
/// service base64-encodes them, so we recover the original bytes by
/// base64-decoding `body['image']` to compare.
final Uint8List _fakeImage = Uint8List.fromList(
    List<int>.generate(2048, (i) => i & 0xFF));

/// Stub backend response — only the fields the entity decoders care
/// about. The tests don't read the response payload (they assert on
/// what was SENT), but the service still calls `fromJson` so a
/// well-formed stub is required.
final Map<String, dynamic> _stubImageSearchResponse = const {
  'answer': 'A picture of a cat sitting on a windowsill.',
  'query': 'what is in this image',
  'model': 'gemini-2.5-flash',
  'sources': <Map<String, Object?>>[],
  'citations': <Map<String, Object?>>[],
  'searchQueries': <String>[],
};

final Map<String, dynamic> _stubFollowUpResponse = const {
  'answer': 'Yes, it looks like a tabby.',
  'model': 'gemini-2.5-flash',
  'sources': <Map<String, Object?>>[],
  'searchQueries': <String>[],
};

/// Build a `TutorAiService` whose underlying Dio routes through a
/// recording adapter. The retry interceptor stays in the chain (this
/// is the same Dio config production uses), but the adapter always
/// returns 200 so the retry loop never fires.
({TutorAiService service, _RecordingAdapter adapter}) _buildService(
    Map<String, dynamic> responseJson) {
  final adapter = _RecordingAdapter(responseJson);
  final apiClient = ApiClient();
  apiClient.dio.httpClientAdapter = adapter;
  return (service: TutorAiService(apiClient), adapter: adapter);
}

// ── Tests ────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── imageSearch matrix ─────────────────────────────────────────────

  group('imageSearch wire shape', () {
    test('Lite + Gemini — keeps liteModel, drops deep + xgrok*', () async {
      final (:service, :adapter) = _buildService(_stubImageSearchResponse);
      await service.imageSearch(
        query: 'what is this',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        provider: null,
        mode: 'lite',
        liteModel: 'gemini-2.5-flash-lite',
        // Defensive: pass garbage in the unused slots and verify the
        // builder drops it cleanly. This is the exact safety net that
        // protects "Lite Gemini accidentally invokes Deep model".
        deepModel: 'gemini-2.5-flash-deep',
        xgrokLiteModel: 'grok-3-mini',
        xgrokDeepModel: 'grok-4',
        xgrokThinkingModel: 'grok-3-mini-fast-reasoning',
      );
      expect(adapter.requests, hasLength(1));
      final body = adapter.requests.single.body;
      expect(adapter.requests.single.path, contains('/ai/image-search'));
      expect(body['mode'], equals('lite'));
      expect(body['provider'], equals('gemini'));
      expect(body['liteModel'], equals('gemini-2.5-flash-lite'));
      expect(body.containsKey('deepModel'), isFalse,
          reason: 'Deep slot must never travel with a Lite request');
      expect(body.containsKey('xgrokLiteModel'), isFalse);
      expect(body.containsKey('xgrokDeepModel'), isFalse);
      expect(body.containsKey('xgrokThinkingModel'), isFalse);
      expect(body.containsKey('xgrokModel'), isFalse);
    });

    test('Deep + Gemini — keeps deepModel, drops lite + xgrok*', () async {
      final (:service, :adapter) = _buildService(_stubImageSearchResponse);
      await service.imageSearch(
        query: 'identify this',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        mode: 'deep',
        deepModel: 'gemini-2.5-pro',
        liteModel: 'should-be-dropped',
        xgrokDeepModel: 'should-be-dropped-too',
      );
      final body = adapter.requests.single.body;
      expect(body['mode'], equals('deep'));
      expect(body['provider'], equals('gemini'));
      expect(body['deepModel'], equals('gemini-2.5-pro'));
      expect(body.containsKey('liteModel'), isFalse);
      expect(body.containsKey('xgrokDeepModel'), isFalse);
    });

    test('Lite + xGrok — keeps xgrokLiteModel, drops gemini-side fields',
        () async {
      final (:service, :adapter) = _buildService(_stubImageSearchResponse);
      await service.imageSearch(
        query: 'what is this',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        provider: 'xgrok',
        mode: 'lite',
        xgrokLiteModel: 'grok-3-mini',
        // Garbage in the dropped slots:
        deepModel: 'should-be-dropped',
        liteModel: 'should-also-be-dropped',
      );
      final body = adapter.requests.single.body;
      expect(body['mode'], equals('lite'));
      expect(body['provider'], equals('xgrok'));
      expect(body['xgrokLiteModel'], equals('grok-3-mini'));
      expect(body.containsKey('deepModel'), isFalse);
      expect(body.containsKey('liteModel'), isFalse);
      expect(body.containsKey('xgrokDeepModel'), isFalse);
      expect(body.containsKey('xgrokThinkingModel'), isFalse);
    });

    test('Deep + xGrok — keeps xgrokDeepModel, drops gemini-side fields',
        () async {
      final (:service, :adapter) = _buildService(_stubImageSearchResponse);
      await service.imageSearch(
        query: 'identify',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        provider: 'xgrok',
        mode: 'deep',
        xgrokDeepModel: 'grok-4',
        // Garbage in the dropped slots:
        deepModel: 'should-be-dropped',
        liteModel: 'should-be-dropped',
        xgrokLiteModel: 'should-be-dropped',
      );
      final body = adapter.requests.single.body;
      expect(body['mode'], equals('deep'));
      expect(body['provider'], equals('xgrok'));
      expect(body['xgrokDeepModel'], equals('grok-4'));
      expect(body.containsKey('deepModel'), isFalse);
      expect(body.containsKey('liteModel'), isFalse);
      expect(body.containsKey('xgrokLiteModel'), isFalse);
    });

    test('image bytes are base64-encoded and present on every shape',
        () async {
      for (final shape in const <Map<String, Object?>>[
        {'mode': 'lite', 'provider': null},
        {'mode': 'deep', 'provider': null},
        {'mode': 'lite', 'provider': 'xgrok'},
        {'mode': 'deep', 'provider': 'xgrok'},
      ]) {
        final (:service, :adapter) =
            _buildService(_stubImageSearchResponse);
        await service.imageSearch(
          query: 'q',
          imageBytes: _fakeImage,
          imageMediaType: 'image/webp',
          mode: shape['mode'] as String?,
          provider: shape['provider'] as String?,
        );
        final body = adapter.requests.single.body;
        expect(body['imageMediaType'], equals('image/webp'),
            reason: 'media type must survive every shape');
        final b64 = body['image'] as String;
        expect(base64Decode(b64), equals(_fakeImage),
            reason: 'bytes must round-trip byte-for-byte for shape $shape');
      }
    });

    test('all six common media types ride through unchanged', () async {
      for (final m in const <String>[
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/heic',
        'image/gif',
        'image/bmp',
      ]) {
        final (:service, :adapter) =
            _buildService(_stubImageSearchResponse);
        await service.imageSearch(
          query: 'q',
          imageBytes: _fakeImage,
          imageMediaType: m,
        );
        expect(adapter.requests.single.body['imageMediaType'], equals(m),
            reason: 'media type "$m" must travel verbatim');
      }
    });
  });

  // ── imageFollowUp matrix ───────────────────────────────────────────

  group('imageFollowUp wire shape', () {
    test('Lite + Gemini follow-up keeps liteModel and drops others',
        () async {
      final (:service, :adapter) = _buildService(_stubFollowUpResponse);
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'is it tabby?',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        initialAnswer: 'A picture of a cat',
        history: const [
          {'role': 'user', 'text': 'is it tabby?'},
        ],
        mode: 'lite',
        liteModel: 'gemini-2.5-flash-lite',
        // Garbage in the dropped slots:
        deepModel: 'should-be-dropped',
        xgrokLiteModel: 'should-be-dropped',
      );
      final body = adapter.requests.single.body;
      expect(adapter.requests.single.path, contains('/ai/image-followup'));
      expect(body['mode'], equals('lite'));
      expect(body['provider'], equals('gemini'));
      expect(body['liteModel'], equals('gemini-2.5-flash-lite'));
      expect(body['initialAnswer'], equals('A picture of a cat'),
          reason:
              'initialAnswer must be forwarded so the backend can ground turn #1 '
              'even when history is empty');
      expect(body['question'], equals('is it tabby?'));
      expect(body['history'], isA<List<dynamic>>());
      expect((body['history'] as List), hasLength(1));
      expect(body.containsKey('deepModel'), isFalse);
      expect(body.containsKey('xgrokLiteModel'), isFalse);
    });

    test('Deep + Gemini follow-up keeps deepModel', () async {
      final (:service, :adapter) = _buildService(_stubFollowUpResponse);
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'what breed?',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        initialAnswer: 'A cat',
        mode: 'deep',
        deepModel: 'gemini-2.5-pro',
      );
      final body = adapter.requests.single.body;
      expect(body['mode'], equals('deep'));
      expect(body['provider'], equals('gemini'));
      expect(body['deepModel'], equals('gemini-2.5-pro'));
      expect(body.containsKey('liteModel'), isFalse);
    });

    test('Lite + xGrok follow-up keeps xgrokLiteModel', () async {
      final (:service, :adapter) = _buildService(_stubFollowUpResponse);
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'context?',
        imageBytes: _fakeImage,
        imageMediaType: 'image/png',
        initialAnswer: 'a tabby cat',
        provider: 'xgrok',
        mode: 'lite',
        xgrokLiteModel: 'grok-3-mini',
      );
      final body = adapter.requests.single.body;
      expect(body['mode'], equals('lite'));
      expect(body['provider'], equals('xgrok'));
      expect(body['xgrokLiteModel'], equals('grok-3-mini'));
      expect(body.containsKey('deepModel'), isFalse);
      expect(body.containsKey('liteModel'), isFalse);
    });

    test('Deep + xGrok follow-up keeps xgrokDeepModel', () async {
      final (:service, :adapter) = _buildService(_stubFollowUpResponse);
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'why?',
        imageBytes: _fakeImage,
        imageMediaType: 'image/png',
        initialAnswer: 'a tabby cat',
        provider: 'xgrok',
        mode: 'deep',
        xgrokDeepModel: 'grok-4',
      );
      final body = adapter.requests.single.body;
      expect(body['mode'], equals('deep'));
      expect(body['provider'], equals('xgrok'));
      expect(body['xgrokDeepModel'], equals('grok-4'));
      expect(body.containsKey('deepModel'), isFalse);
      expect(body.containsKey('xgrokLiteModel'), isFalse);
    });

    test('initialAnswer is omitted when empty (legacy compatibility)',
        () async {
      final (:service, :adapter) = _buildService(_stubFollowUpResponse);
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'q',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        initialAnswer: '',
        mode: 'lite',
      );
      final body = adapter.requests.single.body;
      expect(body.containsKey('initialAnswer'), isFalse,
          reason:
              'empty initialAnswer must NOT be forwarded — that\'s the '
              'pre-initialAnswer legacy behaviour older backend builds '
              'still rely on');
    });

    test(
        'image bytes + history travel on every shape — the core re-attach '
        'guarantee for stateless backend grounding', () async {
      final history = <Map<String, String>>[
        {'role': 'user', 'text': 'what breed?'},
        {'role': 'assistant', 'text': 'a tabby cat'},
        {'role': 'user', 'text': 'how old?'},
      ];
      for (final shape in const <Map<String, Object?>>[
        {'mode': 'lite', 'provider': null},
        {'mode': 'deep', 'provider': null},
        {'mode': 'lite', 'provider': 'xgrok'},
        {'mode': 'deep', 'provider': 'xgrok'},
      ]) {
        final (:service, :adapter) =
            _buildService(_stubFollowUpResponse);
        await service.imageFollowUp(
          query: 'image analysis',
          question: 'how old?',
          imageBytes: _fakeImage,
          imageMediaType: 'image/jpeg',
          history: history,
          initialAnswer: 'a tabby cat',
          mode: shape['mode'] as String?,
          provider: shape['provider'] as String?,
        );
        final body = adapter.requests.single.body;
        expect(base64Decode(body['image'] as String), equals(_fakeImage),
            reason:
                'image bytes must accompany every follow-up turn, regardless '
                'of mode/provider (shape=$shape)');
        expect(body['imageMediaType'], equals('image/jpeg'));
        expect(body['history'], isA<List<dynamic>>());
        expect((body['history'] as List), hasLength(3));
      }
    });
  });

  // ── Real-world model-switch sequence (the headline scenario) ───────
  //
  // Drive a chain of follow-ups against the SAME image with the user
  // flipping toggles between turns: Lite+Gemini → Deep+Gemini →
  // Lite+xGrok → Deep+xGrok. Verifies that each request body carries
  // (1) the correct mode/provider, (2) the correct model slot, and
  // (3) the cumulative history.

  group('mid-chat model switching', () {
    test(
        'four-turn switch chain (Lite/Gemini → Deep/Gemini → Lite/xGrok → '
        'Deep/xGrok) produces correctly-shaped wire bodies on every turn',
        () async {
      final (:service, :adapter) = _buildService(_stubFollowUpResponse);

      // The chat sheet maintains this list in production. We grow it
      // by hand between turns so the test mirrors the real call site.
      final history = <Map<String, String>>[];

      // ── Turn 1: Lite + Gemini ─────────────────────────────────────
      history.add({'role': 'user', 'text': 'is it a cat?'});
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'is it a cat?',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        initialAnswer: 'A picture of a cat',
        history: List.of(history),
        mode: 'lite',
        liteModel: 'gemini-2.5-flash-lite',
      );
      history.add({'role': 'assistant', 'text': 'yes, a tabby cat'});

      // ── Turn 2: Deep + Gemini ─────────────────────────────────────
      history.add({'role': 'user', 'text': 'estimate its age'});
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'estimate its age',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        initialAnswer: 'A picture of a cat',
        history: List.of(history),
        mode: 'deep',
        deepModel: 'gemini-2.5-pro',
      );
      history.add({'role': 'assistant', 'text': 'about 2 years old'});

      // ── Turn 3: Lite + xGrok ──────────────────────────────────────
      history.add({'role': 'user', 'text': 'is it healthy?'});
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'is it healthy?',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        initialAnswer: 'A picture of a cat',
        history: List.of(history),
        provider: 'xgrok',
        mode: 'lite',
        xgrokLiteModel: 'grok-3-mini',
      );
      history.add({'role': 'assistant', 'text': 'appears healthy'});

      // ── Turn 4: Deep + xGrok ──────────────────────────────────────
      history.add({'role': 'user', 'text': 'what breed exactly?'});
      await service.imageFollowUp(
        query: 'image analysis',
        question: 'what breed exactly?',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        initialAnswer: 'A picture of a cat',
        history: List.of(history),
        provider: 'xgrok',
        mode: 'deep',
        xgrokDeepModel: 'grok-4',
      );

      expect(adapter.requests, hasLength(4),
          reason: 'four turns must produce four wire calls');

      // Assertions — one per turn.

      final t1 = adapter.requests[0].body;
      expect(t1['mode'], equals('lite'));
      expect(t1['provider'], equals('gemini'));
      expect(t1['liteModel'], equals('gemini-2.5-flash-lite'));
      expect(t1.containsKey('deepModel'), isFalse);
      expect(t1.containsKey('xgrokLiteModel'), isFalse);
      expect((t1['history'] as List), hasLength(1),
          reason:
              'turn 1 history is the user message only — no prior pairs');

      final t2 = adapter.requests[1].body;
      expect(t2['mode'], equals('deep'));
      expect(t2['provider'], equals('gemini'));
      expect(t2['deepModel'], equals('gemini-2.5-pro'));
      expect(t2.containsKey('liteModel'), isFalse,
          reason:
              'switching from Lite to Deep mid-chat must DROP the Lite '
              'model id — otherwise a permissive backend resolver could '
              'route Deep back to the Lite model');
      expect((t2['history'] as List), hasLength(3),
          reason: 'turn 2 history carries pair 1 + the new user message');

      final t3 = adapter.requests[2].body;
      expect(t3['mode'], equals('lite'));
      expect(t3['provider'], equals('xgrok'));
      expect(t3['xgrokLiteModel'], equals('grok-3-mini'));
      expect(t3.containsKey('deepModel'), isFalse,
          reason:
              'switching to xGrok must DROP every Gemini-side slot, '
              'otherwise a permissive backend resolver could pick '
              'gemini even though provider=xgrok');
      expect(t3.containsKey('liteModel'), isFalse);
      expect((t3['history'] as List), hasLength(5),
          reason: 'turn 3 history carries pairs 1+2 + the new user message');

      final t4 = adapter.requests[3].body;
      expect(t4['mode'], equals('deep'));
      expect(t4['provider'], equals('xgrok'));
      expect(t4['xgrokDeepModel'], equals('grok-4'));
      expect(t4.containsKey('xgrokLiteModel'), isFalse,
          reason:
              'switching from xGrok-Lite to xGrok-Deep must DROP the '
              'xGrok lite slot');
      expect((t4['history'] as List), hasLength(7),
          reason: 'turn 4 history carries pairs 1+2+3 + the new user message');

      // Cross-cutting: every turn carries the SAME image bytes (the
      // re-attach guarantee that lets a stateless backend still ground
      // the conversation correctly when the model changes).
      for (var i = 0; i < adapter.requests.length; i++) {
        final body = adapter.requests[i].body;
        expect(base64Decode(body['image'] as String), equals(_fakeImage),
            reason: 'turn ${i + 1} must re-attach the EXACT same image bytes');
        expect(body['imageMediaType'], equals('image/jpeg'),
            reason: 'media type must be stable across turns');
        expect(body['initialAnswer'], equals('A picture of a cat'),
            reason:
                'initialAnswer must persist across model switches — '
                'it anchors the entire conversation to the original answer');
      }
    });

    test(
        'reverse switch (Deep/xGrok → Lite/Gemini) also drops the prior '
        'slots — guards against asymmetric routing bugs', () async {
      final (:service, :adapter) = _buildService(_stubFollowUpResponse);

      // First turn: Deep + xGrok.
      await service.imageFollowUp(
        query: 'q',
        question: 'a',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        provider: 'xgrok',
        mode: 'deep',
        xgrokDeepModel: 'grok-4',
      );
      // Second turn: switch back to Lite + Gemini.
      await service.imageFollowUp(
        query: 'q',
        question: 'b',
        imageBytes: _fakeImage,
        imageMediaType: 'image/jpeg',
        history: const [
          {'role': 'user', 'text': 'a'},
          {'role': 'assistant', 'text': 'a-answer'},
        ],
        mode: 'lite',
        liteModel: 'gemini-2.5-flash-lite',
      );

      final t1 = adapter.requests[0].body;
      expect(t1['mode'], 'deep');
      expect(t1['provider'], 'xgrok');
      expect(t1['xgrokDeepModel'], 'grok-4');

      final t2 = adapter.requests[1].body;
      expect(t2['mode'], 'lite');
      expect(t2['provider'], 'gemini');
      expect(t2['liteModel'], 'gemini-2.5-flash-lite');
      expect(t2.containsKey('xgrokDeepModel'), isFalse,
          reason:
              'switching back to Gemini must DROP the xGrok deep slot from '
              'the prior turn');
      expect(t2.containsKey('xgrokLiteModel'), isFalse);
      expect(t2.containsKey('xgrokThinkingModel'), isFalse);
    });
  });
}
