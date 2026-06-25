import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'telegram_logger.dart';

/// Lifecycle states emitted by [HoldToSpeakController].
enum HoldToSpeakStatus {
  /// Not active. Initial state and the state after [HoldToSpeakController.stop]
  /// or [HoldToSpeakController.cancel] completes.
  idle,

  /// Permission check / engine cold-start in progress.
  initializing,

  /// Engine is actively listening and emitting partial results.
  listening,

  /// Platform speech engine ended a session (Android's built-in silence
  /// detector or transient error). We are transparently spinning up another
  /// `listen()` call without losing accumulated text.
  restarting,

  /// User released the button. Waiting briefly for the final result from
  /// the engine before completing.
  stopping,

  /// Microphone / speech engine is not available (permission denied,
  /// platform unsupported, init failed). UI should disable voice.
  unsupported,

  /// Repeated permanent errors caused us to bail out. The transcript so far
  /// is still available. UI should surface [HoldToSpeakController.errorMessage].
  error,
}

/// Append [addition] to [existing] while removing any duplicated or
/// overlapping region, so auto-restarts and cumulative engine finals can
/// never double the transcript (the "every word repeated twice" bug seen when
/// holding the mic).
///
/// Android's recognizer produces three real-world shapes that all have to
/// collapse to a single clean transcript:
///   1. **Exact re-send** — a trailing/late final restates text we already
///      committed (`existing` already ends with / contains `addition`).
///   2. **Cumulative superset** — the engine re-emits everything so far plus a
///      few new words (`addition` starts with / contains `existing`).
///   3. **Boundary overlap** — the new chunk's first words repeat our last
///      words (e.g. "…pick up my" + "my son so…").
/// Anything that is genuinely new is appended with a single space.
///
/// Comparisons are case-insensitive; the original casing of the retained text
/// is preserved.
String mergeVoiceTranscript(String existing, String addition) {
  final a = existing.trim();
  final b = addition.trim();
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;

  final al = a.toLowerCase();
  final bl = b.toLowerCase();
  final aw = a.split(RegExp(r'\s+'));
  final bw = b.split(RegExp(r'\s+'));
  // Containment shortcuts are only safe for multi-word chunks — a single
  // common word ("the", "my") legitimately recurs and must not be dropped.
  final bSubstantial = bw.length >= 2;

  // (1) Addition contributes nothing new.
  if (al == bl || al.endsWith(bl)) return a;
  if (bSubstantial && al.contains(bl)) return a;
  // (2) Addition is a superset of what we already have.
  if (bl.startsWith(al)) return b;
  if (bSubstantial && bl.contains(al)) return b;

  // (3) Stitch on the largest word-level overlap between a's tail and b's
  //     head, dropping the repeated head words from b.
  final maxOverlap = min(aw.length, bw.length);
  var overlap = 0;
  for (var k = maxOverlap; k > 0; k--) {
    final aTail = aw.sublist(aw.length - k).join(' ').toLowerCase();
    final bHead = bw.sublist(0, k).join(' ').toLowerCase();
    if (aTail == bHead) {
      overlap = k;
      break;
    }
  }
  if (overlap == 0) return '$a $b';
  return <String>[...aw, ...bw.sublist(overlap)].join(' ');
}

/// Snapshot returned by [HoldToSpeakController.stop].
@immutable
class HoldToSpeakResult {
  const HoldToSpeakResult({
    required this.transcript,
    required this.duration,
    required this.restartCount,
    required this.wasAvailable,
    this.audioPath,
    this.errorMessage,
  });

  /// Final transcript. Joined across any auto-restarted sub-sessions.
  final String transcript;

  /// Total time the user held the mic.
  final Duration duration;

  /// Number of times the underlying engine auto-restarted during the hold.
  /// Useful for diagnostics: `>0` means Android's silence detector fired.
  final int restartCount;

  /// `false` if the device couldn't run speech-to-text at all (permission
  /// denied, web without HTTPS user-gesture, etc.). UI should fall back to
  /// keyboard input.
  final bool wasAvailable;

