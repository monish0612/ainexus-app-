import 'package:dio/dio.dart';

/// Structured wrapper around the rich error envelope the backend
/// emits for AI calls (rephrase, coach, define, news summarise,
/// smart-parse, …). The envelope shape (see `backend/api/src/index.js`
/// global error handler):
///
/// ```json
/// {
///   "error": {
///     "message": "Gemini model \"gemini-3.1-flash-lite\" not found …",
///     "code": "MODEL_NOT_FOUND",
///     "provider": "gemini",          // optional
///     "model": "gemini-3.1-flash-lite" // optional
///   }
/// }
/// ```
///
/// Why this lives in its own file
/// ──────────────────────────────
/// Before this class, every AI call site had its own ad-hoc
/// `catch (e) { _showMessage('Rephrase failed …'); }` block. That
/// swallows the real reason — when the user mistypes a model name
/// in Settings, they end up staring at a generic "failed" toast
/// instead of an actionable "Open Settings → Gemini Lite model and
/// pick one that exists" message. Centralising parsing here means
/// every screen surfaces the same diagnostic copy with zero
/// duplication.
///
/// The class is intentionally `final` and immutable — instances are
/// cheap throw-aways constructed inside a `catch` block.
class AiError {
  const AiError({
    required this.userMessage,
    required this.code,
    this.provider,
    this.model,
    this.status,
    this.cause,
  });

  /// Human-readable message safe to show in a toast / banner.
  /// Always populated, never empty.
  final String userMessage;

  /// Backend-assigned machine-readable code (e.g. `MODEL_NOT_FOUND`,
  /// `RATE_LIMIT`, `BLOCKED`, `TIMEOUT`, `NETWORK`, `INTERNAL`).
  /// Useful for branching UI behaviour (e.g. open Settings on
  /// MODEL_NOT_FOUND). Always populated; falls back to
  /// `'UNKNOWN'` if the backend didn't send one.
  final String code;

  /// `'gemini'`, `'xgrok'`, or `null` if the backend didn't tag it.
  final String? provider;

  /// The model id the backend was trying to use when it failed.
  /// Surfacing this in toasts makes "which model is broken" obvious
  /// without the user having to open logs.
  final String? model;

  /// HTTP status the backend returned (404, 429, 503, 504, …).
  /// `null` when the failure happened before getting any response.
  final int? status;

  /// Original [DioException] (or other) — kept around for telemetry /
  /// rethrow. Never inspected by toast code.
  final Object? cause;

  /// True when the user can almost certainly fix the failure by
  /// changing something in Settings (e.g. picking a different model
  /// id). Used by toasts to add an "Open Settings" action.
  bool get isSettingsActionable =>
      code == 'MODEL_NOT_FOUND' ||
      code == 'INVALID_MODEL' ||
      code == 'CONFIG';

  /// True when retrying without any user action is sensible
  /// (transient: rate limit, server error, timeout, network blip).
  bool get isRetryable =>
      code == 'RATE_LIMIT' ||
      code == 'SERVER' ||
      code == 'TIMEOUT' ||
      code == 'NETWORK' ||
      (status != null && status! >= 500);

  /// Short, action-oriented toast copy. Hides the technical jargon
  /// behind a one-line explanation of what the user should do next.
  /// Falls back to [userMessage] when no specific guidance applies.
  String get toastMessage {
    switch (code) {
      case 'MODEL_NOT_FOUND':
      case 'INVALID_MODEL':
        final m = model;
        return m != null && m.isNotEmpty
            ? 'Model "$m" not available. Open Settings → Gemini Lite model and pick a different one.'
            : 'The configured model isn\'t available. Update it in Settings.';
      case 'RATE_LIMIT':
        return 'Hitting AI rate limit. Try again in a few seconds.';
      case 'BLOCKED':
        return 'AI safety filter blocked this request.';
      case 'TIMEOUT':
        return 'AI took too long to respond. Check your connection and retry.';
      case 'NETWORK':
        return 'Network error reaching the AI service. Check your connection.';
      case 'CONFIG':
        return 'Server isn\'t configured for Gemini yet. Contact support.';
      case 'EMPTY':
        return 'AI returned an empty response. Retry, or pick a different model in Settings.';
      case 'SERVER':
        return 'AI service is having issues. Please retry in a moment.';
      default:
        return userMessage;
    }
  }

