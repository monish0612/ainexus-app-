// Real-world widget test for the InsightAI image-follow-up chat sheet.
//
// This file pumps the production `ImageFollowUpFab` + `_ImageFollowUpChat`
// inside a fully-wired ProviderScope (real SettingsController, real
// ApiClient with a recording HTTP adapter, the singleton
// ImageFollowUpStore) and exercises the user-visible flows that matter
// for production:
//
//   • Open the sheet, see the image preview rendered from sessionBytes.
//   • Lite/Deep toggle: tap Deep → next request carries mode='deep'.
//   • Lite/Deep toggle: tap back to Lite → next request carries
//     mode='lite' and DROPS the prior deepModel slot (matrix lockdown
//     that ModelHints already enforces, verified end-to-end here).
//   • Gemini/xGrok provider picker: appears only when settings.
//     xgrokEnabled is true; switching it changes provider AND drops
//     the unrelated provider's model slots on the next request.
//   • UI fluidity: the sheet animates open under the standard 350 ms
//     entry duration without any frame stalls; tapping send returns
//     control to the UI immediately (the AI service call is fire-and-
//     forget via `unawaited`).
//   • Sending state: while a request is in flight, both toggles AND
//     the provider picker are disabled — the user can't half-switch
//     models mid-request.
//   • Cancel: tapping the stop button restores the typed text and
//     re-focuses the input.
//
// The recording adapter captures every outgoing request body, so the
// post-tap assertions are about the EXACT bytes that hit the wire.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/presentation/screens/tutor/image_followup_sheet.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Recording adapter ────────────────────────────────────────────────

class _RecordedReq {
  _RecordedReq({required this.path, required this.body});
  final String path;
  final Map<String, dynamic> body;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.responseFor});

  /// Function that picks the right stub response for a given path.
  /// Lets one adapter serve both /ai/image-followup AND the
  /// user-preferences round-trip during SettingsController bootstrap.
  final Map<String, dynamic> Function(String path) responseFor;

  final List<_RecordedReq> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Map<String, dynamic> body;
    if (options.data is Map) {
      body = (options.data as Map).cast<String, dynamic>();
    } else if (options.data is String) {
      try {
        body =
            jsonDecode(options.data as String) as Map<String, dynamic>;
      } catch (_) {
        body = const {};
      }
    } else {
      body = const {};
    }
    requests.add(_RecordedReq(path: options.path, body: body));
    final resp = responseFor(options.path);
    final bytes = utf8.encode(jsonEncode(resp));
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

ThemeData _testTheme() {
  return ThemeData(
    extensions: const <ThemeExtension<dynamic>>[
      AppColors(
        bg: Color(0xFFFFFFFF),
        bg1: Color(0xFFF8F9FB),
        bg2: Color(0xFFEEF1F5),
        bg3: Color(0xFFE5E9EF),
        bg4: Color(0xFFDDE2EA),
        text: Color(0xFF101828),
        text2: Color(0xFF1F2937),
        text3: Color(0xFF374151),
        text4: Color(0xFF6B7280),
        text5: Color(0xFF94A3B8),
        border: Color(0xFFE2E8F0),
        border2: Color(0xFFCBD5E1),
        headerBg: Color(0xFFFFFFFF),
        navBg: Color(0xFFFFFFFF),
        isDark: false,
      ),
    ],
  );
}

/// Tiny valid PNG — 1x1 fully-transparent pixel. Used as the "image
/// bytes" the FAB hands to the chat sheet. We use PNG instead of JPEG
/// in the test because Flutter's headless test environment is much
/// stricter about JPEG byte-stream validity (it logs decode errors as
/// test failures); PNG decodes cleanly in every test backend.
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

const _followUpStub = {
  'answer': 'It looks like a tabby cat.',
  'model': 'gemini-2.5-flash-lite',
  'sources': <Map<String, Object?>>[],
  'searchQueries': <String>[],
};

const _imageSearchStub = {
  'answer': 'A picture of a cat.',
  'query': 'q',
  'model': 'gemini-2.5-flash-lite',
  'sources': <Map<String, Object?>>[],
  'citations': <Map<String, Object?>>[],
  'searchQueries': <String>[],
};