  /// Path to the parallel audio recording (only set when `recordAudio: true`
  /// is passed to [HoldToSpeakController.start]). Caller is responsible for
  /// deleting this file when done.
  final String? audioPath;

  /// Non-null when [HoldToSpeakController.status] reached
  /// [HoldToSpeakStatus.error] or [HoldToSpeakStatus.unsupported].
  final String? errorMessage;

  bool get isEmpty => transcript.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// Production-grade hold-to-speak controller.
///
/// Wraps `package:speech_to_text` with:
///
/// 1. **No lost words on Android silence-timeout** — the platform engine
///    aborts a session after 1-3 s of silence even with `pauseFor` set high.
///    We listen for `onStatus('done'/'notListening')` and seamlessly call
///    `listen()` again. The text accumulator carries across sub-sessions so
///    the user sees a single continuous transcript.
///
/// 2. **Final-result tracking** — only `finalResult: true` callbacks are
///    promoted into the committed buffer. Partial callbacks update a
///    transient buffer that's atomically committed when the engine ends a
///    session without delivering a final.
///
/// 3. **No redundant `stop()` during auto-restart** — we restart in ~80 ms
///    and skip `stop()` because the engine is already idle.
///
/// 4. **Single shared engine** — the underlying `SpeechToText` is initialized
///    exactly once across the whole app. Multiple controllers can coexist
///    but only one holds the mic at a time; starting a new controller
///    cancels the previous one.
///
/// 5. **Pre-warm at app launch** — call [warmUp] from `main()` so the first
///    user press doesn't pay a 1-2 s cold-start penalty.
///
/// 6. **Optional parallel raw-audio capture** — when `recordAudio: true` is
///    passed to [start], an AAC file is written via the `record` plugin in
///    parallel with the on-device recognizer. The path is returned in
///    [HoldToSpeakResult.audioPath], ready to be uploaded to a server-side
///    transcription endpoint for high-accuracy fallback.
///
/// 7. **Sound-level monitoring** — UI can read [soundLevelListenable]
///    (a [ValueListenable]) for live waveform/pulse feedback so the user
///    knows the mic is hot. Sound-level updates do NOT trigger the main
///    [ChangeNotifier] notifications — wire them up separately to avoid
///    rebuilding heavy widget trees 10× per second.
///
/// 8. **Resilient error handling** — transient errors (`error_no_match`,
///    `error_speech_timeout`) trigger a silent restart. Permanent errors
///    are retried with exponential backoff up to 5 times before surfacing.
///
/// 9. **Safe disposal** — `notifyListeners` is no-op after [dispose], so
///    async cancellation paths can never throw the "ChangeNotifier used
///    after disposed" assertion when the parent widget unmounts mid-hold.
///
/// Usage:
///
/// ```dart
/// final ctl = HoldToSpeakController(tag: 'Tutor.Coach');
/// ctl.addListener(() {
///   if (ctl.displayText != lastShown) controller.text = ctl.displayText;
/// });
///
/// // On hold-down:
/// await ctl.start();
///
/// // On hold-up:
/// final result = await ctl.stop();
/// controller.text = result.transcript;
/// ```
class HoldToSpeakController extends ChangeNotifier {
  HoldToSpeakController({this.tag = 'Voice'});

  /// Diagnostic tag prepended to all log lines.
  final String tag;

  // ── Shared engine ──────────────────────────────────────────────────────

  /// Single shared engine across the whole app — `SpeechToText.initialize()`
  /// is expensive (binds to the native recognition service) and only needs
  /// to be done once.
  static final stt.SpeechToText _shared = stt.SpeechToText();
  static bool _sharedInitDone = false;
  static bool _sharedInitOk = false;
  static Future<bool>? _sharedInitFuture;

  /// Whichever controller currently owns the mic. The static dispatchers
  /// route `onStatus`/`onError` to this owner so per-widget state doesn't
  /// leak between sessions. `null` when nobody is listening.
  static HoldToSpeakController? _activeOwner;

  // ── Tunables ───────────────────────────────────────────────────────────

