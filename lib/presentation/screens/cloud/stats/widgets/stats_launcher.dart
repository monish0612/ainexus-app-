import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../presentation/screens/cloud/stats/nas_stats_screen.dart';
import '../../../../../presentation/screens/cloud/stats/vps_stats_screen.dart';

/// The "Stats" entry point that lives above the Cloud tab bar.
///
/// Collapsed it is one glass pill. Tapping it expands *in place* into two
/// destinations, NAS and VPS, rather than opening a menu or a sheet: the choice
/// is between exactly two things, and a bottom sheet for a binary choice is a
/// whole extra surface to dismiss.
///
/// The expansion is the only animation, and it does two jobs at once — the row
/// grows via [AnimatedSize] while the chips slide and fade in on a slight
/// stagger, so the second chip arrives just after the first. That stagger is
/// what makes it read as one gesture unfolding instead of two widgets appearing.
class StatsLauncher extends StatefulWidget {
  const StatsLauncher({super.key});

  @override
  State<StatsLauncher> createState() => _StatsLauncherState();
}

class _StatsLauncherState extends State<StatsLauncher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  bool _open = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _controller.reverse();
  }

  void _push(Widget screen) {
    // Collapse on the way out so returning to the Cloud tab does not find the
    // launcher still open from a navigation that happened minutes ago.
    _close();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    // Tapping anywhere that is not the pill or a chip collapses it, which is the
    // gesture people try first and would otherwise do nothing. The InkWells
    // inside win the gesture arena for their own areas, so this only catches the
    // empty space.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _close,
      child: Container(
        decoration: BoxDecoration(
          color: colors.headerBg,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            _StatsPill(open: _open, onTap: _toggle),
            // Flexible, so the chips can only ever occupy the space the pill
            // left behind. Without it the expanded row is sized to the chips'
            // natural width and overflows a 320 px screen; with it they narrow
            // instead, which is the failure mode a reader never notices.
            Flexible(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: AppConstants.animationCurve,
                alignment: Alignment.centerLeft,
                child: _open
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 8),
                          Flexible(
                            child: _StaggeredChip(
                              controller: _controller,
                              order: 0,
                              child: _DestinationChip(
                                label: 'NAS',
                                icon: Icons.storage_rounded,
                                tint: AppColors.accent,
                                onTap: () => _push(const NasStatsScreen()),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: _StaggeredChip(
                              controller: _controller,
                              order: 1,
                              child: _DestinationChip(
                                label: 'VPS',
                                icon: Icons.cloud_rounded,
                                tint: AppColors.accentCyan,
                                onTap: () => _push(const VpsStatsScreen()),
                              ),
                            ),
                          ),
                        ],
                      )
                    // Zero-width rather than shrink so the row keeps its height
                    // and the collapse animates the width alone.
                    : const SizedBox(height: 38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsPill extends StatelessWidget {
  const _StatsPill({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: AppConstants.animationCurve,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: open
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : colors.border2,
            ),
            gradient: LinearGradient(
              colors: open
                  ? [
                      AppColors.accent.withValues(alpha: 0.20),
                      AppColors.accentCyan.withValues(alpha: 0.14),
                    ]
                  : [colors.glassFill, colors.glassFill],
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insights_rounded,
                size: 16,
                color: open ? AppColors.accent : colors.text2,
              ),
              const SizedBox(width: 7),
              Text(
                'Stats',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: open ? AppColors.accent : colors.text,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 5),
              // Rotates rather than swapping icons, so the control's state is
              // legible mid-animation instead of popping between two glyphs.
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 280),
                curve: AppConstants.animationCurve,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 17,
                  color: open ? AppColors.accent : colors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slides and fades one chip in, offset by its position in the row.
class _StaggeredChip extends StatelessWidget {
  const _StaggeredChip({
    required this.controller,
    required this.order,
    required this.child,
  });

  final AnimationController controller;
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Windows overlap so the two chips are in motion together for part of the
    // time — sequential intervals would read as two separate events.
    final begin = (0.12 * order).clamp(0.0, 0.6);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(begin, (begin + 0.7).clamp(0.0, 1.0),
          curve: AppConstants.animationCurve),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(-10 * (1 - t), 0),
            child: child,
          ),
        );
      },
    );
  }
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: tint.withValues(alpha: 0.12),
            border: Border.all(color: tint.withValues(alpha: 0.38)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
