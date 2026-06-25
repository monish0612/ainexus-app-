import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

/// Shared "magazine-formatted" renderer for an AI quick summary.
///
/// This is the same lede / body / KEY FACTS layout the For You catch-up
/// reader ([SummaryReaderScreen]) uses, lifted into a reusable widget so the
/// on-demand "AI Summarize" action in the article detail screen renders an
/// IDENTICAL interactive summary card. The For You reader keeps its own
/// private copy untouched to avoid any risk to that battle-tested flow.
///
/// Backend (rev. 4 prompt) returns a structured plain-text string with:
///   * paragraph 1            -> LEDE (1-2 sentence punchy takeaway)
///   * blank line, paragraph N -> BODY paragraphs (context / details / impact)
///   * optional trailing block where every line starts with "* "
///                             -> KEY FACTS (3-5 bulleted scannable facts)
///
/// Backward-compatible: if the summary is a single plain paragraph (no
/// blank-line separators), it renders as one body paragraph (no lede
/// emphasis), matching the legacy appearance.
class NewsSummaryView extends StatelessWidget {
  const NewsSummaryView({
    super.key,
    required this.summary,
    required this.colors,
    required this.cat,
    this.animate = true,
  });

  final String summary;
  final AppColors colors;
  final Color cat;

  /// Fade/translate the card in on first build. Disable for instant render
  /// (e.g. when toggling back to an already-cached summary).
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final parts = _parseNewsSummary(summary);

    final card = Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cat.withValues(alpha: 0.20)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.bg2,
            Color.alphaBlend(cat.withValues(alpha: 0.04), colors.bg2),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: cat.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 13, color: cat),
              const SizedBox(width: 6),
              Text(
                'QUICK SUMMARY',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: cat,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cat.withValues(alpha: 0.32),
                        cat.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) SizedBox(height: _gapBefore(parts[i])),
            _NewsSummaryPartView(part: parts[i], colors: colors, cat: cat),
          ],
        ],
      ),
    );

    if (!animate) return card;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
      child: card,
    );
  }

  double _gapBefore(_NewsSummaryPart part) {
    switch (part.kind) {
      case _NewsSummaryPartKind.lede:
        return 16;
      case _NewsSummaryPartKind.body:
        return 16;
      case _NewsSummaryPartKind.bullets:
        return 18;
    }
  }
}

enum _NewsSummaryPartKind { lede, body, bullets }

@immutable
class _NewsSummaryPart {
  const _NewsSummaryPart.lede(this.text)
      : kind = _NewsSummaryPartKind.lede,
        bullets = const <String>[];
  const _NewsSummaryPart.body(this.text)
      : kind = _NewsSummaryPartKind.body,
        bullets = const <String>[];
  const _NewsSummaryPart.bullets(this.bullets)
      : kind = _NewsSummaryPartKind.bullets,
        text = '';

  final _NewsSummaryPartKind kind;
  final String text;
  final List<String> bullets;
}

/// Splits a structured summary string into renderable parts. Mirrors the
/// algorithm in [SummaryReaderScreen]; see that file for the full rationale.
List<_NewsSummaryPart> _parseNewsSummary(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const <_NewsSummaryPart>[];

  final paragraphs = trimmed
      .split(RegExp(r'\n[ \t]*\n+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  if (paragraphs.length == 1) {
    return [_NewsSummaryPart.body(paragraphs.single)];
  }

  final parts = <_NewsSummaryPart>[];
  var ledeAssigned = false;
  for (final p in paragraphs) {
    final lines = p.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final isBulletBlock = lines.length >= 2 &&
        lines.every((l) {
          final t = l.trimLeft();
          return t.startsWith('• ') ||
              t.startsWith('- ') ||
              t.startsWith('* ');
        });

    if (isBulletBlock) {
      final bullets = lines
          .map((l) => l.trimLeft().substring(2).trim())
          .where((b) => b.isNotEmpty)
          .toList();
      if (bullets.isNotEmpty) {
        parts.add(_NewsSummaryPart.bullets(bullets));
      }
    } else if (!ledeAssigned) {
      parts.add(_NewsSummaryPart.lede(p));
      ledeAssigned = true;
    } else {
      parts.add(_NewsSummaryPart.body(p));
    }
  }

  return parts;
}

class _NewsSummaryPartView extends StatelessWidget {
  const _NewsSummaryPartView({
    required this.part,
    required this.colors,
    required this.cat,
  });

  final _NewsSummaryPart part;
  final AppColors colors;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    switch (part.kind) {
      case _NewsSummaryPartKind.lede:
        return Text(
          part.text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17.5,
            height: 1.45,
            color: colors.text,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w700,
          ),
        );
      case _NewsSummaryPartKind.body:
        return Text(
          part.text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15.5,
            height: 1.62,
            color: colors.text2,
            letterSpacing: -0.05,
            fontWeight: FontWeight.w500,
          ),
        );
      case _NewsSummaryPartKind.bullets:
        return _NewsKeyFactsList(bullets: part.bullets, colors: colors, cat: cat);
    }
  }
}

class _NewsKeyFactsList extends StatelessWidget {
  const _NewsKeyFactsList({
    required this.bullets,
    required this.colors,
    required this.cat,
  });

  final List<String> bullets;
  final AppColors colors;
  final Color cat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 12,
              decoration: BoxDecoration(
                color: cat,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'KEY FACTS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: cat,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < bullets.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 8, right: 10),
                decoration: BoxDecoration(
                  color: cat,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  bullets[i],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.5,
                    color: colors.text,
                    letterSpacing: -0.05,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
