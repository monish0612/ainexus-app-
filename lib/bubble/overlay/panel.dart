import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/rephrase_platform.dart';
import 'overlay_bridge.dart';
import 'panel_anchor.dart';
import 'tokens.dart';

/// Opaque AMOLED surface for the expanded panel. Never translucent — chat text
/// bleeding through glass made the result unreadable.
class PanelSurface extends StatelessWidget {
  const PanelSurface({
    super.key,
    required this.child,
    this.radius = kPanelRadius,
    this.padding = kPanelPadding,
    this.elevated = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  /// True for nested cards (result, tone field) — slightly lifted off pure black.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: elevated ? kPanelSurface : kPanelBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: kPanelStroke),
        boxShadow: elevated
            ? null
            : const [
                BoxShadow(
                  color: kPanelShadow,
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// What came back from a rephrase attempt: text on success, a short message on
/// failure. Where the text lands is decided later, when the user accepts it.
class PanelResult {
  const PanelResult.success(this.text) : error = null;

  const PanelResult.failure(String this.error) : text = '';

  final String text;
  final String? error;

  bool get ok => error == null;
}

typedef RunRephrase = Future<PanelResult> Function(
  String platform,
  String? intent, {
  required bool fresh,
});

/// The expanded AMOLED panel: grouped Rewrite / Tone / Chat actions, a tone
/// prompt for "Own", and a review flow — the result is shown first; "New
/// version" regenerates a different take, "Use" writes it into the field
/// and closes the panel.
class RephrasePanel extends StatefulWidget {
  const RephrasePanel({
    super.key,
    required this.target,
    required this.onRun,
    required this.onAccept,
    required this.onCopy,
    required this.onClose,
    required this.onFocusRequest,
    required this.onMeasured,
    this.lastPlatformId,
    this.onPlatformUsed,
  });

  final BubbleTarget target;
  final RunRephrase onRun;

  /// Write the reviewed text into the target field; the outcome decides whether
  /// the panel closes (replaced) or explains itself (blocked → copied).
  final Future<ReplaceOutcome> Function(String text) onAccept;

  final void Function(String text) onCopy;
  final VoidCallback onClose;

  /// Lend/return keyboard focus. Must complete before the tone field mounts,
  /// otherwise the IME has nowhere to attach.
  final Future<void> Function(bool focusable) onFocusRequest;

  final void Function(Size size) onMeasured;

  /// Last successful platform id — shown first in the chip row (no auto-run).
  final String? lastPlatformId;

  /// Persist a successful chip choice for the next open.
  final void Function(String platformId)? onPlatformUsed;

  @override
  State<RephrasePanel> createState() => _RephrasePanelState();
}

/// Put [preferredId] first when it exists in [from]; otherwise keep order.
List<RephrasePlatform> platformsWithPreferredFirst(
  String? preferredId, {
  List<RephrasePlatform>? from,
}) {
  final source = from ?? kRephrasePlatforms;
  if (preferredId == null || preferredId.isEmpty) {
    return List<RephrasePlatform>.from(source);
  }
  final preferred = source.where((p) => p.id == preferredId).toList();
  if (preferred.isEmpty) {
    return List<RephrasePlatform>.from(source);
  }
  return [
    ...preferred,
    ...source.where((p) => p.id != preferredId),
  ];
}

class _RephrasePanelState extends State<RephrasePanel> {
  final _contentKey = GlobalKey();
  final _toneCtrl = TextEditingController();
  final _toneFocus = FocusNode();

  String? _activePlatform;
  String? _lastIntent;
  bool _askingTone = false;
  bool _loading = false;
  PanelResult? _result;
  bool _copied = false;
  bool _accepting = false;
  bool _accepted = false;
  bool _blocked = false;
  Size? _reported;

  /// Live swipe-down offset for the dismiss gesture.
  double _dragY = 0;

  /// Clamped font-scale factor, refreshed each build.
  double _scale = 1;

  late RephraseGroup _group = groupForPlatformId(widget.lastPlatformId);

  List<RephrasePlatform> get _platforms => platformsWithPreferredFirst(
        widget.lastPlatformId,
        from: platformsInGroup(_group),
      );

  /// How tall the result text may get before it scrolls. Derived from the
  /// display's panel budget, so a long rephrase never overflows the window.
  double get _resultMaxHeight {
    // Header, group tabs, chip row, gaps, result padding, Use / New row.
    const chrome = 44.0 + 8 + 28 + 8 + 10 + 20 + 40;
    final budget = widget.target.maxHeight -
        kPanelPadding.vertical -
        kPanelShadowMargin * 2 -
        chrome -
        34 * _scale;
    return math.max(48, math.min(150 * _scale, budget));
  }

  @override
  void dispose() {
    _toneCtrl.dispose();
    _toneFocus.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _pick(RephrasePlatform platform) async {
    if (_loading) return;
    if (platform.id == 'own') {
      await _openToneInput();
      return;
    }
    await _run(platform.id, null);
  }

  /// "Own" needs the tone typed here, because the text itself already lives in
  /// the other app's field. In-app you'd type `rephrase to simple tone "..."`;
  /// here only the instruction is missing.
  Future<void> _openToneInput() async {
    setState(() {
      _activePlatform = 'own';
      _askingTone = true;
      _result = null;
    });
    await widget.onFocusRequest(true);
    if (!mounted) return;
    _toneFocus.requestFocus();
  }

  Future<void> _cancelToneInput() async {
    _toneFocus.unfocus();
    await widget.onFocusRequest(false);
    if (!mounted) return;
    setState(() {
      _askingTone = false;
      _activePlatform = null;
    });
  }

  Future<void> _submitTone() async {
    final tone = _toneCtrl.text.trim();
    if (tone.isEmpty) {
      _toneFocus.requestFocus();
      return;
    }
    // Hand focus back to the target field *before* the network call, so the
    // write-back has somewhere to land.
    _toneFocus.unfocus();
    await widget.onFocusRequest(false);
    if (!mounted) return;
    setState(() => _askingTone = false);
    await _run('own', tone);
  }

  Future<void> _run(String platform, String? intent, {bool fresh = false}) async {
    setState(() {
      _activePlatform = platform;
      _lastIntent = intent;
      _loading = true;
      _copied = false;
      _accepting = false;
      _accepted = false;
      _blocked = false;
      // On a regenerate the old text stays visible (dimmed) under the shimmer,
      // so the panel doesn't jump between sizes.
      if (!fresh) _result = null;
    });
    PanelResult result;
    try {
      result = await widget
          .onRun(platform, intent, fresh: fresh)
          .timeout(
            const Duration(seconds: 16),
            onTimeout: () =>
                const PanelResult.failure('Timed out — tap to retry'),
          );
    } catch (_) {
      result = const PanelResult.failure('Rephrase failed — tap to retry');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });
    if (result.ok) {
      HapticFeedback.lightImpact();
      widget.onPlatformUsed?.call(platform);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // Don't fight the tone TextField or an in-flight accept.
    if (_askingTone || _accepting || _accepted) return;
    setState(() {
      _dragY = (_dragY + details.delta.dy).clamp(0.0, 220.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_askingTone || _accepting || _accepted) {
      setState(() => _dragY = 0);
      return;
    }
    final fling = details.primaryVelocity ?? 0;
    if (_dragY > 80 || fling > 700) {
      HapticFeedback.selectionClick();
      widget.onClose();
      return;
    }
    setState(() => _dragY = 0);
  }

  /// "New version": same request, cache bypassed, a different take.
  Future<void> _regenerate() async {
    final platform = _activePlatform;
    if (platform == null || _loading || _accepting) return;
    await _run(platform, _lastIntent, fresh: true);
  }

  /// "Use": write the reviewed text into the field, flash the confirmation,
  /// and close. A blocked field keeps the panel open and explains the copy.
  Future<void> _accept() async {
    final text = _result?.text;
    if (text == null || text.isEmpty || _accepting || _accepted) return;
    setState(() {
      _accepting = true;
      _blocked = false;
    });
    final outcome = await widget.onAccept(text);
    if (!mounted) return;
    if (outcome.replaced) {
      HapticFeedback.lightImpact();
      setState(() {
        _accepting = false;
        _accepted = true;
      });
      await Future<void>.delayed(kAcceptFlash);
      if (mounted) widget.onClose();
    } else {
      // Native already put the text on the clipboard.
      setState(() {
        _accepting = false;
        _blocked = true;
      });
    }
  }

  void _copy() {
    final text = _result?.text;
    if (text == null || text.isEmpty) return;
    widget.onCopy(text);
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _retry() async {
    final platform = _activePlatform;
    if (platform == null) return;
    await _run(platform, _lastIntent);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  /// Tell native the panel's real size so the overlay window hugs it instead of
  /// swallowing touches meant for the app underneath.
  ///
  /// Measures the content column, not the visible glass: the column's intrinsic
  /// height is independent of the current window height, so the window can never
  /// get stuck small and starve a long result of room.
  void _reportSize(double windowWidth) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final content = _contentKey.currentContext?.size;
      if (content == null || content.isEmpty) return;
      final size = Size(
        windowWidth,
        content.height + kPanelPadding.vertical + kPanelShadowMargin * 2,
      );
      final previous = _reported;
      if (previous != null &&
          (previous.width - size.width).abs() < 2 &&
          (previous.height - size.height).abs() < 2) {
        return;
      }
      _reported = size;
      widget.onMeasured(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scale = textScale(context);
    // Never wider than the design cap or the display budget native handed us.
    //
    // Deliberately NOT clamped by media.size (the current window): the window
    // is whatever we last asked for, so using it as an input echoes it back.
    // During the bubble→panel expansion there is a frame where the surface is
    // still bubble-sized (76dp); clamping to it reported a 76dp panel, native
    // shrank the freshly grown window to match, and the panel stayed tiny
    // forever. The budget comes from the display, so it cannot feed back.
    final windowWidth = math.min(
      kPanelMaxWidth + kPanelShadowMargin * 2,
      widget.target.maxWidth,
    );
    final glassWidth = windowWidth - kPanelShadowMargin * 2;
    _reportSize(windowWidth);

    final media = MediaQuery.of(context);
    // Back closes while the Own tone field holds focus (overlay is focusable).
    // Panel sits near the collapsed bubble (thumb reach); Own tone pins to the
    // top so the IME never covers the field.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_askingTone) {
          await _cancelToneInput();
        }
        if (mounted) widget.onClose();
      },
      child: CustomSingleChildLayout(
        delegate: PanelNearBubbleDelegate(
          bubbleX: widget.target.bubbleX,
          bubbleY: widget.target.bubbleY,
          bubbleSize: widget.target.bubbleSize ?? bubbleSize(context),
          safeTop: media.padding.top + 8,
          safeBottom: media.padding.bottom + 8,
          pinTop: _askingTone,
          maxPanelWidth: windowWidth,
          maxPanelHeight: widget.target.maxHeight,
        ),
        child: GestureDetector(
          // opaque so a tap on the panel never falls through to the scrim
          // (that was closing the panel on the same click that opened it).
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: AnimatedContainer(
            duration: kResultSwap,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _dragY, 0),
            // Fade as the user pulls down so the dismiss feels intentional.
            child: Opacity(
              opacity: (1 - (_dragY / 280)).clamp(0.55, 1.0),
              child: SizedBox(
                width: windowWidth,
                child: Padding(
                  padding: const EdgeInsets.all(kPanelShadowMargin),
                  child: SizedBox(
                    width: glassWidth > 0 ? glassWidth : null,
                    child: PanelSurface(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Column(
                          key: _contentKey,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header(),
                            const SizedBox(height: 8),
                            if (_askingTone) _toneRow() else _platformRow(),
                            if (_loading ||
                                _result != null ||
                                widget.target.isEmpty) ...[
                              const SizedBox(height: 10),
                              _statusArea(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final active = rephrasePlatformById(_activePlatform);
    final title = _loading && active != null
        ? active.busyLabel
        : (active != null && _result != null ? active.label : 'Rephrase');
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        _iconButton(_CloseGlyph(), 'Close', widget.onClose, size: 24),
      ],
    );
  }

  Widget _groupTabs() {
    return SizedBox(
      height: 28 * _scale,
      child: Row(
        children: [
          for (final group in RephraseGroup.values) ...[
            if (group != RephraseGroup.values.first) const SizedBox(width: 6),
            _groupTab(group),
          ],
        ],
      ),
    );
  }

  Widget _groupTab(RephraseGroup group) {
    final active = _group == group;
    final label = rephraseGroupLabel(group);
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _loading
              ? null
              : () {
                  if (_group == group) return;
                  setState(() => _group = group);
                },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: active ? kAccent.withValues(alpha: 0.22) : kChipIdle,
              border: Border.all(
                color: active ? kAccent.withValues(alpha: 0.7) : kPanelStroke,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? kTextPrimary : kTextMuted,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _platformRow() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _groupTabs(),
        SizedBox(height: 8 * _scale),
        SizedBox(
          // Grows with the font scale so tall glyphs are never clipped.
          height: 34 * _scale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _platforms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, index) {
              final platform = _platforms[index];
              return _chip(
                platform.chipLabel,
                active: _activePlatform == platform.id,
                onTap: () => _pick(platform),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _toneRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38 * _scale,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: kPanelSurface,
              border: Border.all(color: kPanelStroke),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: _toneCtrl,
              focusNode: _toneFocus,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: kTextPrimary, fontSize: 13),
              cursorColor: kAccent,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Tone, e.g. professional simple',
                hintStyle: TextStyle(color: kTextMuted, fontSize: 13),
              ),
              onSubmitted: (_) => _submitTone(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _iconButton(_SendGlyph(), 'Rephrase with this tone', _submitTone,
            size: 28),
        _iconButton(_CloseGlyph(), 'Cancel tone', _cancelToneInput, size: 24),
      ],
    );
  }

  Widget _statusArea() {
    if (widget.target.isEmpty && _result == null && !_loading) {
      return _note('Nothing to rephrase in this field yet');
    }

    final result = _result;
    final showingText = result?.ok == true;
    return PanelSurface(
      radius: 16,
      elevated: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _resultMaxHeight),
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: kResultSwap,
                switchInCurve: Curves.easeOutCubic,
                child: _resultText(result),
              ),
            ),
          ),
          if (showingText || (result != null && !result.ok)) ...[
            const SizedBox(height: 8),
            _actionRow(result!),
          ],
          if (_blocked) ...[
            const SizedBox(height: 6),
            _note("Couldn't edit this field — copied to clipboard"),
          ],
        ],
      ),
    );
  }

  Widget _resultText(PanelResult? result) {
    if (_loading && result == null) {
      return const Text(
        'Rephrasing…',
        key: ValueKey('loading'),
        style: TextStyle(color: kTextMuted, fontSize: 13),
      );
    }
    final ok = result?.ok == true;
    return Opacity(
      key: ValueKey(ok ? result!.text : (result?.error ?? '')),
      // Dim the old text while a new version streams in.
      opacity: _loading ? 0.4 : 1,
      child: Text(
        ok ? result!.text : (result?.error ?? ''),
        style: TextStyle(
          color: ok ? kTextPrimary : kDanger,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }

  /// Review controls: regenerate a different version, copy, or accept — accept
  /// replaces the text in the field and closes the panel.
  Widget _actionRow(PanelResult result) {
    if (!result.ok) {
      return Row(
        children: [
          const Spacer(),
          _iconButton(_RetryGlyph(), 'Retry', _retry, size: kCopyButtonSize),
        ],
      );
    }
    // A Wrap, not a Row: on narrow windows or large font scales the Use pill
    // flows onto its own line instead of overflowing.
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ghostButton(
              semantics: 'New version',
              glyph: _RegenGlyph(),
              label: 'New',
              onTap: _regenerate,
              busy: _loading,
            ),
            const SizedBox(width: 6),
            _iconButton(
              _copied ? _CheckGlyph() : _CopyGlyph(),
              'Copy rephrased text',
              _copy,
              size: kCopyButtonSize,
            ),
          ],
        ),
        _usePill(),
      ],
    );
  }

  /// The accent-filled accept button. Morphs label → spinner → check.
  Widget _usePill() {
    final Widget inner;
    if (_accepted) {
      inner = CustomPaint(
        key: const ValueKey('done'),
        size: const Size(16, 16),
        painter: _CheckGlyph(),
      );
    } else if (_accepting) {
      inner = const SizedBox(
        key: ValueKey('busy'),
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: kTextPrimary),
      );
    } else {
      inner = const Text(
        'Use',
        key: ValueKey('label'),
        style: TextStyle(
          color: kTextPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      );
    }
    return Semantics(
      // A dedicated node: the inner Text would otherwise merge its own label
      // over this one and make the button invisible to accessibility.
      container: true,
      excludeSemantics: true,
      button: true,
      label: 'Use rephrased text',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _accept,
        child: AnimatedContainer(
          duration: kResultSwap,
          curve: Curves.easeOutCubic,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: _accepted ? const Color(0xFF1E9E63) : kAccent,
          ),
          child: Center(
            child: AnimatedSwitcher(duration: kResultSwap, child: inner),
          ),
        ),
      ),
    );
  }

  /// Compact outlined secondary button (the "New version" regenerate).
  Widget _ghostButton({
    required String semantics,
    required CustomPainter glyph,
    required String label,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: kChipIdle,
            border: Border.all(color: kPanelStroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: kTextMuted,
                  ),
                )
              else
                CustomPaint(size: const Size(14, 14), painter: glyph),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: kTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _note(String text) => Text(
        text,
        style: const TextStyle(color: kTextMuted, fontSize: 11, height: 1.3),
      );

  // ── Small building blocks ────────────────────────────────────────────────

  Widget _chip(
    String label, {
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active ? kAccent.withValues(alpha: 0.22) : kChipIdle,
          border: Border.all(
            color: active ? kAccent.withValues(alpha: 0.7) : kPanelStroke,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? kTextPrimary : kTextMuted,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// A [size]x[size] glass glyph button padded out to a 44dp touch target.
  Widget _iconButton(
    CustomPainter glyph,
    String semantics,
    VoidCallback onTap, {
    double size = 28,
  }) {
    return Semantics(
      button: true,
      label: semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(((44 - size) / 2).clamp(0, 12)),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: kChipIdle,
              border: Border.all(color: kPanelStroke),
            ),
            child: CustomPaint(painter: glyph),
          ),
        ),
      ),
    );
  }
}

class _CopyGlyph extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;
    final back = Rect.fromLTWH(
        s.width * 0.30, s.height * 0.18, s.width * 0.42, s.height * 0.42);
    final front = Rect.fromLTWH(
        s.width * 0.22, s.height * 0.36, s.width * 0.42, s.height * 0.42);
    c.drawRRect(RRect.fromRectAndRadius(back, const Radius.circular(2)), p);
    c.drawRRect(
      RRect.fromRectAndRadius(front, const Radius.circular(2)),
      Paint()..color = const Color(0x22000000),
    );
    c.drawRRect(RRect.fromRectAndRadius(front, const Radius.circular(2)), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CheckGlyph extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(
      Path()
        ..moveTo(s.width * 0.28, s.height * 0.52)
        ..lineTo(s.width * 0.44, s.height * 0.68)
        ..lineTo(s.width * 0.74, s.height * 0.34),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CloseGlyph extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = kTextMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(s.width * 0.34, s.height * 0.34),
        Offset(s.width * 0.66, s.height * 0.66), p);
    c.drawLine(Offset(s.width * 0.66, s.height * 0.34),
        Offset(s.width * 0.34, s.height * 0.66), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _SendGlyph extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(
      Path()
        ..moveTo(s.width * 0.26, s.height * 0.5)
        ..lineTo(s.width * 0.7, s.height * 0.5)
        ..moveTo(s.width * 0.52, s.height * 0.3)
        ..lineTo(s.width * 0.72, s.height * 0.5)
        ..lineTo(s.width * 0.52, s.height * 0.7),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Two curved arrows — "generate a different version".
class _RegenGlyph extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = kTextMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rect = Rect.fromCircle(
      center: Offset(s.width / 2, s.height / 2),
      radius: s.width * 0.34,
    );
    c.drawArc(rect, -0.4, 2.4, false, p);
    c.drawArc(rect, 2.74, 2.4, false, p);
    // Arrow heads.
    final tipA = Offset(s.width * 0.86, s.height * 0.36);
    c.drawLine(tipA, tipA + Offset(-s.width * 0.16, -s.height * 0.02), p);
    c.drawLine(tipA, tipA + Offset(-s.width * 0.02, s.height * 0.16), p);
    final tipB = Offset(s.width * 0.14, s.height * 0.64);
    c.drawLine(tipB, tipB + Offset(s.width * 0.16, s.height * 0.02), p);
    c.drawLine(tipB, tipB + Offset(s.width * 0.02, -s.height * 0.16), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _RetryGlyph extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = kDanger
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(
      center: Offset(s.width / 2, s.height / 2),
      radius: s.width * 0.24,
    );
    c.drawArc(rect, 0.6, 4.9, false, p);
    c.drawLine(
      Offset(s.width * 0.68, s.height * 0.24),
      Offset(s.width * 0.72, s.height * 0.42),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
