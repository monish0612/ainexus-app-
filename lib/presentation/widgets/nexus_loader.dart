import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/reduced_motion.dart';

/// The six wait signatures. One widget, six looks — never a bare
/// [CircularProgressIndicator], and never a seventh bespoke spinner.
enum NexusLoaderVariant {
  /// Fast grounded web search. Particle flow field with firing links.
  research,

  /// Deep / thinking. The same field retuned, plus a breathing ring.
  think,

  /// Image understanding. Thumbnail with a liquid progress ring.
  vision,

  /// First paint of a list. Card-shaped shimmer skeletons.
  list,

  /// Determinate transfer. A meter with popping digits.
  sync,

  /// Terminal state. Check path-draw, or a shake.
  result,
}

/// Which mode the wait belongs to. Drives the color only.
enum NexusLoaderTone { lite, deep, thinking, accent }

/// Terminal outcome for [NexusLoaderVariant.result].
enum NexusResult { success, failure }

/// Stage copy, mirrored from the stores that already own these strings.
///
/// These are NOT new strings. Keep them byte-identical to the source so the
/// wait text a user sees is the same whether it comes from the store's
/// `job.stage` or from a loader rendered before the store has spun up.
abstract final class NexusStageCopy {
  /// `lib/core/services/online_search_store.dart`.
  static const List<String> research = <String>[
    'Searching the web\u2026',
    'Analyzing results\u2026',
    'Preparing answer\u2026',
    'Almost there\u2026',
  ];

  /// `lib/core/services/summarize_store.dart`.
  static const List<String> think = <String>[
    'Connecting to URL\u2026',
    'Extracting page content\u2026',
    'Generating detailed breakdown\u2026',
    'Almost done\u2026',
  ];

  /// `lib/core/services/image_search_store.dart`.
  static const List<String> vision = <String>[
    'Analyzing image\u2026',
    'Examining details\u2026',
    'Composing answer\u2026',
    'Almost there\u2026',
  ];

  /// `lib/presentation/screens/settings/settings_modal.dart`.
  static const String list = 'Loading\u2026';

  /// `lib/presentation/screens/cloud/cloud_screen.dart`.
  static const String sync = 'Uploading\u2026';

  /// `lib/presentation/screens/news/article_detail_modal.dart`.
  static const String success = 'Done';

  /// `lib/core/network/ai_error.dart`.
  static const String failure = 'Something went wrong';

  static List<String> forVariant(NexusLoaderVariant v) => switch (v) {
        NexusLoaderVariant.research => research,
        NexusLoaderVariant.think => think,
        NexusLoaderVariant.vision => vision,
        NexusLoaderVariant.list => const <String>[list],
        NexusLoaderVariant.sync => const <String>[sync],
        NexusLoaderVariant.result => const <String>[success],
      };
}

/// The single wait primitive.
///
/// Every variant emits a real `Semantics(liveRegion: true, label: …)` node
/// carrying the current status copy. A [CustomPainter] is invisible to screen
/// readers and to `find.text`, so that node is both the a11y path and the
/// hook QA asserts on.
///
/// Reduced motion ([reducedMotion]) collapses the *kind* of change to opacity
/// while keeping identical copy, layout and timing budget. Note that
/// `MediaQuery.disableAnimationsOf(context)` does not stop an
/// [AnimationController] on its own — every branch below is explicit.
class NexusLoader extends StatefulWidget {
  const NexusLoader({
    super.key,
    required this.variant,
    this.tone = NexusLoaderTone.lite,
    this.stages,
    this.stageInterval = const Duration(milliseconds: 2000),
    this.label,
    this.progress,
    this.image,
    this.itemCount = 3,
    this.result = NexusResult.success,
    this.size = 132,
    this.complete = false,
    this.child,
    this.revertSignal,
    this.onRevert,
  });

  final NexusLoaderVariant variant;

  /// Color family. Deep is violet, Thinking is gold, Lite/live is cyan.
  final NexusLoaderTone tone;

  /// Status copy. Defaults to [NexusStageCopy.forVariant]. The sequence
  /// advances once per [stageInterval] and HOLDS on the last entry — it never
  /// loops back to the first.
  final List<String>? stages;
  final Duration stageInterval;

  /// Overrides the whole status line with a single fixed string.
  final String? label;

  /// 0..1. Determinate fill for [NexusLoaderVariant.sync] and
  /// [NexusLoaderVariant.vision]. Null means indeterminate.
  final double? progress;

  /// Thumbnail for [NexusLoaderVariant.vision].
  final ImageProvider? image;

  /// Skeleton row count for [NexusLoaderVariant.list].
  final int itemCount;

