// Comprehensive unit tests for [FollowUpHistoryBuilder] and friends.
//
// The builder is the single source of truth for how news/article + InsightAI
// search follow-up turns shape their wire `history` payload. It also owns the
// "should we auto-switch Lite → Deep?" decision. The chat sheets are thin
// adapters around it — when these tests pass, both sheets are covered.
//
// Coverage map:
//
//   • collectCompletedPairs       — pairing rules, orphan handling, error/
//                                   loading filtering, role mismatches.
//   • buildSourceMemoryBlock      — dedup, ordering, capping, filtering,
//                                   formatting (with/without titles), the
//                                   "disabled" config (max=0).
//   • buildModeMismatchHint       — emission rules across all 8 cells of
//                                   {currentIsDeep × hasLiteHistory ×
//                                    detection-token (lite/flash)}.
//   • build                       — short-conversation verbatim path,
//                                   long-conversation layered path, fresh
//                                   vs stale summary, mode-adaptive recent
//                                   window, defensive clamps, immutability
//                                   of the returned wire history.
//   • shouldAutoSwitchToDeep      — every boundary of the decision matrix.
//   • End-to-end                  — multi-turn simulation that walks a
//                                   conversation through threshold + mode
//                                   transitions and snapshots the exact
//                                   wire payload at each step.
//
// All tests are pure-Dart — no widget tree, no Riverpod, no Drift, no
// network. They run in milliseconds and are deterministic.

import 'package:ai_nexus/core/services/followup_history.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Test fixtures ────────────────────────────────────────────────────────────

FollowUpMessage _user(String text, {bool loading = false, bool error = false}) =>
    FollowUpMessage(
      role: 'user',
      text: text,
      isLoading: loading,
      isError: error,
    );

FollowUpMessage _assistant(
  String text, {
  bool loading = false,
  bool error = false,
  String model = '',
  List<FollowUpSourceRef> sources = const [],
}) =>
    FollowUpMessage(
      role: 'assistant',
      text: text,
      isLoading: loading,
      isError: error,
      model: model,
      sources: sources,
    );

/// Builds [count] alternating user/assistant pairs with predictable text:
///   pair 1 → ('q1', 'a1'), pair 2 → ('q2', 'a2'), …
/// Useful for asserting shape of the wire payload at boundary sizes.
List<FollowUpMessage> _conversation(int pairCount,
    {String assistantModel = ''}) {
  final out = <FollowUpMessage>[];
  for (var i = 1; i <= pairCount; i++) {
    out.add(_user('q$i'));
    out.add(_assistant('a$i', model: assistantModel));
  }
  return out;
}