  /// Gap between an auto-restart and the next `listen()` call. Has to be
  /// >0 because some Android OEMs queue the next listen if it arrives during
  /// the engine's teardown. 60 ms is a sweet spot — short enough to feel
  /// continuous, long enough to clear the previous session.
  static const Duration _restartGap = Duration(milliseconds: 60);

  /// Hard cap on how long [stop] waits for a trailing `finalResult`. The
  /// `speech_to_text` package guarantees status='done' fires AFTER the
  /// final has been notified, so in practice this fires very rarely — only
  /// as a defensive backstop if the engine wedges.
  static const Duration _stopFinalTimeout = Duration(milliseconds: 600);

  /// How long we wait after `onStatus('done')` for any trailing notification
  /// to settle before kicking off the next session. The `speech_to_text`
  /// package contract guarantees the final has been delivered before
  /// `done`, so this is mostly a paranoia margin.
  static const Duration _statusFinalTimeout = Duration(milliseconds: 100);

  /// Bail out after this many consecutive permanent errors.
  static const int _maxPermFailures = 5;

  // ── Reactive state (notifies listeners on change) ──────────────────────

  HoldToSpeakStatus _status = HoldToSpeakStatus.idle;
  String _committedText = '';
  String _partialText = '';
  String? _errorMessage;
  Duration _elapsed = Duration.zero;
  int _restartCount = 0;

  /// Sound level (0..1) is exposed as a separate ValueListenable so consumers
  /// who care about it (e.g. for a live waveform) can listen to *just* sound
  /// updates without rebuilding heavy widget trees on every audio frame.
  final ValueNotifier<double> _soundLevelNotifier = ValueNotifier<double>(0.0);
  ValueListenable<double> get soundLevelListenable => _soundLevelNotifier;

  HoldToSpeakStatus get status => _status;

  /// Words already promoted into the immutable transcript (from
  /// `finalResult: true` callbacks or committed partials at session end).
  String get committedText => _committedText;

  /// Latest partial result from the current sub-session. Replaced wholesale
  /// every callback; never appended to.
  String get partialText => _partialText;

  /// What UI should show while the user is holding — a continuous string
  /// of committed + current partial. We merge (rather than blindly join) so a
  /// cumulative partial that already restates the committed text — or one that
  /// overlaps it at the word boundary — never renders the same words twice.
  String get displayText {
    if (_partialText.isEmpty) return _committedText;
    if (_committedText.isEmpty) return _partialText;
    return mergeVoiceTranscript(_committedText, _partialText);
  }

  /// Current microphone input level, normalized to 0..1. Prefer listening to
  /// [soundLevelListenable] in widgets that re-render on audio changes —
  /// reading this getter inside the main listener will rebuild on every
  /// state notification regardless of whether the level changed.
  double get soundLevel => _soundLevelNotifier.value;

  String? get errorMessage => _errorMessage;
  Duration get elapsed => _elapsed;
  int get restartCount => _restartCount;

  bool get isListening =>
      _status == HoldToSpeakStatus.listening ||
      _status == HoldToSpeakStatus.restarting;

  bool get isAvailable => _sharedInitDone && _sharedInitOk;

  // ── Internal control flags ─────────────────────────────────────────────

  bool _holdActive = false;
  bool _stopRequested = false;
  bool _cancelRequested = false;
  bool _restartScheduled = false;
  bool _disposed = false;

  /// Set true the moment we issue the first successful `listen()` call for
  /// the current hold. Used to short-circuit the stop-timeout when a tap is
  /// released before the engine ever started — there's nothing to wait for.
  bool _engineEverStarted = false;

  /// Idempotency latch for [_finalizeStop] — multiple call sites can race
  /// (the stop timer, a final result, an engine error). Whoever wins runs
  /// the body; subsequent callers no-op.
  bool _finalizeRan = false;

  Timer? _elapsedTimer;
  Timer? _stopFinalizeTimer;
  Timer? _statusFinalizeTimer;
  DateTime? _startedAt;
  String? _localeId;
  int _consecutivePermFailures = 0;