  final NexusResult result;

  /// Square edge for research / think / vision / result.
  final double size;

  /// Flips research/think into their completion sequence, and cross-fades a
  /// [child] in over a [NexusLoaderVariant.list] skeleton.
  final bool complete;

  /// Real content revealed when [complete] is set. List variant only.
  final Widget? child;

  /// Bump this to revert a [NexusResult.failure] early — this is the
  /// keystroke path. Otherwise the error state reverts itself after 3s.
  final Object? revertSignal;

  /// Fired when the error state reverts.
  final VoidCallback? onRevert;

  /// Stable hooks for QA and widget tests.
  static const ValueKey<String> statusKey = ValueKey<String>('nexus-status');
  static const ValueKey<String> badgeKey = ValueKey<String>('nexus-badge');

  @override
  State<NexusLoader> createState() => _NexusLoaderState();
}

// ── Timing + field constants ─────────────────────────────────────────────

/// The particle field repeats exactly every [_loopSeconds]. Every time-varying
/// term below uses an integer multiple of [_omega], so the wrap is invisible
/// and the controller can stay on a finite `repeat(min:max:)` range.
const double _loopSeconds = 20;
const double _omega = 2 * math.pi / _loopSeconds;

/// Fires per second along a link. 1.5 × 20s = 30, so firing is loop-periodic.
const double _fireRate = 1.5;

const Duration _breathPeriod = Duration(milliseconds: 2400);
const Duration _completePeriod = Duration(milliseconds: 900);
const Duration _shimmerPeriod = Duration(milliseconds: 1400);
const Duration _listCrossFade = Duration(milliseconds: 400);
const Duration _errorHold = Duration(seconds: 3);
const Duration _resultPeriod = Duration(milliseconds: 480);

/// 80ms of the 480ms result animation, held flat before the stroke starts.
const double _checkDrawFraction = 80 / 480;

