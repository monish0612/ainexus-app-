import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../core/constants/app_constants.dart';
// io_stub keeps the web build compiling; the upload path never runs on web
// because parallel voice recording is only enabled when `!kIsWeb`.
import '../../core/platform/io_stub.dart';
import '../../core/services/telegram_logger.dart';

/// Client for the server-side speech-to-text gateway (`stt-gateway`).
///
/// The gateway wraps Groq Whisper Large v3 Turbo (+ an optional Gemini
/// Flash-Lite correction pass) behind `POST /v1/transcribe`. The app's
/// voice flow is:
///
///   1. `HoldToSpeakController.start(recordAudio: true)` — on-device STT
///      runs as usual AND a parallel 16 kHz mono AAC (m4a) clip is captured.
///   2. On release the on-device transcript is shown **instantly** (exactly
///      the pre-gateway behaviour, so nothing ever feels slower or broken).
///   3. The m4a is uploaded here in the background. If the gateway returns
///      a transcript AND the user hasn't touched the text since, the
///      corrected text silently replaces the on-device one.
///
/// Every failure mode (offline, timeout, 5xx, bad key) simply returns
/// `null` — the on-device transcript remains and the feature degrades
/// gracefully. Transient failures (timeouts, connection drops, 5xx) get
/// one automatic retry with a short backoff before giving up; permanent
/// errors (401 bad key, 413 too large, 422 bad format) never retry.
/// All failures are reported through [TLog] (→ Telegram). The temp audio
/// file is always deleted once the attempt(s) finish, success or not.
class SttGatewayService {
  SttGatewayService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              // Not ApiClient: different host, X-Client-Key instead of the
              // app JWT, and much tighter timeouts (fallback must be fast).
              connectTimeout: const Duration(seconds: 3),
              sendTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'X-Client-Key': AppConstants.sttClientKey},
            ));

  final Dio _dio;

  static const _tag = 'SttGateway';

  /// Total upload attempts for transient failures (1 initial + 1 retry).
  static const _maxAttempts = 2;

  /// Pause before the retry — long enough for a flaky connection to
  /// recover, short enough that the corrected-text swap still feels live.
  static const _retryDelay = Duration(milliseconds: 400);

  bool get isEnabled => AppConstants.sttGatewayEnabled;

  /// Upload the audio file at [path] and return the corrected transcript,
  /// or `null` on any failure. Deletes the file afterwards unless
  /// [deleteFile] is false.
  ///
  /// [vocabulary] carries app-specific terms (bank names, categories, …)
  /// the correction pass should prefer when resolving mis-heard words.
  Future<String?> transcribeFile(
    String path, {
    String? language,
    List<String> vocabulary = const [],
    bool deleteFile = true,
  }) async {
    if (!isEnabled) {
      if (deleteFile) _deleteQuietly(path);
      return null;
    }

    final sw = Stopwatch()..start();
    try {
      final file = File(path);
      if (!await file.exists()) {
        TLog.w(_tag, 'Audio file missing: $path');
        return null;
      }

      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        try {
          // FormData is single-use in Dio — build a fresh one per attempt.
          final form = FormData.fromMap({
            'file': await MultipartFile.fromFile(
              path,
              filename: path.split('/').last,
            ),
            if (language != null && language.isNotEmpty) 'language': language,
            if (vocabulary.isNotEmpty) 'vocabulary': vocabulary.join(','),
          });

          final response = await _dio.post<Map<String, dynamic>>(
            '${AppConstants.sttGatewayUrl}/v1/transcribe',
            data: form,
          );
          sw.stop();

          final data = response.data;
          final text = (data?['text'] as String?)?.trim();
          if (text == null || text.isEmpty) {
            TLog.w(_tag,
                'Gateway returned empty text (${sw.elapsedMilliseconds}ms)');
            return null;
          }

          TLog.i(
            _tag,
            'Transcribed in ${sw.elapsedMilliseconds}ms '
            '(attempt $attempt, stt=${data?['stt_latency_ms']}ms, '
            'correction=${data?['correction_latency_ms']}ms, '
            '${text.length} chars)',
          );
          return text;
        } on DioException catch (e) {
          final detail =
              '${e.type.name}${e.response != null ? ' HTTP ${e.response!.statusCode}' : ''}';

          if (_isTransient(e) && attempt < _maxAttempts) {
            // Timeout / connection drop / 5xx — worth one more shot.
            TLog.w(
              _tag,
              'Gateway attempt $attempt failed ($detail, '
              '${sw.elapsedMilliseconds}ms) — retrying once',
            );
            await Future<void>.delayed(_retryDelay);
            continue;
          }

          // Out of retries, or a permanent error (401 key, 413 size,
          // 422 format) where retrying can't help. Fall back silently to
          // the on-device transcript; ship the failure to Telegram.
          sw.stop();
          if (_isTransient(e)) {
            TLog.e(
              _tag,
              'Gateway unreachable after $_maxAttempts attempts '
              '($detail, ${sw.elapsedMilliseconds}ms) — '
              'keeping on-device transcript',
              error: e.message,
            );
          } else {
            TLog.e(
              _tag,
              'Gateway rejected request ($detail, '
              '${sw.elapsedMilliseconds}ms) — check key/config',
              error: e.response?.data?.toString() ?? e.message,
            );
          }
          return null;
        }
      }
      return null; // unreachable — loop always returns/continues
    } catch (e, st) {
      sw.stop();
      TLog.e(_tag, 'Unexpected gateway error', error: e, st: st);
      return null;
    } finally {
      if (deleteFile) _deleteQuietly(path);
    }
  }

  /// Timeouts, connection drops and 5xx responses are worth retrying;
  /// 4xx responses (bad key, oversize, bad format) are permanent.
  static bool _isTransient(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return code >= 500 || code == 429;
      default:
        return false;
    }
  }

  /// Silently swap the gateway-corrected transcript into [ctrl] — but only
  /// if the field still shows exactly the on-device transcript the user was
  /// left with. If they've already edited, sent, or re-dictated, we leave
  /// their text alone.
  ///
  /// Returns true when the swap happened.
  static bool applyCorrectedText(
    TextEditingController ctrl,
    String nativeText,
    String corrected,
  ) {
    if (corrected.trim().isEmpty) return false;
    if (ctrl.text != nativeText) return false;
    if (ctrl.text == corrected) return true; // already identical
    ctrl.value = TextEditingValue(
      text: corrected,
      selection: TextSelection.collapsed(offset: corrected.length),
    );
    return true;
  }

  void _deleteQuietly(String path) {
    unawaited(
      File(path).delete().catchError((Object _) => File(path)),
    );
  }
}
