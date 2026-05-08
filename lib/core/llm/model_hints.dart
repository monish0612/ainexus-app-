/// Strict, side-effect-free builder for the model-routing fields that the
/// backend's grounded-search / article-followup / search-followup /
/// deep-research endpoints consume.
///
/// ─── Why this exists ────────────────────────────────────────────────────────
/// The backend selects the actual LLM (and decides whether to enable Google
/// Search grounding) based on the combination of `provider` + `mode` plus the
/// matching model id field. Forwarding *any other* model id field is risky:
/// if the backend's resolver is even a little permissive (e.g.
/// `body.deepModel ?? body.liteModel ?? default`) a "lite" request can be
/// silently routed to a "deep" / non-grounded model. That's exactly the bug
/// that broke real-time information for InsightAI Lite searches.
///
/// This builder enforces two invariants on every outgoing request:
///
///   1. PROVIDER ISOLATION — when provider='gemini', no `xgrok*` field is
///      ever sent. When provider='xgrok', `deepModel` (the Gemini deep slot)
///      is never sent.
///   2. MODE ISOLATION — only the model id matching the active mode is sent.
///      Lite requests do not carry a deep model id, deep requests do not
///      carry a lite model id, etc.
///
/// All callers funnel through here, so the invariants hold for every endpoint
/// even if a future caller forgets to pre-filter its arguments.
library;

class ModelHints {
  const ModelHints._();

  /// Canonical mode names. The wire spec only accepts these three.
  static const String modeLite = 'lite';
  static const String modeDeep = 'deep';
  static const String modeThinking = 'thinking';

  static const String providerGemini = 'gemini';
  static const String providerXGrok = 'xgrok';

  /// Returns the model-routing fields to merge into a request body. The
  /// returned map always contains a normalized `mode` and `provider`, plus
  /// at most ONE model id field — the one that matches the active
  /// (provider, mode) pair. Unrelated arguments are dropped.
  ///
  /// Empty / whitespace-only strings are treated as absent.
  ///
  /// [legacyXgrokModel] is the pre-Lite/Deep/Thinking single-slot xGrok
  /// override the backend used to accept. It is honoured only when the
  /// active mode is `lite` and no `xgrokLiteModel` was supplied. The raw
  /// `xgrokModel` field is also forwarded in that case so older backend
  /// builds keep working.
  static Map<String, dynamic> build({
    String? provider,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    String? legacyXgrokModel,
  }) {
    final p = _normalizeProvider(provider);
    final m = _normalizeMode(mode, provider: p);

    final out = <String, dynamic>{
      'provider': p,
      'mode': m,
    };

    if (p == providerXGrok) {
      // xGrok has no server-side "default" model — every mode needs an
      // explicit slot. We forward only the slot for the active mode and
      // drop the others to prevent any backend-side resolver ambiguity.
      switch (m) {
        case modeDeep:
          final v = _clean(xgrokDeepModel);
          if (v != null) out['xgrokDeepModel'] = v;
          break;
        case modeThinking:
          final v = _clean(xgrokThinkingModel);
          if (v != null) out['xgrokThinkingModel'] = v;
          break;
        case modeLite:
        default:
          final lite = _clean(xgrokLiteModel) ?? _clean(legacyXgrokModel);
          if (lite != null) out['xgrokLiteModel'] = lite;
          // Older backend builds keyed off the raw `xgrokModel` field. We
          // mirror the lite slot into it so an older deployment keeps
          // working without reverting the per-mode plumbing on the client.
          final legacy = _clean(legacyXgrokModel);
          if (legacy != null) out['xgrokModel'] = legacy;
          break;
      }
    } else {
      // Gemini path. Deep & Thinking both use the Gemini "deep" slot. Lite
      // forwards the user-configured `liteModel` so the backend pins the
      // exact Flash/Lite version the user selected in Settings (synced
      // cross-device). When [liteModel] is absent the backend falls back to
      // its auto-discovered lite model, preserving legacy behaviour.
      if (m == modeDeep || m == modeThinking) {
        final v = _clean(deepModel);
        if (v != null) out['deepModel'] = v;
      } else {
        final v = _clean(liteModel);
        if (v != null) out['liteModel'] = v;
      }
    }

    return out;
  }

  /// Convenience: merge [build] output into [body] in-place and return it.
  /// Existing keys in [body] win — callers should not pre-populate model
  /// hint fields, but if they do, the explicit value is respected.
  static Map<String, dynamic> mergeInto(
    Map<String, dynamic> body, {
    String? provider,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    String? legacyXgrokModel,
  }) {
    final hints = build(
      provider: provider,
      mode: mode,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
      legacyXgrokModel: legacyXgrokModel,
    );
    hints.forEach((k, v) {
      body.putIfAbsent(k, () => v);
    });
    return body;
  }

  // ── Internals ────────────────────────────────────────────────────────────

  static String _normalizeProvider(String? raw) {
    final t = raw?.trim().toLowerCase();
    if (t == providerXGrok) return providerXGrok;
    return providerGemini;
  }

  static String _normalizeMode(String? raw, {required String provider}) {
    final t = raw?.trim().toLowerCase();
    if (t == modeDeep) return modeDeep;
    if (t == modeThinking) {
      // Thinking is an xGrok-only depth. Collapse it to deep on the Gemini
      // side so the backend's mode dispatcher always sees a value it knows
      // how to route.
      return provider == providerXGrok ? modeThinking : modeDeep;
    }
    return modeLite;
  }

  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
