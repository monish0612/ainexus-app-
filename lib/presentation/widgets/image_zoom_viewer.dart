import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Max pinch/zoom factor for the viewer.
const double kZoomViewerMaxScale = 6.0;

/// Scale applied by a double-tap zoom-in.
const double kZoomViewerDoubleTapScale = 2.6;

/// A gesture is treated as a dismiss once it has travelled this far (logical
/// pixels) or been flung faster than [kZoomViewerDismissVelocity].
const double kZoomViewerDismissDistance = 120;
const double kZoomViewerDismissVelocity = 700;

/// Pure helper: matrix that zooms to [scale] centred on [focalPoint]
/// (in the viewer's coordinate space), keeping that point visually anchored.
///
/// Extracted so the zoom math can be unit-tested independently of any widget
/// or device — the anchoring is what guarantees "no scaling / jump issues".
Matrix4 buildZoomToPointMatrix(Offset focalPoint, double scale) {
  return Matrix4.identity()
    ..translateByDouble(
      -focalPoint.dx * (scale - 1),
      -focalPoint.dy * (scale - 1),
      0,
      1,
    )
    ..scaleByDouble(scale, scale, scale, 1);
}

/// Pure helper: should a release with the given drag [distance] (logical px)
/// and fling [velocity] (px/s) dismiss the viewer?
bool zoomViewerShouldDismiss({
  required double distance,
  required double velocity,
}) =>
    distance > kZoomViewerDismissDistance ||
    velocity > kZoomViewerDismissVelocity;

/// Opens a full-screen, immersive image viewer for [imageUrl].
///
/// Gestures:
///   • Pinch to zoom / pan while zoomed (via [InteractiveViewer]).
///   • Double-tap to zoom in at the tapped point, double-tap again to reset.
///   • Swipe in any direction (at 1× zoom) to dismiss — the image follows the
///     finger and the backdrop fades out; release past the threshold to close.
///   • System back button / back-swipe gesture, the ✕ button, a single tap on
///     the backdrop, or a tap on the image (at 1×) all close it.
///
/// A [heroTag] wires a shared-element transition so the image smoothly grows
/// from its inline position into the viewer and back.
Future<void> showImageZoomViewer(
  BuildContext context, {
  required String imageUrl,
  Object? heroTag,
}) {
  final src = imageUrl.trim();
  if (src.isEmpty) return Future<void>.value();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) =>
          ImageZoomViewer(imageUrl: src, heroTag: heroTag),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

class ImageZoomViewer extends StatefulWidget {
  const ImageZoomViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
  });

  final String imageUrl;
  final Object? heroTag;

  @override
  State<ImageZoomViewer> createState() => _ImageZoomViewerState();
}

