// ─────────────────────────────────────────────────────────────────────────────
//  FollowUp History Builder — pure, deterministic, fully unit-tested
// ─────────────────────────────────────────────────────────────────────────────
//
// Owns the "what does the wire history look like" decision for every chat
// follow-up turn (news article + InsightAI search). Extracted from the
// chat-sheet State classes so the layered-history construction logic can
// be exercised in isolation by `test/core/services/followup_history_test.dart`
// — without booting Riverpod, Drift, the AI service or a widget tree.
//
// ── Layered history shape ────────────────────────────────────────────────────
//
//   1. [summary-context pseudo-pair]   — cumulative deep-grade digest of
//                                        pairs 1…(N-K). Only emitted when
//                                        pair count > [summarizeThreshold].
//   2. [source-memory pseudo-pair]     — deduped most-recent-first list
//                                        of every URL cited in prior
//                                        assistant turns, capped at
//                                        [sourceMemoryMax]. Lets the
//                                        model re-ground in known
//                                        sources without bloating
//                                        context with snippets.
//   3. [mode-mismatch pseudo-pair]     — emitted only when current turn
//                                        is Deep AND the recent verbatim
//                                        window has lite/flash answers.
//                                        Tells the deep model to verify
//                                        rather than rubber-stamp earlier
//                                        brevity.
//   4. [recent K full pairs]           — verbatim for short-range
//                                        coherence. K adapts to mode:
//                                        [recentPairsLite] or
//                                        [recentPairsDeep].
//   5. <new user question>             — appended by caller.
//
// ── Determinism guarantees ───────────────────────────────────────────────────
//
// Every public function is pure:
//   • No I/O.
//   • No random / time-dependent inputs.
//   • Same arguments → byte-for-byte identical output.
//
// This is a load-bearing property: the tests check not just the count of
// emitted blocks but the EXACT structure of each. If a future refactor
// changes wording it must update the tests in lock-step.

import 'package:flutter/foundation.dart';

// ── Plain data types (no Flutter dependency) ─────────────────────────────────

/// A neutral chat-message DTO used for history construction. Both
/// `ArticleFollowUpStore` and `SearchFollowUpStore` adapt their internal
/// `_ChatMessage` instances to this shape before calling the builder.
@immutable
class FollowUpMessage {
  const FollowUpMessage({
    required this.role,
    required this.text,
    this.isLoading = false,
    this.isError = false,
    this.model = '',
    this.sources = const [],
  });

  /// Either `'user'` or `'assistant'`. Anything else is treated as
  /// "skip this row" by every helper in this module.
  final String role;
  final String text;
  final bool isLoading;
  final bool isError;
  final String model;
  final List<FollowUpSourceRef> sources;
}

/// Source citation reference. Only [url] is required; [title] is purely
/// for human-readable formatting in the source-memory block.
@immutable
class FollowUpSourceRef {
  const FollowUpSourceRef({required this.url, this.title = ''});
  final String url;
  final String title;
}

/// Cached conversation summary. The summary covers exactly
/// [pairsCovered] (user, assistant) pairs starting from pair #1.
@immutable
class FollowUpSummary {
  const FollowUpSummary({required this.text, required this.pairsCovered});
  final String text;
  final int pairsCovered;
}

// ── Configuration ────────────────────────────────────────────────────────────

/// Tunable thresholds for the layered-history builder. Defaults match
/// what the chat sheets ship to production today; tests instantiate
/// custom configs to exercise boundary conditions deterministically.
@immutable
class FollowUpHistoryConfig {
  const FollowUpHistoryConfig({
    this.summarizeThreshold = 10,
    this.recentPairsLite = 5,
    this.recentPairsDeep = 12,
    this.sourceMemoryMax = 20,
    this.autoDeepThreshold = 10,
  })  : assert(summarizeThreshold > 0),
        assert(recentPairsLite > 0),
        assert(recentPairsDeep >= recentPairsLite),
        assert(sourceMemoryMax >= 0),
        assert(autoDeepThreshold > 0);

  /// When the pair count exceeds this value, the wire history switches
  /// from "all-verbatim" to the layered (summary + recent) layout.
  final int summarizeThreshold;

  /// Number of most-recent verbatim pairs included when the active turn
  /// is in Lite mode.
  final int recentPairsLite;

