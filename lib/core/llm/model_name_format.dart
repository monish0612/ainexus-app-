/// Pretty-prints a backend model id (as echoed in the response `model` field)
/// into a short, human-friendly badge label like "Gemini 3.1 Flash Lite
/// Preview" or "Gemini 2.5 Flash" or "GPT-4".
///
/// Lives here (not inside any screen) so it can be unit-tested without a
/// widget tree. Unknown shapes degrade gracefully to the original id, lightly
/// truncated.
String shortModelName(String model) {
  final lower = model.toLowerCase().trim();
  if (lower.isEmpty) return '';

  if (lower.contains('gemini')) {
    // Examples that must round-trip:
    //   "gemini/gemini-2.5-flash"             → "Gemini 2.5 Flash"
    //   "gemini-3.1-pro"                      → "Gemini 3.1 Pro"
    //   "gemini-3.1-flash-lite-preview"       → "Gemini 3.1 Flash Lite Preview"
    //   "gemini/gemini-3.1-flash-lite-preview" → same as above
    //   "gemini"                              → "Gemini"
    final stripped = lower.replaceFirst(RegExp(r'^gemini/'), '');
    final m =
        RegExp(r'^gemini-(\d+(?:\.\d+)?)(?:-(.+))?$').firstMatch(stripped);
    if (m == null) return 'Gemini';
    final ver = m.group(1) ?? '';
    final tail = m.group(2) ?? '';
    if (tail.isEmpty) return 'Gemini $ver';
    final pretty = tail
        .split('-')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
    return 'Gemini $ver $pretty';
  }

  if (lower.contains('grok')) {
    // "grok-4-1-fast-reasoning" → "Grok 4 1 Fast Reasoning"
    // We deliberately skip a leading "x" if present (e.g. "xgrok-...").
    final stripped = lower.replaceFirst(RegExp(r'^x?grok[-/]?'), '');
    if (stripped.isEmpty) return 'Grok';
    final pretty = stripped
        .split(RegExp(r'[-_]'))
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
    return 'Grok $pretty';
  }

  if (lower.contains('llama')) return 'Llama 3.3';
  if (lower.contains('gpt-4')) return 'GPT-4';
  if (lower.contains('gpt-3')) return 'GPT-3.5';
  if (lower.contains('claude')) return 'Claude';

  if (model.length > 22) return '${model.substring(0, 20)}\u2026';
  return model;
}
