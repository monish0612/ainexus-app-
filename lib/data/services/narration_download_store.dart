import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/services/telegram_logger.dart';
import 'narration_api.dart';
import 'narration_download.dart';

/// Phone-side opus cache. Play prefers these files; wipe on read/delete.
class NarrationDownloadStore extends ChangeNotifier {
  NarrationDownloadStore._();
  static final NarrationDownloadStore instance = NarrationDownloadStore._();

  static const _kIndexKey = 'narration.downloaded_ids';

  @visibleForTesting
  static Directory? debugRootOverride;

  @visibleForTesting
  static Future<({int status, List<int> body})> Function(
    String url,
    Map<String, String> headers,
    int resumeFrom,
  )? debugGetBytes;

  Directory? _root;
  SharedPreferences? _prefs;
  final Set<String> _ready = <String>{};
  final Map<String, NarrationDownloadProgress> _progress =
      <String, NarrationDownloadProgress>{};
  final Map<String, Future<void>> _inflight = <String, Future<void>>{};
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  final Map<String, int> _epochs = <String, int>{};

  Future<void> hydrate({SharedPreferences? prefs}) async {
    if (!PlatformCapabilities.canUseDartIoFiles) return;
    _prefs = prefs ?? await SharedPreferences.getInstance();
    try {
      _root = debugRootOverride ??
          Directory(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'narration_audio',
            ),
          );
      if (!await _root!.exists()) {
        await _root!.create(recursive: true);
      }
    } catch (e) {
      TLog.w('NarrationDL', 'hydrate dir failed: $e');
      return;
    }
    final stored = _prefs?.getStringList(_kIndexKey) ?? const <String>[];
    _ready
      ..clear()
      ..addAll(stored);
    final stale = <String>[];
    for (final id in _ready.toList()) {
      if (!await _fileLooksReady(id)) {
        stale.add(id);
      }
    }
    if (stale.isNotEmpty) {
      for (final id in stale) {
        _ready.remove(id);
        await _deleteFiles(id);
      }
      await _persistIndex();
    }
    notifyListeners();
    TLog.i('NarrationDL', 'offline cache n=${_ready.length}');
  }

  bool isReady(String articleId) => _ready.contains(articleId);

  NarrationDownloadProgress progressOf(String articleId) {
    if (_ready.contains(articleId)) {
      return const NarrationDownloadProgress.ready();
    }
    return _progress[articleId] ?? const NarrationDownloadProgress.idle();
  }

  File? localFile(String articleId) {
    final root = _root;
    final name = narrationDownloadBasename(articleId);
    if (root == null || name.isEmpty) return null;
    return File(p.join(root.path, name));
  }

  Future<bool> hasPlayableFile(String articleId) async {
    if (!isReady(articleId)) return false;
    return _fileLooksReady(articleId);
  }

  Future<void> download(
    String articleId, {
    ApiClient? client,
    Future<bool> Function()? waitUntilReady,
  }) async {
    if (!PlatformCapabilities.canUseDartIoFiles) return;
    if (debugGetBytes == null &&
        WidgetsBinding.instance.runtimeType
            .toString()
            .contains('TestWidgetsFlutterBinding')) {
      return;
    }
    if (_root == null) await hydrate();
    final id = articleId.trim();
    if (id.isEmpty) return;
    if (_ready.contains(id) && await _fileLooksReady(id)) return;
    final existing = _inflight[id];
    if (existing != null) {
      await existing;
      if (_ready.contains(id) && await _fileLooksReady(id)) return;
    }
    final raced = _inflight[id];
    if (raced != null) {
      await raced;
      return;
    }
    if (_ready.contains(id) && await _fileLooksReady(id)) return;
    final epoch = _epochs[id] ?? 0;
    final run = _downloadLoop(
      id,
      client: client,
      waitUntilReady: waitUntilReady,
      epoch: epoch,
    );
    _inflight[id] = run;
    try {
      await run;
    } finally {
      if (identical(_inflight[id], run)) {
        _inflight.remove(id);
      }
    }
  }

  Future<void> wipe(Iterable<String> ids) async {
    var changed = false;
    final touched = <String>[];
    var filesDeleted = 0;
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      touched.add(id);
      _epochs[id] = (_epochs[id] ?? 0) + 1;
      _tokens[id]?.cancel('wiped');
      _tokens.remove(id);
      final dest = localFile(id);
      final existed = dest != null && await dest.exists();
      await _deleteFiles(id);
      if (existed) filesDeleted += 1;
      if (_ready.remove(id)) changed = true;
      _progress.remove(id);
      changed = true;
    }
    if (changed) {
      await _persistIndex();
      notifyListeners();
      final idBit = touched.length == 1 ? ' id=${touched.single}' : '';
      TLog.i(
        'NarrationDL',
        'deleted local audio n=${touched.length} files=$filesDeleted$idBit',
      );
    }
  }

  Future<void> pruneTo(Set<String> liveArticleIds) async {
    final gone = _ready.where((id) => !liveArticleIds.contains(id)).toList();
    if (gone.isEmpty) return;
    await wipe(gone);
  }

  @visibleForTesting
  void resetForTest() {
    _ready.clear();
    _progress.clear();
    _inflight.clear();
    _tokens.clear();
    _epochs.clear();
    _root = debugRootOverride;
  }

  bool _isStale(String id, int epoch) => (_epochs[id] ?? 0) != epoch;

  Future<void> _downloadLoop(
    String id, {
    ApiClient? client,
    Future<bool> Function()? waitUntilReady,
    required int epoch,
  }) async {
    if (_isStale(id, epoch)) return;
    TLog.i('NarrationDL', 'download start id=$id');
    _setProgress(
      id,
      const NarrationDownloadProgress(
        phase: NarrationDownloadPhase.downloading,
        attempt: 1,
      ),
    );
    if (waitUntilReady != null) {
      final ready = await waitUntilReady();
      if (_isStale(id, epoch)) return;
      if (!ready) {
        _setProgress(
          id,
          const NarrationDownloadProgress.error('Audio is not ready yet'),
        );
        return;
      }
    }
    Object? lastErr;
    for (var attempt = 0; attempt < kNarrationDownloadMaxAttempts; attempt++) {
      if (_isStale(id, epoch)) return;
      try {
        await _attempt(id, client: client, attempt: attempt, epoch: epoch);
        return;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel || _isStale(id, epoch)) return;
        lastErr = e;
        final code = e.response?.statusCode;
        if (!isRetryableDownloadStatus(code) ||
            attempt >= kNarrationDownloadMaxAttempts - 1) {
          break;
        }
      } on StateError catch (e) {
        lastErr = e;
        break;
      } catch (e) {
        lastErr = e;
        if (attempt >= kNarrationDownloadMaxAttempts - 1) break;
      }
      if (_isStale(id, epoch)) return;
      _setProgress(
        id,
        NarrationDownloadProgress(
          phase: NarrationDownloadPhase.downloading,
          attempt: attempt + 2,
        ),
      );
      await Future<void>.delayed(narrationDownloadBackoff(attempt));
    }
    if (_isStale(id, epoch)) return;
    TLog.w('NarrationDL', 'download failed $id: $lastErr');
    _setProgress(
      id,
      const NarrationDownloadProgress.error(
        'Could not download. Tap to retry.',
      ),
    );
  }

  Future<void> _attempt(
    String id, {
    ApiClient? client,
    required int attempt,
    required int epoch,
  }) async {
    final dest = localFile(id);
    if (dest == null) {
      throw StateError('download dir unavailable');
    }
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    var resumeFrom = 0;
    if (await part.exists()) {
      resumeFrom = await part.length();
    }

    final url = ApiEndpoints.narrationAudio(id);
    final headers = NarrationApi(client ?? ApiClient()).audioHeaders();
    final token = CancelToken();
    _tokens[id] = token;

    late List<int> bytes;
    if (debugGetBytes != null) {
      final res = await debugGetBytes!(url, headers, resumeFrom);
      if (res.status >= 400) {
        throw DioException(
          requestOptions: RequestOptions(path: url),
          response: Response<List<int>>(
            requestOptions: RequestOptions(path: url),
            statusCode: res.status,
            data: res.body,
          ),
        );
      }
      if (resumeFrom > 0 && res.status == 206) {
        final prefix = await part.readAsBytes();
        bytes = <int>[...prefix, ...res.body];
      } else {
        bytes = res.body;
      }
    } else {
      final dio = (client ?? ApiClient()).dio;
      final res = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: kNarrationDownloadReceiveTimeout,
          headers: {
            ...headers,
            if (resumeFrom > 0) HttpHeaders.rangeHeader: 'bytes=$resumeFrom-',
          },
          extra: {kNoRetry: true},
        ),
        cancelToken: token,
        onReceiveProgress: (got, total) {
          _setProgress(
            id,
            NarrationDownloadProgress(
              phase: NarrationDownloadPhase.downloading,
              received: resumeFrom + got,
              total: total < 0 ? null : resumeFrom + total,
              attempt: attempt + 1,
            ),
          );
        },
      );
      final payload = res.data ?? const <int>[];
      if (resumeFrom > 0 && res.statusCode == 206) {
        final prefix = await part.readAsBytes();
        bytes = <int>[...prefix, ...payload];
      } else {
        bytes = payload;
      }
    }

    if (_isStale(id, epoch)) {
      await _deleteFiles(id);
      return;
    }
    if (!isValidDownloadedOpus(
      exists: true,
      length: bytes.length,
      header: bytes.length >= 4 ? bytes.sublist(0, 4) : const <int>[],
    )) {
      await _deleteFiles(id);
      throw StateError('invalid opus');
    }
    await part.writeAsBytes(bytes, flush: true);
    if (_isStale(id, epoch)) {
      await _deleteFiles(id);
      return;
    }
    if (await dest.exists()) {
      await dest.delete();
    }
    await part.rename(dest.path);
    if (_isStale(id, epoch)) {
      await _deleteFiles(id);
      return;
    }
    _ready.add(id);
    _tokens.remove(id);
    if (_isStale(id, epoch)) {
      _ready.remove(id);
      await _deleteFiles(id);
      return;
    }
    await _persistIndex();
    _setProgress(
      id,
      NarrationDownloadProgress.ready(received: bytes.length, total: bytes.length),
    );
    TLog.i('NarrationDL', 'offline audio saved ${bytes.length}B id=$id');
  }

  Future<bool> _fileLooksReady(String id) async {
    final file = localFile(id);
    if (file == null || !await file.exists()) return false;
    final len = await file.length();
    final raf = await file.open();
    try {
      final header = await raf.read(4);
      return isValidDownloadedOpus(
        exists: true,
        length: len,
        header: header,
      );
    } finally {
      await raf.close();
    }
  }

  Future<void> _deleteFiles(String id) async {
    final dest = localFile(id);
    if (dest == null) return;
    try {
      if (await dest.exists()) await dest.delete();
    } catch (_) {}
    final part = File('${dest.path}.part');
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  void _setProgress(String id, NarrationDownloadProgress next) {
    _progress[id] = next;
    notifyListeners();
  }

  Future<void> _persistIndex() async {
    await _prefs?.setStringList(_kIndexKey, _ready.toList());
  }
}