  Completer<HoldToSpeakResult>? _stopCompleter;

  // ── Audio recording (opt-in) ───────────────────────────────────────────

  bool _shouldRecord = false;
  AudioRecorder? _recorder;
  String? _audioPath;
  bool _isRecording = false;

  // ── Static lifecycle ───────────────────────────────────────────────────

  /// Pre-warm the speech engine. Safe to call multiple times — only the
  /// first call does work. Run from `main()` after permission setup.
  ///
  /// Returns `true` if the engine is available on this device.
  static Future<bool> warmUp() async => _ensureInitialized();

  /// True iff the engine has been initialized and is operational.
  static bool get engineAvailable => _sharedInitDone && _sharedInitOk;

  static Future<bool> _ensureInitialized() async {
    if (_sharedInitDone) return _sharedInitOk;
    _sharedInitFuture ??= _doInit();
    return _sharedInitFuture!;
  }

  static Future<bool> _doInit() async {
    try {
      final ok = await _shared.initialize(
        onStatus: _dispatchStatus,
        onError: _dispatchError,
        debugLogging: false,
      );
      _sharedInitDone = true;
      _sharedInitOk = ok;
      TLog.i('HoldToSpeak', 'Engine ready (available=$ok)');
      return ok;
    } catch (e, st) {
      TLog.e('HoldToSpeak', 'Engine init failed', error: e, st: st);
      _sharedInitDone = true;
      _sharedInitOk = false;
      _sharedInitFuture = null;
      return false;
    }
  }

  static void _dispatchStatus(String status) {
    final owner = _activeOwner;
    if (owner != null && !owner._disposed) owner._onEngineStatus(status);
  }