class _ImageZoomViewerState extends State<ImageZoomViewer>
    with TickerProviderStateMixin {
  final TransformationController _controller = TransformationController();

  // Drives the double-tap zoom in/out (animates the transformation matrix).
  late final AnimationController _zoomAnim;
  Animation<Matrix4>? _zoomTween;

  // Drives the snap-back of a cancelled dismiss drag.
  late final AnimationController _snapAnim;

  TapDownDetails? _doubleTapDetails;

  /// Live offset of the image while swiping to dismiss (only active at 1×).
  Offset _dismiss = Offset.zero;

  /// True only while the current interaction is a valid dismiss swipe (started
  /// at 1× zoom with a single pointer). Guards against dismissing mid-pinch or
  /// while panning a zoomed image.
  bool _dismissActive = false;

  @override
  void initState() {
    super.initState();
    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        final value = _zoomTween?.value;
        if (value != null) _controller.value = value;
      });
    _snapAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _zoomAnim.dispose();
    _snapAnim.dispose();
    _controller.dispose();
    super.dispose();
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();
  bool get _isZoomed => _scale > 1.02;

  void _close() => Navigator.of(context).maybePop();

  void _animateZoomTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _controller.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic),
    );
    _zoomAnim
      ..reset()
      ..forward();
  }

  void _handleDoubleTap() {
    // Interrupt any in-flight snap so state stays consistent.
    _snapAnim.stop();
    if (_isZoomed) {
      _animateZoomTo(Matrix4.identity());
      return;
    }
    final details = _doubleTapDetails;
    if (details == null) return;
    _animateZoomTo(
      buildZoomToPointMatrix(details.localPosition, kZoomViewerDoubleTapScale),
    );
  }

  void _handleTap() {
    // A single tap on the image dismisses only when not zoomed, so tapping to
    // inspect a zoomed image never closes it by accident.
    if (!_isZoomed) _close();
  }

  // ── Interaction (single recognizer via InteractiveViewer) ────────────────

  void _onInteractionStart(ScaleStartDetails d) {
    _snapAnim.stop();
    _zoomAnim.stop();
    _dismissActive = !_isZoomed && d.pointerCount == 1;
  }

  void _onInteractionUpdate(ScaleUpdateDetails d) {
    // A second finger (pinch) cancels a dismiss and hands control back to the
    // InteractiveViewer for a clean zoom.
    if (d.pointerCount > 1 || d.scale > 1.02) {
      if (_dismissActive || _dismiss != Offset.zero) {
        setState(() {
          _dismissActive = false;
          _dismiss = Offset.zero;
        });
      }
      return;
    }
    if (!_dismissActive) return;
    setState(() => _dismiss += d.focalPointDelta);
  }

  void _onInteractionEnd(ScaleEndDetails d) {
    if (!_dismissActive) return;
    _dismissActive = false;
    final distance = _dismiss.distance;
    final velocity = d.velocity.pixelsPerSecond.distance;
    if (distance > 0 &&
        zoomViewerShouldDismiss(distance: distance, velocity: velocity)) {
      _close();
    } else if (_dismiss != Offset.zero) {
      _snapDismissBack();
    }
  }

  void _snapDismissBack() {
    final from = _dismiss;
    final tween = Tween<Offset>(begin: from, end: Offset.zero)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_snapAnim);
    void listener() => setState(() => _dismiss = tween.value);
    tween.addListener(listener);
    _snapAnim
      ..reset()
      ..forward().whenCompleteOrCancel(() => tween.removeListener(listener));
  }

  @override
  Widget build(BuildContext context) {
    // The backdrop fades and the image shrinks slightly as it is dragged away.
    final dismissProgress = (_dismiss.distance / 320).clamp(0.0, 1.0);
    final backdropOpacity = 1.0 - dismissProgress * 0.85;
    final dragScale = 1.0 - dismissProgress * 0.12;

    Widget image = CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => const Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(LucideIcons.imageOff, color: Colors.white38, size: 40),
      ),
    );

    if (widget.heroTag != null) {
      image = Hero(tag: widget.heroTag!, child: image);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Frosted, dimmable backdrop. A tap here always closes.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: backdropOpacity),
                    ),
                  ),
                ),
              ),
            ),
            // Image stage: one gesture detector for tap/double-tap; all
            // pan/zoom/dismiss motion is driven by InteractiveViewer's own
            // recognizer so nothing competes in the gesture arena.
            Positioned.fill(
              child: GestureDetector(
                onTap: _handleTap,
                onDoubleTapDown: (d) => _doubleTapDetails = d,
                onDoubleTap: _handleDoubleTap,
                child: Transform.translate(
                  offset: _dismiss,
                  child: Transform.scale(
                    scale: dragScale,
                    child: InteractiveViewer(
                      transformationController: _controller,
                      minScale: 1.0,
                      maxScale: kZoomViewerMaxScale,
                      clipBehavior: Clip.none,
                      onInteractionStart: _onInteractionStart,
                      onInteractionUpdate: _onInteractionUpdate,
                      onInteractionEnd: _onInteractionEnd,
                      // Fill the viewport so BoxFit.contain scales the image to
                      // fit the screen. A Center here would hand the image loose
                      // constraints, collapsing it to its intrinsic (decoded)
                      // size — which renders small/soft and breaks the Hero.
                      child: SizedBox.expand(child: image),
                    ),
                  ),
                ),
              ),
            ),
            // Close button.
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: _CircleIconButton(icon: LucideIcons.x, onTap: _close),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
