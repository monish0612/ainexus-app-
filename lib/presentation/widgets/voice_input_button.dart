import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/services/telegram_logger.dart';
import '../../core/theme/app_colors.dart';

/// Self-contained hold-to-speak mic button for follow-up chat inputs.
///
/// Hold → records speech → release → replaces [controller] text with result.
/// Uses [speech_to_text] with dictation mode and auto-restart on silence while
/// held. Text is accumulated across engine auto-restarts so nothing is lost
/// when Android's native silence detector fires.
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

  /// Tag for TLog messages.
  final String tag;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _listening = false;
  bool _holdActive = false;

  /// Text recognised in previous listen sessions within the same hold gesture.
  /// Android's speech recogniser fires silence-timeout after 1-3 s which kills
  /// the session; we restart transparently but must keep what was already said.
  String _accumulatedText = '';

  /// Guards against overlapping restart attempts.
  bool _restarting = false;

  /// When true, `onResult` callbacks are ignored (stop/restart in progress).
  bool _resultsGated = false;

  static const _kRestartDelay = Duration(milliseconds: 350);
  static const _kMaxRestartRetries = 3;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _initSpeech();
  }

  @override
  void dispose() {
    _holdActive = false;
    _resultsGated = true;
    if (_listening) {
      try {
        _speech.stop();
      } catch (e) {
        TLog.w('VoiceInput', 'Failed to stop speech on dispose', error: e);
      }
    }
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            if (_holdActive) {
              _restartSession();
            } else {
              _setListening(false);
            }
          }
        },
        onError: (error) {
          TLog.w(widget.tag, 'Speech error: ${error.errorMsg} (permanent=${error.permanent})');
          if (error.permanent && mounted) {
            if (_holdActive) {
              _restartSession();
            } else {
              _setListening(false);
            }
          }
        },
      );
      TLog.d(widget.tag, 'Speech init: available=$_available');
    } catch (e) {
      TLog.e(widget.tag, 'Speech init failed', error: e);
      _available = false;
    }
  }

  void _setListening(bool value) {
    if (_listening == value) return;
    setState(() => _listening = value);
    widget.onListeningChanged?.call(value);
    if (value) {
      _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  Future<void> _start() async {
    if (_listening || widget.disabled) return;
    if (!_available) {
      TLog.w(widget.tag, 'Speech not available on device');
      return;
    }

    try {
      _holdActive = true;
      _accumulatedText = '';
      _restarting = false;
      widget.controller.clear();
      _setListening(true);
      TLog.i(widget.tag, 'Hold-to-speak started');
      await _beginSession();
    } catch (e) {
      TLog.e(widget.tag, 'Failed to start voice', error: e);
      _holdActive = false;
      _setListening(false);
    }
  }

  Future<void> _beginSession() async {
    if (!_holdActive || !mounted) return;
    _resultsGated = false;
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted || _resultsGated) return;
          final sessionWords = result.recognizedWords;
          final combined = _accumulatedText.isEmpty
              ? sessionWords
              : '$_accumulatedText $sessionWords';
          widget.controller.value = TextEditingValue(
            text: combined,
            selection: TextSelection.collapsed(offset: combined.length),
          );
        },
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 60),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: true,
        ),
      );
    } catch (e) {
      TLog.e(widget.tag, 'Listen session error', error: e);
      if (_holdActive && mounted) {
        _restartSession();
      } else {
        _holdActive = false;
        _setListening(false);
      }
    }
  }

  Future<void> _restartSession() async {
    if (!_holdActive || !mounted || _restarting) return;
    _restarting = true;

    for (var attempt = 1; attempt <= _kMaxRestartRetries; attempt++) {
      if (!_holdActive || !mounted) break;
      try {
        // Gate results BEFORE stop so the final onResult from stop() is
        // ignored — this prevents the doubled-text bug.
        _resultsGated = true;
        await _speech.stop();

        // NOW safe to snapshot: no more callbacks can fire for the old session.
        final currentText = widget.controller.text.trim();
        if (currentText.isNotEmpty) {
          _accumulatedText = currentText;
        }

        await Future<void>.delayed(_kRestartDelay);
        if (!_holdActive || !mounted) break;
        // _beginSession resets the gate to false before calling listen().
        await _beginSession();
        _restarting = false;
        TLog.d(widget.tag, 'Session restarted (attempt $attempt, accumulated ${_accumulatedText.length} chars)');
        return;
      } catch (e) {
        TLog.w(widget.tag, 'Restart attempt $attempt failed', error: e);
        await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
      }
    }

    _restarting = false;
    _resultsGated = false;
    if (mounted && _holdActive) {
      TLog.e(widget.tag, 'All restart attempts failed — stopping');
      _holdActive = false;
      _setListening(false);
    }
  }

  Future<void> _stop() async {
    if (!_listening) return;
    _holdActive = false;

    // Snapshot the final text BEFORE gating, then gate to block stale
    // onResult callbacks that _speech.stop() may fire.
    final textBeforeStop = widget.controller.text.trim();
    _resultsGated = true;
    _accumulatedText = '';
    _restarting = false;

    try {
      await _speech.stop();
    } catch (e) {
      TLog.w(widget.tag, 'Stop speech error', error: e);
    }

    if (!mounted) return;

    // Restore the clean text in case a stale callback snuck through.
    if (widget.controller.text.trim() != textBeforeStop) {
      widget.controller.value = TextEditingValue(
        text: textBeforeStop,
        selection: TextSelection.collapsed(offset: textBeforeStop.length),
      );
    }

    TLog.i(
      widget.tag,
      'Hold-to-speak ended → "${textBeforeStop.length > 60 ? '${textBeforeStop.substring(0, 60)}…' : textBeforeStop}"',
    );
    _resultsGated = false;
    _setListening(false);
  }

  @override
  Widget build(BuildContext context) {
    final active = _listening;
    final color = active ? const Color(0xFFF87171) : AppColors.accent;
    final opacity = widget.disabled && !active ? 0.35 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, child) {
            final scale = active ? _pulseAnim.value : 1.0;
            return Transform.scale(
              scale: scale,
              child: child,
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
