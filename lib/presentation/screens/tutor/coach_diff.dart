import 'dart:math';

import 'package:flutter/material.dart';

/// Span builders for the AI Coach "Corrected" card.
///
/// Two presentations of the same correction:
///   * [coachCleanSpans] — the default. Renders ONLY the final corrected
///     sentence (removed words are dropped entirely, no strikethrough), with
///     the words that were added/changed relative to the original subtly
///     highlighted. This keeps the result fully readable.
///   * [coachDiffSpans] — the opt-in "Changes" view. A full word-level diff
///     showing removals struck through and additions highlighted.
///
/// Both share the same LCS alignment so the two views stay consistent.
List<List<int>> _lcsTable(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] =
          a[i] == b[j] ? 1 + dp[i + 1][j + 1] : max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  return dp;
}

List<String> _words(String s) =>
    s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Full word-level diff: unchanged words in [textColor], removals struck
/// through in [removedColor], additions emphasised in [addedColor].
List<InlineSpan> coachDiffSpans({
  required String original,
  required String corrected,
  required Color textColor,
  required Color removedColor,
  required Color addedColor,
}) {
  final ow = _words(original);
  final cw = _words(corrected);
  final n = ow.length;
  final m = cw.length;
  final dp = _lcsTable(ow, cw);

  final spans = <InlineSpan>[];
  var i = 0;
  var j = 0;

  void gap() {
    if (spans.isNotEmpty) {
      spans.add(TextSpan(text: ' ', style: TextStyle(color: textColor)));
    }
  }

  while (i < n && j < m) {
    if (ow[i] == cw[j]) {
      gap();
      spans.add(TextSpan(text: ow[i], style: TextStyle(color: textColor)));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      gap();
      spans.add(
        TextSpan(
          text: ow[i],
          style: TextStyle(
            color: removedColor,
            decoration: TextDecoration.lineThrough,
            decorationColor: removedColor,
          ),
        ),
      );
      i++;
    } else {
      gap();
      spans.add(
        TextSpan(
          text: cw[j],
          style: TextStyle(color: addedColor, fontWeight: FontWeight.w600),
        ),
      );
      j++;
    }
  }
  while (i < n) {
    gap();
    spans.add(
      TextSpan(
        text: ow[i],
        style: TextStyle(
          color: removedColor,
          decoration: TextDecoration.lineThrough,
          decorationColor: removedColor,
        ),
      ),
    );
    i++;
  }
  while (j < m) {
    gap();
    spans.add(
      TextSpan(
        text: cw[j],
        style: TextStyle(color: addedColor, fontWeight: FontWeight.w600),
      ),
    );
    j++;
  }
  return spans;
}

/// Clean corrected-text spans: renders ONLY the corrected sentence. Removed
/// words are omitted (never struck through), and the words that were newly
/// added/changed relative to the original are emphasised in [addedColor] so
/// the improvements are still visible while staying readable.
List<InlineSpan> coachCleanSpans({
  required String original,
  required String corrected,
  required Color textColor,
  required Color addedColor,
}) {
  final ow = _words(original);
  final cw = _words(corrected);
  final n = ow.length;
  final m = cw.length;
  final dp = _lcsTable(ow, cw);

  final spans = <InlineSpan>[];
  var i = 0;
  var j = 0;

  void emit(String text, {required bool added}) {
    if (spans.isNotEmpty) {
      spans.add(TextSpan(text: ' ', style: TextStyle(color: textColor)));
    }
    spans.add(
      TextSpan(
        text: text,
        style: added
            ? TextStyle(color: addedColor, fontWeight: FontWeight.w700)
            : TextStyle(color: textColor),
      ),
    );
  }

  while (i < n && j < m) {
    if (ow[i] == cw[j]) {
      emit(cw[j], added: false);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      // Removed from the original — intentionally skipped (not rendered).
      i++;
    } else {
      emit(cw[j], added: true);
      j++;
    }
  }
  // Any remaining corrected words are net additions.
  while (j < m) {
    emit(cw[j], added: true);
    j++;
  }
  return spans;
}
