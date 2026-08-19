import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/api_client.dart';
import '../../core/platform/io_stub.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/nas_file.dart';

/// Files kept on the home NAS instead of Google Drive.
///
/// Every call goes to this app's own API, which reaches the NAS over WireGuard
/// and speaks WebDAV to Nextcloud on the other side. The phone therefore needs
/// no NAS credential, no VPN profile and no knowledge of the home network — it
/// works identically on mobile data and is one less secret to lose with a
/// handset.
///
/// The read endpoints answer 200 even when the NAS is off, carrying the reason
/// in the body. That is deliberate on the server side and this class preserves
/// it: a switched-off NAS produces an explanatory empty state, not a thrown
/// exception the Files tab would have to render as a failure.
class NasFilesService {
  NasFilesService(this._api);

  final ApiClient _api;

  Dio get _dio => _api.dio;

  /// Whether the NAS can be used as a destination, and why not if it cannot.
  ///
  /// Never throws. A phone with no signal cannot tell the difference between
  /// "the server is down" and "the NAS is down", and guessing would be worse
  /// than admitting the state is unknown.
  Future<NasStorageStatus> status({CancelToken? cancelToken}) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.cloudNasStatus,
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data == null) return NasStorageStatus.unknown;
      return NasStorageStatus.fromJson(data);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return NasStorageStatus.unknown;
      TLog.w('Cloud/NAS', 'status check failed: ${e.message}');
      return NasStorageStatus.unknown;
    } catch (e) {
      TLog.w('Cloud/NAS', 'status check failed: $e');
      return NasStorageStatus.unknown;
    }
  }

  /// Contents of the `Cloud Storage` folder, newest first.
  ///
  /// Throws [NasUnavailable] when the folder could not be read, so the caller
  /// can show the reason. An *empty* folder is not an error and returns `[]`.
  Future<List<NasFile>> listFiles({CancelToken? cancelToken}) async {
    late final Response<Map<String, dynamic>> res;
    try {
      res = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.cloudNasFiles,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw NasUnavailable(_describeTransport(e));
    }

    final data = res.data;
    if (data == null) throw const NasUnavailable('The server sent an empty reply.');

    if (data['ok'] != true) {
      throw NasUnavailable(
        (data['message'] as String?) ?? 'The NAS could not be read.',
        reason: data['reason'] as String?,
      );
    }

    final raw = data['files'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(NasFile.fromJson)
        .where((f) => f.name.isNotEmpty)
        .toList(growable: false);
  }

  /// Stream a file up to the NAS.
  ///
  /// Retrying is switched off for this request rather than left to the shared
  /// interceptor. The multipart body is read from disk as it is sent, so by the
  /// time a failure is known there is nothing left to replay — and the failure
  /// this endpoint actually produces (503, "the NAS is switched off") will not
  /// have changed by the end of a backoff.
  Future<NasFile> uploadFile(
    File file, {
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'upload-${DateTime.now().millisecondsSinceEpoch}';
    final size = await file.length();

    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: name),
    });

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.cloudNasUpload,
        data: form,
        cancelToken: cancelToken,
        onSendProgress: onProgress,
        options: Options(
          extra: const {kNoRetry: true},
          // A large file over a home uplink is slow, not stalled. The default
          // 30s send timeout would make anything sizeable impossible.
          sendTimeout: const Duration(minutes: 30),
          receiveTimeout: const Duration(minutes: 30),
        ),
      );

      final f = res.data?['file'];
      final uploadedName =
          f is Map && f['name'] is String ? f['name'] as String : name;
      return NasFile(
        name: uploadedName,
        sizeBytes: size,
        modified: DateTime.now(),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw NasUnavailable(_describeResponse(e));
    }
  }

  /// Pull a file down to the device.
  ///
  /// Saved into the same `downloads` folder [GoogleDriveService] uses, so a
  /// file fetched from the NAS ends up exactly where the owner already looks
  /// for one fetched from Drive. Which destination it came from is a detail of
  /// where it was stored, not of where it now is.
  Future<File> downloadFile(
    String name, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    final downloadDir = Directory('${dir.path}${sep}downloads');
    if (!downloadDir.existsSync()) downloadDir.createSync(recursive: true);
    final savePath = '${downloadDir.path}$sep$name';

    try {
      await _dio.download(
        ApiEndpoints.cloudNasDownload(name),
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          extra: const {kNoRetry: true},
          receiveTimeout: const Duration(minutes: 30),
        ),
      );
      return File(savePath);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw NasUnavailable(_describeResponse(e));
    }
  }

  Future<void> deleteFile(String name, {CancelToken? cancelToken}) async {
    try {
      await _dio.delete<dynamic>(
        ApiEndpoints.cloudNasDelete(name),
        cancelToken: cancelToken,
        options: Options(extra: const {kNoRetry: true}),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw NasUnavailable(_describeResponse(e));
    }
  }

  /// The server already writes one sentence per failure and knows far more
  /// about which one applies than the phone does, so prefer its wording and
  /// only fall back to a generic line when there is no body to read.
  static String _describeResponse(DioException e) {
    final body = e.response?.data;
    if (body is Map && body['error'] is String) return body['error'] as String;
    return _describeTransport(e);
  }

  static String _describeTransport(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The connection timed out.';
      case DioExceptionType.connectionError:
        return 'No connection. Check your network.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) return 'Your session has expired.';
        return 'The server returned an error${code == null ? '' : ' ($code)'}.';
      default:
        return 'Could not reach the server.';
    }
  }
}

/// The NAS could not do what was asked, with a sentence explaining why.
class NasUnavailable implements Exception {
  const NasUnavailable(this.message, {this.reason});

  final String message;

  /// Machine-readable tag from the API (`not_configured`, `unreachable`, …)
  /// when there was one.
  final String? reason;

  bool get isNotConfigured => reason == 'not_configured';

  @override
  String toString() => message;
}

final nasFilesServiceProvider = Provider<NasFilesService>(
  (ref) => NasFilesService(ref.watch(apiClientProvider)),
);
