import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';

/// The shared vocabulary both Stats screens are built from: cards, chips, the
/// live pulse, the offline treatment, and the number formatting.
///
/// It lives in one file so the NAS and VPS screens cannot drift apart. They show
/// different machines but they are the same dashboard, and a chip that means
/// "healthy" on one has to look identical on the other.

// ── formatting ──────────────────────────────────────────────────────────────
//
// Every one of these returns an em dash for null rather than "0". A dashboard
// whose job is to be trusted must never present an unknown as a measurement.

const String kUnknown = '—';

String formatBytes(int? bytes, {int decimals = 1}) {
  if (bytes == null) return kUnknown;
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // Whole numbers below the megabyte, decimals above: "512 KB" and "1.4 GB"
  // both read naturally, "512.0 KB" and "1 GB" do not.
  final d = unit <= 1 ? 0 : decimals;
  return '${value.toStringAsFixed(d)} ${units[unit]}';
}

String formatGb(num? gb, {int decimals = 1}) =>
    gb == null ? kUnknown : '${gb.toStringAsFixed(decimals)} GB';

String formatPct(num? pct, {int decimals = 0}) =>
    pct == null ? kUnknown : '${pct.toStringAsFixed(decimals)}%';

/// Coarse on purpose. Nobody reads "3 days, 4 hours, 12 minutes and 6 seconds"
/// off a dashboard; they want to know roughly how long it has been up.
String formatDuration(int? seconds) {
  if (seconds == null) return kUnknown;
  final s = seconds < 0 ? 0 : seconds;
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ${(m % 60).toString().padLeft(2, '0')}m';
  final d = h ~/ 24;
  return '${d}d ${h % 24}h';
}

String formatAgo(int? seconds) {
  if (seconds == null) return 'never';
  if (seconds < 5) return 'just now';
  return '${formatDuration(seconds)} ago';
}

// ── the offline treatment ───────────────────────────────────────────────────

/// Drains the colour out of a live dashboard and makes it inert.
///
/// One widget gives all three halves of "the NAS is off": the saturation matrix
/// greys everything without any widget needing to know it is disabled, the
/// reduced opacity pushes it behind the banner in the visual hierarchy, and the
/// [IgnorePointer] means nothing inside can be tapped. Gauges animate down to
/// zero because they are fed zeroes by the screen, so the transition to off is a
/// visible sweep rather than a jump cut — you can see the machine going quiet.
class StatsOfflineShroud extends StatelessWidget {
  const StatsOfflineShroud({
    super.key,
    required this.offline,
    required this.child,
  });

  final bool offline;
  final Widget child;

  /// The standard luminance weights (0.2126 / 0.7152 / 0.0722). Getting these
  /// wrong is what makes naive greyscale look muddy: the eye is far more
  /// sensitive to green than to blue, so an even split darkens greens wrongly.
  static const List<double> _greyscale = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    if (!offline) return child;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: 0.55,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(_greyscale),
          child: child,
        ),
      ),
    );
  }
}

/// The "NAS is off" notice.
///
/// Deliberately calm. A switched-off NAS is the normal state of a machine its
/// owner switches off, not an incident, so this is not red, has no warning
/// triangle, and does not shout. It says what is true, when it was last seen,
/// and — only for the two reasons that are actually faults — what to do.
class StatsOfflineBanner extends StatelessWidget {
  const StatsOfflineBanner({
    super.key,
    required this.title,
    required this.message,
    this.lastSeen,
    this.isFault = false,
    this.onRetry,
  });

  final String title;
  final String message;
  final DateTime? lastSeen;
  final bool isFault;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final tint = isFault ? const Color(0xFFFF6B6B) : colors.text3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.12),
            ),
            child: Icon(
              isFault ? Icons.error_outline_rounded : Icons.power_settings_new,
              size: 20,
              color: tint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.text3,
                    height: 1.35,
                  ),
                ),
                if (lastSeen case final seen?) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Last seen ${formatAgo(DateTime.now().difference(seen).inSeconds)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.text4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: 20, color: colors.text3),
              tooltip: 'Try again',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// A pulsing dot plus "updated Ns ago".
