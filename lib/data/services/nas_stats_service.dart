import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../domain/entities/nas_stats.dart';
import '../../presentation/screens/cloud/stats/live/stat_metric.dart';

/// Thrown when the *phone* could not reach the API.
///
/// This is the distinction the whole feature rests on. A NAS that is switched
/// off comes back as a perfectly good HTTP 200 with `online: false`, and the
/// dashboard draws its dull zeroed state. Only a genuine transport failure —
/// no signal, VPS down, JWT rejected — throws, and that gets a different
/// message, because telling the owner "your NAS is off" when actually his phone
/// has no signal would send him to the wrong room to fix the wrong thing.
class NasStatsUnavailable implements Exception {
  const NasStatsUnavailable(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// True when re-authenticating might help, as opposed to waiting.
  bool get isAuthFailure => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'NasStatsUnavailable($message)';
}

/// Fetches the NAS + VPS snapshot from `GET /api/v1/cloud/stats`.
///
/// Deliberately thin. It does not retry, cache, or log: [ApiClient]'s retry
/// interceptor already covers transient failures with backoff and jitter, and
/// stacking a second retry layer under a 1-second poll would turn one slow
/// response into a queue of overlapping requests. Caching lives on the server
/// where one entry protects the NAS from every device at once. Telegram logging
/// lives in the controller, which is the only place that knows whether a
/// failure is new or the twentieth in a row.
class NasStatsService {
  NasStatsService(this._api);

  final ApiClient _api;

  Future<NasStatsEnvelope> fetch({CancelToken? cancelToken}) async {
    try {
      final res = await _api.get<dynamic>(
        ApiEndpoints.cloudStats,
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is! Map) {
        throw const NasStatsUnavailable('The server sent an unreadable reply.');
      }
      return NasStatsEnvelope.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw NasStatsUnavailable(
        _describe(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// On-demand 7D / 30D series. Not called by the poller.
  ///
  /// A 404 (older API) or an empty body is an empty envelope, never a crash:
  /// the enlarged view must still show Now from the local rolling window.
  Future<StatsHistoryEnvelope> fetchHistory(
    StatsHistoryRange range, {
    required StatMetric metric,
    CancelToken? cancelToken,
  }) async {
    if (range == StatsHistoryRange.now) {
      return StatsHistoryEnvelope.empty(range);
    }
    try {
      final res = await _api.get<dynamic>(
        ApiEndpoints.cloudStatsHistory(range.query),
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is! Map) return StatsHistoryEnvelope.empty(range);
      return StatsHistoryEnvelope.fromJson(
        Map<String, dynamic>.from(data),
        metric,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return StatsHistoryEnvelope.empty(range);
      }
      throw NasStatsUnavailable(
        _describe(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Phrased for the person holding the phone, not for a log file.
  static String _describe(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      return 'Your session has expired. Sign in again to see live stats.';
    }
    if (code != null && code >= 500) {
      return 'The stats server is having trouble. Trying again shortly.';
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The stats server took too long to answer.',
      DioExceptionType.connectionError =>
        'No connection to the stats server. Check your network.',
      DioExceptionType.cancel => 'Cancelled.',
      _ => 'Could not load live stats right now.',
    };
  }
}
