import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/network/api_endpoints.dart';
import '../../core/notifications/android_status_bar_icon.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/news_entities.dart';
import 'narration_api.dart';
import 'narration_completion_store.dart';
import 'narration_download.dart';
import 'narration_download_store.dart';
import 'narration_playback.dart';

/// Background / lock-screen handler. Separate from the dataSync FGS.
class NarrationAudioHandler extends BaseAudioHandler with SeekHandler {
  NarrationAudioHandler({required NarrationApi api}) : _api = api {
    _player.playbackEventStream.listen(_emitState);
    _player.positionStream.listen(_onPosition);
    _player.processingStateStream.listen((state) {
      final name = switch (state) {
        ProcessingState.idle => 'idle',
        ProcessingState.loading => 'loading',
        ProcessingState.buffering => 'buffering',
        ProcessingState.ready => 'ready',
        ProcessingState.completed => 'completed',
      };
      if (_advance.onState(name)) {
        unawaited(_onTrackEnded());
      }
    });
  }

  final NarrationApi _api;
  final AudioPlayer _player = AudioPlayer();
  ConcatenatingAudioSource? _chunks;
  Timer? _chunkPoll;
  int _loadedChunks = 0;
  final List<Article> _queue = <Article>[];
  int _index = 0;
  bool _completedSent = false;
  bool _loadedFromLocal = false;
  final NarrationAdvanceGate _advance = NarrationAdvanceGate();
  VoidCallback? onFallbackRequested;

  AudioPlayer get player => _player;

  Future<void> playArticle(Article article,
      {List<Article> queue = const []}) async {
    if (isNarrationIdDropped(article.id)) {
      TLog.w('Narration', 'skip play, article audio was dropped');
      return;
    }
    final live = [
      for (final a in (queue.isEmpty ? [article] : queue))
        if (!isNarrationIdDropped(a.id)) a,
    ];
    _queue
      ..clear()
      ..addAll(live);
    _index = _queue.indexWhere((a) => a.id == article.id);
    if (_index < 0) {
      if (isNarrationIdDropped(article.id)) return;
      _queue.insert(0, article);
      _index = 0;
    }
    final same = mediaItem.valueOrNull?.id == article.id;
    final idle = _player.processingState == ProcessingState.idle;
    final localReady =
        await NarrationDownloadStore.instance.hasPlayableFile(article.id);
    final reuse = shouldReuseLoadedSource(
      currentId: same ? article.id : mediaItem.valueOrNull?.id,
      articleId: article.id,
      idle: idle,
    );
    if (reuse &&
        !shouldReloadForLocalFile(
          localReady: localReady,
          currentIsLocal: _loadedFromLocal,
        )) {
      _completedSent = false;
      try {
        if (isNarrationIdDropped(article.id)) return;
        await play();
        return;
      } catch (e) {
        TLog.w('Narration', 'replay seek failed, reloading: $e');
      }
    }
    await _loadCurrent();
    if (isNarrationIdDropped(article.id)) {
      await stop();
      return;
    }
    if (_chunks != null && _loadedChunks == 0) return;
    await play();
  }

  Future<void> replay() => play();

