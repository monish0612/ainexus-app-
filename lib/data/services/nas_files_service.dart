import 'dart:async';
import 'dart:math' as math;

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

  /// 32 GB per file. Bigger than that is almost certainly a mistaken whole-disk
  /// image, and the NAS would be the one to suffer it.
  static const maxUploadBytes = 32 * 1024 * 1024 * 1024;

  /// Matches the server. Advertised again by `/resumable/start` and preferred
  /// when the two ever differ, so a server-side change does not strand a phone.
  static const chunkSize = 8 * 1024 * 1024;

  /// Below this a single PUT is fewer round-trips and just as reliable.
  static const simpleThreshold = 5 * 1024 * 1024;

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
  /// Small files go as one multipart POST. Anything at or above 5 MB is sent
  /// in 8 MB chunks: a dropped packet then retries that slice instead of the
  /// whole film, and no single request is long enough for a proxy idle-timeout
  /// to kill it. Retrying is switched off on each HTTP call; the loop below
  /// retries a failed *chunk* while the bytes are still on disk.
  Future<NasFile> uploadFile(
    File file, {
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'upload-${DateTime.now().millisecondsSinceEpoch}';
    final size = await file.length();
    if (size > maxUploadBytes) {
      throw NasUnavailable(
        'That file is larger than NAS uploads allow.',
        reason: 'too_large',
      );
    }

    if (size < simpleThreshold) {
      return _simpleUpload(
        file,
        name: name,
        size: size,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    return _chunkedUpload(
      file,
      name: name,
      size: size,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<NasFile> _simpleUpload(
    File file, {
    required String name,
    required int size,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
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

  Future<NasFile> _chunkedUpload(
    File file, {
    required String name,
    required int size,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    String? uploadId;
    try {
      final started = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.cloudNasUploadResumableStart,
        data: {
          'name': name,
          'size': size,
          'mimeType': _guessMime(name),
        },
        cancelToken: cancelToken,
        options: Options(extra: const {kNoRetry: true}),
      );
      uploadId = started.data?['uploadId'] as String?;
      final advertised = (started.data?['chunkSize'] as num?)?.toInt();
      if (uploadId == null || uploadId.isEmpty) {
        throw const NasUnavailable('The server did not start the upload.');
      }
      final slice = (advertised != null && advertised > 0) ? advertised : chunkSize;

      final raf = await file.open(mode: FileMode.read);
      var offset = 0;
      var lastReported = 0;
      try {
        while (offset < size) {
          if (cancelToken?.isCancelled == true) {
            throw DioException(
              requestOptions: RequestOptions(),
              type: DioExceptionType.cancel,
              error: 'Upload cancelled by user',
            );
          }
          final end = math.min(offset + slice, size);
          await raf.setPosition(offset);
          final chunk = await raf.read(end - offset);
          final chunkOffset = offset;

          final res = await _putChunkWithRetry(
            uploadId: uploadId,
            chunk: chunk,
            start: offset,
            total: size,
            cancelToken: cancelToken,
            onSendProgress: (sent, _) {
              final totalSent = chunkOffset + sent;
              if (totalSent > lastReported) {
                lastReported = totalSent;
                onProgress?.call(totalSent, size);
              }
            },
          );

          offset = end;
          if (offset > lastReported) {
            lastReported = offset;
            onProgress?.call(offset, size);
          }

          final data = res.data;
          if (data != null && data['done'] == true) {
            final f = data['file'];
            final uploadedName =
                f is Map && f['name'] is String ? f['name'] as String : name;
            return NasFile(
              name: uploadedName,
              sizeBytes: size,
              modified: DateTime.now(),
            );
          }
        }
      } finally {
        await raf.close();
      }

      throw const NasUnavailable('The upload finished without a confirmation.');
    } on DioException catch (e) {
      if (uploadId != null) unawaited(_abort(uploadId));
      if (e.type == DioExceptionType.cancel) rethrow;
      throw NasUnavailable(_describeResponse(e));
    } catch (e) {
      if (uploadId != null) unawaited(_abort(uploadId));
      if (e is NasUnavailable) rethrow;
      throw NasUnavailable(e.toString());
    }
  }

  Future<Response<Map<String, dynamic>>> _putChunkWithRetry({
    required String uploadId,
    required List<int> chunk,
    required int start,
    required int total,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
  }) async {
    const maxAttempts = 5;
    DioException? last;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await _dio.put<Map<String, dynamic>>(
          ApiEndpoints.cloudNasUploadResumable(uploadId),
          data: chunk,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          options: Options(
            extra: const {kNoRetry: true},
            contentType: 'application/octet-stream',
            sendTimeout: const Duration(minutes: 5),
            receiveTimeout: const Duration(minutes: 5),
            headers: {
              Headers.contentLengthHeader: chunk.length,
              'Content-Type': 'application/octet-stream',
              'x-chunk-start': '$start',
              'x-chunk-total': '$total',
            },
          ),
        );
      } on DioException catch (e) {
        last = e;
        if (e.type == DioExceptionType.cancel) rethrow;
        if (e.response?.statusCode == 413 ||
            e.response?.statusCode == 400 ||
            e.response?.statusCode == 401 ||
            e.response?.statusCode == 403) {
          rethrow;
        }
        if (attempt == maxAttempts - 1) rethrow;
        final delay = Duration(seconds: 1 << attempt);
        TLog.w(
          'Cloud/NAS',
          'chunk at $start retry ${attempt + 1}/$maxAttempts after ${delay.inSeconds}s',
        );
        await Future<void>.delayed(delay);
      }
    }
    throw last ?? DioException(requestOptions: RequestOptions());
  }

  Future<void> _abort(String uploadId) async {
    try {
      await _dio.delete<dynamic>(
        ApiEndpoints.cloudNasUploadResumableAbort(uploadId),
        options: Options(extra: const {kNoRetry: true}),
      );
    } catch (_) {
      // Best-effort cleanup of the Nextcloud temp collection.
    }
  }

  static String _guessMime(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return 'application/octet-stream';
    return switch (name.substring(dot + 1).toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
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
