import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/platform/io_stub.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/services/telegram_logger.dart';

const _kFolderId = '1ybi-QMnDHDSFLXiRQjFacrJ7uLGmFX13';

// Service account credentials are injected at build time and NEVER stored in
// source control. Pass via:
//   flutter build apk --dart-define=GOOGLE_DRIVE_SA_JSON="$(cat sa.json)"
// On platforms where this is empty (e.g. web build with kIsWeb guards), the
// Drive feature is disabled at the call sites in `cloud_screen.dart`.
const _kServiceAccountJson = String.fromEnvironment(
  'GOOGLE_DRIVE_SA_JSON',
  defaultValue: '',
);

final googleDriveServiceProvider = Provider<GoogleDriveService>((ref) {
  return GoogleDriveService();
});

class DriveFileInfo {
  const DriveFileInfo({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.createdTime,
    required this.modifiedTime,
    required this.starred,
    this.thumbnailLink,
  });

  final String id;
  final String name;
  final String mimeType;
  final int size;
  final DateTime createdTime;
  final DateTime modifiedTime;
  final bool starred;
  final String? thumbnailLink;

  String get ext {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  bool get isImage =>
      mimeType.startsWith('image/') ||
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'}
          .contains(ext);
}

class DriveFileListResult {
  const DriveFileListResult({
    required this.files,
    this.nextPageToken,
  });
  final List<DriveFileInfo> files;
  final String? nextPageToken;
}

class DriveStorageQuota {
  const DriveStorageQuota({required this.usageBytes, required this.limitBytes});
  final int usageBytes;
  final int limitBytes;

  double get usedGb => usageBytes / (1024 * 1024 * 1024);
  double get totalGb => limitBytes / (1024 * 1024 * 1024);
  double get freeGb => totalGb - usedGb;
  double get fraction => limitBytes > 0 ? usageBytes / limitBytes : 0;
}

typedef DriveProgressCallback = void Function(int transferred, int total);

class GoogleDriveService {
  GoogleDriveService();

