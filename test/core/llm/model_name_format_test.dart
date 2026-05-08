import 'package:ai_nexus/core/llm/model_name_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortModelName', () {
    // ── Gemini ──────────────────────────────────────────────────────────────

    test('gemini/gemini-3.1-flash-lite-preview → Gemini 3.1 Flash Lite Preview',
        () {
      expect(shortModelName('gemini/gemini-3.1-flash-lite-preview'),
          equals('Gemini 3.1 Flash Lite Preview'));
    });

    test('gemini-3.1-flash-lite-preview (no LiteLLM prefix)', () {
      expect(shortModelName('gemini-3.1-flash-lite-preview'),
          equals('Gemini 3.1 Flash Lite Preview'));
    });

    test('gemini-3.1-pro → Gemini 3.1 Pro', () {
      expect(shortModelName('gemini-3.1-pro'), equals('Gemini 3.1 Pro'));
    });

    test('gemini-3.1-pro-preview → Gemini 3.1 Pro Preview', () {
      expect(shortModelName('gemini-3.1-pro-preview'),
          equals('Gemini 3.1 Pro Preview'));
    });

    test('gemini/gemini-2.5-flash → Gemini 2.5 Flash', () {
      expect(shortModelName('gemini/gemini-2.5-flash'),
          equals('Gemini 2.5 Flash'));
    });

    test('gemini-2.5-flash-lite → Gemini 2.5 Flash Lite', () {
      expect(shortModelName('gemini-2.5-flash-lite'),
          equals('Gemini 2.5 Flash Lite'));
    });

    test('gemini-2.0-flash → Gemini 2.0 Flash', () {
      expect(shortModelName('gemini-2.0-flash'), equals('Gemini 2.0 Flash'));
    });

    test('integer-only version: gemini-2-flash → Gemini 2 Flash', () {
      expect(shortModelName('gemini-2-flash'), equals('Gemini 2 Flash'));
    });

    test('mixed case is folded: GEMINI-3.1-PRO → Gemini 3.1 Pro', () {
      expect(shortModelName('GEMINI-3.1-PRO'), equals('Gemini 3.1 Pro'));
    });

    test('bare "gemini" with no version → Gemini', () {
      expect(shortModelName('gemini'), equals('Gemini'));
    });

    test('unparseable Gemini-ish id falls back to "Gemini"', () {
      expect(shortModelName('gemini-experimental-build-xyz'), equals('Gemini'));
    });

    // ── xGrok / Grok ────────────────────────────────────────────────────────

    test('grok-4-0709 → Grok 4 0709', () {
      expect(shortModelName('grok-4-0709'), equals('Grok 4 0709'));
    });

    test('grok-4-1-fast-non-reasoning → Grok 4 1 Fast Non Reasoning', () {
      expect(shortModelName('grok-4-1-fast-non-reasoning'),
          equals('Grok 4 1 Fast Non Reasoning'));
    });

    test('grok-4-1-fast-reasoning → Grok 4 1 Fast Reasoning', () {
      expect(shortModelName('grok-4-1-fast-reasoning'),
          equals('Grok 4 1 Fast Reasoning'));
    });

    test('xgrok prefix is stripped', () {
      expect(shortModelName('xgrok-4-0709'), equals('Grok 4 0709'));
    });

    // ── Other providers ─────────────────────────────────────────────────────

    test('GPT-4 family', () {
      expect(shortModelName('gpt-4o-mini'), equals('GPT-4'));
      expect(shortModelName('gpt-4'), equals('GPT-4'));
    });

    test('GPT-3 family', () {
      expect(shortModelName('gpt-3.5-turbo'), equals('GPT-3.5'));
    });

    test('Claude', () {
      expect(shortModelName('anthropic/claude-sonnet-4'), equals('Claude'));
    });

    test('Llama', () {
      expect(shortModelName('groq/llama-3.1-70b'), equals('Llama 3.3'));
    });

    // ── Edge cases ──────────────────────────────────────────────────────────

    test('empty string returns empty', () {
      expect(shortModelName(''), equals(''));
      expect(shortModelName('   '), equals(''));
    });

    test('long unknown id is truncated with ellipsis', () {
      const id = 'this-is-a-very-long-unknown-model-name-id';
      final out = shortModelName(id);
      expect(out.length, lessThanOrEqualTo(21));
      expect(out, endsWith('\u2026'));
    });

    test('short unknown id is returned as-is', () {
      expect(shortModelName('foo-mini'), equals('foo-mini'));
    });
  });
}