  static void _dispatchError(dynamic error) {
    final owner = _activeOwner;
    if (owner != null && !owner._disposed) owner._onEngineError(error);
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// Begin listening. Returns `false` if the engine is unavailable on this
  /// device (permissions denied, plugin not supported, etc.) — UI should
  /// surface a "Voice not available" hint in that case.
  ///
  /// If another controller is currently holding the mic, it is cancelled
  /// first and ownership transfers to this controller. If THIS controller
  /// has an in-flight [stop] from a previous hold (e.g. the user released
  /// and then immediately re-pressed), the prior stop is finalized
  /// synchronously with whatever transcript was captured.
  Future<bool> start({
    String? localeId,
    bool recordAudio = false,
  }) async {
    if (_disposed) return false;
    if (_holdActive) return true;

    // Steal the mic from any other controller still holding it.
    if (_activeOwner != null && _activeOwner != this) {
      try {
        await _activeOwner!.cancel();
      } catch (e) {
        TLog.w(tag, 'Failed to cancel previous owner', error: e);
      }
    }

    // Force-finalize any prior stop that hadn't completed yet — the user
    // has clearly moved on. Without this, a re-press during the 600 ms
    // post-release window would corrupt the prior session's result by
    // resetting [_committedText] before its completer fires.
    if (_stopCompleter != null) {
      _drainPendingStop();
    }

    _activeOwner = this;

    // Reset all state BEFORE the first `_setStatus` notification, otherwise
    // listeners that rebuild on initializing would see the previous hold's
    // transcript briefly.
    _committedText = '';
    _partialText = '';
    _errorMessage = null;
    _elapsed = Duration.zero;
    _restartCount = 0;
    _consecutivePermFailures = 0;
    _holdActive = true;
    _stopRequested = false;
    _cancelRequested = false;
    _restartScheduled = false;
    _finalizeRan = false;
    _engineEverStarted = false;
    _localeId = localeId;
    _shouldRecord = recordAudio;
    _audioPath = null;
    _startedAt = DateTime.now();
    _soundLevelNotifier.value = 0.0;

    _setStatus(HoldToSpeakStatus.initializing);

    final ok = await _ensureInitialized();
    if (_disposed) return false;
    if (!ok || _cancelRequested) {
      _holdActive = false;
      if (_activeOwner == this) _activeOwner = null;
      _setStatus(HoldToSpeakStatus.unsupported);
      return false;
    }

    _startElapsedTimer();

    if (recordAudio) {
      // Fire and forget — recording failures are non-fatal; STT can still work.
      unawaited(_startAudioRecording());
    }

    final started = await _beginEngineSession();
    if (_disposed) return false;
    // Cleanup ANY time we're not actually listening — covers both the
    // "couldn't start" case AND the rare-but-possible race where stop()
    // finalized while we were still inside _ensureInitialized() (otherwise
    // the elapsed timer would run forever).
    if (!started || !_holdActive) {
      _stopElapsedTimer();
      await _stopAudioRecording(discard: true);
      if (_holdActive) {
        _holdActive = false;
        if (_activeOwner == this) _activeOwner = null;
      }
    }
    return started && _holdActive;
  }

  /// Stop listening and return the final transcript. Safe to call when
  /// already stopped (returns the existing snapshot). Waits up to
  /// [_stopFinalTimeout] for a trailing `finalResult` from the engine
  /// before completing. If the engine never reached `listening` state for
  /// this hold (super-fast tap), returns immediately with whatever was
  /// captured.
  Future<HoldToSpeakResult> stop() async {
    if (_disposed) return _buildResult();

    if (!_holdActive && _stopCompleter == null) {
      // Already stopped or never started.
      return _buildResult();
    }

    _holdActive = false;
    _stopRequested = true;
    _setStatus(HoldToSpeakStatus.stopping);

    // Capture the completer's future BEFORE any path that could call
    // [_finalizeStop] (which nulls `_stopCompleter`). Without this, the
    // short-circuit branch below would null-deref.
    final completer =
        _stopCompleter ??= Completer<HoldToSpeakResult>();
    final future = completer.future;

    // If the engine never even reached `listening` (e.g. user tapped &
    // released within ~100 ms of pressing), there's nothing to wait for —
    // finalize immediately so the consumer's await returns instantly.
    if (!_engineEverStarted) {
      try {
        await _shared.stop();
      } catch (_) {}
      _finalizeStop();
      return future;
    }

    // Best-effort tell the engine to stop. Some Android OEMs error here if
    // the engine had already self-stopped — we ignore.
    try {
      await _shared.stop();
    } catch (e) {
      TLog.d(tag, 'Engine stop returned: $e');
    }

    _stopFinalizeTimer?.cancel();
    _stopFinalizeTimer = Timer(_stopFinalTimeout, () {
      if (!_finalizeRan) _finalizeStop();
    });

    return future;
  }

  /// Discard the current session without returning a transcript. Use when
  /// the user navigates away, switches tabs, or the parent widget is
  /// unmounted.
  ///
  /// Safe to call after [dispose] — the disposed-listener guard prevents
  /// any "ChangeNotifier used after disposed" assertion from firing on
  /// the trailing status notification.
  Future<void> cancel() async {
    if (!_holdActive &&
        _status == HoldToSpeakStatus.idle &&
        _stopCompleter == null &&
        _activeOwner != this) {
      return;
    }

    _cancelRequested = true;
    _holdActive = false;
    _stopRequested = true;
    _stopFinalizeTimer?.cancel();
    _statusFinalizeTimer?.cancel();
    _stopElapsedTimer();

    if (_activeOwner == this) {
      try {
        await _shared.cancel();
      } catch (e) {
        TLog.d(tag, 'Engine cancel returned: $e');
      }
    }

    await _stopAudioRecording(discard: true);

    final completer = _stopCompleter;
    _stopCompleter = null;
    _finalizeRan = true;

    if (_activeOwner == this) _activeOwner = null;
    _setStatus(HoldToSpeakStatus.idle);

    if (completer != null && !completer.isCompleted) {
      completer.complete(_buildResult());
    }
  }

  // ── Engine session lifecycle ───────────────────────────────────────────

  Future<bool> _beginEngineSession() async {
    if (_disposed) return false;
    if (!_holdActive || _stopRequested) return false;
    _restartScheduled = false;

    try {
      // listenFor and pauseFor are set very high — Android's *internal*
      // silence detector still fires after 1-3 s, but we transparently
      // restart from `_onEngineStatus`. Setting them low here would just
      // give us a second source of truncations.
      await _shared.listen(
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevel,
        listenFor: const Duration(minutes: 30),
        pauseFor: const Duration(minutes: 30),
        localeId: _localeId,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: true,
          enableHapticFeedback: false,
        ),
      );
      _engineEverStarted = true;
      _setStatus(HoldToSpeakStatus.listening);
      return true;
    } catch (e, st) {
      TLog.w(tag, 'listen() threw — will retry', error: e, st: st);
      _consecutivePermFailures++;
      if (_consecutivePermFailures >= _maxPermFailures) {
        _errorMessage = 'Voice engine error: $e';
        _setStatus(HoldToSpeakStatus.error);
        _holdActive = false;
        if (_activeOwner == this) _activeOwner = null;
        return false;
      }
      Future<void>.delayed(_backoff(_consecutivePermFailures), () {
        if (!_disposed && _holdActive && !_stopRequested) {
          unawaited(_beginEngineSession());
        }
      });
      // Caller treats this as "still holding"; we'll retry.
      return true;
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    // Suppress late events that arrive after we've already finalized this
    // hold (e.g. a stray trailing final the engine emits after `stop()`
    // returned to the consumer). Without this guard the listener could
    // write a "longer" transcript into the target [TextEditingController]
    // *after* the consumer already wrote the final one, causing flicker.
    if (_disposed || _cancelRequested || _finalizeRan) return;

    final words = result.recognizedWords;
    final isFinal = result.finalResult;

    if (isFinal) {
      // Promote into the immutable buffer. Final's recognizedWords contains
      // the full text for the session; the partial is consumed.
      _commitFinalText(words);
      _partialText = '';
      _consecutivePermFailures = 0;
    } else {
      _partialText = words;
    }
    notifyListeners();

    if (isFinal && _stopRequested) {
      _stopFinalizeTimer?.cancel();
      _finalizeStop();
    } else if (isFinal && _restartScheduled) {
      // Final arrived right when we were about to restart — proceed now
      // since we already have the words; saves the 100 ms wait.
      _statusFinalizeTimer?.cancel();
      _doRestart();
    }
  }

  void _commitFinalText(String words) {
    final clean = words.trim();
    if (clean.isEmpty) return;
    _committedText = mergeVoiceTranscript(_committedText, clean);
  }

  void _onSoundLevel(double level) {
    if (_disposed) return;
    // Android delivers values roughly in 0–10 (dB-ish); iOS delivers
    // dBFS-ish negative values. We approximate both into a 0..1 range for
    // UI use, with a small dead-zone so we don't notify on every tiny
    // jitter.
    double normalized;
    if (level < 0) {
      normalized = ((level + 60) / 60).clamp(0.0, 1.0);
    } else {
      normalized = (level / 10.0).clamp(0.0, 1.0);
    }
    if ((normalized - _soundLevelNotifier.value).abs() < 0.02) return;
    // ValueNotifier.value setter notifies its OWN listeners — this does NOT
    // trigger our main `notifyListeners`, so widgets that care only about
    // text/state won't rebuild on audio frames.
    _soundLevelNotifier.value = normalized;
  }

  void _onEngineStatus(String s) {
    if (_disposed || _cancelRequested || _finalizeRan) return;

    if (s == 'done' || s == 'notListening') {
      if (_stopRequested) {
        // User-requested stop — give the engine a tiny window to deliver
        // the trailing final, then finalize.
        _stopFinalizeTimer?.cancel();
        _stopFinalizeTimer = Timer(_statusFinalTimeout, () {
          if (!_finalizeRan) _finalizeStop();
        });
      } else if (_holdActive) {
        // Android's silence timeout fired or engine self-ended — we have
        // to restart transparently.
        _scheduleRestartAfterStatusDone();
      }
    } else if (s == 'listening') {
      _consecutivePermFailures = 0;
      _setStatus(HoldToSpeakStatus.listening);
    }
  }

  void _onEngineError(dynamic error) {
    if (_disposed || _cancelRequested || _finalizeRan) return;

    final msg = (error?.errorMsg as String?) ?? error.toString();
    final permanent = (error?.permanent as bool?) ?? false;

    final transient = msg.contains('timeout') ||
        msg.contains('no_match') ||
        msg.contains('no-match') ||
        msg.contains('no_speech') ||
        msg.contains('busy');

    TLog.d(
      tag,
      'Engine error: $msg permanent=$permanent transient=$transient',
    );

    if (transient && _holdActive && !_stopRequested) {
      _scheduleRestartAfterStatusDone();
      return;
    }

    if (permanent) {
      _consecutivePermFailures++;
      if (_stopRequested ||
          _consecutivePermFailures >= _maxPermFailures) {
        _errorMessage = 'Voice error: $msg';
        if (_stopCompleter != null && !_finalizeRan) {
          _finalizeStop();
        } else if (_holdActive) {
          _setStatus(HoldToSpeakStatus.error);
          _holdActive = false;
          if (_activeOwner == this) _activeOwner = null;
        }
      } else if (_holdActive) {
        _scheduleRestartAfterStatusDone();
      }
    }
  }

  /// Wait briefly for a trailing final result, then kick off a fresh
  /// `listen()` call. Idempotent — multiple calls coalesce.
  void _scheduleRestartAfterStatusDone() {
    if (_disposed || _restartScheduled || !_holdActive || _stopRequested) {
      return;
    }
    _restartScheduled = true;
    _setStatus(HoldToSpeakStatus.restarting);

    _statusFinalizeTimer?.cancel();
    _statusFinalizeTimer = Timer(_statusFinalTimeout, _doRestart);
  }

  void _doRestart() {
    _statusFinalizeTimer?.cancel();
    if (_disposed || !_restartScheduled || !_holdActive || _stopRequested) {
      _restartScheduled = false;
      return;
    }

    // If the engine ended without delivering a final, promote whatever
    // partial we last saw — we do NOT want to lose those words across
    // the restart boundary.
    if (_partialText.trim().isNotEmpty) {
      _commitFinalText(_partialText);
      _partialText = '';
      notifyListeners();
    }

    _restartCount++;
    _restartScheduled = false;

    Future<void>.delayed(_restartGap, () {
      if (!_disposed && _holdActive && !_stopRequested) {
        unawaited(_beginEngineSession());
      }
    });
  }

  Duration _backoff(int attempt) {
    final ms = min(2000, 100 * (1 << (attempt - 1)));
    return Duration(milliseconds: ms);
  }

  // ── Stop finalization ──────────────────────────────────────────────────

  /// Force-completes a prior `stop()` that hasn't yet resolved (e.g. user
  /// re-pressed the mic before the 600 ms stop-finalize timer fired). The
  /// pending completer is satisfied with whatever transcript we have so
  /// far so the prior caller's `await stop()` returns immediately.
  void _drainPendingStop() {
    _stopFinalizeTimer?.cancel();
    _statusFinalizeTimer?.cancel();
    _stopElapsedTimer();

    if (_partialText.trim().isNotEmpty) {
      _commitFinalText(_partialText);
      _partialText = '';
    }

    final completer = _stopCompleter;
    _stopCompleter = null;
    _finalizeRan = true;

    // Audio recording for the prior session: stop synchronously-ish; we
    // don't wait for the file to flush because the new session is starting.
    unawaited(_stopAudioRecording());

    if (completer != null && !completer.isCompleted) {
      completer.complete(_buildResult());
    }
  }

  void _finalizeStop() {
    if (_finalizeRan) return;
    _finalizeRan = true;

    _stopFinalizeTimer?.cancel();
    _statusFinalizeTimer?.cancel();
    _stopElapsedTimer();

    // If a final never arrived, the latest partial IS the answer.
    if (_partialText.trim().isNotEmpty) {
      _commitFinalText(_partialText);
      _partialText = '';
    }

    final completer = _stopCompleter;
    _stopCompleter = null;
    _holdActive = false;
    _stopRequested = false;

    // Stop audio capture — we want the file flushed before returning.
    unawaited(_stopAudioRecording().then((_) {
      if (_disposed) return;
      if (_activeOwner == this) _activeOwner = null;
      _setStatus(HoldToSpeakStatus.idle);
      if (completer != null && !completer.isCompleted) {
        final result = _buildResult();
        TLog.i(
          tag,
          'Hold ended — ${result.duration.inMilliseconds}ms, '
          '${result.transcript.length} chars, '
          '${result.restartCount} restarts',
        );
        completer.complete(result);
      }
    }));
  }

  HoldToSpeakResult _buildResult() {
    return HoldToSpeakResult(
      transcript: _committedText.trim(),
      duration: _elapsed,
      restartCount: _restartCount,
      wasAvailable: _sharedInitOk,
      audioPath: _audioPath,
      errorMessage: _errorMessage,
    );
  }

  // ── Audio recording (optional) ─────────────────────────────────────────

  Future<void> _startAudioRecording() async {
    if (!_shouldRecord || _disposed) return;
    try {
      _recorder = AudioRecorder();
      final hasPerm = await _recorder!.hasPermission();
      if (!hasPerm) {
        TLog.w(tag, 'Audio recording: permission denied');
        _shouldRecord = false;
        _recorder = null;
        return;
      }
      // POSIX-style separator works on every platform we ship to (Android,
      // iOS, web, desktop). `Platform.pathSeparator` would throw on web.
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/h2s_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );
      _audioPath = path;
      _isRecording = true;
      TLog.d(tag, 'Audio recording started → $path');
    } catch (e, st) {
      TLog.w(tag, 'Audio recording failed to start', error: e, st: st);
      _shouldRecord = false;
      _recorder = null;
    }
  }

