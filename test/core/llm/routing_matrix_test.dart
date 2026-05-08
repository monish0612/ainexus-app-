// Comprehensive end-to-end routing matrix.
//
// Exhaustively walks the (provider × mode × model-slot) cube the way the
// production app drives it: starting from a Settings snapshot, the test
// derives the same liteModel / deepModel / xgrok* values the UI call sites
// derive, and asserts the resulting wire body has EXACTLY the right model id
// for that route — and nothing else.
//
// Why this matters: this test is the safety net for the cross-cutting promise
// "Settings is the single source of truth". If a future refactor accidentally
// re-introduces a hardcoded model id, picks the wrong slot for a mode, or
// leaks an xGrok field into a Gemini call (or vice versa), this matrix
// catches it before it reaches the user.

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/llm/model_hints.dart';

class _Settings {
  const _Settings({
    required this.liteModel,
    required this.deepModel,
    required this.xgrokEnabled,
    required this.xgrokLiteModel,
    required this.xgrokDeepModel,
    required this.xgrokThinkingModel,
  });

  final String liteModel;
  final String deepModel;
  final bool xgrokEnabled;
  final String xgrokLiteModel;
  final String xgrokDeepModel;
  final String xgrokThinkingModel;
}

const _settingsAllConfigured = _Settings(
  liteModel: 'gemini-3.1-flash-lite-preview',
  deepModel: 'gemini-3.1-pro-preview',
  xgrokEnabled: true,
  xgrokLiteModel: 'grok-4-1-fast-non-reasoning',
  xgrokDeepModel: 'grok-4-0709',
  xgrokThinkingModel: 'grok-4-1-fast-reasoning',
);

/// Mirrors what every UI call site does:
///   - `mode` is `'deep'` if user toggled Deep, otherwise `'lite'`.
///   - When xGrok is the chosen provider, deep/lite Gemini slots are nulled.
///   - When Gemini is the chosen provider, all xGrok slots are nulled.
Map<String, dynamic> _wireBodyForCallSite({
  required _Settings settings,
  required bool useDeepModel,
  required bool useXGrok,
}) {
  final xgrokOn = settings.xgrokEnabled && useXGrok;
  return ModelHints.build(
    provider: xgrokOn ? 'xgrok' : 'gemini',
    mode: useDeepModel ? 'deep' : 'lite',
    deepModel: useDeepModel && !xgrokOn ? settings.deepModel : null,
    liteModel: !useDeepModel && !xgrokOn ? settings.liteModel : null,
    xgrokLiteModel: xgrokOn ? settings.xgrokLiteModel : null,
    xgrokDeepModel: xgrokOn ? settings.xgrokDeepModel : null,
    xgrokThinkingModel: xgrokOn ? settings.xgrokThinkingModel : null,
  );
}

/// Asserts the wire body contains exactly one model id field, namely
/// [expectedKey] = [expectedValue], and that all OTHER model id slots are
/// absent. Prevents bleeds across provider × mode boundaries.
void _expectExactlyOneModelKey(
  Map<String, dynamic> body,
  String expectedKey,
  String expectedValue,
) {
  const allModelKeys = <String>{
    'liteModel',
    'deepModel',
    'xgrokLiteModel',
    'xgrokDeepModel',
    'xgrokThinkingModel',
    'xgrokModel',
  };
  expect(body[expectedKey], equals(expectedValue),
      reason: 'expected $expectedKey=$expectedValue in $body');
  for (final k in allModelKeys) {
    if (k == expectedKey) continue;
    expect(body.containsKey(k), isFalse,
        reason: 'unexpected $k present in body: $body');
  }
}