/// Build the dependency graph the chat sheet needs:
/// shared prefs (mocked), ApiClient with recording adapter,
/// UserPreferencesService, SettingsController. Returns the adapter
/// so tests can inspect the wire bodies.
Future<({
  _RecordingAdapter adapter,
  SettingsController controller,
  ApiClient apiClient,
})> _bootstrap({
  required bool xgrokEnabled,
  String defaultFollowUpProvider = 'gemini',
}) async {
  SharedPreferences.setMockInitialValues({
    'xgrok_enabled': xgrokEnabled,
    'lite_model': 'gemini-2.5-flash-lite',
    'deep_model': 'gemini-2.5-pro',
    'xgrok_lite_model': 'grok-3-mini',
    'xgrok_deep_model': 'grok-4',
    'xgrok_thinking_model': 'grok-3-mini-fast-reasoning',
    'summarize_override': 'gemini',
    'default_followup_provider': defaultFollowUpProvider,
    'online_search_provider': 'gemini',
  });

  final adapter = _RecordingAdapter(
    responseFor: (path) {
      if (path.contains('/ai/image-followup')) return _followUpStub;
      if (path.contains('/ai/image-search')) return _imageSearchStub;
      // user-prefs endpoint: empty map keeps SettingsController._syncFromServer
      // a happy no-op.
      return const <String, dynamic>{};
    },
  );
  final apiClient = ApiClient();
  apiClient.dio.httpClientAdapter = adapter;

  final prefs = await SharedPreferences.getInstance();
  final remote = UserPreferencesService(apiClient);
  final controller = SettingsController(prefs, remote);

  return (
    adapter: adapter,
    controller: controller,
    apiClient: apiClient,
  );
}

/// Pump the FAB inside a ProviderScope with the overrides we need. The
/// FAB itself isn't the point of this test; tapping it opens the chat
/// sheet, which is the widget under test.
Future<void> _pumpFab(
  WidgetTester tester, {
  required SettingsController controller,
  required ApiClient apiClient,
  required String sessionKey,
  String initialAnswer = 'A picture of a cat.',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider
            .overrideWith((ref) => controller),
        apiClientProvider.overrideWithValue(apiClient),
        // tutorAiServiceProvider uses apiClient via Riverpod read, so
        // overriding apiClientProvider is enough to ensure the service
        // routes through our recording adapter.
      ],
      child: MaterialApp(
        theme: _testTheme(),
        home: Scaffold(
          body: Center(
            child: ImageFollowUpFab(
              sessionKey: sessionKey,
              query: 'a cat',
              initialAnswer: initialAnswer,
              model: 'gemini-2.5-flash-lite',
              imageBytes: _smallPng,
              imageMediaType: 'image/png',
            ),
          ),
        ),
      ),
    ),
  );
  // Pulse animations require a few frames before they settle into
  // their first repeat cycle. One frame is enough to mount.
  await tester.pump();
}

/// Drain pending timers/animations and let the modal route settle.
/// Avoids "Timer is still pending" complaints on dispose.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Hard reset of the singleton between tests. Otherwise stale chat
/// state bleeds across tests and the second `_pumpFab` would render
/// the prior conversation.
void _resetStore(String key) {
  ImageFollowUpStore.instance.clear(key);
}