  /// Number of most-recent verbatim pairs included when the active turn
  /// is in Deep mode (wider window — deep models afford more context).
  final int recentPairsDeep;

  /// Hard cap on unique source URLs surfaced in the source-memory block.
  /// Set to 0 to disable source memory entirely.
  final int sourceMemoryMax;

  /// Pair count at which the UI auto-upgrades Lite → Deep. Equal to
  /// [summarizeThreshold] in production so the very turn that begins
  /// summarization also gets the deeper answering model.
  final int autoDeepThreshold;
}

// ── Composition result ───────────────────────────────────────────────────────

/// Output of [FollowUpHistoryBuilder.build]. The wire history is in
/// [history]; the additional fields tell the caller whether/how to fire
/// background side-effects (re-summarization).
@immutable
class FollowUpHistoryResult {
  const FollowUpHistoryResult({
    required this.history,
    required this.shouldTriggerSummarization,
    required this.oldPairs,
    required this.oldPairCount,
    required this.recentPairs,
  });

  /// The exact `[{role, text}, ...]` list to send on the wire.
  final List<Map<String, String>> history;

  /// True when the caller should fire a background `summarizeHistory`
  /// for [oldPairs]. False when no summarization is needed (short
  /// conversation OR cached summary already covers all old pairs).
  final bool shouldTriggerSummarization;

  /// The "graduated" pairs that should be summarized. Populated only
  /// when [shouldTriggerSummarization] is true.
  final List<Map<String, String>> oldPairs;

  /// Pair count of [oldPairs] (i.e. `oldPairs.length / 2`). Used by the
  /// caller's [FollowUpSummary.pairsCovered] write.
  final int oldPairCount;

  /// The recent verbatim pairs that were spliced into [history]. Useful
  /// for diagnostics + tests; not directly used by the wire payload
  /// (already concatenated into [history]).
  final List<Map<String, String>> recentPairs;
}

// ── Builder ──────────────────────────────────────────────────────────────────

/// Stateless, idempotent layered-history composer. Construct once
/// (cheap — just holds a config) and reuse across many turns.
class FollowUpHistoryBuilder {
  const FollowUpHistoryBuilder(
      {this.config = const FollowUpHistoryConfig()});

  final FollowUpHistoryConfig config;

  // ── Pair collection ───────────────────────────────────────────────────────

  /// Walks [messages] and emits `{role, text}` entries for every
  /// (user, assistant) tuple where BOTH sides are finalized — i.e.
  /// neither side has `isLoading=true` nor `isError=true`.
  ///
  /// Pairing is greedy left-to-right: each user message is paired with
  /// the immediately following assistant message (when present and
  /// finalized). Unmatched users — including a trailing "orphan" user
  /// awaiting an assistant — are skipped entirely.
  ///
  /// When [excludeOrphanTail] is true, the last message is treated as
  /// an orphaned user (no assistant counterpart yet) and excluded from
  /// pairing even if it would otherwise be the start of a (truncated)
  /// pair. This matches the pair-collection semantics used by the
  /// chat-sheet "auto-retry orphaned question" path: the orphan must
  /// be re-sent verbatim and not absorbed into the history.
  List<Map<String, String>> collectCompletedPairs(
    List<FollowUpMessage> messages, {
    bool excludeOrphanTail = false,
  }) {
    final upperBound = excludeOrphanTail
        ? (messages.length - 1).clamp(0, messages.length)
        : messages.length;
    final pairs = <Map<String, String>>[];
    for (var i = 0; i < upperBound; i++) {
      final m = messages[i];
      if (m.isLoading || m.isError) continue;
      if (m.role != 'user') continue;
      // Look-ahead bound mirrors [upperBound] so the orphan tail is
      // never consulted as a candidate "assistant" partner.
      if (i + 1 >= upperBound) break;
      final next = messages[i + 1];
      if (next.role != 'assistant') continue;
      if (next.isLoading || next.isError) continue;
      pairs.add({'role': 'user', 'text': m.text});
      pairs.add({'role': 'assistant', 'text': next.text});
      i++; // skip past the assistant we just consumed
    }
    return pairs;
  }

  // ── Source memory ─────────────────────────────────────────────────────────

