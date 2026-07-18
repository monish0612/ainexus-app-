import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/services/nuke_report.dart';
import '../../../../core/theme/app_colors.dart';

/// Shared UI for the "nuke" easter egg so every entry point (Tracker Ask-AI
/// search, Insights search, InsightAI search) shows the exact same
/// confirm → wipe → futuristic result window. Kept in one place to avoid drift
/// between call sites.
class NukeEasterEgg {
  const NukeEasterEgg._();

  /// A deliberately friction-y confirmation — nuke is irreversible and reaches
  /// the cloud, so we never fire it on a stray keystroke. Returns `true` when
  /// the user explicitly confirms. Copy adapts to the [scope].
  static Future<bool> confirm(BuildContext context, NukeScope scope) async {
    HapticFeedback.heavyImpact();
    final colors = Theme.of(context).extension<AppColors>()!;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (ctx) => _NukeConfirmDialog(colors: colors, scope: scope),
    );
    return ok ?? false;
  }

  /// Presents the cinematic "data cleared" window. Uses the root navigator so
  /// it survives a source sheet being popped, and a blurred barrier so the
  /// reset reads as a system-level event.
  static Future<void> showReport(
    BuildContext context,
    NukeReport report,
  ) {
    HapticFeedback.heavyImpact();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Nuke result',
      barrierColor: Colors.black.withValues(alpha: 0.86),
      transitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.82 + 0.18 * curved.value.clamp(0.0, 1.0),
            child: _NukeReportWindow(report: report),
          ),
        );
      },
    );
  }
}

// ── Confirmation ───────────────────────────────────────────────────────────

class _NukeConfirmDialog extends StatelessWidget {
  const _NukeConfirmDialog({required this.colors, required this.scope});

  final AppColors colors;
  final NukeScope scope;