class _NexusLoaderState extends State<NexusLoader>
    with TickerProviderStateMixin {
  /// Monotonic seconds, looping at [_loopSeconds]. Research / think / vision.
  AnimationController? _field;

  /// Breathing ring (think) and the indeterminate vision sweep.
  AnimationController? _breath;

  /// Research / think completion, and the result check path-draw.
  AnimationController? _complete;

  /// One shared controller for every skeleton row — never one per row.
  AnimationController? _shimmer;

  /// Error shake.
  AnimationController? _shake;
  Animation<double>? _shakeOffset;

  /// [_complete], delayed and eased, for the success check path-draw.
  Animation<double>? _checkDraw;

  List<_Particle> _particles = const <_Particle>[];

  int _stage = 0;
  Timer? _stageTimer;
  Timer? _revertTimer;
  bool _reverted = false;
  bool _resultStarted = false;

  double _syncFrom = 0;

  // ── Vision level spring ────────────────────────────────────────────────
  //
  // The liquid front chases `progress` through a hand-integrated spring
  // rather than a curve, so a jump from 20% to 60% glides and settles instead
  // of teleporting. Stiffness 200 / damping 22.63 is `AppSprings.slow`
  // (ratio 0.8 at mass 1) — the same numbers, integrated here because the
  // level feeds a painter, not a widget property.
  //
  // It runs under reduced motion too: how full the bar is, is information.
  // The ticker stops itself the moment the level is at rest.
  static const double _levelStiffness = 200;
  static const double _levelDamping = 22.63;

  Ticker? _levelTicker;
  final ValueNotifier<double> _visionLevel = ValueNotifier<double>(0);
  double _levelVelocity = 0;
  Duration _lastLevelTick = Duration.zero;

  List<String> get _stages =>
      widget.label != null ? <String>[widget.label!] : (widget.stages ?? NexusStageCopy.forVariant(widget.variant));

  String get _statusText {
    final s = _stages;
    if (s.isEmpty) return '';
    if (widget.variant == NexusLoaderVariant.result) {
      if (_reverted) return '';
      return widget.label ??
          (widget.result == NexusResult.success
              ? NexusStageCopy.success
              : NexusStageCopy.failure);
    }
    return s[_stage.clamp(0, s.length - 1)];
  }

  /// What a screen reader announces. Sync folds the percentage in, because
  /// the digits themselves sit behind [ExcludeSemantics].
  String get _semanticsLabel {
    if (widget.variant != NexusLoaderVariant.sync) return _statusText;
    final percent = ((widget.progress ?? 0).clamp(0.0, 1.0) * 100).round();
    return '$_statusText $percent%';
  }

  @override
  void initState() {
    super.initState();

    switch (widget.variant) {
      case NexusLoaderVariant.research:
        _particles = _seedParticles(46, 0.10);
        _startField();
        _complete = AnimationController(vsync: this, duration: _completePeriod);
      case NexusLoaderVariant.think:
        // Roughly half the density and a slower drift: thinking should read
        // as deliberate where research reads as busy.
        _particles = _seedParticles(22, 0.06);
        _startField();
        _breath = AnimationController(vsync: this, duration: _breathPeriod)
          ..repeat(reverse: true);
        _complete = AnimationController(vsync: this, duration: _completePeriod);
      case NexusLoaderVariant.vision:
        _startField();
        _breath = AnimationController(vsync: this, duration: _breathPeriod)
          ..repeat(reverse: true);
        _visionLevel.value = widget.progress ?? 0;
      case NexusLoaderVariant.list:
        _shimmer = AnimationController(vsync: this, duration: _shimmerPeriod);
      case NexusLoaderVariant.sync:
        _syncFrom = widget.progress ?? 0;
      case NexusLoaderVariant.result:
        _complete = AnimationController(vsync: this, duration: _resultPeriod);
        // The stroke starts ~80ms after the icon lands. Expressed as an
        // Interval on the controller rather than a Future.delayed, so it is
        // cancelled with the widget instead of outliving it.
        _checkDraw = CurvedAnimation(
          parent: _complete!,
          curve: const Interval(_checkDrawFraction, 1, curve: Curves.easeOutCubic),
        );
        _shake = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 280),
        );
        _shakeOffset = _buildShake(_shake!);
    }

    _startStageClock();
    if (widget.complete) _complete?.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = reducedMotion(context);

    // The field controller must not keep ticking under reduced motion — the
    // painter reads a frozen t = 0 and draws a pre-seeded static field.
    if (_field != null) {
      if (still && _field!.isAnimating) {
        _field!.stop();
        _field!.value = 0;
      } else if (!still && !_field!.isAnimating) {
        _field!.repeat(min: 0, max: _loopSeconds, period: _loopDuration);
      }
    }
    // The breathing controller keeps running either way: under reduced motion
    // it drives opacity (0.2 → 0.3) instead of radius, on the same 2400ms.
    if (_shimmer != null) {
      if (still && _shimmer!.isAnimating) {
        _shimmer!.stop();
        _shimmer!.value = 0;
      } else if (!still && !_shimmer!.isAnimating) {
        _shimmer!.repeat();
      }
    }
    if (widget.variant == NexusLoaderVariant.result && !_resultStarted) {
      _resultStarted = true;
      _runResult();
    }
  }

  @override
  void didUpdateWidget(NexusLoader old) {
    super.didUpdateWidget(old);
    if (widget.complete && !old.complete) _complete?.forward();
    if (!widget.complete && old.complete) _complete?.value = 0;
    if (widget.variant == NexusLoaderVariant.sync) {
      _syncFrom = old.progress ?? 0;
    }
    if (widget.variant == NexusLoaderVariant.vision &&
        widget.progress != null &&
        widget.progress != old.progress) {
      _startLevelSpring();
    }
    if (widget.result != old.result || widget.revertSignal != old.revertSignal) {
      _reverted = false;
      _runResult();
    }
  }

  static const Duration _loopDuration =
      Duration(milliseconds: (_loopSeconds * 1000) ~/ 1);

  void _startField() {
    _field = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: _loopSeconds, period: _loopDuration);
  }

  void _startLevelSpring() {
    _levelTicker ??= createTicker(_integrateLevel);
    if (!_levelTicker!.isActive) {
      _lastLevelTick = Duration.zero;
      _levelTicker!.start();
    }
  }

  void _integrateLevel(Duration elapsed) {
    // Clamp dt so a dropped frame or a debugger pause cannot blow the
    // explicit integrator up.
    final dt = _lastLevelTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastLevelTick).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _lastLevelTick = elapsed;

    final target = (widget.progress ?? 0).clamp(0.0, 1.0);
    final x = _visionLevel.value;
    _levelVelocity +=
        (-_levelStiffness * (x - target) - _levelDamping * _levelVelocity) * dt;
    final next = x + _levelVelocity * dt;

    if ((next - target).abs() < 0.0005 && _levelVelocity.abs() < 0.0005) {
      _levelVelocity = 0;
      _visionLevel.value = target;
      _levelTicker!.stop();
      return;
    }
    _visionLevel.value = next;
  }

  void _startStageClock() {
    final total = _stages.length;
    if (total < 2 || widget.variant == NexusLoaderVariant.result) return;
    // Identical clock under reduced motion — only the transition collapses to
    // a cross-fade. The sequence stops dead on the final stage.
    _stageTimer = Timer.periodic(widget.stageInterval, (timer) {
      if (!mounted) return timer.cancel();
      if (_stage >= total - 1) return timer.cancel();
      setState(() => _stage++);
    });
  }

  void _runResult() {
    _revertTimer?.cancel();
    if (widget.result == NexusResult.success) {
      _shake?.value = 0;
      _complete?.forward(from: 0);
      return;
    }
    _complete?.value = 0;
    if (!reducedMotion(context)) _shake?.forward(from: 0);
    _revertTimer = Timer(_errorHold, () {
      if (!mounted || _reverted) return;
      setState(() => _reverted = true);
      widget.onRevert?.call();
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _revertTimer?.cancel();
    _field?.dispose();
    _breath?.dispose();
    _complete?.dispose();
    _shimmer?.dispose();
    _shake?.dispose();
    _levelTicker?.dispose();
    _visionLevel.dispose();
    super.dispose();
  }

  // ── Colors ────────────────────────────────────────────────────────────

  Color _toneColor(AppColors c) => switch (widget.tone) {
        NexusLoaderTone.lite => c.modeLite,
        NexusLoaderTone.deep => c.modeDeep,
        NexusLoaderTone.thinking => c.modeThinking,
        NexusLoaderTone.accent => c.accentText,
      };

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final still = reducedMotion(context);
    final tone = _toneColor(colors);

    final body = switch (widget.variant) {
      NexusLoaderVariant.research => _buildField(colors, tone, still),
      NexusLoaderVariant.think => _buildField(colors, tone, still),
      NexusLoaderVariant.vision => _buildVision(colors, tone, still),
      NexusLoaderVariant.list => _buildList(colors, still),
      NexusLoaderVariant.sync => _buildSync(colors, tone, still),
      NexusLoaderVariant.result => _buildResult(colors, tone, still),
    };

    // Real content has taken over; stop announcing a wait state and let the
    // child own its own semantics.
    if (widget.variant == NexusLoaderVariant.list &&
        widget.complete &&
        widget.child != null) {
      return body;
    }

    // The painter itself is invisible to assistive tech and to `find.text`,
    // so the status copy is published here regardless of variant.
    return Semantics(
      liveRegion: true,
      label: _semanticsLabel,
      container: true,
      child: ExcludeSemantics(child: body),
    );
  }

  // ── research / think ──────────────────────────────────────────────────

  Widget _buildField(AppColors colors, Color tone, bool still) {
    final isThink = widget.variant == NexusLoaderVariant.think;

    final field = RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable?>[
            _field,
            _breath,
            _complete,
          ]),
          builder: (context, _) {
            final breath = _breath?.value ?? 0;
            return CustomPaint(
              painter: _FlowFieldPainter(
                t: still ? 0 : (_field?.value ?? 0),
                particles: _particles,
                color: tone,
                coreColor: colors.text,
                linkDistance: isThink ? 0.46 : 0.30,
                activity: still ? 0 : (isThink ? 0.35 : 1.0),
                baseAlpha: still ? 0.4 : 1.0,
                completion: _complete?.value ?? 0,
                // Reduced motion pins the ring radius and breathes opacity
                // 0.2 → 0.3 instead, on the same 2400ms clock.
                ringScale: isThink && !still ? 1 + 0.06 * breath : 1,
                ringOpacity: isThink ? 0.2 + 0.1 * breath : 0,
                still: still,
              ),
            );
          },
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[field, AppSpacing.gapMd, _statusLine(colors, still)],
    );
  }

  /// Fixed-width status line. The box is measured off the LONGEST stage with
  /// a [TextPainter] so it never resizes mid-swap.
  Widget _statusLine(AppColors colors, bool still) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.text3,
              fontWeight: FontWeight.w600,
            ) ??
        TextStyle(color: colors.text3);
    final scaler = MediaQuery.textScalerOf(context);

    var widest = 0.0;
    for (final s in _stages) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, tp.width);
      tp.dispose();
    }

    return SizedBox(
      key: NexusLoader.statusKey,
      width: widest + 1,
      height: (style.fontSize ?? 13) * (style.height ?? 1.25) * 1.9,
      child: AnimatedSwitcher(
        duration: AppMotion.standardEnter,
        switchInCurve: AppMotion.standardDecelerate,
        switchOutCurve: AppMotion.standardAccelerate,
        transitionBuilder: (child, animation) {
          final fade = FadeTransition(opacity: animation, child: child);
          // Reduced motion keeps the same 250ms budget and cross-fades only.
          if (still) return fade;
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.45),
              end: Offset.zero,
            ).animate(animation),
            child: fade,
          );
        },
        child: Align(
          key: ValueKey<String>(_statusText),
          alignment: Alignment.center,
          child: Text(
            _statusText,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: style,
          ),
        ),
      ),
    );
  }

  // ── vision ────────────────────────────────────────────────────────────

  Widget _buildVision(AppColors colors, Color tone, bool still) {
    const inset = 14.0;
    final thumbSide = widget.size - inset * 2;

    final thumb = ClipRRect(
      borderRadius: AppRadii.brCard,
      child: SizedBox(
        width: thumbSide,
        height: thumbSide,
        child: widget.image == null
            ? ColoredBox(color: colors.bg3)
            : Image(image: widget.image!, fit: BoxFit.cover),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RepaintBoundary(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: Listenable.merge(
                <Listenable?>[_field, _breath, _visionLevel],
              ),
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    thumb,
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LiquidRingPainter(
                          t: still ? 0 : (_field?.value ?? 0),
                          // Determinate: the spring-tracked level. Otherwise
                          // the front just breathes around a nominal third.
                          fill: widget.progress == null
                              ? 0.35 + 0.15 * (_breath?.value ?? 0)
                              : _visionLevel.value,
                          indeterminate: widget.progress == null,
                          inset: inset,
                          radius: AppRadii.card,
                          color: tone,
                          trackColor: colors.border,
                          tickColor: colors.text5,
                          // Reduced motion flattens the front: no tilt, no
                          // ripple, no tremor — the level still moves.
                          liquid: !still,
                          sweepPhase: _breath?.value ?? 0,
                          still: still,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        AppSpacing.gapMd,
        _statusLine(colors, still),
      ],
    );
  }

  // ── list ──────────────────────────────────────────────────────────────

  Widget _buildList(AppColors colors, bool still) {
    final skeleton = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < widget.itemCount; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == widget.itemCount - 1 ? 0 : AppSpacing.md,
            ),
            child: _skeletonRow(colors, i, still),
          ),
      ],
    );

    if (widget.child == null) return skeleton;
    return AnimatedSwitcher(
      duration: _listCrossFade,
      child: widget.complete
          ? KeyedSubtree(
              key: const ValueKey<String>('content'),
              child: widget.child!,
            )
          : KeyedSubtree(
              key: const ValueKey<String>('skeleton'),
              child: skeleton,
            ),
    );
  }

  /// A card-shaped skeleton: same radius, padding, avatar diameter, line count
  /// and line-length ratios as the real card. Not generic grey bars.
  Widget _skeletonRow(AppColors colors, int index, bool still) {
    const lineRatios = <double>[0.62, 0.92, 0.45];

    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: colors.shimmerBase,
              borderRadius: AppRadii.brXs,
            ),
          ),
        );

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: AppRadii.brCard,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.shimmerBase,
              shape: BoxShape.circle,
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                bar(lineRatios[0], 12),
                AppSpacing.gapSm,
                bar(lineRatios[1], 10),
                AppSpacing.gapS,
                bar(lineRatios[2], 10),
              ],
            ),
          ),
        ],
      ),
    );

    // Same shapes, same count, same stagger under reduced motion — the sweep
    // is simply replaced by a flat 0.5 alpha.
    if (still) return Opacity(opacity: 0.5, child: card);

    return AnimatedBuilder(
      animation: _shimmer!,
      builder: (context, child) {
        final phase = (_shimmer!.value + index * 0.12) % 1.0;
        final dx = phase * 3 - 1.5;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(dx - 0.7, -0.3),
            end: Alignment(dx + 0.7, 0.3),
            colors: <Color>[
              colors.shimmerBase,
              colors.shimmerHighlight,
              colors.shimmerBase,
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: card,
    );
  }

  // ── sync ──────────────────────────────────────────────────────────────

  Widget _buildSync(AppColors colors, Color tone, bool still) {
    final target = (widget.progress ?? 0).clamp(0.0, 1.0);
    final percent = (target * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              _statusText,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.text3,
                  ),
            ),
            _digits(percent, colors, tone, still),
          ],
        ),
        AppSpacing.gapSm,
        ClipRRect(
          borderRadius: AppRadii.brPill,
          child: SizedBox(
            height: 6,
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: ColoredBox(color: colors.bg3)),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Progress is information — the bar keeps moving under
                    // reduced motion. Only the spring overshoot is dropped.
                    return TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: _syncFrom, end: target),
                      duration: AppMotion.standardEnter,
                      curve: still ? AppMotion.standard : Curves.easeOutBack,
                      builder: (context, value, _) => Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: value.clamp(0.0, 1.0),
                        child: Container(
                          width: constraints.maxWidth,
                          height: 6,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                tone.withValues(alpha: 0.65),
                                tone,
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Per-character [AnimatedSwitcher] keyed on the digit value, so only the
  /// digits that actually changed animate. Reduced motion drops the pop.
  Widget _digits(int percent, AppColors colors, Color tone, bool still) {
    final text = '$percent%';
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: tone,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < text.length; i++)
          AnimatedSwitcher(
            duration: still ? Duration.zero : AppMotion.microHover,
            transitionBuilder: (child, animation) {
              final fade = FadeTransition(opacity: animation, child: child);
              if (still) return fade;
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.6),
                  end: Offset.zero,
                ).animate(animation),
                child: fade,
              );
            },
            child: Text(
              text[i],
              key: ValueKey<String>('$i:${text[i]}'),
              style: style,
            ),
          ),
      ],
    );
  }

  // ── result ────────────────────────────────────────────────────────────

  Widget _buildResult(AppColors colors, Color tone, bool still) {
    final failed = widget.result == NexusResult.failure && !_reverted;
    // Reverting drops back to the neutral idle border rather than implying
    // success that never happened.
    final edge = _reverted
        ? colors.border
        : (failed ? colors.danger : colors.success);

    final badge = SizedBox(
      key: NexusLoader.badgeKey,
      width: widget.size,
      height: widget.size,
      child: AnimatedContainer(
        // Reduced motion does not translate on error; the border cross-fades
        // to the error color over 150ms instead.
        duration: still ? AppMotion.microHover : AppMotion.standardExit,
        decoration: BoxDecoration(
          color: _reverted ? Colors.transparent : edge.withValues(alpha: 0.10),
          shape: BoxShape.circle,
          border: Border.all(color: edge.withValues(alpha: 0.45), width: 2),
        ),
        child: _reverted
            ? const SizedBox.shrink()
            : failed
                ? Center(
                    child: Icon(
                      Icons.close_rounded,
                      size: widget.size * 0.42,
                      color: edge,
                    ),
                  )
                : RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _checkDraw!,
                      builder: (context, _) => CustomPaint(
                        painter: _CheckPainter(
                          // Success renders complete under reduced motion:
                          // no path-draw, no rotate, no bob, no blur.
                          progress: still ? 1 : _checkDraw!.value,
                          color: edge,
                        ),
                      ),
                    ),
                  ),
      ),
    );

    final Widget shell;
    if (failed && !still) {
      shell = AnimatedBuilder(
        animation: _shakeOffset!,
        builder: (context, child) => Transform.translate(
          offset: Offset(_shakeOffset!.value, 0),
          child: child,
        ),
        child: badge,
      );
    } else if (!failed && still) {
      shell = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: AppMotion.standardEnter,
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: badge,
      );
    } else {
      shell = badge;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[shell, AppSpacing.gapMd, _statusLine(colors, still)],
    );
  }

  static Animation<double> _buildShake(AnimationController c) {
    const curve = Cubic(0.22, 1, 0.36, 1);
    return TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 6).chain(CurveTween(curve: curve)),
        weight: 80,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 6, end: -6).chain(CurveTween(curve: curve)),
        weight: 80,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: -6, end: 4).chain(CurveTween(curve: curve)),
        weight: 60,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 4, end: 0).chain(CurveTween(curve: curve)),
        weight: 60,
      ),
    ]).animate(c);
  }

  static List<_Particle> _seedParticles(int count, double drift) {
    // Fixed seed: the reduced-motion static field is the exact frame the
    // animated field starts from.
    final rng = math.Random(0x4E58);
    return <_Particle>[
      for (var i = 0; i < count; i++)
        _Particle(
          x0: 0.10 + rng.nextDouble() * 0.80,
          y0: 0.10 + rng.nextDouble() * 0.80,
          sx: (2 + rng.nextInt(6)) * _omega,
          sy: (2 + rng.nextInt(6)) * _omega,
          px: rng.nextDouble() * math.pi * 2,
          py: rng.nextDouble() * math.pi * 2,
          r: 0.9 + rng.nextDouble() * 1.5,
          drift: drift,
        ),
    ];
  }
}