List<Map<String, String>> _flatPairs(int n) {
  final out = <Map<String, String>>[];
  for (var i = 1; i <= n; i++) {
    out.add({'role': 'user', 'text': 'q$i'});
    out.add({'role': 'assistant', 'text': 'a$i'});
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  const builder = FollowUpHistoryBuilder();

  group('FollowUpHistoryConfig', () {
    test('defaults match production thresholds', () {
      const cfg = FollowUpHistoryConfig();
      expect(cfg.summarizeThreshold, 10);
      expect(cfg.recentPairsLite, 5);
      expect(cfg.recentPairsDeep, 12);
      expect(cfg.sourceMemoryMax, 20);
      expect(cfg.autoDeepThreshold, 10);
    });

    test('asserts reject bad configs', () {
      expect(
        () => FollowUpHistoryConfig(summarizeThreshold: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => FollowUpHistoryConfig(recentPairsLite: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => FollowUpHistoryConfig(
            recentPairsLite: 5, recentPairsDeep: 3),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => FollowUpHistoryConfig(autoDeepThreshold: 0),
        throwsA(isA<AssertionError>()),
      );
      // sourceMemoryMax >= 0 — 0 is valid (disabled).
      expect(() => const FollowUpHistoryConfig(sourceMemoryMax: 0),
          returnsNormally);
      expect(
        () => FollowUpHistoryConfig(sourceMemoryMax: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ─── collectCompletedPairs ────────────────────────────────────────────────

  group('collectCompletedPairs', () {
    test('empty list → no pairs', () {
      expect(builder.collectCompletedPairs(const []), isEmpty);
    });

    test('single user → no pair', () {
      expect(builder.collectCompletedPairs([_user('q1')]), isEmpty);
    });

    test('single assistant → no pair', () {
      expect(builder.collectCompletedPairs([_assistant('a1')]), isEmpty);
    });

    test('one complete pair', () {
      final pairs = builder.collectCompletedPairs([
        _user('q1'),
        _assistant('a1'),
      ]);
      expect(pairs, [
        {'role': 'user', 'text': 'q1'},
        {'role': 'assistant', 'text': 'a1'},
      ]);
    });

    test('multiple complete pairs preserve order', () {
      final pairs = builder.collectCompletedPairs(_conversation(3));
      expect(pairs.length, 6);
      expect(pairs[0]['text'], 'q1');
      expect(pairs[1]['text'], 'a1');
      expect(pairs[5]['text'], 'a3');
    });

    test('loading assistant skipped — does NOT consume the user before it', () {
      final pairs = builder.collectCompletedPairs([
        _user('q1'),
        _assistant('streaming…', loading: true),
        _user('q2'),
        _assistant('a2'),
      ]);
      // q1 has no finalized assistant partner → dropped. q2/a2 paired.
      expect(pairs, [
        {'role': 'user', 'text': 'q2'},
        {'role': 'assistant', 'text': 'a2'},
      ]);
    });

    test('error assistant skipped — same drop semantics', () {
      final pairs = builder.collectCompletedPairs([
        _user('q1'),
        _assistant('boom', error: true),
        _user('q2'),
        _assistant('a2'),
      ]);
      expect(pairs, [
        {'role': 'user', 'text': 'q2'},
        {'role': 'assistant', 'text': 'a2'},
      ]);
    });

    test('orphan tail user with excludeOrphanTail=false is just unpaired', () {
      // The user has no assistant after it, so the look-ahead naturally
      // drops it even without the explicit flag.
      final pairs = builder.collectCompletedPairs([
        _user('q1'),
        _assistant('a1'),
        _user('q2-orphan'),
      ]);
      expect(pairs, [
        {'role': 'user', 'text': 'q1'},
        {'role': 'assistant', 'text': 'a1'},
      ]);
    });

    test('excludeOrphanTail=true narrows the look-ahead window', () {
      // Even though [q2 -> a2] looks like a complete pair, with the flag
      // the assistant at index length-1 is not considered as a partner.
      final pairs = builder.collectCompletedPairs(
        [
          _user('q1'),
          _assistant('a1'),
          _user('q2'),
          _assistant('a2-orphan-actually-the-last'),
        ],
        excludeOrphanTail: true,
      );
      // q2 cannot be paired because the look-ahead bound is length-1.
      expect(pairs, [
        {'role': 'user', 'text': 'q1'},
        {'role': 'assistant', 'text': 'a1'},
      ]);
    });

    test('excludeOrphanTail with empty list does not throw', () {
      expect(
        builder.collectCompletedPairs(const [], excludeOrphanTail: true),
        isEmpty,
      );
    });

    test('excludeOrphanTail with single message does not throw', () {
      expect(
        builder
            .collectCompletedPairs([_user('q1')], excludeOrphanTail: true),
        isEmpty,
      );
    });

    test('two users in a row — first gets dropped (no assistant after)', () {
      final pairs = builder.collectCompletedPairs([
        _user('q1'),
        _user('q2'),
        _assistant('a2'),
      ]);
      expect(pairs, [
        {'role': 'user', 'text': 'q2'},
        {'role': 'assistant', 'text': 'a2'},
      ]);
    });

    test('assistant followed by user — leading assistant ignored', () {
      final pairs = builder.collectCompletedPairs([
        _assistant('stray'),
        _user('q1'),
        _assistant('a1'),
      ]);
      expect(pairs, _flatPairs(1));
    });

    test('loading user is skipped — its assistant cannot be paired alone', () {
      final pairs = builder.collectCompletedPairs([
        _user('voice…', loading: true),
        _assistant('a-orphan'),
        _user('q2'),
        _assistant('a2'),
      ]);
      expect(pairs, [
        {'role': 'user', 'text': 'q2'},
        {'role': 'assistant', 'text': 'a2'},
      ]);
    });

    test('returns plain Map<String,String> — no extra keys', () {
      final pairs = builder.collectCompletedPairs(_conversation(1));
      expect(pairs.first.keys.toSet(), {'role', 'text'});
    });
  });

  // ─── buildSourceMemoryBlock ───────────────────────────────────────────────

  group('buildSourceMemoryBlock', () {
    test('empty list → empty', () {
      expect(builder.buildSourceMemoryBlock(const []), isEmpty);
    });

    test('no sources anywhere → empty', () {
      expect(builder.buildSourceMemoryBlock(_conversation(3)), isEmpty);
    });

    test('config sourceMemoryMax=0 → always empty', () {
      const disabled = FollowUpHistoryBuilder(
        config: FollowUpHistoryConfig(sourceMemoryMax: 0),
      );
      final msgs = [
        _user('q1'),
        _assistant('a1', sources: const [
          FollowUpSourceRef(url: 'https://x', title: 'X'),
        ]),
      ];
      expect(disabled.buildSourceMemoryBlock(msgs), isEmpty);
    });

    test('single assistant with one URL produces formatted line', () {
      final result = builder.buildSourceMemoryBlock([
        _assistant('a', sources: const [
          FollowUpSourceRef(url: 'https://example.com', title: 'Example'),
        ]),
      ]);
      expect(result.length, 2);
      expect(result[0]['role'], 'user');
      expect(
        result[0]['text'],
        contains('- https://example.com — Example'),
      );
      expect(result[1]['role'], 'assistant');
      expect(result[1]['text'], contains('Noted'));
    });

    test('source with empty title omits the trailing dash', () {
      final result = builder.buildSourceMemoryBlock([
        _assistant('a', sources: const [
          FollowUpSourceRef(url: 'https://example.com'),
        ]),
      ]);
      // Single-line case: no trailing newline after the URL, and the
      // " — " title separator must NOT be emitted.
      expect(result[0]['text'], endsWith('- https://example.com'));
      expect(result[0]['text'], isNot(contains(' — ')));
    });

    test('dedup across messages — exact URL match', () {
      final result = builder.buildSourceMemoryBlock([
        _assistant('a1', sources: const [
          FollowUpSourceRef(url: 'https://x'),
        ]),
        _assistant('a2', sources: const [
          FollowUpSourceRef(url: 'https://x'),
          FollowUpSourceRef(url: 'https://y'),
        ]),
      ]);
      // Only 2 unique URLs.
      expect('- https://x'.allMatches(result[0]['text']!).length, 1);
      expect('- https://y'.allMatches(result[0]['text']!).length, 1);
    });

    test('order is most-recent-first', () {
      final result = builder.buildSourceMemoryBlock([
        _assistant('old', sources: const [
          FollowUpSourceRef(url: 'https://old'),
        ]),
        _assistant('mid', sources: const [
          FollowUpSourceRef(url: 'https://mid'),
        ]),
        _assistant('new', sources: const [
          FollowUpSourceRef(url: 'https://new'),
        ]),
      ]);
      final text = result[0]['text']!;
      final newIdx = text.indexOf('https://new');
      final midIdx = text.indexOf('https://mid');
      final oldIdx = text.indexOf('https://old');
      expect(newIdx >= 0 && midIdx > newIdx && oldIdx > midIdx, isTrue);
    });

    test('respects sourceMemoryMax cap', () {
      const tight = FollowUpHistoryBuilder(
        config: FollowUpHistoryConfig(sourceMemoryMax: 3),
      );
      final result = tight.buildSourceMemoryBlock([
        _assistant('a', sources: List.generate(
          10,
          (i) => FollowUpSourceRef(url: 'https://u$i'),
        )),
      ]);
      final text = result[0]['text']!;
      // 3 URLs in, the rest must NOT appear.
      expect('https://u'.allMatches(text).length, 3);
      expect(text.contains('https://u3'), isFalse);
    });

    test('empty / whitespace URLs are filtered', () {
      final result = builder.buildSourceMemoryBlock([
        _assistant('a', sources: const [
          FollowUpSourceRef(url: ''),
          FollowUpSourceRef(url: '   '),
          FollowUpSourceRef(url: 'https://real'),
        ]),
      ]);
      expect(result[0]['text'], contains('https://real'));
      expect(result[0]['text']!.split('\n').where((l) => l.startsWith('-')).length, 1);
    });

    test('URLs are trimmed before dedup', () {
      final result = builder.buildSourceMemoryBlock([
        _assistant('a1', sources: const [
          FollowUpSourceRef(url: '  https://x  '),
        ]),
        _assistant('a2', sources: const [
          FollowUpSourceRef(url: 'https://x'),
        ]),
      ]);
      // Both should resolve to the same URL → only one line.
      expect('https://x'.allMatches(result[0]['text']!).length, 1);
    });

    test('user messages with sources are ignored', () {
      final result = builder.buildSourceMemoryBlock([
        const FollowUpMessage(
          role: 'user',
          text: 'q',
          sources: [FollowUpSourceRef(url: 'https://from-user')],
        ),
        _assistant('a'),
      ]);
      expect(result, isEmpty);
    });

    test('loading / error assistants are ignored', () {
      final result = builder.buildSourceMemoryBlock([
        _assistant('a-loading', loading: true, sources: const [
          FollowUpSourceRef(url: 'https://loading'),
        ]),
        _assistant('a-error', error: true, sources: const [
          FollowUpSourceRef(url: 'https://error'),
        ]),
      ]);
      expect(result, isEmpty);
    });
  });

  // ─── buildModeMismatchHint ────────────────────────────────────────────────

  group('buildModeMismatchHint', () {
    test('lite mode never emits a hint', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: false,
        messages: [
          _assistant('a1', model: 'gemini-3.1-flash-lite-preview'),
        ],
      );
      expect(result, isEmpty);
    });

    test('deep mode + no history → no hint', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: true,
        messages: const [],
      );
      expect(result, isEmpty);
    });

    test('deep mode + only deep-model history → no hint', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: true,
        messages: [
          _assistant('a1', model: 'gemini-3.1-pro-preview'),
          _assistant('a2', model: 'grok-4-0709'),
        ],
      );
      expect(result, isEmpty);
    });

    test('deep mode + lite-model history → hint emitted', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: true,
        messages: [
          _assistant('a1', model: 'gemini-3.1-flash-lite-preview'),
        ],
      );
      expect(result.length, 2);
      expect(result[0]['role'], 'user');
      expect(result[0]['text'], contains('lite model'));
    });

    test('deep mode + flash-model history → hint emitted', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: true,
        messages: [
          _assistant('a1', model: 'gemini-2.5-flash'),
        ],
      );
      expect(result.length, 2);
    });

    test('case-insensitive token detection', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: true,
        messages: [
          _assistant('a1', model: 'GEMINI-FLASH-LITE'),
        ],
      );
      expect(result.length, 2);
    });

    test('non-lite/non-flash model ids are NOT detected (e.g. xGrok fast)', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: true,
        messages: [
          _assistant('a1', model: 'grok-4-1-fast-non-reasoning'),
        ],
      );
      // 'fast' alone shouldn't trigger — only 'lite' or 'flash'.
      expect(result, isEmpty);
    });

    test('loading / error assistants are not considered for detection', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: true,
        messages: [
          _assistant('streaming…',
              loading: true, model: 'gemini-flash-lite'),
          _assistant('boom', error: true, model: 'gemini-flash-lite'),
        ],
      );
      expect(result, isEmpty);
    });

    test('user messages ignored for detection', () {
      final result = builder.buildModeMismatchHint(
        currentIsDeep: true,
        messages: [
          const FollowUpMessage(role: 'user', text: 'q', model: 'lite'),
        ],
      );
      expect(result, isEmpty);
    });
  });

  // ─── build (layered history composition) ─────────────────────────────────

  group('build', () {
    test('zero pairs, no extras → empty unmodifiable history', () {
      final result = builder.build(
        messages: const [],
        allPairs: const [],
        currentIsDeep: false,
        cachedSummary: null,
      );
      expect(result.history, isEmpty);
      expect(result.shouldTriggerSummarization, isFalse);
      expect(result.oldPairCount, 0);
      // Confirm the returned list is unmodifiable so callers can't
      // accidentally mutate the wire payload after the fact.
      expect(() => result.history.add({'role': 'x', 'text': 'y'}),
          throwsUnsupportedError);
    });

    test('≤ threshold pairs without extras → straight verbatim path', () {
      final pairs = _flatPairs(5);
      final result = builder.build(
        messages: _conversation(5),
        allPairs: pairs,
        currentIsDeep: false,
        cachedSummary: null,
      );
      expect(result.history, pairs);
      expect(result.shouldTriggerSummarization, isFalse);
      expect(result.oldPairs, isEmpty);
    });

    test('= threshold (10 pairs) is still verbatim', () {
      final pairs = _flatPairs(10);
      final result = builder.build(
        messages: _conversation(10),
        allPairs: pairs,
        currentIsDeep: false,
        cachedSummary: null,
      );
      expect(result.history, pairs);
      expect(result.shouldTriggerSummarization, isFalse);
    });

    test('< threshold with sources → src + verbatim', () {
      final msgs = [
        _user('q1'),
        _assistant('a1', sources: const [
          FollowUpSourceRef(url: 'https://x'),
        ]),
      ];
      final pairs = _flatPairs(1);
      final result = builder.build(
        messages: msgs,
        allPairs: pairs,
        currentIsDeep: false,
        cachedSummary: null,
      );
      // 2 src entries + 2 pair entries.
      expect(result.history.length, 4);
      expect(result.history[0]['text'], contains('https://x'));
      expect(result.history[2], pairs[0]);
      expect(result.history[3], pairs[1]);
    });

    test('< threshold deep mode + lite history → src + hint + verbatim', () {
      final msgs = [
        _user('q1'),
        _assistant('a1',
            model: 'gemini-flash-lite',
            sources: const [FollowUpSourceRef(url: 'https://x')]),
      ];
      final pairs = _flatPairs(1);
      final result = builder.build(
        messages: msgs,
        allPairs: pairs,
        currentIsDeep: true,
        cachedSummary: null,
      );
      // 2 src + 2 hint + 2 pair = 6 entries.
      expect(result.history.length, 6);
      expect(result.history[0]['text'], contains('https://x'));
      expect(result.history[2]['text'], contains('lite model'));
      expect(result.history[4]['text'], 'q1');
    });

    test('> threshold lite mode → 5 recent pairs only when no summary', () {
      final pairs = _flatPairs(11);
      final result = builder.build(
        messages: _conversation(11),
        allPairs: pairs,
        currentIsDeep: false,
        cachedSummary: null,
      );
      // No summary, no sources, no hint → just the 5 most recent (10
      // entries).
      expect(result.history.length, 10);
      expect(result.history.first['text'], 'q7');
      expect(result.history.last['text'], 'a11');
      expect(result.shouldTriggerSummarization, isTrue);
      expect(result.oldPairCount, 6); // pairs 1..6
    });

    test('> threshold deep mode → 12 recent pairs window', () {
      final pairs = _flatPairs(20);
      final result = builder.build(
        messages: _conversation(20),
        allPairs: pairs,
        currentIsDeep: true,
        cachedSummary: null,
      );
      // 12 recent pairs verbatim (24 entries), plus no summary.
      expect(result.history.length, 24);
      expect(result.history.first['text'], 'q9');
      expect(result.history.last['text'], 'a20');
      expect(result.shouldTriggerSummarization, isTrue);
      expect(result.oldPairCount, 8);
    });

    test('> threshold deep mode but pairs < deep window → clamps to all', () {
      // 11 pairs < deep recent window of 12 → clamp keeps everything in
      // recentPairs and emits no oldPairs.
      final pairs = _flatPairs(11);
      final result = builder.build(
        messages: _conversation(11),
        allPairs: pairs,
        currentIsDeep: true,
        cachedSummary: null,
      );
      expect(result.history.length, 22); // all 11 pairs
      expect(result.recentPairs.length, 22);
      expect(result.oldPairs, isEmpty);
      // No olds → nothing meaningful to summarize. The builder must
      // suppress the trigger so the caller doesn't fire a no-op API
      // call against an empty payload.
      expect(result.shouldTriggerSummarization, isFalse);
      expect(result.oldPairCount, 0);
    });

    test('fresh summary covers all olds → no trigger, used as-is', () {
      final pairs = _flatPairs(15);
      const summary = FollowUpSummary(text: 'sum', pairsCovered: 10);
      final result = builder.build(
        messages: _conversation(15),
        allPairs: pairs,
        currentIsDeep: false,
        cachedSummary: summary,
      );
      // Layout: summary (2) + recent 5 pairs (10) = 12 entries.
      expect(result.history.length, 12);
      expect(result.history[0]['text'], contains('(10 exchanges)'));
      expect(result.history[2]['text'], 'q11');
      expect(result.shouldTriggerSummarization, isFalse);
      expect(result.oldPairCount, 10);
    });

    test('stale summary (covers fewer than oldPairCount) → trigger', () {
      final pairs = _flatPairs(15);
      const summary = FollowUpSummary(text: 'sum', pairsCovered: 5);
      final result = builder.build(
        messages: _conversation(15),
        allPairs: pairs,
        currentIsDeep: false,
        cachedSummary: summary,
      );
      // Stale summary still emitted in the wire history (best-available
      // memory), AND a re-summarization is requested.
      expect(result.history[0]['text'], contains('(5 exchanges)'));
      expect(result.shouldTriggerSummarization, isTrue);
      expect(result.oldPairCount, 10);
    });

    test('summary covers more than oldPairCount → still treated as fresh', () {
      // Defensive: a stored summary may have come from an older session
      // where the recent window was wider, leaving pairsCovered ahead
      // of the current oldPairCount. We use it without re-summarizing.
      final pairs = _flatPairs(15);
      const summary = FollowUpSummary(text: 'sum', pairsCovered: 12);
      final result = builder.build(
        messages: _conversation(15),
        allPairs: pairs,
        currentIsDeep: false,
        cachedSummary: summary,
      );
      expect(result.shouldTriggerSummarization, isFalse);
      expect(result.history[0]['text'], contains('(12 exchanges)'));
    });

    test('long conversation full layered shape (lite)', () {
      final pairs = _flatPairs(50);
      const summary = FollowUpSummary(text: 'big', pairsCovered: 45);
      final msgs = [
        ..._conversation(45, assistantModel: 'gemini-flash-lite'),
        ..._conversation(5).map((m) => m.role == 'assistant'
            ? _assistant(m.text, model: 'gemini-3.1-pro-preview')
            : m),
      ];
      // Mixed-model history → if current is deep, mode-mismatch hint
      // emitted. We test deep here.
      final result = builder.build(
        messages: msgs,
        allPairs: pairs,
        currentIsDeep: true,
        cachedSummary: summary,
      );
      // Layout: summary (2) + (no sources) + hint (2) + recent 12 pairs
      // (24) = 28 entries.
      expect(result.history.length, 28);
      expect(result.history[0]['text'], contains('(45 exchanges)'));
      expect(result.history[2]['text'], contains('lite model'));
      expect(result.history[4]['text'], 'q39');
      expect(result.shouldTriggerSummarization, isFalse);
    });

    test('history is unmodifiable for safety', () {
      final result = builder.build(
        messages: _conversation(11),
        allPairs: _flatPairs(11),
        currentIsDeep: false,
        cachedSummary: null,
      );
      expect(() => result.history.removeAt(0), throwsUnsupportedError);
      expect(() => result.recentPairs.add({'role': 'x', 'text': 'y'}),
          throwsUnsupportedError);
    });
  });

  // ─── shouldAutoSwitchToDeep ──────────────────────────────────────────────

  group('shouldAutoSwitchToDeep', () {
    test('below threshold → false', () {
      expect(
        builder.shouldAutoSwitchToDeep(
          pairCount: 9,
          currentIsDeep: false,
          alreadyAutoSwitched: false,
        ),
        isFalse,
      );
    });

    test('exactly at threshold → true (when eligible)', () {
      expect(
        builder.shouldAutoSwitchToDeep(
          pairCount: 10,
          currentIsDeep: false,
          alreadyAutoSwitched: false,
        ),
        isTrue,
      );
    });

    test('above threshold → true (when eligible)', () {
      expect(
        builder.shouldAutoSwitchToDeep(
          pairCount: 200,
          currentIsDeep: false,
          alreadyAutoSwitched: false,
        ),
        isTrue,
      );
    });

    test('already deep → never switch', () {
      expect(
        builder.shouldAutoSwitchToDeep(
          pairCount: 200,
          currentIsDeep: true,
          alreadyAutoSwitched: false,
        ),
        isFalse,
      );
    });

    test('already auto-switched once → never switch again (sticky)', () {
      expect(
        builder.shouldAutoSwitchToDeep(
          pairCount: 200,
          currentIsDeep: false,
          alreadyAutoSwitched: true,
        ),
        isFalse,
      );
    });

    test('honours custom threshold', () {
      const tight = FollowUpHistoryBuilder(
        config: FollowUpHistoryConfig(autoDeepThreshold: 3),
      );
      expect(
        tight.shouldAutoSwitchToDeep(
          pairCount: 2,
          currentIsDeep: false,
          alreadyAutoSwitched: false,
        ),
        isFalse,
      );
      expect(
        tight.shouldAutoSwitchToDeep(
          pairCount: 3,
          currentIsDeep: false,
          alreadyAutoSwitched: false,
        ),
        isTrue,
      );
    });

    test('decision is pure — same args → same answer (32 spins)', () {
      for (var i = 0; i < 32; i++) {
        expect(
          builder.shouldAutoSwitchToDeep(
            pairCount: 10,
            currentIsDeep: false,
            alreadyAutoSwitched: false,
          ),
          isTrue,
        );
      }
    });
  });

  // ─── End-to-end multi-turn simulation ─────────────────────────────────────

  group('end-to-end conversation simulation', () {
    test('lite chat under threshold stays verbatim every turn', () {
      var msgs = <FollowUpMessage>[];
      for (var turn = 1; turn <= 5; turn++) {
        msgs.add(_user('q$turn'));
        msgs.add(_assistant('a$turn',
            model: 'gemini-flash-lite',
            sources: [FollowUpSourceRef(url: 'https://t$turn')]));
        final pairs = builder.collectCompletedPairs(msgs);
        final result = builder.build(
          messages: msgs,
          allPairs: pairs,
          currentIsDeep: false,
          cachedSummary: null,
        );
        // Even with sources, history is bounded: src(2) + 2*turn pairs.
        expect(result.shouldTriggerSummarization, isFalse);
        expect(result.history.length, 2 + 2 * turn);
      }
    });

    test('crossing threshold switches to layered + requests summarization', () {
      final msgs = <FollowUpMessage>[];
      for (var turn = 1; turn <= 11; turn++) {
        msgs.add(_user('q$turn'));
        msgs.add(_assistant('a$turn', model: 'gemini-flash-lite'));
      }
      final pairs = builder.collectCompletedPairs(msgs);
      expect(pairs.length ~/ 2, 11);

      // First time over threshold, no summary yet.
      final lite = builder.build(
        messages: msgs,
        allPairs: pairs,
        currentIsDeep: false,
        cachedSummary: null,
      );
      expect(lite.shouldTriggerSummarization, isTrue);
      expect(lite.oldPairCount, 6);
      // 5 recent pairs (10) verbatim.
      expect(lite.history.length, 10);
      expect(lite.history.first['text'], 'q7');

      // Same conversation, but the user has now flipped to Deep — and
      // because all prior answers were lite, the mode-mismatch hint
      // appears. Wider verbatim window.
      final deep = builder.build(
        messages: msgs,
        allPairs: pairs,
        currentIsDeep: true,
        cachedSummary: null,
      );
      // Pair count (11) < deep recent window (12) → clamp = all
      // verbatim, no oldPairs. Hint still emitted.
      expect(deep.history.length, 2 + 22); // hint + all 11 pairs
      expect(deep.history[0]['text'], contains('lite model'));
      expect(deep.recentPairs.length, 22);
      expect(deep.oldPairs, isEmpty);
    });

    test('200-turn marathon stays bounded at every step', () {
      final msgs = <FollowUpMessage>[];
      var summary = const FollowUpSummary(text: 's', pairsCovered: 0);
      for (var turn = 1; turn <= 200; turn++) {
        msgs.add(_user('q$turn'));
        msgs.add(_assistant('a$turn', model: 'gemini-3.1-pro-preview'));
        final pairs = builder.collectCompletedPairs(msgs);

        // Pretend the background summarizer always catches up (covers
        // every old pair). This is the steady-state situation we
        // optimise for.
        final pairCount = pairs.length ~/ 2;
        if (pairCount > 10) {
          final oldPairCount = pairCount - 12; // deep window
          if (oldPairCount > 0) {
            summary = FollowUpSummary(text: 's', pairsCovered: oldPairCount);
          }
        }

        final result = builder.build(
          messages: msgs,
          allPairs: pairs,
          currentIsDeep: true,
          cachedSummary: summary.pairsCovered == 0 ? null : summary,
        );

        // Hard ceiling on history size:
        //   • summary pseudo-pair  → 2
        //   • mode-mismatch hint   → 0 (all-deep history)
        //   • source memory        → 0 (no sources here)
        //   • recent verbatim      → up to 12 pairs = 24
        // Total ≤ 26 entries regardless of pair count.
        expect(result.history.length, lessThanOrEqualTo(26),
            reason: 'turn $turn busted the ceiling');
        // Once steady-state, no trigger.
        if (pairCount > 10) {
          expect(result.shouldTriggerSummarization, isFalse,
              reason: 'turn $turn wrongly asked to re-summarize');
        }
      }
    });
  });
}