  http.Client? _authClient;
  drive.DriveApi? _driveApi;
  String? _accessToken;
  DateTime? _tokenExpiry;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(minutes: 60),
    sendTimeout: const Duration(minutes: 60),
  ));

  String get folderId => _kFolderId;

  Future<void> _ensureAuth({bool force = false}) async {
    if (!force &&
        _authClient != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return;
    }

    if (_kServiceAccountJson.isEmpty) {
      throw StateError(
        'Google Drive service account is not configured. '
        'Build with --dart-define=GOOGLE_DRIVE_SA_JSON=...',
      );
    }

    try {
      final credentials = auth.ServiceAccountCredentials.fromJson(
        json.decode(_kServiceAccountJson) as Map<String, dynamic>,
      );

      final httpClient = http.Client();
      final accessCreds =
          await auth.obtainAccessCredentialsViaServiceAccount(
        credentials,
        [drive.DriveApi.driveScope],
        httpClient,
      );

      _accessToken = accessCreds.accessToken.data;
      _tokenExpiry = accessCreds.accessToken.expiry;

      _authClient = auth.authenticatedClient(httpClient, accessCreds);
      _driveApi = drive.DriveApi(_authClient!);

      TLog.i('GDrive', 'Authenticated as service account'
          '${force ? ' (force refresh)' : ''}');
    } catch (e, st) {
      TLog.e('GDrive', 'Auth failed', error: e, st: st);
      rethrow;
    }
  }

  /// Authorization header value, guarding against a null/empty token so we
  /// never send a literal `Bearer null` (which fails with a confusing 401).
  String get _bearer {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Google Drive access token unavailable');
    }
    return 'Bearer $token';
  }

  Future<void> _refreshTokenIfNeeded() async {
    if (_tokenExpiry == null) return;
    if (DateTime.now()
        .isAfter(_tokenExpiry!.subtract(_tokenRefreshBuffer))) {
      TLog.d('GDrive', 'Token near expiry, refreshing');
      await _ensureAuth(force: true);
    }
  }

  static const _fileFields =
      'files(id,name,mimeType,size,createdTime,modifiedTime,starred,thumbnailLink),nextPageToken';

  Future<DriveFileListResult> listFiles({
    String? pageToken,
    int pageSize = 50,
    String? searchQuery,
  }) async {
    if (!PlatformCapabilities.canUseGoogleDrive) {
      return const DriveFileListResult(files: [], nextPageToken: null);
    }
    await _ensureAuth();
    try {
      var q = "'$_kFolderId' in parents and trashed = false";
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final escaped = searchQuery.replaceAll("'", "\\'");
        q += " and name contains '$escaped'";
      }

      final fileList = await _driveApi!.files.list(
        q: q,
        $fields: _fileFields,
        orderBy: 'modifiedTime desc',
        pageSize: pageSize,
        pageToken: pageToken,
      );

      final files = (fileList.files ?? []).map(_mapDriveFile).toList();
      return DriveFileListResult(
        files: files,
        nextPageToken: fileList.nextPageToken,
      );
    } catch (e) {
      TLog.e('GDrive', 'listFiles failed', error: e);
      rethrow;
    }
  }

  /// Full-text search across all files in the folder.
  Future<DriveFileListResult> searchFiles(String query) async {
    await _ensureAuth();
    try {
      final escaped = query.replaceAll("'", "\\'");
      final q =
          "'$_kFolderId' in parents and trashed = false and (name contains '$escaped' or fullText contains '$escaped')";

      final fileList = await _driveApi!.files.list(
        q: q,
        $fields: _fileFields,
        orderBy: 'modifiedTime desc',
        pageSize: 50,
      );

      return DriveFileListResult(
        files: (fileList.files ?? []).map(_mapDriveFile).toList(),
        nextPageToken: fileList.nextPageToken,
      );
    } catch (e) {
      TLog.e('GDrive', 'searchFiles failed', error: e);
      rethrow;
    }
  }

  DriveFileInfo _mapDriveFile(drive.File f) {
    return DriveFileInfo(
      id: f.id ?? '',
      name: f.name ?? 'Unnamed',
      mimeType: f.mimeType ?? 'application/octet-stream',
      size: int.tryParse(f.size ?? '0') ?? 0,
      createdTime: f.createdTime ?? DateTime.now(),
      modifiedTime: f.modifiedTime ?? DateTime.now(),
      starred: f.starred ?? false,
      thumbnailLink: f.thumbnailLink,
    );
  }

  Future<DriveStorageQuota> getStorageQuota() async {
    await _ensureAuth();
    try {
      final about = await _driveApi!.about.get(
        $fields: 'storageQuota',
      );
      final q = about.storageQuota;
      return DriveStorageQuota(
        usageBytes: int.tryParse(q?.usage ?? '0') ?? 0,
        limitBytes: int.tryParse(q?.limit ?? '16106127360') ?? 16106127360,
      );
    } catch (e) {
      TLog.w('GDrive', 'getStorageQuota failed', error: e);
      return const DriveStorageQuota(
        usageBytes: 0,
        limitBytes: 16106127360,
      );
    }
  }

  /// 10 GB maximum upload size per file or combined multi-file batch.
  static const maxUploadBytes = 10 * 1024 * 1024 * 1024;

  /// 8 MB chunks for efficient large file uploads (multiple of 256 KB).
  static const _chunkSize = 8 * 1024 * 1024;

  /// Files below this use simple (single-request) upload.
  static const _simpleThreshold = 5 * 1024 * 1024;

  /// Maximum retry attempts for downloads.
  static const _maxDownloadRetries = 10;

  /// Refresh token this long before expiry during long transfers.
  static const _tokenRefreshBuffer = Duration(minutes: 5);

  Future<String> _initResumableSession(
    String fileName,
    String mimeType,
    int fileSize, {
    CancelToken? cancelToken,
  }) async {
    await _ensureAuth();

    final metadataJson = json.encode({
      'name': fileName,
      'parents': [_kFolderId],
    });

    final resp = await _dio.post<void>(
      'https://www.googleapis.com/upload/drive/v3/files'
      '?uploadType=resumable&fields=id,name,mimeType,size,createdTime,modifiedTime,starred,thumbnailLink',
      data: metadataJson,
      cancelToken: cancelToken,
      options: Options(
        headers: {
          'Authorization': _bearer,
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Type': mimeType,
          'X-Upload-Content-Length': '$fileSize',
        },
        validateStatus: (s) => s != null && s < 400,
      ),
    );

    final location = resp.headers.value('location');
    if (location == null || location.isEmpty) {
      throw Exception('Resumable session missing Location header');
    }
    TLog.d('GDrive', 'Resumable session created for $fileName');
    return location;
  }

  /// Upload a file to Google Drive with robust retry, cancellation,
  /// and progress tracking. Supports files up to [maxUploadBytes] (10 GB).
  ///
  /// Progress is reported at byte level within each chunk for smooth ETA.
  Future<DriveFileInfo> uploadFile(
    File file, {
    DriveProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!PlatformCapabilities.canUseGoogleDrive) {
      throw UnsupportedError(
        'Google Drive integration is not available on the web build yet.',
      );
    }
    await _ensureAuth();

    final fileName = file.path.split(Platform.pathSeparator).last;
    final fileSize = await file.length();
    final mimeType = _guessMimeType(fileName);

    if (fileSize > maxUploadBytes) {
      final msg = 'File $fileName (${_fmtBytesLog(fileSize)}) exceeds '
          '${_fmtBytesLog(maxUploadBytes)} limit';
      TLog.e('GDrive', msg);
      throw Exception(msg);
    }

    final isResumable = fileSize >= _simpleThreshold;
    TLog.i(
      'GDrive',
      'Upload started: $fileName (${_fmtBytesLog(fileSize)}) '
      '[${isResumable ? 'resumable, ${(fileSize / _chunkSize).ceil()} chunks' : 'simple'}]',
    );

    if (!isResumable) {
      return _simpleUpload(file, fileName, fileSize);
    }

    final sw = Stopwatch()..start();

    try {
      final uploadUri = await _initResumableSession(
        fileName,
        mimeType,
        fileSize,
        cancelToken: cancelToken,
      );

      var offset = 0;
      Map<String, dynamic>? completedJson;
      final raf = await file.open(mode: FileMode.read);
      var lastMilestone = 0;
      var chunksUploaded = 0;
      var lastReportedBytes = 0;

      try {
        while (offset < fileSize) {
          if (cancelToken?.isCancelled == true) {
            throw DioException(
              requestOptions: RequestOptions(),
              type: DioExceptionType.cancel,
              error: 'Upload cancelled by user',
            );
          }

          if (chunksUploaded > 0 && chunksUploaded % 50 == 0) {
            await _refreshTokenIfNeeded();
          }

          final end = math.min(offset + _chunkSize, fileSize);
          final chunkLen = end - offset;

          await raf.setPosition(offset);
          final chunk = await raf.read(chunkLen);

          final chunkOffset = offset;
          final resp = await _uploadChunkWithRetry(
            uploadUri,
            chunk,
            offset,
            end - 1,
            fileSize,
            mimeType,
            cancelToken: cancelToken,
            onChunkSendProgress: (sent, _) {
              final totalSent = chunkOffset + sent;
              if (totalSent > lastReportedBytes) {
                lastReportedBytes = totalSent;
                onProgress?.call(totalSent, fileSize);
              }
            },
          );

          offset = end;
          chunksUploaded++;
          if (offset > lastReportedBytes) {
            lastReportedBytes = offset;
            onProgress?.call(offset, fileSize);
          }

          final pct = (offset * 100 / fileSize).floor();
          if (pct >= lastMilestone + 5) {
            lastMilestone = (pct ~/ 5) * 5;
            final elapsed = sw.elapsedMilliseconds;
            final speed = elapsed > 0 ? offset / elapsed * 1000 : 0;
            TLog.d(
              'GDrive',
              'Upload $fileName: $lastMilestone% '
              '(${_fmtBytesLog(offset)}/${_fmtBytesLog(fileSize)}, '
              '${_fmtBytesLog(speed.toInt())}/s)',
            );
          }

          if (resp.statusCode == 200 || resp.statusCode == 201) {
            completedJson = resp.data;
          }
        }
      } finally {
        await raf.close();
      }

      sw.stop();

      if (completedJson == null) {
        throw Exception('Upload finished but no metadata returned');
      }

      final avgSpeed = sw.elapsedMilliseconds > 0
          ? fileSize / sw.elapsedMilliseconds * 1000
          : 0;
      TLog.i(
        'GDrive',
        'Upload complete: ${completedJson['id']} '
        '($fileName, ${_fmtBytesLog(fileSize)}, ${sw.elapsed.inSeconds}s, '
        'avg ${_fmtBytesLog(avgSpeed.toInt())}/s)',
      );

      return DriveFileInfo(
        id: completedJson['id'] as String? ?? '',
        name: completedJson['name'] as String? ?? fileName,
        mimeType:
            completedJson['mimeType'] as String? ?? 'application/octet-stream',
        size: int.tryParse('${completedJson['size']}') ?? fileSize,
        createdTime: DateTime.tryParse(
                '${completedJson['createdTime']}') ??
            DateTime.now(),
        modifiedTime: DateTime.tryParse(
                '${completedJson['modifiedTime']}') ??
            DateTime.now(),
        starred: completedJson['starred'] as bool? ?? false,
        thumbnailLink: completedJson['thumbnailLink'] as String?,
      );
    } on DioException catch (e) {
      sw.stop();
      if (e.type == DioExceptionType.cancel) {
        TLog.w('GDrive', 'Upload cancelled: $fileName '
            '(after ${sw.elapsed.inSeconds}s)');
        rethrow;
      }
      TLog.e('GDrive', 'Upload failed: $fileName (${e.type}, '
          '${e.error?.runtimeType}, ${sw.elapsed.inSeconds}s elapsed)',
          error: e, st: e.stackTrace);
      rethrow;
    } catch (e, st) {
      sw.stop();
      TLog.e('GDrive', 'Upload failed: $fileName', error: e, st: st);
      rethrow;
    }
  }

  /// Simple upload for files under 5 MB, with retry.
  Future<DriveFileInfo> _simpleUpload(
    File file,
    String fileName,
    int fileSize,
  ) async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final fileMetadata = drive.File()
          ..name = fileName
          ..parents = [_kFolderId];

        final media = drive.Media(file.openRead(), fileSize);
        final created = await _driveApi!.files.create(
          fileMetadata,
          uploadMedia: media,
          $fields:
              'id,name,mimeType,size,createdTime,modifiedTime,starred,thumbnailLink',
        );

        TLog.i('GDrive', 'Simple upload complete: ${created.id} ($fileName)');
        return _mapDriveFile(created);
      } catch (e) {
        if (attempt < maxAttempts - 1) {
          final delay = Duration(seconds: math.pow(2, attempt).toInt());
          TLog.w('GDrive', 'Simple upload retry #${attempt + 1} for '
              '$fileName after ${delay.inSeconds}s');
          await Future<void>.delayed(delay);
          await _refreshTokenIfNeeded();
          continue;
        }
        TLog.e('GDrive', 'Simple upload failed after $maxAttempts attempts: '
            '$fileName', error: e);
        rethrow;
      }
    }
    throw Exception('Simple upload failed after max retries: $fileName');
  }

  /// Whether [e] is a network-level error that should be retried.
  /// Handles timeouts, connection errors, AND the critical case of
  /// [DioExceptionType.unknown] wrapping a [SocketException] / IO error
  /// (e.g. "Write failed — Software caused connection abort" from Doze mode).
  static bool _isRetryableNetworkError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        final err = e.error;
        if (err is SocketException) return true;
        if (err is HttpException) return true;
        final s = err.toString().toLowerCase();
        return s.contains('socket') ||
            s.contains('connection') ||
            s.contains('broken pipe') ||
            s.contains('reset by peer') ||
            s.contains('write failed') ||
            s.contains('software caused');
      default:
        return false;
    }
  }

  /// Upload a single chunk with exponential-backoff retry, jitter, and
  /// network-error resilience. Retries up to [maxRetries] times with a
  /// ceiling of 5 minutes between attempts to survive Android Doze.
  Future<Response<Map<String, dynamic>>> _uploadChunkWithRetry(
    String uploadUri,
    List<int> chunk,
    int rangeStart,
    int rangeEnd,
    int totalSize,
    String mimeType, {
    CancelToken? cancelToken,
    int maxRetries = 12,
    void Function(int, int)? onChunkSendProgress,
  }) async {
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final resp = await _dio.put<Map<String, dynamic>>(
          uploadUri,
          data: Stream<List<int>>.value(chunk),
          cancelToken: cancelToken,
          onSendProgress: onChunkSendProgress,
          options: Options(
            headers: {
              'Content-Length': '${chunk.length}',
              'Content-Range': 'bytes $rangeStart-$rangeEnd/$totalSize',
              'Content-Type': mimeType,
            },
            validateStatus: (s) =>
                s != null && (s == 200 || s == 201 || s == 308),
          ),
        );
        return resp;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;

        final code = e.response?.statusCode;
        final isServerError = code != null && code >= 500;
        final isRetryable = isServerError || _isRetryableNetworkError(e);

        if (isRetryable && attempt < maxRetries - 1) {
          final baseMs =
              math.min(1000 * math.pow(2, attempt).toInt(), 300000);
          final jitter =
              math.Random().nextInt((baseMs * 0.3).toInt().clamp(1, 90000));
          final delay = Duration(milliseconds: baseMs + jitter);
          TLog.w(
            'GDrive',
            'Chunk retry #${attempt + 1}/$maxRetries '
            '(bytes $rangeStart-$rangeEnd, ${e.type}, '
            '${e.error?.runtimeType}) '
            'waiting ${delay.inSeconds}s',
          );
          await Future<void>.delayed(delay);

          if (attempt >= 1) await _refreshTokenIfNeeded();
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Max retries exceeded for chunk upload');
  }

  String _guessMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const map = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'svg': 'image/svg+xml',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'zip': 'application/zip',
      'rar': 'application/x-rar-compressed',
      '7z': 'application/x-7z-compressed',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'json': 'application/json',
      'xml': 'application/xml',
      'html': 'text/html',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  /// Build an authenticated thumbnail URL for image previews.
  String? getThumbnailUrl(DriveFileInfo file, {int size = 220}) {
    if (file.thumbnailLink == null) return null;
    return '${file.thumbnailLink!.replaceAll(RegExp(r'=s\d+'), '')}=s$size';
  }

  /// Get auth headers for authenticated image requests.
  Map<String, String> get authHeaders => {
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  /// Download a file with automatic retry, exponential backoff, and
  /// cancellation support.
  Future<File> downloadFile(
    String fileId,
    String fileName, {
    DriveProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!PlatformCapabilities.canUseGoogleDrive) {
      throw UnsupportedError(
        'Google Drive integration is not available on the web build yet.',
      );
    }
    await _ensureAuth();

    TLog.i('GDrive', 'Download started: $fileName ($fileId)');
    final sw = Stopwatch()..start();

    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}${Platform.pathSeparator}downloads'
        '${Platform.pathSeparator}$fileName';

    final downloadDir =
        Directory('${dir.path}${Platform.pathSeparator}downloads');
    if (!downloadDir.existsSync()) {
      downloadDir.createSync(recursive: true);
    }

    for (var attempt = 0; attempt < _maxDownloadRetries; attempt++) {
      try {
        if (cancelToken?.isCancelled == true) {
          throw DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.cancel,
          );
        }

        if (attempt > 0) await _refreshTokenIfNeeded();

        await _dio.download(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
          savePath,
          options: Options(
            headers: {'Authorization': _bearer},
          ),
          onReceiveProgress: onProgress,
          cancelToken: cancelToken,
        );

        sw.stop();
        final savedFile = File(savePath);
        final size = await savedFile.length();
        TLog.i('GDrive', 'Download complete: $fileName '
            '(${_fmtBytesLog(size)}, ${sw.elapsed.inSeconds}s)');
        return savedFile;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          sw.stop();
          TLog.w('GDrive', 'Download cancelled: $fileName');
          rethrow;
        }

        final code = e.response?.statusCode;
        final isServerError = code != null && code >= 500;
        final isRetryable = isServerError || _isRetryableNetworkError(e);

        if (isRetryable && attempt < _maxDownloadRetries - 1) {
          final baseMs =
              math.min(1000 * math.pow(2, attempt).toInt(), 300000);
          final jitter =
              math.Random().nextInt((baseMs * 0.3).toInt().clamp(1, 90000));
          final delay = Duration(milliseconds: baseMs + jitter);
          TLog.w('GDrive', 'Download retry #${attempt + 1}/$_maxDownloadRetries '
              'for $fileName after ${delay.inSeconds}s '
              '(${e.type}, ${e.error?.runtimeType})');
          await Future<void>.delayed(delay);
          continue;
        }

        sw.stop();
        TLog.e(
          'GDrive',
          'Download failed after ${attempt + 1} attempts: $fileName',
          error: e,
          st: e.stackTrace,
        );
        rethrow;
      } catch (e, st) {
        sw.stop();
        TLog.e('GDrive', 'Download failed: $fileName', error: e, st: st);
        rethrow;
      }
    }

    throw Exception(
        'Download failed after $_maxDownloadRetries attempts: $fileName');
  }

  Future<void> deleteFile(String fileId) async {
    if (!PlatformCapabilities.canUseGoogleDrive) return;
    await _ensureAuth();
    try {
      await _driveApi!.files.delete(fileId);
      TLog.i('GDrive', 'Deleted file $fileId');
    } catch (e) {
      TLog.e('GDrive', 'Delete failed', error: e);
      rethrow;
    }
  }

  Future<void> toggleStar(String fileId, {required bool starred}) async {
    if (!PlatformCapabilities.canUseGoogleDrive) return;
    await _ensureAuth();
    try {
      await _driveApi!.files.update(
        drive.File()..starred = starred,
        fileId,
      );
    } catch (e) {
      TLog.e('GDrive', 'Toggle star failed', error: e);
      rethrow;
    }
  }

  static String _fmtBytesLog(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}