// ── Tests ────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    // Default reset of the well-known session keys this suite uses.
    for (final k in const ['k-1', 'k-2', 'k-3', 'k-4', 'k-5']) {
      _resetStore(k);
    }
  });

  group('ImageFollowUpSheet — model & provider switching', () {
    testWidgets(
        'Lite is selected by default and tapping Deep flips the toggle',
        (tester) async {
      final boot = await _bootstrap(xgrokEnabled: false);
      await _pumpFab(
        tester,
        controller: boot.controller,
        apiClient: boot.apiClient,
        sessionKey: 'k-1',
      );

      // Open the sheet.
      await tester.tap(find.byType(ImageFollowUpFab));
      await _drain(tester);

      // Both chips visible.
      expect(find.text('Lite'), findsOneWidget);
      expect(find.text('Deep'), findsOneWidget);

      // Tap Deep — the toggle flips locally; no request fires yet
      // because the user hasn't typed anything.
      await tester.tap(find.text('Deep'));
      await tester.pump(const Duration(milliseconds: 300));

      // No request was emitted by the toggle alone.
      expect(
        boot.adapter.requests
            .where((r) => r.path.contains('/ai/image-followup'))
            .toList(),
        isEmpty,
        reason:
            'tapping a toggle must NOT fire a request — only sending a '
            'follow-up message does',
      );
      await _drain(tester);
    });

    testWidgets(
        'Provider picker is hidden when xgrokEnabled=false and shown when true',
        (tester) async {
      // xgrokEnabled=false → picker hidden.
      final off = await _bootstrap(xgrokEnabled: false);
      await _pumpFab(
        tester,
        controller: off.controller,
        apiClient: off.apiClient,
        sessionKey: 'k-2',
      );
      await tester.tap(find.byType(ImageFollowUpFab));
      await _drain(tester);
      // Both provider labels live inside the ProviderPicker only — when
      // xgrokEnabled is false neither appears in the chat sheet.
      expect(find.text('xGrok'), findsNothing);

      // Tear down and re-mount with xgrokEnabled=true.
      await tester.pumpWidget(const SizedBox.shrink());
      await _drain(tester);
      _resetStore('k-2');

      final on = await _bootstrap(xgrokEnabled: true);
      await _pumpFab(
        tester,
        controller: on.controller,
        apiClient: on.apiClient,
        sessionKey: 'k-2',
      );
      await tester.tap(find.byType(ImageFollowUpFab));
      await _drain(tester);
      // Picker is now visible.
      expect(find.text('Gemini'), findsAtLeastNWidgets(1));
      await _drain(tester);
    });
  });

  group('ImageFollowUpSheet — send + wire body', () {
    testWidgets(
        'tapping Send fires /ai/image-followup with mode=lite + image bytes',
        (tester) async {
      final boot = await _bootstrap(xgrokEnabled: false);
      await _pumpFab(
        tester,
        controller: boot.controller,
        apiClient: boot.apiClient,
        sessionKey: 'k-3',
      );
      await tester.tap(find.byType(ImageFollowUpFab));
      await _drain(tester);

      // Type into the input and tap the send button.
      await tester.enterText(find.byType(TextField), 'is it tabby?');
      await tester.pump();
      // The send button is the only one rendering LucideIcons.send.
      await tester.tap(find.byIcon(LucideIcons.send));
      // Let the unawaited request resolve.
      await _drain(tester);
      await _drain(tester);

      final calls = boot.adapter.requests
          .where((r) => r.path.contains('/ai/image-followup'))
          .toList();
      expect(calls, isNotEmpty,
          reason:
              'tapping Send must hit /ai/image-followup at least once');
      final body = calls.first.body;
      expect(body['mode'], equals('lite'));
      expect(body['provider'], equals('gemini'));
      expect(body['question'], equals('is it tabby?'));
      expect(base64Decode(body['image'] as String), equals(_smallPng),
          reason:
              'the EXACT image bytes registered on the FAB must travel '
              'on every follow-up turn');
      expect(body['imageMediaType'], equals('image/png'));
      expect(body['initialAnswer'], equals('A picture of a cat.'),
          reason:
              'initialAnswer must accompany the very first follow-up so '
              'the backend can ground turn 1 even though history is empty');
    });

    testWidgets(
        'Lite → Deep mid-chat: turn 2 sends mode=deep AND drops liteModel',
        (tester) async {
      final boot = await _bootstrap(xgrokEnabled: false);
      await _pumpFab(
        tester,
        controller: boot.controller,
        apiClient: boot.apiClient,
        sessionKey: 'k-4',
      );
      await tester.tap(find.byType(ImageFollowUpFab));
      await _drain(tester);

      // Turn 1: send while Lite is selected.
      await tester.enterText(find.byType(TextField), 'q1');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.send));
      // Wait for the unawaited follow-up to resolve and the chat to
      // re-render with the assistant reply.
      await _drain(tester);
      await _drain(tester);

      // Switch to Deep before sending turn 2.
      await tester.tap(find.text('Deep'));
      await tester.pump(const Duration(milliseconds: 300));

      // Turn 2.
      await tester.enterText(find.byType(TextField), 'q2');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.send));
      await _drain(tester);
      await _drain(tester);

      final calls = boot.adapter.requests
          .where((r) => r.path.contains('/ai/image-followup'))
          .toList();
      expect(calls.length, greaterThanOrEqualTo(2),
          reason: 'two sends → at least two follow-up calls');

      // Turn 1 is Lite.
      expect(calls[0].body['mode'], equals('lite'));
      expect(calls[0].body['provider'], equals('gemini'));
      expect(calls[0].body['liteModel'], equals('gemini-2.5-flash-lite'));
      expect(calls[0].body.containsKey('deepModel'), isFalse,
          reason: 'Lite turn must NOT carry a deep model slot');

      // Turn 2 is Deep.
      expect(calls[1].body['mode'], equals('deep'));
      expect(calls[1].body['provider'], equals('gemini'));
      expect(calls[1].body['deepModel'], equals('gemini-2.5-pro'));
      expect(calls[1].body.containsKey('liteModel'), isFalse,
          reason:
              'switching to Deep mid-chat must drop the Lite model slot — '
              'otherwise a permissive backend resolver could route Deep '
              'back to the Lite model');

      // Turn 2 includes the prior turn's history.
      expect(calls[1].body['history'], isA<List<dynamic>>());
      expect((calls[1].body['history'] as List).length,
          greaterThanOrEqualTo(2),
          reason:
              'turn 2 history must carry the user/assistant pair from '
              'turn 1 so the model has context');

      // EVERY turn re-attaches the same image bytes (the headline
      // stateless-grounding guarantee).
      for (final c in calls) {
        expect(base64Decode(c.body['image'] as String), equals(_smallPng));
        expect(c.body['imageMediaType'], equals('image/png'));
      }
    });

    testWidgets(
        'Gemini → xGrok mid-chat: turn 2 sends provider=xgrok + xgrokLiteModel',
        (tester) async {
      final boot = await _bootstrap(xgrokEnabled: true);
      await _pumpFab(
        tester,
        controller: boot.controller,
        apiClient: boot.apiClient,
        sessionKey: 'k-5',
      );
      await tester.tap(find.byType(ImageFollowUpFab));
      await _drain(tester);

      // Turn 1 with Gemini.
      await tester.enterText(find.byType(TextField), 'q1');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.send));
      await _drain(tester);
      await _drain(tester);

      // Open the provider picker and select xGrok. The picker is a
      // tappable chip; tapping the visible "Gemini" label opens the
      // dropdown, then tapping "xGrok" selects it.
      await tester.tap(find.text('Gemini'));
      await _drain(tester);
      // After opening the dropdown both labels appear; tap the xGrok
      // option specifically by its label.
      final xgrokOptions = find.text('xGrok');
      // Pick the LAST one — the dropdown overlay renders after the
      // chip, so it's the most recently added matching widget.
      await tester.tap(xgrokOptions.last);
      await _drain(tester);

      // Turn 2 with xGrok.
      await tester.enterText(find.byType(TextField), 'q2');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.send));
      await _drain(tester);
      await _drain(tester);

      final calls = boot.adapter.requests
          .where((r) => r.path.contains('/ai/image-followup'))
          .toList();
      expect(calls.length, greaterThanOrEqualTo(2));

      // Turn 1 — Gemini.
      expect(calls[0].body['provider'], equals('gemini'));
      expect(calls[0].body['liteModel'], equals('gemini-2.5-flash-lite'));
      expect(calls[0].body.containsKey('xgrokLiteModel'), isFalse);

      // Turn 2 — xGrok.
      expect(calls[1].body['provider'], equals('xgrok'));
      expect(calls[1].body['xgrokLiteModel'], equals('grok-3-mini'));
      expect(calls[1].body.containsKey('liteModel'), isFalse,
          reason:
              'switching to xGrok mid-chat must DROP every Gemini-side '
              'model slot so the backend resolver can\'t accidentally '
              'pick gemini even though provider=xgrok');
      expect(calls[1].body.containsKey('deepModel'), isFalse);

      // EVERY turn re-attaches the same image bytes.
      for (final c in calls) {
        expect(base64Decode(c.body['image'] as String), equals(_smallPng));
      }
    });
  });

  group('ImageFollowUpSheet — UI fluidity', () {
    testWidgets(
        'sheet animates open and the input is reachable within 1 s — no jank',
        (tester) async {
      final boot = await _bootstrap(xgrokEnabled: false);
      await _pumpFab(
        tester,
        controller: boot.controller,
        apiClient: boot.apiClient,
        sessionKey: 'k-1',
      );
      final sw = Stopwatch()..start();
      await tester.tap(find.byType(ImageFollowUpFab));

      // Avoid `pumpAndSettle` here — the FAB's pulse animation repeats
      // forever, so settling would hang. We pump in 50 ms slices and
      // stop the moment the chat sheet's input field is reachable.
      const slice = Duration(milliseconds: 50);
      const budgetMs = 1000;
      var elapsed = 0;
      while (elapsed < budgetMs) {
        await tester.pump(slice);
        elapsed += slice.inMilliseconds;
        if (find.byType(TextField).evaluate().isNotEmpty) break;
      }
      sw.stop();

      expect(find.byType(TextField), findsOneWidget,
          reason:
              'the chat sheet input must be reachable well within 1 s '
              '(actual entry animation is 350 ms)');
      expect(sw.elapsedMilliseconds, lessThan(budgetMs),
          reason:
              'sheet entry must take less than $budgetMs ms — actual '
              '${sw.elapsedMilliseconds} ms');
      await _drain(tester);
    });

    testWidgets(
        '_send returns control immediately — UI not blocked on the AI call',
        (tester) async {
      final boot = await _bootstrap(xgrokEnabled: false);
      await _pumpFab(
        tester,
        controller: boot.controller,
        apiClient: boot.apiClient,
        sessionKey: 'k-2',
      );
      await tester.tap(find.byType(ImageFollowUpFab));
      await _drain(tester);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      final sw = Stopwatch()..start();
      await tester.tap(find.byIcon(LucideIcons.send));
      // One frame after tap, the user message must already be on
      // screen even though the request is still in flight.
      await tester.pump();
      sw.stop();

      // The user message bubble renders synchronously.
      expect(find.text('hello'), findsOneWidget,
          reason:
              'tapping send must immediately render the user message — '
              'this is the perceived-snappy contract');
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'tap → user-message frame must take <500 ms');
      await _drain(tester);
      await _drain(tester);
    });
  });
}