  @override
  Widget build(BuildContext context) {
    final (String title, String body, String cta) = switch (scope) {
      NukeScope.full => (
          'Nuke the entire app?',
          'This permanently deletes ALL local data — expenses, budget, salary, '
              'news, saved words, files, searches & learnings — and clears your '
              'cloud financial data. Tables stay, every row is wiped. No undo.',
          'Nuke all',
        ),
      NukeScope.news => (
          'Nuke all news?',
          'This permanently deletes EVERY article — including your saved ones — '
              'from this device AND the server. Read, unread, saved: all of it. '
              'There is no undo.',
          'Nuke news',
        ),
      NukeScope.expense => (
          'Nuke expenses?',
          'This permanently deletes ALL expenses, budget history and salary '
              'records from this device AND the cloud. There is no undo.',
          'Nuke it',
        ),
    };

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x55EF4444)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66EF4444),
              blurRadius: 40,
              spreadRadius: 2,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('☢️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFFF922B)],
              ).createShader(r),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.5,
                color: colors.text2,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: colors.bg3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFFF922B)],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66EF4444),
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(
                        LucideIcons.zap,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(
                        cta,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Result window ────────────────────────────────────────────────────────────

class _NukeReportWindow extends StatefulWidget {
  const _NukeReportWindow({required this.report});

  final NukeReport report;

  @override
  State<_NukeReportWindow> createState() => _NukeReportWindowState();
}

class _NukeReportWindowState extends State<_NukeReportWindow>
    with TickerProviderStateMixin {
  // Drives the headline + staggered line reveal + count-up (plays once).
  late final AnimationController _intro;
  // Drives the expanding shockwave rings (replays on tap — "interactive").
  late final AnimationController _shock;

  static const _neonA = Color(0xFFCC5DE8); // violet
  static const _neonB = Color(0xFF22D3EE); // cyan
  static const _neonC = Color(0xFFFF6B6B); // coral

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    _shock = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _intro.dispose();
    _shock.dispose();
    super.dispose();
  }

  void _replayShock() {
    HapticFeedback.lightImpact();
    _shock.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final lines = report.nonEmptyLines;
    final (String headline, String coreGlyph, String subtitle) = switch (report.scope) {
      NukeScope.full => (
          'SYSTEM WIPED',
          '☢️',
          'All systems reset to a clean slate',
        ),
      NukeScope.news => (
          'NEWS WIPED',
          '📰',
          'Every article cleared — a clean slate',
        ),
      NukeScope.expense => (
          'EXPENSES NUKED',
          '💥',
          'Financial data reset to a clean slate',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B0B12), Color(0xFF130A1C)],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: _neonA.withValues(alpha: 0.45)),
                boxShadow: [
                  BoxShadow(
                    color: _neonA.withValues(alpha: 0.45),
                    blurRadius: 48,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reactor core + shockwave (tap to replay).
                  GestureDetector(
                    onTap: _replayShock,
                    child: SizedBox(
                      height: 168,
                      width: double.infinity,
                      child: AnimatedBuilder(
                        animation: _shock,
                        builder: (context, _) => CustomPaint(
                          painter: _ShockwavePainter(
                            t: _shock.value,
                            colorA: _neonB,
                            colorB: _neonA,
                          ),
                          child: Center(
                            child: _PulsingGlyph(emoji: coreGlyph),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // FittedBox guards the wide, letter-spaced headline
                        // from overflowing on very narrow screens.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ShaderMask(
                            shaderCallback: (r) => const LinearGradient(
                              colors: [_neonB, _neonA, _neonC],
                            ).createShader(r),
                            child: Text(
                              headline,
                              maxLines: 1,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (lines.isEmpty)
                          _EmptyState()
                        else
                          ...List.generate(lines.length, (i) {
                            return _ReportRow(
                              line: lines[i],
                              intro: _intro,
                              index: i,
                              total: lines.length,
                            );
                          }),
                        const SizedBox(height: 18),
                        _MetaBar(report: report),
                        const SizedBox(height: 16),
                        _StartFreshButton(
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        'Already pristine — nothing to clear ✨',
        textAlign: TextAlign.center,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// A single cleared-domain row that slides + fades in on a stagger and counts
/// its number up from zero — a small "wipe ticker" per data type.
class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.line,
    required this.intro,
    required this.index,
    required this.total,
  });

  final NukeLine line;
  final AnimationController intro;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Stagger the reveal across the back 80% of the intro animation.
    final start = (0.15 + (index / math.max(1, total)) * 0.7).clamp(0.0, 0.95);
    final anim = CurvedAnimation(
      parent: intro,
      curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final t = anim.value;
        final shown = (line.count * t).round();
        final badge = _badge(line.cloudSynced);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Text(line.emoji, style: const TextStyle(fontSize: 17)),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        line.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      badge,
                      const SizedBox(width: 10),
                    ],
                    // Flexible + ellipsis guards against very large counts
                    // pushing the row past the dialog edge.
                    Flexible(
                      child: Text(
                        '−$shown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF22D3EE),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _badge(bool? synced) {
    // null = local-only domain → no badge (nothing to sync).
    if (synced == null) return null;
    final (label, color, icon) = synced
        ? ('SYNCED', const Color(0xFF34D399), LucideIcons.cloud)
        : ('QUEUED', const Color(0xFFF59E0B), LucideIcons.refreshCw);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBar extends StatelessWidget {
  const _MetaBar({required this.report});

  final NukeReport report;

  @override
  Widget build(BuildContext context) {
    final synced = report.fullySynced;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _stat('CLEARED', '${report.totalCleared}'),
          _divider(),
          _stat('TIME', '${report.elapsedMs}ms'),
          _divider(),
          _stat('CLOUD', synced ? 'SYNCED' : 'QUEUED',
              color: synced ? const Color(0xFF34D399) : const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color ?? Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 26,
        color: Colors.white.withValues(alpha: 0.08),
      );
}

class _StartFreshButton extends StatelessWidget {
  const _StartFreshButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF22D3EE), Color(0xFFCC5DE8)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66CC5DE8),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: TextButton.icon(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(LucideIcons.sparkles, size: 17, color: Colors.white),
          label: Text(
            'Start Fresh',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingGlyph extends StatefulWidget {
  const _PulsingGlyph({required this.emoji});

  final String emoji;

  @override
  State<_PulsingGlyph> createState() => _PulsingGlyphState();
}

class _PulsingGlyphState extends State<_PulsingGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final wave = (math.sin(_c.value * 2 * math.pi) + 1) / 2;
        return Transform.scale(
          scale: 0.9 + wave * 0.18,
          child: child,
        );
      },
      child: Text(widget.emoji, style: const TextStyle(fontSize: 46)),
    );
  }
}

/// Paints expanding concentric shockwave rings + a central radial glow. Driven
/// by a single 0→1 progress so it can replay on tap.
class _ShockwavePainter extends CustomPainter {
  _ShockwavePainter({
    required this.t,
    required this.colorA,
    required this.colorB,
  });

  final double t;
  final Color colorA;
  final Color colorB;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.92;

    // Central radial glow.
    final glow = Paint()
      ..shader = ui.Gradient.radial(center, maxR * 0.6, [
        colorB.withValues(alpha: 0.30),
        colorB.withValues(alpha: 0.0),
      ]);
    canvas.drawCircle(center, maxR * 0.6, glow);

    // Three rings, each offset in phase so they ripple outward.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.22).clamp(0.0, 1.0);
      if (phase <= 0 || phase >= 1) continue;
      final r = maxR * Curves.easeOut.transform(phase);
      final alpha = (1 - phase) * 0.7;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - phase) + 0.6
        ..color = Color.lerp(colorA, colorB, i / 2)!.withValues(alpha: alpha);
      canvas.drawCircle(center, r, ring);
    }
  }

  @override
  bool shouldRepaint(_ShockwavePainter old) =>
      old.t != t || old.colorA != colorA || old.colorB != colorB;
}
