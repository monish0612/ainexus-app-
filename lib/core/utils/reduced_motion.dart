import 'package:flutter/widgets.dart';

/// True when the user asked the OS to reduce motion.
///
/// Also honours `accessibleNavigation` (TalkBack / Switch Access): a screen
/// reader driving the UI wants surfaces to be where it left them, not
/// mid-flight, and the two settings are almost always turned on together.
///
/// Overlay tokens keep their own `maybeOf` lookup for the bubble isolate.
bool reducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context);

/// [full] normally, [Duration.zero] when motion is reduced.
///
/// The collapse target is zero rather than a shortened duration on purpose:
/// "remove animations" means the change should simply be there.
Duration motionDuration(BuildContext context, Duration full) =>
    reducedMotion(context) ? Duration.zero : full;

/// An [AnimatedSwitcher] transition that fades and — only at full motion —
/// scales. The fade and its duration are identical either way, so the
/// timing budget of the surrounding layout never changes.
AnimatedSwitcherTransitionBuilder fadeScaleTransition(BuildContext context) {
  if (reducedMotion(context)) {
    return (Widget child, Animation<double> animation) =>
        FadeTransition(opacity: animation, child: child);
  }
  return (Widget child, Animation<double> animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      );
}
