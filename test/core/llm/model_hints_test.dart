// Unit tests for the production-grade ModelHints builder.
//
// These tests are the safety net against the regression that broke real-time
// answers in InsightAI Lite: the previous build leaked `deepModel` (a Gemini
// deep-mode model id) into every Lite request because the body assembler did
// not filter by (provider, mode). The builder under test strips any field
// that does not belong to the active (provider, mode) pair, so even a
// careless caller cannot reintroduce that bug.

import 'package:ai_nexus/core/llm/model_hints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelHints.build', () {
    // ── Gemini ──────────────────────────────────────────────────────────────

    group('Gemini provider', () {
      test('lite mode without liteModel sends ONLY provider+mode', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'lite',
          deepModel: 'gemini-3.1-pro-preview',
          xgrokLiteModel: 'grok-4-1-fast-non-reasoning',
          xgrokDeepModel: 'grok-4-0709',
          xgrokThinkingModel: 'grok-4-1-fast-reasoning',
        );

        expect(body, equals({'provider': 'gemini', 'mode': 'lite'}));
        expect(body.containsKey('deepModel'), isFalse,
            reason: 'Gemini lite must NOT carry deepModel — that is the '
                'regression that broke InsightAI real-time answers.');
        expect(body.containsKey('liteModel'), isFalse);
        expect(body.containsKey('xgrokLiteModel'), isFalse);
        expect(body.containsKey('xgrokDeepModel'), isFalse);
        expect(body.containsKey('xgrokThinkingModel'), isFalse);
      });

      test('lite mode forwards liteModel and strips deep/xgrok fields', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'lite',
          liteModel: 'gemini-3.1-flash-lite-preview',
          deepModel: 'gemini-3.1-pro-preview',
          xgrokLiteModel: 'grok-lite',
          xgrokDeepModel: 'grok-deep',
          xgrokThinkingModel: 'grok-thinking',
        );

        expect(
            body,
            equals({
              'provider': 'gemini',
              'mode': 'lite',
              'liteModel': 'gemini-3.1-flash-lite-preview',
            }));
        expect(body.containsKey('deepModel'), isFalse,
            reason: 'lite must never leak deepModel even when both are set.');
      });

      test('liteModel value is trimmed before forwarding', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'lite',
          liteModel: '  gemini-3.1-flash-lite-preview  ',
        );
        expect(body['liteModel'], equals('gemini-3.1-flash-lite-preview'));
      });

      test('whitespace-only liteModel is treated as absent on lite mode', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'lite',
          liteModel: '   ',
        );
        expect(body, equals({'provider': 'gemini', 'mode': 'lite'}));
      });

      test('liteModel does NOT bleed into deep/thinking modes', () {
        final deep = ModelHints.build(
          provider: 'gemini',
          mode: 'deep',
          liteModel: 'gemini-3.1-flash-lite-preview',
          deepModel: 'gemini-3.1-pro-preview',
        );
        expect(deep.containsKey('liteModel'), isFalse,
            reason: 'liteModel is lite-only — deep requests must not carry '
                'it, otherwise the backend may route to lite instead of pro.');
        expect(deep['deepModel'], equals('gemini-3.1-pro-preview'));
      });

      test('deep mode forwards deepModel and strips xGrok fields', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'deep',
          deepModel: 'gemini-3.1-pro-preview',
          xgrokLiteModel: 'grok-lite',
          xgrokDeepModel: 'grok-deep',
          xgrokThinkingModel: 'grok-thinking',
        );

        expect(
            body,
            equals({
              'provider': 'gemini',
              'mode': 'deep',
              'deepModel': 'gemini-3.1-pro-preview',
            }));
      });

      test('thinking mode collapses to deep on Gemini', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'thinking',
          deepModel: 'gemini-3.1-pro-preview',
        );

        expect(body['mode'], equals('deep'),
            reason: 'Gemini does not have a thinking depth; must be collapsed '
                'to deep so the backend dispatcher always sees a known mode.');
        expect(body['deepModel'], equals('gemini-3.1-pro-preview'));
      });

      test('null/empty provider defaults to gemini', () {
        expect(ModelHints.build(provider: null, mode: 'lite')['provider'],
            equals('gemini'));
        expect(ModelHints.build(provider: '', mode: 'lite')['provider'],
            equals('gemini'));
        expect(ModelHints.build(provider: '   ', mode: 'lite')['provider'],
            equals('gemini'));
      });

      test('null/empty mode defaults to lite', () {
        expect(ModelHints.build(provider: 'gemini', mode: null)['mode'],
            equals('lite'));
        expect(ModelHints.build(provider: 'gemini', mode: '')['mode'],
            equals('lite'));
        expect(ModelHints.build(provider: 'gemini', mode: '   ')['mode'],
            equals('lite'));
      });

      test('unknown mode normalizes to lite (fail-safe)', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'turbo-mega-deep',
          deepModel: 'gemini-3.1-pro-preview',
        );
        expect(body['mode'], equals('lite'));
        expect(body.containsKey('deepModel'), isFalse,
            reason: 'Unknown mode falls back to lite, which strips deepModel.');
      });

      test('whitespace-only deepModel is treated as absent on deep mode', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'deep',
          deepModel: '   ',
        );
        expect(body, equals({'provider': 'gemini', 'mode': 'deep'}));
      });

      test('deepModel value is trimmed before forwarding', () {
        final body = ModelHints.build(
          provider: 'gemini',
          mode: 'deep',
          deepModel: '  gemini-3.1-pro-preview  ',
        );
        expect(body['deepModel'], equals('gemini-3.1-pro-preview'));
      });
    });

    // ── xGrok ───────────────────────────────────────────────────────────────

    group('xGrok provider', () {
      test('lite mode forwards ONLY xgrokLiteModel; Gemini deepModel stripped',
          () {
        final body = ModelHints.build(
          provider: 'xgrok',
          mode: 'lite',
          deepModel: 'gemini-3.1-pro-preview',
          xgrokLiteModel: 'grok-4-1-fast-non-reasoning',
          xgrokDeepModel: 'grok-4-0709',
          xgrokThinkingModel: 'grok-4-1-fast-reasoning',
        );

        expect(
            body,
            equals({
              'provider': 'xgrok',
              'mode': 'lite',
              'xgrokLiteModel': 'grok-4-1-fast-non-reasoning',
            }));
        expect(body.containsKey('deepModel'), isFalse,
            reason: 'Cross-provider isolation: Gemini deepModel must not leak '
                'into xGrok requests, even when both fields are populated.');
        expect(body.containsKey('xgrokDeepModel'), isFalse);
        expect(body.containsKey('xgrokThinkingModel'), isFalse);
      });

      test('deep mode forwards ONLY xgrokDeepModel', () {
        final body = ModelHints.build(
          provider: 'xgrok',
          mode: 'deep',
          deepModel: 'gemini-3.1-pro-preview',
          xgrokLiteModel: 'grok-lite',
          xgrokDeepModel: 'grok-4-0709',
          xgrokThinkingModel: 'grok-thinking',
        );

        expect(
            body,
            equals({
              'provider': 'xgrok',
              'mode': 'deep',
              'xgrokDeepModel': 'grok-4-0709',
            }));
      });

      test('thinking mode forwards ONLY xgrokThinkingModel', () {
        final body = ModelHints.build(
          provider: 'xgrok',
          mode: 'thinking',
          deepModel: 'gemini-3.1-pro-preview',
          xgrokLiteModel: 'grok-lite',
          xgrokDeepModel: 'grok-deep',
          xgrokThinkingModel: 'grok-4-1-fast-reasoning',
        );

        expect(
            body,
            equals({
              'provider': 'xgrok',
              'mode': 'thinking',
              'xgrokThinkingModel': 'grok-4-1-fast-reasoning',
            }));
      });

      test('legacy xgrokModel is mapped to lite slot when no xgrokLiteModel',
          () {
        final body = ModelHints.build(
          provider: 'xgrok',
          mode: 'lite',
          legacyXgrokModel: 'grok-legacy-id',
        );

        expect(body['xgrokLiteModel'], equals('grok-legacy-id'));
        // We also forward the raw `xgrokModel` field for older backend
        // builds that key off the pre-Lite/Deep/Thinking single slot.
        expect(body['xgrokModel'], equals('grok-legacy-id'));
      });

      test('xgrokLiteModel takes precedence over legacy xgrokModel', () {
        final body = ModelHints.build(
          provider: 'xgrok',
          mode: 'lite',
          xgrokLiteModel: 'grok-explicit-lite',
          legacyXgrokModel: 'grok-legacy',
        );

        expect(body['xgrokLiteModel'], equals('grok-explicit-lite'),
            reason: 'Explicit per-mode field beats the legacy slot.');
        // Legacy is still echoed for older backends.
        expect(body['xgrokModel'], equals('grok-legacy'));
      });

      test('legacy xgrokModel does NOT bleed into deep / thinking modes', () {
        final deep = ModelHints.build(
          provider: 'xgrok',
          mode: 'deep',
          legacyXgrokModel: 'grok-legacy',
        );
        expect(deep.containsKey('xgrokDeepModel'), isFalse);
        expect(deep.containsKey('xgrokModel'), isFalse,
            reason: 'Legacy slot is lite-only; it must not appear on '
                'deep/thinking requests.');

        final thinking = ModelHints.build(
          provider: 'xgrok',
          mode: 'thinking',
          legacyXgrokModel: 'grok-legacy',
        );
        expect(thinking.containsKey('xgrokThinkingModel'), isFalse);
        expect(thinking.containsKey('xgrokModel'), isFalse);
      });

      test('xgrok with no model ids still sends mode+provider (backend default)',
          () {
        final body = ModelHints.build(provider: 'xgrok', mode: 'lite');
        expect(body, equals({'provider': 'xgrok', 'mode': 'lite'}));
      });
    });

    // ── Cross-cutting invariants ────────────────────────────────────────────

    group('Invariants', () {
      test('the wire body NEVER carries more than one model id', () {
        // Exhaustive sweep over (provider × mode) with all model ids
        // populated. Exactly zero or one `*Model` field must appear.
        const providers = <String?>[null, 'gemini', 'xgrok', 'GEMINI', 'XGROK'];
        const modes = <String?>[null, 'lite', 'deep', 'thinking', 'unknown'];

        for (final p in providers) {
          for (final m in modes) {
            final body = ModelHints.build(
              provider: p,
              mode: m,
              deepModel: 'd',
              liteModel: 'l',
              xgrokLiteModel: 'xl',
              xgrokDeepModel: 'xd',
              xgrokThinkingModel: 'xt',
              legacyXgrokModel: 'xm',
            );

            final modelKeys = body.keys
                .where((k) => k.toLowerCase().endsWith('model'))
                .toList();
            // Legacy `xgrokModel` is a duplicate of the lite slot for
            // back-compat; it does not count as a separate routing target.
            final routingKeys =
                modelKeys.where((k) => k != 'xgrokModel').toList();

            expect(routingKeys.length, lessThanOrEqualTo(1),
                reason: 'provider=$p mode=$m produced multiple routing model '
                    'fields: $routingKeys');
          }
        }
      });

      test('case-insensitive provider/mode parsing', () {
        final body = ModelHints.build(
          provider: 'XGROK',
          mode: 'DEEP',
          xgrokDeepModel: 'grok-4-0709',
        );
        expect(body['provider'], equals('xgrok'));
        expect(body['mode'], equals('deep'));
        expect(body['xgrokDeepModel'], equals('grok-4-0709'));
      });

      test('lite never carries any non-lite model id (any provider)', () {
        for (final p in ['gemini', 'xgrok']) {
          final body = ModelHints.build(
            provider: p,
            mode: 'lite',
            deepModel: 'd',
            xgrokDeepModel: 'xd',
            xgrokThinkingModel: 'xt',
          );
          expect(body.containsKey('deepModel'), isFalse,
              reason: 'lite/$p leaked deepModel');
          expect(body.containsKey('xgrokDeepModel'), isFalse,
              reason: 'lite/$p leaked xgrokDeepModel');
          expect(body.containsKey('xgrokThinkingModel'), isFalse,
              reason: 'lite/$p leaked xgrokThinkingModel');
        }
      });

      test('deep never carries any lite/thinking model id (any provider)', () {
        for (final p in ['gemini', 'xgrok']) {
          final body = ModelHints.build(
            provider: p,
            mode: 'deep',
            liteModel: 'l',
            xgrokLiteModel: 'xl',
            xgrokThinkingModel: 'xt',
            legacyXgrokModel: 'xm',
          );
          expect(body.containsKey('liteModel'), isFalse,
              reason: 'deep/$p leaked Gemini liteModel');
          expect(body.containsKey('xgrokLiteModel'), isFalse,
              reason: 'deep/$p leaked xgrokLiteModel');
          expect(body.containsKey('xgrokThinkingModel'), isFalse,
              reason: 'deep/$p leaked xgrokThinkingModel');
          expect(body.containsKey('xgrokModel'), isFalse,
              reason: 'deep/$p leaked legacy xgrokModel');
        }
      });

      test('thinking never carries any lite/deep model id', () {
        final body = ModelHints.build(
          provider: 'xgrok',
          mode: 'thinking',
          xgrokLiteModel: 'xl',
          xgrokDeepModel: 'xd',
          legacyXgrokModel: 'xm',
        );
        expect(body.containsKey('xgrokLiteModel'), isFalse);
        expect(body.containsKey('xgrokDeepModel'), isFalse);
        expect(body.containsKey('xgrokModel'), isFalse);
      });

      test('Gemini provider strips ALL xGrok fields, regardless of mode', () {
        for (final m in ['lite', 'deep', 'thinking']) {
          final body = ModelHints.build(
            provider: 'gemini',
            mode: m,
            liteModel: 'gemini-3.1-flash-lite-preview',
            deepModel: 'gemini-3.1-pro-preview',
            xgrokLiteModel: 'xl',
            xgrokDeepModel: 'xd',
            xgrokThinkingModel: 'xt',
            legacyXgrokModel: 'xm',
          );
          expect(body.keys.where((k) => k.toLowerCase().contains('xgrok')),
              isEmpty,
              reason: 'gemini/$m leaked xgrok-namespaced fields: $body');
        }
      });

      test('xGrok provider strips Gemini deep/lite Models, regardless of mode',
          () {
        for (final m in ['lite', 'deep', 'thinking']) {
          final body = ModelHints.build(
            provider: 'xgrok',
            mode: m,
            deepModel: 'gemini-3.1-pro-preview',
            liteModel: 'gemini-3.1-flash-lite-preview',
          );
          expect(body.containsKey('deepModel'), isFalse,
              reason: 'xgrok/$m leaked Gemini deepModel: $body');
          expect(body.containsKey('liteModel'), isFalse,
              reason: 'xgrok/$m leaked Gemini liteModel: $body');
        }
      });
    });

    // ── mergeInto ──────────────────────────────────────────────────────────

    group('mergeInto', () {
      test('adds hints to a body without overwriting existing keys', () {
        final body = <String, dynamic>{
          'query': 'hi',
          'mode': 'caller-supplied',
        };
        ModelHints.mergeInto(
          body,
          provider: 'gemini',
          mode: 'lite',
        );
        expect(body['query'], equals('hi'));
        expect(body['mode'], equals('caller-supplied'),
            reason: 'mergeInto must not stomp explicit caller values.');
        expect(body['provider'], equals('gemini'));
      });

      test('returns the same body instance', () {
        final body = <String, dynamic>{};
        final out = ModelHints.mergeInto(body, provider: 'gemini', mode: 'lite');
        expect(identical(out, body), isTrue);
      });
    });
  });
}
