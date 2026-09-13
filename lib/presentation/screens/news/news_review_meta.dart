import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Structured rating / pros / cons block the backend prepends to review
/// articles (Gizbot gadgets, Only Kollywood, TOI English films):
///
///     **⭐ Rating: 3.75 / 5**
///
///     #### ✅ Pros
///     - …
///
///     #### ❌ Cons
///     - …
///
///     ---
@immutable
class NewsReviewMeta {
  const NewsReviewMeta({
    required this.rating,
    required this.pros,
    required this.cons,
    required this.bodyAfter,
  });

  final String rating;
  final List<String> pros;
  final List<String> cons;

  /// Markdown body with the meta header stripped.
  final String bodyAfter;

  bool get isEmpty => rating.isEmpty && pros.isEmpty && cons.isEmpty;

  /// Numeric score when [rating] is like `3.75`, `3.75 / 5`, or `3.75/5`.
  double? get score {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(rating);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  static NewsReviewMeta? tryParse(String markdown) {
    final ratingRx = RegExp(r'^\*\*⭐\s*Rating:\s*([^*]+?)\*\*');
    final firstLine = markdown.trimLeft();
    final m = ratingRx.firstMatch(firstLine);
    if (m == null) return null;

    final searchSlice = markdown.substring(0, markdown.length.clamp(0, 1500));
    final sepRx = RegExp(r'\n\s*---\s*\n');
    final sepMatch = sepRx.firstMatch(searchSlice);
    if (sepMatch == null) return null;

    final header = markdown.substring(0, sepMatch.start);
    final bodyAfter = markdown.substring(sepMatch.end).trimLeft();
    final rating = m.group(1)?.trim() ?? '';

    List<String> collectAfterHeading(RegExp headingRx) {
      final lines = header.split('\n');
      final out = <String>[];
      var inSection = false;
      for (final raw in lines) {
        final line = raw.trimRight();
        if (headingRx.hasMatch(line)) {
          inSection = true;
          continue;
        }
        if (inSection) {
          if (line.startsWith('#### ')) break;
          final bullet = RegExp(r'^\s*[-*]\s+(.*)$').firstMatch(line);
          if (bullet != null) {
            final text = bullet.group(1)?.trim();
            if (text != null && text.isNotEmpty) out.add(text);
          }
        }
      }
      return out;
    }

    final meta = NewsReviewMeta(
      rating: rating,
      pros: collectAfterHeading(RegExp(r'^####\s*✅\s*Pros\b')),
      cons: collectAfterHeading(RegExp(r'^####\s*❌\s*Cons\b')),
      bodyAfter: bodyAfter,
    );
    if (meta.isEmpty) return null;
    return meta;
  }

  static String? ratingLabelOf(String? markdown) {
    if (markdown == null || markdown.isEmpty) return null;
    final meta = tryParse(markdown);
    if (meta == null || meta.rating.isEmpty) return null;
    return meta.rating;
  }
}

/// Compact gold rating chip for feed cards. Reader uses a larger pill.
class NewsRatingBadge extends StatelessWidget {
  const NewsRatingBadge({
    super.key,
    required this.rating,
    this.onDark = false,
    this.compact = false,
  });

  final String rating;
  final bool onDark;
  final bool compact;

  static const Color _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final hasScale = RegExp(r'/\s*\d').hasMatch(rating);
    final numeric = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(rating)?.group(1);
    final display = compact
        ? (numeric ?? rating)
        : (hasScale ? rating : '$rating / 5');
    final score = NewsReviewMeta(rating: rating, pros: const [], cons: const [], bodyAfter: '').score;
    final padH = compact ? 7.0 : 10.0;
    final padV = compact ? 3.0 : 5.0;
    final starSize = compact ? 10.0 : 12.0;
    final textSize = compact ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.black.withValues(alpha: 0.55)
            : _amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: onDark
              ? _amber.withValues(alpha: 0.55)
              : _amber.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.star, size: starSize, color: _amber),
          SizedBox(width: compact ? 4 : 5),
          Text(
            display,
            style: GoogleFonts.plusJakartaSans(
              fontSize: textSize,
              fontWeight: FontWeight.w800,
              height: 1,
              color: onDark ? Colors.white : const Color(0xFF1F2937),
              letterSpacing: -0.2,
            ),
          ),
          if (score != null && !compact) ...[
            const SizedBox(width: 6),
            _MiniStars(score: score, size: 9),
          ],
        ],
      ),
    );
  }
}

class _MiniStars extends StatelessWidget {
  const _MiniStars({required this.score, required this.size});

  final double score;
  final double size;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFF59E0B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(5, (i) {
        final filled = score >= i + 1;
        final half = !filled && score >= i + 0.5;
        return Padding(
          padding: const EdgeInsets.only(left: 1),
          child: Icon(
            filled
                ? Icons.star_rounded
                : half
                    ? Icons.star_half_rounded
                    : Icons.star_border_rounded,
            size: size,
            color: amber,
          ),
        );
      }),
    );
  }
}
