import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/network/api_endpoints.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/news_entities.dart';
import 'narration_api.dart';
import 'narration_completion_store.dart';

/// Background / lock-screen handler. Separate from the dataSync FGS.
class NarrationAudioHandler extends BaseAudioHandler with SeekHandler {
  NarrationAudioHandler({required NarrationApi api}) : _api = api {
    _player.playbackEventStream.listen(_emitState);
    _player.positionStream.listen(_onPosition);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        unawaited(_onTrackEnded());
      }
    });
  }

  final NarrationApi _api;
  final AudioPlayer _player = AudioPlayer();
  final List<Article> _queue = <Article>[];
  int _index = 0;
  bool _completedSent = false;
  VoidCallback? onFallbackRequested;

  AudioPlayer get player => _player;

  Future<void> playArticle(Article article, {List<Article> queue = const []}) async {
    _queue
      ..clear()
      ..addAll(queue.isEmpty ? [article] : queue);
    _index = _queue.indexWhere((a) => a.id == article.id);
    if (_index < 0) {
      _queue.insert(0, article);
      _index = 0;
    }
    await _loadCurrent();
    await play();
  }

  Future<void> _loadCurrent() async {
    if (_index < 0 || _index >= _queue.length) return;
    final article = _queue[_index];
    _completedSent = false;
    final url = ApiEndpoints.narrationAudio(article.id);
    final headers = _api.audioHeaders();
    mediaItem.add(
      MediaItem(
        id: article.id,
        title: article.title,
        artist: article.source,
        artUri: article.imageUrl.isEmpty ? null : Uri.tryParse(article.imageUrl),
      ),
    );
    await _player.setSpeed(NarrationCompletionStore.instance.speed);
    await _player.setPitch(1.0);
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(url), headers: headers),
    );
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await NarrationCompletionStore.instance.setSpeed(speed);
    await _player.setSpeed(NarrationCompletionStore.instance.speed);
    await _player.setPitch(1.0);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
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
    if (_index + 1 >= _queue.length) {
      await stop();
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
    await NarrationCompletionStore.instance.mark(article.id);
    await _api.complete(article.id);
  }
}

NarrationAudioHandler? _handler;

Future<NarrationAudioHandler?> initNarrationAudio(NarrationApi api) async {
  if (!PlatformCapabilities.canUseAudioService) return null;
  if (_handler != null) return _handler;
  try {
    _handler = await AudioService.init(
      builder: () => NarrationAudioHandler(api: api),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.ainexus.narration',
        androidNotificationChannelName: 'Article narration',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    return _handler;
  } catch (e) {
    TLog.w('Narration', 'AudioService.init failed: $e');
    return null;
  }
}

NarrationAudioHandler? get narrationHandler => _handler;