///
/// The pulse is the honest part. A static "Live" label keeps claiming to be live
/// after the feed has died; a dot that stops breathing when polling stops tells
/// the truth without a word of copy.
class LivePulse extends StatefulWidget {
  const LivePulse({
    super.key,
    required this.live,
    this.ageSeconds,
    this.label,
  });

  final bool live;
  final int? ageSeconds;
  final String? label;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.live) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant LivePulse old) {
    super.didUpdateWidget(old);
    if (widget.live == old.live) return;
    if (widget.live) {
      _controller.repeat(reverse: true);
    } else {
      // Stop at full opacity rather than wherever the pulse happened to be, so
      // a stopped feed does not look like a half-faded bug.
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final dot = widget.live ? const Color(0xFF51CF66) : colors.text4;
    final text = widget.label ??
        (widget.live
            ? 'Live · ${formatAgo(widget.ageSeconds)}'
            : 'Not updating');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_controller.value);
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dot,
                boxShadow: widget.live
                    ? [
                        BoxShadow(
                          color: dot.withValues(alpha: 0.25 + 0.45 * t),
                          blurRadius: 4 + 6 * t,
                          spreadRadius: 1 + 2 * t,
                        ),
                      ]
                    : null,
              ),
            );
          },
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: colors.text3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ── building blocks ─────────────────────────────────────────────────────────

class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.cardGradientTop, colors.cardGradientBottom],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: colors.text4,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// Severity, so a chip's colour is decided in one place rather than at each
/// call site where the three ideas would slowly diverge.
enum StatTone { neutral, good, warn, bad, info }

Color toneColor(StatTone tone, AppColors colors) => switch (tone) {
      StatTone.good => const Color(0xFF51CF66),
      StatTone.warn => const Color(0xFFFCC419),
      StatTone.bad => const Color(0xFFFF6B6B),
      StatTone.info => AppColors.accentCyan,
      StatTone.neutral => colors.text3,
    };

class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.label,
    this.tone = StatTone.neutral,
    this.icon,
  });

  final String label;
  final StatTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final c = toneColor(tone, colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          // Flexible, not a bare Text: a chip sits in a Wrap and is handed the
          // full row width as its ceiling, so a long label like
          // "Live TV off by choice" would otherwise push the pill past the card
          // edge on a 320 px screen instead of shortening itself.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label on the left and a value on the right.
///
/// A [Wrap] rather than a [Row] because the value must never be truncated — a
/// half-printed byte count is worse than no byte count — and on a 320 px screen
/// "Load average (1 / 5 / 15 min)" beside "0.40 · 0.30 · 0.20" does not fit on
/// one line. With `spaceBetween` the two sit apart when there is room and the
/// value drops to its own line when there is not, so the number always survives
/// intact.
class StatRow extends StatelessWidget {
  const StatRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 2,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: colors.text4),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: colors.text3,
                  ),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? colors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet explanatory line, for the facts that stop a correct number from
/// looking like a wrong one — the 14-day snapshot note above all.
class StatsNote extends StatelessWidget {
  const StatsNote({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon ?? Icons.info_outline_rounded, size: 13, color: colors.text4),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: colors.text4,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Header used by both Stats screens: a back arrow, the machine's name, and the
/// live pulse. Not `CompactHeader`, which carries the avatar and settings entry
/// that make no sense on a pushed detail screen.
class StatsHeader extends StatelessWidget {
  const StatsHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.live,
    this.ageSeconds,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final bool live;
  final int? ageSeconds;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 10),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back_rounded, color: colors.text),
              tooltip: 'Back',
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: colors.text,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: colors.text3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            LivePulse(live: live, ageSeconds: ageSeconds),
          ],
        ),
      ),
    );
  }
}