void main() {
  group('Routing matrix — Settings → wire body', () {
    // ── Gemini Lite from Settings ────────────────────────────────────────
    test('Gemini lite uses settings.liteModel (xgrok off)', () {
      final body = _wireBodyForCallSite(
        settings: _settingsAllConfigured,
        useDeepModel: false,
        useXGrok: false,
      );
      expect(body['provider'], 'gemini');
      expect(body['mode'], 'lite');
      _expectExactlyOneModelKey(
          body, 'liteModel', 'gemini-3.1-flash-lite-preview');
    });

    test('Gemini lite uses settings.liteModel (xgrok enabled but UI says off)',
        () {
      // xgrok toggle ON in Settings, but the call site disables xGrok for
      // this particular request (e.g. user picked Gemini explicitly via the
      // per-call provider toggle). The body must not leak xgrok ids.
      final body = _wireBodyForCallSite(
        settings: _settingsAllConfigured,
        useDeepModel: false,
        useXGrok: false,
      );
      _expectExactlyOneModelKey(
          body, 'liteModel', 'gemini-3.1-flash-lite-preview');
    });

    // ── Gemini Deep from Settings ────────────────────────────────────────
    test('Gemini deep uses settings.deepModel (xgrok off)', () {
      final body = _wireBodyForCallSite(
        settings: _settingsAllConfigured,
        useDeepModel: true,
        useXGrok: false,
      );
      expect(body['provider'], 'gemini');
      expect(body['mode'], 'deep');
      _expectExactlyOneModelKey(
          body, 'deepModel', 'gemini-3.1-pro-preview');
    });

    // ── xGrok Lite from Settings ─────────────────────────────────────────
    test('xGrok lite uses settings.xgrokLiteModel', () {
      final body = _wireBodyForCallSite(
        settings: _settingsAllConfigured,
        useDeepModel: false,
        useXGrok: true,
      );
      expect(body['provider'], 'xgrok');
      expect(body['mode'], 'lite');
      _expectExactlyOneModelKey(
          body, 'xgrokLiteModel', 'grok-4-1-fast-non-reasoning');
    });

    // ── xGrok Deep from Settings ─────────────────────────────────────────
    test('xGrok deep uses settings.xgrokDeepModel', () {
      final body = _wireBodyForCallSite(
        settings: _settingsAllConfigured,
        useDeepModel: true,
        useXGrok: true,
      );
      expect(body['provider'], 'xgrok');
      expect(body['mode'], 'deep');
      _expectExactlyOneModelKey(
          body, 'xgrokDeepModel', 'grok-4-0709');
    });

    // ── xGrok Thinking from Settings (mode passed through directly) ───────
    test('xGrok thinking uses settings.xgrokThinkingModel', () {
      final body = ModelHints.build(
        provider: 'xgrok',
        mode: 'thinking',
        xgrokLiteModel: _settingsAllConfigured.xgrokLiteModel,
        xgrokDeepModel: _settingsAllConfigured.xgrokDeepModel,
        xgrokThinkingModel: _settingsAllConfigured.xgrokThinkingModel,
      );
      expect(body['provider'], 'xgrok');
      expect(body['mode'], 'thinking');
      _expectExactlyOneModelKey(
          body, 'xgrokThinkingModel', 'grok-4-1-fast-reasoning');
    });
  });

  group('Routing matrix — invariants under every permutation', () {
    // Cartesian product of every (provider, mode, settings-permutation) the
    // production app can construct, asserting:
    //   1. Exactly one model id field is sent for each non-empty permutation.
    //   2. Provider isolation is total (no cross-provider field bleeds).
    //   3. Mode isolation is total (no cross-mode field bleeds).
    final providers = <String?>['gemini', 'xgrok', null, ' GEMINI ', 'xGrok'];
    final modes = <String?>['lite', 'deep', 'thinking', null, ' LITE ', 'unknown'];

    for (final providerRaw in providers) {
      for (final modeRaw in modes) {
        test(
          'provider="${providerRaw ?? '<null>'}" mode="${modeRaw ?? '<null>'}" honours all isolation rules',
          () {
            final body = ModelHints.build(
              provider: providerRaw,
              mode: modeRaw,
              liteModel: 'L-from-settings',
              deepModel: 'D-from-settings',
              xgrokLiteModel: 'XL-from-settings',
              xgrokDeepModel: 'XD-from-settings',
              xgrokThinkingModel: 'XT-from-settings',
            );

            // Exactly two of provider/mode are always present.
            expect(body.containsKey('provider'), isTrue);
            expect(body.containsKey('mode'), isTrue);
            final p = body['provider'];
            final m = body['mode'];

            // At most one model key
            const allModelKeys = <String>{
              'liteModel',
              'deepModel',
              'xgrokLiteModel',
              'xgrokDeepModel',
              'xgrokThinkingModel',
              'xgrokModel',
            };
            final present = allModelKeys.where(body.containsKey).toList();
            expect(present.length, lessThanOrEqualTo(1),
                reason: 'multiple model keys leaked: $present in $body');

            if (p == 'gemini') {
              // No xgrok keys allowed
              for (final k in [
                'xgrokLiteModel',
                'xgrokDeepModel',
                'xgrokThinkingModel',
                'xgrokModel'
              ]) {
                expect(body.containsKey(k), isFalse,
                    reason: 'gemini path leaked $k: $body');
              }
              if (m == 'deep' || m == 'thinking') {
                expect(body['deepModel'], 'D-from-settings');
                expect(body.containsKey('liteModel'), isFalse);
              } else {
                expect(body['liteModel'], 'L-from-settings');
                expect(body.containsKey('deepModel'), isFalse);
              }
            } else {
              // xgrok path. Gemini deep/lite slots must be absent.
              expect(body.containsKey('deepModel'), isFalse,
                  reason: 'xgrok path leaked deepModel: $body');
              expect(body.containsKey('liteModel'), isFalse,
                  reason: 'xgrok path leaked liteModel: $body');
              switch (m) {
                case 'deep':
                  expect(body['xgrokDeepModel'], 'XD-from-settings');
                  expect(body.containsKey('xgrokLiteModel'), isFalse);
                  expect(body.containsKey('xgrokThinkingModel'), isFalse);
                  break;
                case 'thinking':
                  expect(body['xgrokThinkingModel'], 'XT-from-settings');
                  expect(body.containsKey('xgrokLiteModel'), isFalse);
                  expect(body.containsKey('xgrokDeepModel'), isFalse);
                  break;
                default: // lite
                  expect(body['xgrokLiteModel'], 'XL-from-settings');
                  expect(body.containsKey('xgrokDeepModel'), isFalse);
                  expect(body.containsKey('xgrokThinkingModel'), isFalse);
              }
            }
          },
        );
      }
    }
  });

  group('Routing matrix — empty / unset Settings', () {
    test('Gemini lite with empty liteModel sends NO model id (backend default)',
        () {
      final body = ModelHints.build(provider: 'gemini', mode: 'lite');
      expect(body, equals({'provider': 'gemini', 'mode': 'lite'}));
    });

    test('xGrok lite with empty xgrokLiteModel sends NO model id', () {
      final body = ModelHints.build(provider: 'xgrok', mode: 'lite');
      expect(body, equals({'provider': 'xgrok', 'mode': 'lite'}));
    });
  });

  group('Routing matrix — Settings updates propagate immediately', () {
    test('changing settings.liteModel updates the next request body', () {
      final firstBody = ModelHints.build(
        provider: 'gemini',
        mode: 'lite',
        liteModel: 'gemini-3.1-flash-lite-preview',
      );
      final updatedBody = ModelHints.build(
        provider: 'gemini',
        mode: 'lite',
        liteModel: 'gemini-4.0-flash-lite',
      );
      expect(firstBody['liteModel'], 'gemini-3.1-flash-lite-preview');
      expect(updatedBody['liteModel'], 'gemini-4.0-flash-lite');
    });

    test('changing settings.deepModel updates the next request body', () {
      final body = ModelHints.build(
        provider: 'gemini',
        mode: 'deep',
        deepModel: 'gemini-4.0-pro',
      );
      expect(body['deepModel'], 'gemini-4.0-pro');
    });

    test('toggling xGrok flips the entire model slot scheme', () {
      // User's full Settings snapshot (with xGrok enabled).
      const s = _settingsAllConfigured;

      // User picks Gemini lite for this call.
      final geminiBody = _wireBodyForCallSite(
        settings: s,
        useDeepModel: false,
        useXGrok: false,
      );
      _expectExactlyOneModelKey(
          geminiBody, 'liteModel', 'gemini-3.1-flash-lite-preview');

      // User toggles to xGrok lite — same Settings, different call-site flag.
      final xgrokBody = _wireBodyForCallSite(
        settings: s,
        useDeepModel: false,
        useXGrok: true,
      );
      _expectExactlyOneModelKey(
          xgrokBody, 'xgrokLiteModel', 'grok-4-1-fast-non-reasoning');

      // The two bodies do not share any model id slot.
      const allModelKeys = <String>{
        'liteModel',
        'deepModel',
        'xgrokLiteModel',
        'xgrokDeepModel',
        'xgrokThinkingModel',
        'xgrokModel',
      };
      final geminiKeys = allModelKeys.where(geminiBody.containsKey).toSet();
      final xgrokKeys = allModelKeys.where(xgrokBody.containsKey).toSet();
      expect(geminiKeys.intersection(xgrokKeys), isEmpty,
          reason: 'provider isolation broken: $geminiKeys ∩ $xgrokKeys');
    });
  });
}