  // ── Construction helpers ─────────────────────────────────────

  /// Parse a [DioException] (the only path AI errors take in this
  /// app) into an [AiError]. Falls back to a generic envelope when
  /// the response body isn't the expected shape — never throws.
  factory AiError.fromDio(DioException e, {String? fallbackMessage}) {
    final status = e.response?.statusCode;
    final body = e.response?.data;

    String? message;
    String? code;
    String? provider;
    String? model;

    // The structured envelope is always under `error`. Either a
    // string (legacy) or an object (new). Be defensive about both.
    final errField = (body is Map) ? body['error'] : null;
    if (errField is Map) {
      final m = (errField['message'] ?? errField['msg'])?.toString().trim();
      if (m != null && m.isNotEmpty) message = m;
      final c = errField['code']?.toString().trim();
      if (c != null && c.isNotEmpty) code = c;
      final p = errField['provider']?.toString().trim();
      if (p != null && p.isNotEmpty) provider = p;
      final mod = errField['model']?.toString().trim();
      if (mod != null && mod.isNotEmpty) model = mod;
    } else if (errField is String && errField.trim().isNotEmpty) {
      message = errField.trim();
    }

    // Fall back to the DioException's own descriptors when the body
    // didn't have a useful envelope (timeouts, connection refused,
    // socket hang-ups all land here).
    if (message == null || message.isEmpty) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          message = 'Request timed out';
          code ??= 'TIMEOUT';
          break;
        case DioExceptionType.connectionError:
          message = 'Network error — check your connection';
          code ??= 'NETWORK';
          break;
        case DioExceptionType.cancel:
          message = 'Request cancelled';
          code ??= 'CANCELLED';
          break;
        case DioExceptionType.badResponse:
          message = 'Server returned ${status ?? 'an error'}';
          code ??= status != null && status >= 500 ? 'SERVER' : 'API';
          break;
        case DioExceptionType.badCertificate:
          message = 'TLS certificate error';
          code ??= 'NETWORK';
          break;
        case DioExceptionType.unknown:
          message = e.message ?? fallbackMessage ?? 'Unknown network error';
          code ??= 'UNKNOWN';
          break;
      }
    }

    // At this point `message` is provably non-null (the switch
    // assigns it in every branch and the body-parse branch above
    // only ran when it had a non-empty value), but it could still
    // be empty — fall back to the caller-supplied default in that
    // case so the toast layer never shows an empty string.
    final resolved = message.isNotEmpty
        ? message
        : (fallbackMessage ?? 'Something went wrong');

    // Express `{ error: "Too many requests..." }` is a string, not the
    // Gemini envelope. HTTP 429 still means RATE_LIMIT so the toast and
    // logs stay short instead of dumping DioException.
    var resolvedCode = code;
    if (status == 429 &&
        (resolvedCode == null ||
            resolvedCode == 'UNKNOWN' ||
            resolvedCode == 'API')) {
      resolvedCode = 'RATE_LIMIT';
    }

    return AiError(
      userMessage: resolved,
      code: resolvedCode ?? 'UNKNOWN',
      provider: provider,
      model: model,
      status: status,
      cause: e,
    );
  }

  /// Generic catch-all when the failure isn't a [DioException]
  /// (e.g. local parsing errors, `StateError` from an empty
  /// response). Avoid losing the cause.
  factory AiError.fromAny(Object e, {String? fallbackMessage}) {
    if (e is DioException) return AiError.fromDio(e, fallbackMessage: fallbackMessage);
    return AiError(
      userMessage: fallbackMessage ?? e.toString(),
      code: 'UNKNOWN',
      cause: e,
    );
  }

  @override
  String toString() =>
      'AiError(code=$code, status=$status, model=$model, '
      'provider=$provider, message="$userMessage")';
}