  Future<void> _loadCurrent() async {
    if (_index < 0 || _index >= _queue.length) return;
    final article = _queue[_index];
    _completedSent = false;
    mediaItem.add(
      MediaItem(
        id: article.id,
        title: article.title,
        artist: article.source,
        artUri:
            article.imageUrl.isEmpty ? null : Uri.tryParse(article.imageUrl),
      ),
    );
    await _player.setSpeed(NarrationCompletionStore.instance.speed);
    await _player.setPitch(1.0);
    final local = NarrationDownloadStore.instance.localFile(article.id);
    if (local != null &&
        await NarrationDownloadStore.instance.hasPlayableFile(article.id)) {
      _loadedFromLocal = true;
      await _player.setFilePath(local.path);
      return;
    }
    _loadedFromLocal = false;
    _chunkPoll?.cancel();
    _loadedChunks = 0;
    _chunks = ConcatenatingAudioSource(children: []);
    await _player.setAudioSource(_chunks!);
    _chunkPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      _pullChunks(article.id);
    });
    await _pullChunks(article.id);
  }

  Future<void> _pullChunks(String articleId) async {
    final playlist = _chunks;
    if (playlist == null) return;
    final job = await _api.status(articleId);
    if (job.chunkError != null || job.status == NarrationJobStatus.failed) {
      _chunkPoll?.cancel();
      await _player.pause();
      return;
    }
    final headers = _api.audioHeaders();
    for (final index in job.chunks) {
      if (index < _loadedChunks) continue;
      await playlist.add(
        AudioSource.uri(
          Uri.parse(ApiEndpoints.narrationChunk(articleId, index)),
          headers: headers,
        ),
      );
      _loadedChunks = index + 1;
    }
    if (playlist.length == 0) return;
    final ended = _player.processingState == ProcessingState.completed;
    if (!_player.playing && !ended) {
      await _player.play();
      return;
    }
    if (ended) {
      final next = (_player.currentIndex ?? -1) + 1;
      if (next < playlist.length) {
        await _player.seek(Duration.zero, index: next);
        await _player.play();
      }
    }
    if (job.complete && _loadedChunks >= job.chunks.length) {
      _chunkPoll?.cancel();
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await NarrationCompletionStore.instance.setSpeed(speed);
    await _player.setSpeed(NarrationCompletionStore.instance.speed);
    await _player.setPitch(1.0);
  }

  @override
  Future<void> play() async {
    if (shouldSeekToStartBeforePlay(
      completed: _player.processingState == ProcessingState.completed,
    )) {
      _completedSent = false;
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _chunkPoll?.cancel();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToPrevious() async {
    if (_index <= 0) return;
    _index -= 1;
    await _loadCurrent();
    await play();
  }

  @override
  Future<void> skipToNext() async {
    if (shouldKeepSourceAtQueueEnd(index: _index, length: _queue.length)) {
      return;
    }
    _index += 1;
    try {
      await _loadCurrent();
      await play();
    } catch (e) {
      TLog.w('Narration', 'next track failed: $e');
      onFallbackRequested?.call();
    }
  }

  void _emitState(PlaybackEvent event) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _index,
      ),
    );
  }

  void _onPosition(Duration position) {
    final total = _player.duration;
    if (total == null || total.inMilliseconds <= 0) return;
    if (position.inMilliseconds / total.inMilliseconds >= 0.95) {
      unawaited(_markComplete());
    }
  }

  Future<void> _onTrackEnded() async {
    await _markComplete();
    await skipToNext();
  }

  Future<void> _markComplete() async {
    if (_completedSent) return;
    if (_index < 0 || _index >= _queue.length) return;
    _completedSent = true;
    final article = _queue[_index];
    // Local checkmark only. Do NOT call /complete — that used to wipe the
    // opus file. Audio is removed only when the article is cleared/deleted.
    await NarrationCompletionStore.instance.mark(article.id);
  }

  Future<void> dropArticles(Iterable<String> ids) async {
    final dropped = {for (final id in ids) id};
    if (dropped.isEmpty) return;
    final current = mediaItem.valueOrNull?.id;
    if (shouldStopNarrationPlayback(currentId: current, droppedIds: dropped)) {
      await stop();
      _queue.clear();
      _index = 0;
      _completedSent = false;
      _loadedFromLocal = false;
      return;
    }
    _queue.removeWhere((a) => dropped.contains(a.id));
    if (_index >= _queue.length) {
      _index = _queue.isEmpty ? 0 : _queue.length - 1;
    }
  }
}

NarrationAudioHandler? _handler;
Future<NarrationAudioHandler?>? _initInFlight;

/// Connects lock-screen / media-playback. Safe to call from Listen; must
/// never run before the first Flutter frame — `AudioServiceActivity` plus an
/// early `AudioService.init` deadlocks the native splash on some launches.
///
/// Splash uses a short [timeout] so a hung MediaBrowser cannot freeze the
/// UI. An explicit Listen tap may wait longer on the same in-flight init.
Future<NarrationAudioHandler?> initNarrationAudio(
  NarrationApi api, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (!PlatformCapabilities.canUseAudioService) return null;
  if (_handler != null) return _handler;
  _initInFlight ??= AudioService.init(
    builder: () => NarrationAudioHandler(api: api),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.ainexus.narration',
      androidNotificationChannelName: 'Article narration',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: AndroidStatusBarIcon.audioServiceRes,
      notificationColor: AndroidStatusBarIcon.accent,
    ),
  ).then<NarrationAudioHandler?>((h) {
    _handler = h;
    final dropped = snapshotDroppedNarrationIds();
    if (dropped.isNotEmpty) {
      unawaited(h.dropArticles(dropped));
    }
    return h;
  }, onError: (Object e, StackTrace _) {
    TLog.w('Narration', 'AudioService.init failed: $e');
    return null;
  });
  try {
    return await _initInFlight!.timeout(timeout);
  } on TimeoutException {
    TLog.w(
      'Narration',
      'AudioService.init timed out — UI stays up, Listen can wait on the same in-flight init',
    );
    return _handler;
  }
}

NarrationAudioHandler? get narrationHandler => _handler;

Future<void> dropNarrationFor(Iterable<String> ids) async {
  rememberDroppedNarrationIds(ids);
  await NarrationDownloadStore.instance.wipe(ids);
  final h = _handler;
  if (h == null) return;
  await h.dropArticles(ids);
}