// ── Particle field ───────────────────────────────────────────────────────

@immutable
class _Particle {
  const _Particle({
    required this.x0,
    required this.y0,
    required this.sx,
    required this.sy,
    required this.px,
    required this.py,
    required this.r,
    required this.drift,
  });

  final double x0;
  final double y0;
  final double sx;
  final double sy;
  final double px;
  final double py;
  final double r;
  final double drift;
}

class _FlowFieldPainter extends CustomPainter {
  _FlowFieldPainter({
    required this.t,
    required this.particles,
    required this.color,
    required this.coreColor,
    required this.linkDistance,
    required this.activity,
    required this.baseAlpha,
    required this.completion,
    required this.ringScale,
    required this.ringOpacity,
    required this.still,
  });

  /// Seconds, looping at [_loopSeconds]. Frozen at 0 under reduced motion.
  final double t;
  final List<_Particle> particles;
  final Color color;
  final Color coreColor;

  /// Normalized link threshold (fraction of the square edge).
  final double linkDistance;

  /// 0 disables firing links entirely.
  final double activity;
  final double baseAlpha;

  /// 0..1 completion sequence: links flash, particles spiral in, core ignites.
  final double completion;

  final double ringScale;
  final double ringOpacity;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);

    if (ringOpacity > 0) {
      canvas.drawCircle(
        center,
        s * 0.42 * ringScale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: ringOpacity * baseAlpha),
      );
    }

    final spiral = completion <= 0
        ? 0.0
        : Curves.easeInCubic.transform(completion.clamp(0.0, 1.0));

    final points = <Offset>[];
    for (final p in particles) {
      var x = p.x0 +
          p.drift *
              0.5 *
              (math.sin(p.sx * t + p.px) +
                  math.sin(p.y0 * math.pi * 2 + 3 * _omega * t));
      var y = p.y0 +
          p.drift *
              0.5 *
              (math.cos(p.sy * t + p.py) +
                  math.cos(p.x0 * math.pi * 2 - 2 * _omega * t));
      x = x.clamp(0.06, 0.94);
      y = y.clamp(0.06, 0.94);

      if (spiral > 0) {
        final dx = x - 0.5;
        final dy = y - 0.5;
        final rad = math.sqrt(dx * dx + dy * dy) * (1 - spiral);
        final ang = math.atan2(dy, dx) + spiral * 2.6;
        x = 0.5 + rad * math.cos(ang);
        y = 0.5 + rad * math.sin(ang);
      }
      points.add(Offset(x * size.width, y * size.height));
    }

    // Links. All of them flash at the front of the completion sequence.
    final flash = completion <= 0
        ? 0.0
        : (1 - (completion / 0.35)).clamp(0.0, 1.0);
    final threshold = linkDistance * s;
    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final near = <(int, int)>[];
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final d = (points[i] - points[j]).distance;
        if (d >= threshold) continue;
        near.add((i, j));
        final closeness = 1 - d / threshold;
        final alpha =
            (closeness * 0.28 + flash * 0.55).clamp(0.0, 1.0) * baseAlpha;
        canvas.drawLine(
          points[i],
          points[j],
          linkPaint..color = color.withValues(alpha: alpha),
        );
      }
    }

    // Occasionally one link fires: a bright head travels along it.
    if (activity > 0 && near.isNotEmpty && completion <= 0) {
      final tick = t * _fireRate * activity;
      final link = near[tick.floor().abs() % near.length];
      final u = tick - tick.floorToDouble();
      final head = Offset.lerp(points[link.$1], points[link.$2], u)!;
      canvas.drawLine(
        points[link.$1],
        points[link.$2],
        linkPaint..color = color.withValues(alpha: 0.42 * baseAlpha),
      );
      canvas.drawCircle(
        head,
        2.4,
        Paint()
          ..color = coreColor.withValues(alpha: 0.9 * baseAlpha)
          // One blurred Paint for the whole frame beats building a radial
          // gradient shader per particle per frame.
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    final dotGlow = Paint()
      ..color = color.withValues(alpha: 0.55 * baseAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final dotCore = Paint()..color = color.withValues(alpha: 0.95 * baseAlpha);
    for (var i = 0; i < points.length; i++) {
      final r = particles[i].r * (1 + flash * 0.6);
      canvas.drawCircle(points[i], r * 2.1, dotGlow);
      canvas.drawCircle(points[i], r, dotCore);
    }

    // White-hot core plus one expanding ring.
    if (completion > 0.45) {
      final k = ((completion - 0.45) / 0.55).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        s * 0.05 * (1 - k * 0.3),
        Paint()
          ..color = coreColor.withValues(alpha: 1 - k * 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        center,
        s * (0.06 + 0.40 * Curves.easeOutCubic.transform(k)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * (1 - k)
          ..color = color.withValues(alpha: (1 - k) * 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(_FlowFieldPainter old) =>
      old.t != t ||
      old.completion != completion ||
      old.ringScale != ringScale ||
      old.ringOpacity != ringOpacity ||
      old.color != color ||
      old.baseAlpha != baseAlpha ||
      old.still != still;
}

// ── Liquid progress ring ─────────────────────────────────────────────────

class _LiquidRingPainter extends CustomPainter {
  _LiquidRingPainter({
    required this.t,
    required this.fill,
    required this.indeterminate,
    required this.inset,
    required this.radius,
    required this.color,
    required this.trackColor,
    required this.tickColor,
    required this.liquid,
    required this.sweepPhase,
    required this.still,
  });

  final double t;
  final double fill;
  final bool indeterminate;
  final double inset;
  final double radius;
  final Color color;
  final Color trackColor;
  final Color tickColor;

  /// False under reduced motion: tilt, ripple and tremor all go to zero and
  /// the front stays flat.
  final bool liquid;
  final double sweepPhase;
  final bool still;

  static const int _steps = 14;
  static const int _ticks = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final thumb = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(thumb, Radius.circular(radius));

    _paintLiquid(canvas, thumb, rrect);
    _paintRing(canvas, size);
  }

  void _paintLiquid(Canvas canvas, Rect thumb, RRect rrect) {
    final level = thumb.bottom - thumb.height * fill.clamp(0.0, 1.0);
    final tilt = liquid ? math.sin(2 * _omega * t) * 5.0 : 0.0;
    final amp = liquid ? 2.6 : 0.0;

    final path = Path()
      ..moveTo(thumb.left, thumb.bottom)
      ..lineTo(thumb.left, level - tilt / 2);
    for (var i = 0; i <= _steps; i++) {
      final u = i / _steps;
      final x = thumb.left + thumb.width * u;
      final ripple = amp * math.sin(u * math.pi * 3 + 5 * _omega * t) +
          amp * 0.45 * math.sin(u * math.pi * 5 - 3 * _omega * t);
      path.lineTo(x, level + (u - 0.5) * tilt + ripple);
    }
    path
      ..lineTo(thumb.right, thumb.bottom)
      ..close();

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0.22),
          ],
        ).createShader(thumb),
    );
    // Thin meniscus along the front only.
    final front = Path()..moveTo(thumb.left, level - tilt / 2);
    for (var i = 0; i <= _steps; i++) {
      final u = i / _steps;
      final x = thumb.left + thumb.width * u;
      final ripple = amp * math.sin(u * math.pi * 3 + 5 * _omega * t) +
          amp * 0.45 * math.sin(u * math.pi * 5 - 3 * _omega * t);
      front.lineTo(x, level + (u - 0.5) * tilt + ripple);
    }
    canvas.drawPath(
      front,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.95),
    );
    canvas.restore();
  }

  void _paintRing(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 2;

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = trackColor,
    );

    // Ticks. Determinate lights them up to `fill`; indeterminate sweeps a
    // comet head over them, or — under reduced motion — cross-fades them all.
    final crossFade = still ? 0.25 + 0.45 * sweepPhase : 0.0;
    final headAngle = -math.pi / 2 + sweepPhase * math.pi * 2;
    for (var i = 0; i < _ticks; i++) {
      final frac = i / _ticks;
      final angle = -math.pi / 2 + frac * math.pi * 2;
      final lit = indeterminate
          ? (still
              ? crossFade
              : _cometFalloff(angle, headAngle))
          : (frac <= fill ? 1.0 : 0.0);
      final tickPaint = Paint()
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(tickColor, color, lit)!
            .withValues(alpha: 0.35 + 0.65 * lit);
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * r;
      final inner =
          center + Offset(math.cos(angle), math.sin(angle)) * (r - 4 - 2 * lit);
      canvas.drawLine(inner, outer, tickPaint);
    }

    if (!indeterminate) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -math.pi / 2,
        math.pi * 2 * fill.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      return;
    }

    if (still) return;
    final head = center + Offset(math.cos(headAngle), math.sin(headAngle)) * r;
    canvas.drawCircle(
      head,
      3,
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  /// 1 at the comet head, fading to 0 about a fifth of a turn behind it.
  double _cometFalloff(double angle, double headAngle) {
    var delta = (headAngle - angle) % (math.pi * 2);
    if (delta < 0) delta += math.pi * 2;
    const tail = math.pi * 0.4;
    if (delta > tail) return 0;
    return 1 - delta / tail;
  }

  @override
  bool shouldRepaint(_LiquidRingPainter old) =>
      old.t != t ||
      old.fill != fill ||
      old.sweepPhase != sweepPhase ||
      old.indeterminate != indeterminate ||
      old.color != color ||
      old.still != still;
}

// ── Success check ────────────────────────────────────────────────────────

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.44, h * 0.68)
      ..lineTo(w * 0.73, h * 0.34);

    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.4, w * 0.055)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}