  /// Returns a 2-element pseudo-pair listing unique source URLs cited
  /// in past finalized assistant turns, most-recent-first, capped at
  /// [FollowUpHistoryConfig.sourceMemoryMax].
  ///
  /// Returns `[]` (length 0) when there are no eligible sources, so
  /// callers can spread the result freely with no extra null-checks.
  ///
  /// Filtering rules (so the wire payload stays tight):
  ///   • Only `assistant` messages are scanned.
  ///   • Loading/error messages are skipped.
  ///   • Empty / whitespace-only URLs are dropped.
  ///   • URLs are deduplicated by exact string match after trimming.
  List<Map<String, String>> buildSourceMemoryBlock(
      List<FollowUpMessage> messages) {
    if (config.sourceMemoryMax == 0) return const [];
    if (messages.isEmpty) return const [];
    final seen = <String>{};
    final ordered = <FollowUpSourceRef>[];
    // Walk most-recent-first so the cap retains the freshest URLs.
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role != 'assistant' || m.isLoading || m.isError) continue;
      for (final s in m.sources) {
        final url = s.url.trim();
        if (url.isEmpty) continue;
        if (seen.add(url)) {
          ordered.add(FollowUpSourceRef(url: url, title: s.title.trim()));
          if (ordered.length >= config.sourceMemoryMax) break;
        }
      }
      if (ordered.length >= config.sourceMemoryMax) break;
    }
    if (ordered.isEmpty) return const [];
    final lines = ordered.map((r) {
      final title = r.title.isEmpty ? '' : ' — ${r.title}';
      return '- ${r.url}$title';
    }).join('\n');
    return [
      {
        'role': 'user',
        'text':
            '[Sources cited earlier in this conversation that may be useful '
                'for continuity and re-grounding]:\n$lines',
      },
      {
        'role': 'assistant',
        'text':
            'Noted — I will reference these when relevant and re-verify them when the question demands it.',
      },
    ];
  }

  // ── Mode-mismatch hint ────────────────────────────────────────────────────

  /// Returns the "verify, don't rubber-stamp" hint pseudo-pair when —
  /// and only when — the current turn is in Deep mode AND at least one
  /// finalized assistant message in [messages] was produced by a
  /// lite/flash model. Returns `[]` otherwise.
  ///
  /// Detection uses case-insensitive substring match on
  /// [FollowUpMessage.model] for the tokens `lite` and `flash`. This
  /// matches the model-id convention used elsewhere in the app
  /// (e.g. `gemini-3.1-flash-lite-preview`, `grok-4-1-fast-non-reasoning`
  /// is intentionally NOT considered lite — same as the chat-sheet UI).
  List<Map<String, String>> buildModeMismatchHint({
    required bool currentIsDeep,
    required List<FollowUpMessage> messages,
  }) {
    if (!currentIsDeep) return const [];
    final hasLite = messages.any((m) {
      if (m.role != 'assistant' || m.isLoading || m.isError) return false;
      final id = m.model.toLowerCase();
      return id.contains('lite') || id.contains('flash');
    });
    if (!hasLite) return const [];
    return const [
      {
        'role': 'user',
        'text':
            '[Note: some earlier answers in this conversation were produced '
                'with a faster lite model. Where the current question depends on '
                'those, verify the facts against fresh evidence and elaborate '
                'with the depth Deep mode allows.]',
      },
      {
        'role': 'assistant',
        'text':
            'Understood — I will validate and expand where helpful.',
      },
    ];
  }

  // ── Layered history composition ───────────────────────────────────────────

  /// Composes the full wire history per the layered structure documented
  /// at the top of this file.
  ///
  /// The caller is responsible for:
  ///   1. Calling [collectCompletedPairs] to build [allPairs] from the
  ///      live message list.
  ///   2. Looking up the cached summary for this chat from its store.
  ///   3. Reacting to [FollowUpHistoryResult.shouldTriggerSummarization]
  ///      by firing a background `summarizeHistory` call (the builder
  ///      itself never performs I/O).
  FollowUpHistoryResult build({
    required List<FollowUpMessage> messages,
    required List<Map<String, String>> allPairs,
    required bool currentIsDeep,
    FollowUpSummary? cachedSummary,
  }) {
    final recentToKeep =
        currentIsDeep ? config.recentPairsDeep : config.recentPairsLite;
    final pairCount = allPairs.length ~/ 2;

    final modeMismatchHint = buildModeMismatchHint(
      currentIsDeep: currentIsDeep,
      messages: messages,
    );
    final sourceMemory = buildSourceMemoryBlock(messages);

    // ── Short conversations: send everything verbatim. ─────────────────────
    if (pairCount <= config.summarizeThreshold) {
      if (sourceMemory.isEmpty && modeMismatchHint.isEmpty) {
        return FollowUpHistoryResult(
          history: List<Map<String, String>>.unmodifiable(allPairs),
          shouldTriggerSummarization: false,
          oldPairs: const [],
          oldPairCount: 0,
          recentPairs: List<Map<String, String>>.unmodifiable(allPairs),
        );
      }
      final history = <Map<String, String>>[
        ...sourceMemory,
        ...modeMismatchHint,
        ...allPairs,
      ];
      return FollowUpHistoryResult(
        history: List<Map<String, String>>.unmodifiable(history),
        shouldTriggerSummarization: false,
        oldPairs: const [],
        oldPairCount: 0,
        recentPairs: List<Map<String, String>>.unmodifiable(allPairs),
      );
    }

    // ── Long conversations: layered (summary + src + hint + recent). ───────
    final recentCount = recentToKeep * 2;
    // Defensive clamp: a misconfigured caller could pass fewer pairs than
    // the recent window — in that case keep everything verbatim.
    final clampedRecent =
        recentCount > allPairs.length ? allPairs.length : recentCount;
    final recentStart = allPairs.length - clampedRecent;
    final oldPairs = allPairs.sublist(0, recentStart);
    final recentPairs = allPairs.sublist(recentStart);
    final oldPairCount = oldPairs.length ~/ 2;

    final summaryPair = (cachedSummary != null)
        ? <Map<String, String>>[
            {
              'role': 'user',
              'text':
                  '[Summary of our earlier conversation (${cachedSummary.pairsCovered} exchanges)]:\n${cachedSummary.text}',
            },
            {
              'role': 'assistant',
              'text':
                  'I have context from our earlier discussion and will use it to answer your questions.',
            },
          ]
        : <Map<String, String>>[];

    final history = <Map<String, String>>[
      ...summaryPair,
      ...sourceMemory,
      ...modeMismatchHint,
      ...recentPairs,
    ];

    // Trigger summarization when there is real work to do:
    //   • at least one graduated old pair to summarize, AND
    //   • either no cached summary at all, OR the cached summary is
    //     stale (covers fewer than the current graduated old-pair
    //     count).
    //
    // Skipping when [oldPairCount] is 0 prevents wasted API calls in
    // the wide-window-clamp case (e.g. 11 pairs in Deep mode, where
    // the recent window of 12 already absorbs everything verbatim).
    final shouldTrigger = oldPairCount > 0 &&
        (cachedSummary == null ||
            cachedSummary.pairsCovered < oldPairCount);

    return FollowUpHistoryResult(
      history: List<Map<String, String>>.unmodifiable(history),
      shouldTriggerSummarization: shouldTrigger,
      oldPairs: List<Map<String, String>>.unmodifiable(oldPairs),
      oldPairCount: oldPairCount,
      recentPairs: List<Map<String, String>>.unmodifiable(recentPairs),
    );
  }

  // ── Auto-switch decision ──────────────────────────────────────────────────

  /// Decides whether the UI should automatically promote the active
  /// turn from Lite → Deep. Pure: caller is responsible for actually
  /// flipping the toggle, showing the snackbar and firing the memory
  /// consolidation pass.
  ///
  /// Returns true iff ALL of:
  ///   • [pairCount] >= [FollowUpHistoryConfig.autoDeepThreshold]
  ///   • [currentIsDeep] is false (we never override an already-deep
  ///     state)
  ///   • [alreadyAutoSwitched] is false (sticky one-time upgrade per
  ///     sheet session — preserves user's manual choice if they flip
  ///     back to Lite afterwards)
  bool shouldAutoSwitchToDeep({
    required int pairCount,
    required bool currentIsDeep,
    required bool alreadyAutoSwitched,
  }) {
    if (currentIsDeep) return false;
    if (alreadyAutoSwitched) return false;
    return pairCount >= config.autoDeepThreshold;
  }
}
