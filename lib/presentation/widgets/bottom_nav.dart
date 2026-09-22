import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/reduced_motion.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = <_NavItem>[
    _NavItem(icon: LucideIcons.wallet, label: 'Expense'),
    _NavItem(icon: LucideIcons.newspaper, label: 'News'),
    _NavItem(icon: LucideIcons.graduationCap, label: 'Tutor'),
    _NavItem(icon: LucideIcons.cloud, label: 'Cloud'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    Widget nav = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.navBg,
        border: Border(
          top: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: SizedBox(
          height: AppConstants.navHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_items.length, (i) {
                return _NavButton(
                  item: _items[i],
                  isActive: i == currentIndex,
                  isDark: colors.isDark,
                  onTap: () => onTap(i),
                );
              }),
            ),
          ),
        ),
      ),
    );

    // Dark navBg is 97% opaque; a zero-sigma BackdropFilter was a
    // full-width saveLayer that changed nothing. Light still frosts through
    // the remaining 3% (sigma 12). Raster cost is not measured here.
    if (!colors.isDark) {
      nav = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: nav,
        ),
      );
    }
    return nav;
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  final _NavItem item;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton>
    with SingleTickerProviderStateMixin {
  /// Unbounded so the release can overshoot slightly on the way back to 1.0.
  late final AnimationController _scaleCtrl;

  static const double _pressedScale = 0.86;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController.unbounded(vsync: this, value: 1);
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    _scaleCtrl.animateWith(
      SpringSimulation(
        AppSprings.fast,
        _scaleCtrl.value,
        target,
        _scaleCtrl.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    // `text4` clears 4.5:1 in both palettes, so the inactive label no longer
    // sits at the old ~2.7:1.
    final activeColor = colors.accentText;
    final inactiveColor = colors.text4;

    final still = reducedMotion(context);

    return Semantics(
      button: true,
      selected: widget.isActive,
      label: widget.item.label,
      child: GestureDetector(
        onTapDown: (_) {
          if (!still) _springTo(_pressedScale);
        },
        onTapUp: (_) {
          if (!still) _springTo(1);
          widget.onTap();
        },
        onTapCancel: () {
          if (!still) _springTo(1);
        },
        behavior: HitTestBehavior.opaque,
        child: ScaleTransition(
          scale: still ? const AlwaysStoppedAnimation(1.0) : _scaleCtrl,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Tinted capsule behind the active icon. Shape, not just hue,
                // so the selected tab survives grayscale.
                AnimatedContainer(
                  duration: still ? Duration.zero : AppMotion.standardEnter,
                  curve: AppMotion.emphasized,
                  width: widget.isActive ? 44 : 30,
                  height: widget.isActive ? 30 : 30,
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? AppColors.accent.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: AppRadii.brPill,
                  ),
                ),
                AnimatedSwitcher(
                  duration: still ? Duration.zero : AppMotion.microHover,
                  child: Icon(
                    widget.item.icon,
                    key: ValueKey('${widget.item.label}_${widget.isActive}'),
                    size: 22,
                    color: widget.isActive ? activeColor : inactiveColor,
                  ),
                ),
                Positioned(
                  bottom: 4,
                  child: AnimatedContainer(
                    duration: still ? Duration.zero : AppMotion.standardEnter,
                    curve: AppMotion.emphasized,
                    width: widget.isActive ? 14 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: AppRadii.brPill,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
