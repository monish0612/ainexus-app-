/// How wide a "nuke" reached. Drives the result window's copy/visuals.
enum NukeScope {
  /// Expense-domain reset (expenses + budget + salary). Triggered from the
  /// Expense tab search boxes.
  expense,

  /// Full from-scratch app wipe — every local table reset to zero rows.
  /// Triggered from the InsightAI search box.
  full,

  /// News-only wipe — deletes EVERY article (including saved ones), locally
  /// and on the server. Triggered by the `nuke` command in the News tab's
  /// saved-articles search box.
  news,
}

/// A single line in the post-nuke "what got cleared" window.
class NukeLine {
  const NukeLine({
    required this.label,
    required this.emoji,
    required this.count,
    this.cloudSynced,
  });

  final String label;
  final String emoji;

  /// Rows removed for this domain (captured *before* the wipe).
  final int count;

  /// `true` = cleared on the cloud too (confirmed), `false` = cloud clear is
  /// queued for retry, `null` = local-only domain (no bulk cloud delete — it
  /// re-hydrates from the server on next use, so there is nothing to sync).
  final bool? cloudSynced;
}

/// Structured, UI-ready summary of a completed nuke. Both the expense-scope
/// and full-app nuke services emit this so a single window can render either.
class NukeReport {
  const NukeReport({
    required this.scope,
    required this.lines,
    required this.fullySynced,
    required this.elapsedMs,
  });

  final NukeScope scope;
  final List<NukeLine> lines;

  /// Every cloud-backed domain confirmed cleared remotely.
  final bool fullySynced;
  final int elapsedMs;

  /// Total rows removed across all reported domains.
  int get totalCleared => lines.fold(0, (sum, l) => sum + l.count);

  /// Lines that actually had data — the window only animates these in.
  List<NukeLine> get nonEmptyLines =>
      lines.where((l) => l.count > 0).toList(growable: false);
}
