import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/services/hold_to_speak_service.dart';
import '../../core/theme/app_colors.dart';

/// Self-contained hold-to-speak mic button for follow-up chat inputs.
///
/// Hold → records speech → release → replaces [controller] text with the
/// final transcript. All robustness lives in [HoldToSpeakController]
/// (silence-recovery, restart accumulation, sound-level monitoring,
/// permission handling, single-engine coordination).
///
/// This widget is a thin UI shell that:
///   * pipes live partials into the parent [TextEditingController] for
///     immediate visual feedback;
///   * runs a pulse animation while the mic is hot;
///   * scales the icon based on incoming audio level so the user can see
///     that the mic is actually listening (the previous version gave no
///     such feedback, leaving users to guess whether their words were
///     being captured during pauses).
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.controller,
    required this.colors,
    this.onListeningChanged,
    this.disabled = false,
    this.tag = 'Voice',
  });

  final TextEditingController controller;
  final AppColors colors;

  /// Called when listening state changes (for parent to disable send, etc.).
  final ValueChanged<bool>? onListeningChanged;

  /// Disables the button (e.g. while sending).
  final bool disabled;

  /// Tag for log messages.
  final String tag;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  late final HoldToSpeakController _voice;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  bool _wasListening = false;
  String _lastShownText = '';

  @override
  void initState() {
    super.initState();
    _voice = HoldToSpeakController(tag: widget.tag);
    _voice.addListener(_onVoiceUpdate);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Pre-warm the engine so the first press doesn't cold-start.
    HoldToSpeakController.warmUp();
  }

  @override
  void dispose() {
    _voice.removeListener(_onVoiceUpdate);
    _voice.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onVoiceUpdate() {
    if (!mounted) return;
    final listening = _voice.isListening;
    bool needsRebuild = false;

    // Pipe live partials into the parent controller. We only write when the
    // text actually changes to avoid spurious cursor jumps during typing.
    final next = _voice.displayText;
    if (next != _lastShownText) {
      _lastShownText = next;
      widget.controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      needsRebuild = true;
    }

    if (listening != _wasListening) {
      _wasListening = listening;
      widget.onListeningChanged?.call(listening);
      if (listening) {
        _pulseCtrl.repeat(reverse: true);
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.reset();
      }
      needsRebuild = true;
    }

    if (needsRebuild) setState(() {});
  }

  Future<void> _onPointerDown() async {
    if (widget.disabled || _voice.isListening) return;
    widget.controller.clear();
    _lastShownText = '';
    await _voice.start();
  }

  Future<void> _onPointerUp() async {
    if (!_voice.isListening &&
        _voice.status != HoldToSpeakStatus.stopping &&
        _voice.status != HoldToSpeakStatus.initializing) {
      return;
    }
    final result = await _voice.stop();
    if (!mounted) return;
    final text = result.transcript;
    _lastShownText = text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _onPointerCancel() => _onPointerUp();

  @override
  Widget build(BuildContext context) {
    final active = _voice.isListening;
    final color = active ? const Color(0xFFF87171) : AppColors.accent;
    final opacity = widget.disabled && !active ? 0.35 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _onPointerDown(),
        onPointerUp: (_) => _onPointerUp(),
        onPointerCancel: (_) => _onPointerCancel(),
        // Sound-level updates have their own ValueListenable so they DON'T
        // rebuild the whole button tree on every audio frame — only the
        // inner Transform.scale rebuilds, and only when the level changes.
        child: ValueListenableBuilder<double>(
          valueListenable: _voice.soundLevelListenable,
          builder: (context, level, child) {
            return AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, _) {
                final levelBoost = active ? (level * 0.10) : 0.0;
                final scale = active ? _pulseAnim.value + levelBoost : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: active ? 0.18 : 0.10),
              border: Border.all(
                color: color.withValues(alpha: active ? 0.5 : 0.25),
                width: active ? 1.5 : 1.0,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active ? LucideIcons.micOff : LucideIcons.mic,
                  size: 16,
                  color: color,
                ),
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      '●',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 5,
                        color: color,
                        fontWeight: FontWeight.w900,
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
