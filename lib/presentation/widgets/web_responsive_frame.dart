import 'package:flutter/material.dart';

import '../../core/platform/platform_capabilities.dart';
import '../../core/theme/app_colors.dart';

/// On the web build, when the viewport is wider than a phone, this widget
/// centres the entire app inside a phone-width column and paints the
/// surrounding area with a tasteful gradient + radial accent. The result
/// is that the existing mobile UI looks intentional on desktop browsers
/// rather than being stretched edge-to-edge.
///
/// On Android (and on web at narrow viewports), this widget renders its
/// child unchanged — preserving the original full-width layout exactly.
class WebResponsiveFrame extends StatelessWidget {
  const WebResponsiveFrame({super.key, required this.child});

  final Widget child;

  /// Phone-like column width. Matches the native canvas (412dp Pixel-class
  /// devices). The header/nav bar inside the child fills this width.
  static const double _phoneWidth = 430;

  /// Below this viewport width we render the child edge-to-edge — the user
  /// is on a phone-sized screen even if it's a browser window.
  static const double _desktopBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.isWeb) return child;

    final size = MediaQuery.sizeOf(context);
    if (size.width < _desktopBreakpoint) return child;

    final colors = Theme.of(context).extension<AppColors>()!;

    return Stack(
      children: [
        // Backdrop that fills the browser window with a soft gradient,
        // visually distinct from the centred phone canvas.
        Positioned.fill(
          child: _DesktopBackdrop(colors: colors),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _phoneWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.bg,
                  border: Border.symmetric(
                    vertical: BorderSide(color: colors.border, width: 1),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopBackdrop extends StatelessWidget {
  const _DesktopBackdrop({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final isDark = colors.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF000000), Color(0xFF050811), Color(0xFF000000)]
              : const [Color(0xFFF8FAFC), Color(0xFFEEF2FF), Color(0xFFF8FAFC)],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.6, -0.7),
            radius: 1.2,
            colors: [
              const Color(0xFF0D59F2).withValues(alpha: isDark ? 0.10 : 0.06),
              Colors.transparent,
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