  Future<void> _stopAudioRecording({bool discard = false}) async {
    if (!_isRecording || _recorder == null) return;
    _isRecording = false;
    try {
      await _recorder!.stop();
    } catch (e) {
      TLog.w(tag, 'Audio recording stop error', error: e);
    }
    try {
      await _recorder!.dispose();
    } catch (_) {}
    _recorder = null;

    if (discard && _audioPath != null) {
      try {
        await File(_audioPath!).delete();
      } catch (_) {}
      _audioPath = null;
    }
  }

  // ── Elapsed timer ──────────────────────────────────────────────────────
  //
  // We update [_elapsed] internally for diagnostics in [_buildResult] but
  // do NOT call `notifyListeners()` from the tick — that would cause every
  // consumer to rebuild 4× per second for the entire hold even when no
  // visible state has changed. UIs that need a live counter should listen
  // to a separate ticker.

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_startedAt == null) return;
      _elapsed = DateTime.now().difference(_startedAt!);
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (_startedAt != null) {
      _elapsed = DateTime.now().difference(_startedAt!);
    }
  }

  // ── Status helper ──────────────────────────────────────────────────────

  void _setStatus(HoldToSpeakStatus next) {
    if (_disposed || _status == next) return;
    _status = next;
    notifyListeners();
  }

  // ── Disposal ───────────────────────────────────────────────────────────
  //
  // We override [notifyListeners] to no-op once disposed — the async
  // cancel/finalize paths can race with widget teardown and would
  // otherwise throw the "ChangeNotifier used after being disposed"
  // assertion in debug builds.

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_holdActive || _stopCompleter != null || _activeOwner == this) {
      // Fire-and-forget cancel; everything checks `_disposed` before
      // touching state so it's safe to let it run after super.dispose().
      // Synchronously satisfy any pending stop completer first to avoid
      // hung awaiters in the consumer.
      final completer = _stopCompleter;
      _stopCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete(_buildResult());
      }
      unawaited(cancel());
    }
    _elapsedTimer?.cancel();
    _stopFinalizeTimer?.cancel();
    _statusFinalizeTimer?.cancel();
    _soundLevelNotifier.dispose();
    super.dispose();
  }
}
