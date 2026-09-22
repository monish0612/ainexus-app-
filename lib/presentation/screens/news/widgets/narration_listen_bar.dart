import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/auth/app_token_store.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/telegram_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/utils/reduced_motion.dart';
import '../../../../data/services/article_tts_service.dart';
import '../../../../data/services/narration_api.dart';
import '../../../../data/services/narration_audio_handler.dart';
import '../../../../data/services/narration_completion_store.dart';
import '../../../../data/services/narration_download.dart';
import '../../../../data/services/narration_download_store.dart';
import '../../../../data/services/narration_models.dart';
import '../../../../data/services/narration_playback.dart';
import '../../../../domain/entities/news_entities.dart';

/// Server narration first; on-device [ArticleTtsService] if the pipeline
/// is down, timed out, or the breaker is open.
const Key kNewsListenDownloadKey = ValueKey('article-download-audio');

class NarrationListenBar extends ConsumerStatefulWidget {
  const NarrationListenBar({
    super.key,
    required this.article,
    required this.ttsService,
    required this.accentColor,
    required this.colors,
    required this.fallback,
    this.isFullContent = false,
    this.queue = const <Article>[],
  });

  final Article article;
  final ArticleTtsService ttsService;
  final Color accentColor;
  final AppColors colors;
  final Widget fallback;
  final bool isFullContent;
  final List<Article> queue;

  @override
  ConsumerState<NarrationListenBar> createState() => _NarrationListenBarState();
}

class _NarrationListenBarState extends ConsumerState<NarrationListenBar> {
  late final NarrationApi _api;
  NarrationJob _job = const NarrationJob(status: NarrationJobStatus.unknown);
  bool _booted = false;
  Timer? _poll;
  Timer? _giveUp;
  bool _starting = false;
  bool _downloading = false;
  bool _warmed = false;
  int _bootGen = 0;
  int _transientTries = 0;
  DateTime? _pollStartedAt;
  bool _offeredUnreachableFallback = false;
  ListenSurface? _surface;

  static bool get _inWidgetTest => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  @override
  void initState() {
    super.initState();
    _api = NarrationApi(ref.read(apiClientProvider));
    unawaited(_boot());
  }

  @override
  void didUpdateWidget(NarrationListenBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.article.id != widget.article.id) {
      _poll?.cancel();
      _giveUp?.cancel();
      setState(() {
        _booted = false;
        _job = const NarrationJob(status: NarrationJobStatus.unknown);
        _transientTries = 0;
        _offeredUnreachableFallback = false;
        _pollStartedAt = null;
        _surface = null;
      });
      unawaited(_boot());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _giveUp?.cancel();
    super.dispose();
  }

  Future<void> _waitForAuthToken() async {
    if (AppTokenStore.instance.hasToken) return;
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (mounted &&
        !AppTokenStore.instance.hasToken &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  void _applyJob(
    NarrationJob next, {
    required int gen,
    bool allowTerminalFallback = false,
  }) {
    if (!mounted || gen != _bootGen) return;
    final localReady =
        NarrationDownloadStore.instance.isReady(widget.article.id);
    if (!shouldAcceptNarrationJob(
      current: _job,
      next: next,
      localReady: localReady,
      booted: _booted,
      allowTerminalFallback: allowTerminalFallback,
    )) {
      return;
    }
    setState(() {
      _job = next;
      _booted = true;
    });
  }

  Future<void> _boot() async {
    // Never setState from the initState call stack (the widget-test
    // shortcut used to do that and left the bar stuck on "Checking").
    final gen = ++_bootGen;
    await Future<void>.value();
    if (!mounted || gen != _bootGen) return;
    if (_inWidgetTest) {
      setState(() {
        _job = const NarrationJob(
          status: NarrationJobStatus.fallback,
          configured: false,
          reason: 'widget_test',
        );
        _booted = true;
      });
      return;
    }
    await _waitForAuthToken();
    if (!mounted || gen != _bootGen) return;
    await NarrationDownloadStore.instance.hydrate();
    if (!mounted || gen != _bootGen) return;

    final statusFuture = _api.status(widget.article.id);
    NarrationJob job;
    try {
      job = await statusFuture.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      job = const NarrationJob(
        status: NarrationJobStatus.unknown,
        reason: 'timeout',
      );
      unawaited(statusFuture.then((lateJob) {
        _applyJob(lateJob, gen: gen);
        if (lateJob.isPreparing || lateJob.isReady) {
          if (shouldKeepPollingNarration(lateJob)) _startPoll();
        }
      }));
    }
    if (!mounted || gen != _bootGen) return;
    if (shouldEnsureOnBoot(job)) {
      final ensureFuture = _api.ensure(widget.article);
      try {
        job = await ensureFuture.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        job = const NarrationJob(
          status: NarrationJobStatus.unknown,
          reason: 'ensure_timeout',
        );
        unawaited(ensureFuture.then((lateJob) {
          _applyJob(lateJob, gen: gen);
          if (shouldKeepPollingNarration(lateJob)) _startPoll();
        }));
      }
    }
    if (!mounted || gen != _bootGen) return;
    _applyJob(job, gen: gen);
    if (shouldKeepPollingNarration(_job)) _startPoll();
  }

  void _startPoll() {
    _poll?.cancel();
    _transientTries = 0;
    _offeredUnreachableFallback = false;
    _pollStartedAt = DateTime.now();
    _armPoll();
    _giveUp?.cancel();
    _giveUp = Timer(const Duration(minutes: 8), () {
      if (!mounted) return;
      if (_job.isPreparing) {
        _applyJob(
          const NarrationJob(
            status: NarrationJobStatus.fallback,
            reason: 'generate_timeout',
          ),
          gen: _bootGen,
          allowTerminalFallback: true,
        );
      }
    });
  }

  void _armPoll() {
    _poll?.cancel();
    _poll = Timer(narrationPollInterval(_transientTries), () {
      unawaited(_onPollTick());
    });
  }

  Future<void> _onPollTick() async {
    final job = await _api.status(widget.article.id);
    if (!mounted) return;
    final gen = _bootGen;
    if (job.isReady || job.isPreparing) {
      _applyJob(job, gen: gen);
      if (job.isReady) {
        _poll?.cancel();
        _giveUp?.cancel();
        return;
      }
      if (job.isPreparing) _transientTries = 0;
      if (mounted) _armPoll();
      return;
    }
    if (isTransientNarrationFailure(job)) {
      _transientTries += 1;
      final elapsed = DateTime.now().difference(_pollStartedAt ?? DateTime.now());
      if (!_offeredUnreachableFallback &&
          narrationShouldOfferUnreachableFallback(elapsed)) {
        _offeredUnreachableFallback = true;
        _applyJob(
          const NarrationJob(
            status: NarrationJobStatus.fallback,
            configured: false,
            reason: 'unreachable_exhausted',
          ),
          gen: gen,
          allowTerminalFallback: true,
        );
      } else {
        _applyJob(job, gen: gen);
      }
      if (mounted && shouldKeepPollingNarration(_job)) _armPoll();
      return;
    }
    _applyJob(
      job,
      gen: gen,
      allowTerminalFallback: isTerminalNarrationFailure(job),
    );
    if (mounted && shouldKeepPollingNarration(_job)) _armPoll();
  }

  Future<bool> _waitUntilReady() async {
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_job.isReady) return true;
      if (isTerminalNarrationFailure(_job) && !_job.isPreparing) return false;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return _job.isReady;
  }

  /// AudioService.init is the long pole on a cold Listen tap: it spins up
  /// the media session, the notification channel and ExoPlayer. Paying for
  /// it while the user is still reading — once, off the first frame that
  /// shows a playable card — takes it off the tap path entirely.
  void _warmAudioService() {
    if (_warmed || _inWidgetTest) return;
    _warmed = true;
    if (narrationHandler != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await initNarrationAudio(NarrationApi(ref.read(apiClientProvider)));
      } catch (e) {
        TLog.w('Narration', 'AudioService warm-up failed: $e');
      }
    });
  }

  void _setStarting(bool value) {
    if (_starting == value) return;
    if (!mounted) {
      _starting = value;
      return;
    }
    setState(() => _starting = value);
  }

  Future<void> _playServer() async {
    if (_starting) return;
    _setStarting(true);
    try {
      final localReady =
          await NarrationDownloadStore.instance.hasPlayableFile(
        widget.article.id,
      );
      if (shouldEnsureBeforePlay(_job, localReady: localReady)) {
        final ensured = await _api.ensure(widget.article);
        if (!mounted) return;
        _applyJob(ensured, gen: _bootGen);
        if (ensured.isPreparing) {
          _startPoll();
          final ready = await _waitUntilReady();
          if (!ready || !mounted) return;
        } else if (!ensured.isReady) {
          return;
        }
      }
      final handler = narrationHandler ??
          await initNarrationAudio(
            NarrationApi(ref.read(apiClientProvider)),
            timeout: const Duration(seconds: 20),
          );
      if (handler == null) {
        if (shouldShowOnDeviceAfterPlayError(
          localReady: localReady,
          job: _job,
        )) {
          _applyJob(
            const NarrationJob(
              status: NarrationJobStatus.fallback,
              reason: 'no_audio_service',
            ),
            gen: _bootGen,
            allowTerminalFallback: true,
          );
        } else {
          TLog.w('Narration', 'AudioService not ready, keeping narrated player');
        }
        return;
      }
      if (isNarrationIdDropped(widget.article.id)) return;
      // just_audio's `play()` future does not complete until the track
      // ENDS, and playArticle awaits it — so awaiting playArticle held the
      // button in its pending state for the whole article and tripped the
      // 20s timeout on every single play. Wait for first audio instead.
      final started = Completer<void>();
      final sub = handler.player.playingStream.listen((isPlaying) {
        if (isPlaying && !started.isCompleted) started.complete();
      });
      final play = handler.playArticle(widget.article, queue: widget.queue);
      unawaited(play.then(
        (_) {
          if (!started.isCompleted) started.complete();
        },
        onError: (Object e, StackTrace s) {
          if (started.isCompleted) {
            TLog.w('Narration', 'playback ended with an error: $e');
          } else {
            started.completeError(e, s);
          }
        },
      ));
      try {
        await started.future.timeout(const Duration(seconds: 20));
      } finally {
        unawaited(sub.cancel());
      }
    } catch (e) {
      if (!mounted) return;
      final localReady = await NarrationDownloadStore.instance.hasPlayableFile(
        widget.article.id,
      );
      if (!shouldShowOnDeviceAfterPlayError(
        localReady: localReady,
        job: _job,
      )) {
        TLog.w('Narration', 'play failed, keeping narrated player: $e');
        return;
      }
      _applyJob(
        const NarrationJob(
          status: NarrationJobStatus.fallback,
          reason: 'play_failed',
        ),
        gen: _bootGen,
        allowTerminalFallback: true,
      );
    } finally {
      _setStarting(false);
    }
  }

  Future<void> _downloadAudio() async {
    if (_downloading) return;
    if (await NarrationDownloadStore.instance.hasPlayableFile(
      widget.article.id,
    )) {
      return;
    }
    _downloading = true;
    try {
      if (_inWidgetTest) return;
      await NarrationDownloadStore.instance.download(
        widget.article.id,
        client: ref.read(apiClientProvider),
        waitUntilReady: () async {
          if (_job.isReady) return true;
          if (shouldEnsureBeforePlay(_job)) {
            final ensured = await _api.ensure(widget.article);
            if (!mounted) return false;
            _applyJob(ensured, gen: _bootGen);
            if (ensured.isPreparing) {
              _startPoll();
              return _waitUntilReady();
            }
            return ensured.isReady ||
                NarrationDownloadStore.instance.isReady(widget.article.id);
          }
          if (_job.isPreparing) return _waitUntilReady();
          return _job.isReady;
        },
      );
    } finally {
      _downloading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NarrationDownloadStore.instance,
      builder: (context, _) {
        final localReady =
            NarrationDownloadStore.instance.isReady(widget.article.id);
        final surface = whichListenSurface(
          job: _job,
          localReady: localReady,
          booted: _booted,
        );
        if (_surface == ListenSurface.onDevice &&
            surface != ListenSurface.onDevice) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(widget.ttsService.stop());
          });
        }
        _surface = surface;
        switch (surface) {
          case ListenSurface.checking:
            return _PreparingCard(
              accentColor: widget.accentColor,
              colors: widget.colors,
              label: 'Checking audio…',
              articleId: widget.article.id,
              onDownload: _downloadAudio,
            );
          case ListenSurface.preparing:
            return _PreparingCard(
              accentColor: widget.accentColor,
              colors: widget.colors,
              label: 'Preparing your audio…',
              articleId: widget.article.id,
              onDownload: _downloadAudio,
            );
          case ListenSurface.server:
            _warmAudioService();
            return _ServerPlayerCard(
              article: widget.article,
              accentColor: widget.accentColor,
              colors: widget.colors,
              isFullContent: widget.isFullContent,
              starting: _starting,
              onPlay: _playServer,
              onDownload: _downloadAudio,
            );
          case ListenSurface.onDevice:
            return widget.fallback;
        }
      },
    );
  }
}

class _PreparingCard extends StatelessWidget {
  const _PreparingCard({
    required this.accentColor,
    required this.colors,
    required this.label,
    required this.articleId,
    required this.onDownload,
  });

  final Color accentColor;
  final AppColors colors;
  final String label;
  final String articleId;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return NewsListenSurface(
      accentColor: accentColor,
      colors: colors,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          NewsListenDownloadDisc(
            accentColor: accentColor,
            articleId: articleId,
            onTap: onDownload,
          ),
        ],
      ),
    );
  }
}

class _ServerPlayerCard extends StatelessWidget {
  const _ServerPlayerCard({
    required this.article,
    required this.accentColor,
    required this.colors,
    required this.isFullContent,
    required this.starting,
    required this.onPlay,
    required this.onDownload,
  });

  final Article article;
  final Color accentColor;
  final AppColors colors;
  final bool isFullContent;

  /// Play was tapped and the load is still in flight.
  final bool starting;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final handler = narrationHandler;
    return ListenableBuilder(
      listenable: NarrationCompletionStore.instance,
      builder: (context, _) {
        final done = NarrationCompletionStore.instance.isCompleted(article.id);
        final speed = NarrationCompletionStore.instance.speed;
        return StreamBuilder<PlayerState>(
          stream: handler?.player.playerStateStream,
          builder: (context, _) {
            return StreamBuilder<Duration>(
              stream: handler?.player.positionStream,
              builder: (context, _) {
                final playingThis = handler != null &&
                    handler.mediaItem.valueOrNull?.id == article.id &&
                    handler.player.processingState != ProcessingState.idle;
                final completed = handler != null &&
                    handler.player.processingState == ProcessingState.completed;
                final playing = playingThis && handler.player.playing;
                final position =
                    playingThis ? handler.player.position : Duration.zero;
                final total = playingThis ? handler.player.duration : null;

                return NewsListenSurface(
                  accentColor: accentColor,
                  colors: colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  LucideIcons.headphones,
                                  size: 18,
                                  color: accentColor,
                                ),
                              ),
                              if (done)
                                const Positioned(
                                  right: -3,
                                  bottom: -3,
                                  child: Icon(
                                    LucideIcons.checkCircle2,
                                    size: 15,
                                    color: Color(0xFF34D399),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isFullContent
                                      ? 'Listen to Article'
                                      : 'Listen to Explainer',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                    color: done
                                        ? colors.text.withValues(alpha: 0.55)
                                        : colors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  starting && !playing
                                      ? 'Loading audio…'
                                      : narrationStatusLabel(
                                          isThisArticle: playingThis,
                                          playing: playing,
                                          completed: completed,
                                          listened: done,
                                        ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colors.text4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          NewsListenDownloadDisc(
                            accentColor: accentColor,
                            articleId: article.id,
                            onTap: onDownload,
                          ),
                          const SizedBox(width: 8),
                          NewsListenPlayDisc(
                            accentColor: accentColor,
                            playing: playing,
                            pending: starting && !playing,
                            onTap: () {
                              final h = handler;
                              final tap = narrationPlayTap(
                                isThisArticle: playingThis,
                                completed: h != null &&
                                    h.player.processingState ==
                                        ProcessingState.completed,
                              );
                              switch (tap) {
                                case NarrationPlayTap.toggle:
                                  if (h == null) return;
                                  if (h.player.playing) {
                                    h.pause();
                                  } else {
                                    h.play();
                                  }
                                case NarrationPlayTap.restart:
                                  h?.replay();
                                case NarrationPlayTap.start:
                                  onPlay();
                              }
                            },
                          ),
                        ],
                      ),
                      if (playingThis &&
                          total != null &&
                          total.inMilliseconds > 0) ...[
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                          ),
                          child: Slider(
                            value: position.inMilliseconds
                                .clamp(0, total.inMilliseconds)
                                .toDouble(),
                            max: total.inMilliseconds.toDouble(),
                            activeColor: accentColor,
                            onChanged: (v) {
                              handler.seek(
                                Duration(milliseconds: v.round()),
                              );
                            },
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              _fmt(position),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: colors.text4,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _fmt(total),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                color: colors.text4,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in _speeds)
                            GestureDetector(
                              onTap: () async {
                                final h = handler ?? narrationHandler;
                                if (h != null) {
                                  await h.setPlaybackSpeed(s);
                                } else {
                                  await NarrationCompletionStore.instance
                                      .setSpeed(s);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: (speed - s).abs() < 0.01
                                      ? accentColor.withValues(alpha: 0.18)
                                      : accentColor.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${s}x',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Shared listen-card chrome so the preparing state, server player, and
/// on-device TTS fallback all read as one control.
class NewsListenSurface extends StatelessWidget {
  const NewsListenSurface({
    super.key,
    required this.accentColor,
    required this.colors,
    required this.child,
  });

  final Color accentColor;
  final AppColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: colors.isDark ? 0.22 : 0.10),
            blurRadius: colors.isDark ? 18 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17.5),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(
                        alpha: colors.isDark ? 0.24 : 0.12,
                      ),
                      colors.bg2,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: ColoredBox(
                color: accentColor,
                child: const SizedBox(width: 4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class NewsListenDownloadDisc extends StatelessWidget {
  const NewsListenDownloadDisc({
    super.key,
    required this.accentColor,
    required this.articleId,
    required this.onTap,
  });

  final Color accentColor;
  final String articleId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NarrationDownloadStore.instance,
      builder: (context, _) {
        final progress =
            NarrationDownloadStore.instance.progressOf(articleId);
        final phase = progress.phase;
        final icon = switch (phase) {
          NarrationDownloadPhase.ready => LucideIcons.check,
          NarrationDownloadPhase.downloading => LucideIcons.loader2,
          NarrationDownloadPhase.error => LucideIcons.rotateCw,
          NarrationDownloadPhase.idle => LucideIcons.download,
        };
        final filled = phase == NarrationDownloadPhase.ready;
        return Semantics(
          button: true,
          label: narrationDownloadSemantics(phase),
          child: Material(
            key: kNewsListenDownloadKey,
            color: Colors.transparent,
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.none,
            child: InkWell(
              onTap: shouldAllowDownloadTap(phase) ? onTap : null,
              customBorder: const CircleBorder(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? accentColor : accentColor.withValues(alpha: 0.16),
                  border: Border.all(
                    color: accentColor.withValues(alpha: filled ? 0 : 0.45),
                    width: 1.5,
                  ),
                  boxShadow: filled
                      ? [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (phase == NarrationDownloadPhase.downloading)
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: accentColor,
                          value: progress.total == null
                              ? null
                              : progress.fraction,
                        ),
                      ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        icon,
                        key: ValueKey(phase),
                        size: 18,
                        color: filled ? Colors.white : accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class NewsListenPlayDisc extends StatefulWidget {
  const NewsListenPlayDisc({
    super.key,
    required this.accentColor,
    required this.playing,
    this.pending = false,
    this.onTap,
  });

  final Color accentColor;
  final bool playing;

  /// The tap has been accepted but audio has not started yet. Server
  /// narration spends multiple seconds here on a cold start (AudioService
  /// boot + source load), so the disc must stop looking idle immediately.
  final bool pending;
  final VoidCallback? onTap;

  @override
  State<NewsListenPlayDisc> createState() => _NewsListenPlayDiscState();
}

class _NewsListenPlayDiscState extends State<NewsListenPlayDisc>
    with SingleTickerProviderStateMixin {
  static const double _pressedScale = 0.92;

  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _pressDown() {
    if (reducedMotion(context)) return;
    _press.animateTo(
      _pressedScale,
      duration: AppMotion.microPress,
      curve: AppMotion.standard,
    );
  }

  void _pressUp() {
    if (reducedMotion(context)) {
      _press.value = 1;
      return;
    }
    _press.animateWith(
      SpringSimulation(AppSprings.magnetic, _press.value, 1, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final glyph = widget.pending
        ? const SizedBox(
            key: ValueKey<String>('pending'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          )
        : Padding(
            key: ValueKey<bool>(widget.playing),
            padding: EdgeInsets.only(left: widget.playing ? 0 : 2),
            child: Icon(
              widget.playing ? LucideIcons.pause : LucideIcons.play,
              size: 20,
              color: Colors.white,
            ),
          );

    final disc = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: accent.a * 0.45),
            blurRadius: widget.pending ? 20 : 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: motionDuration(context, AppMotion.microHover),
        transitionBuilder: fadeScaleTransition(context),
        child: glyph,
      ),
    );

    final labelled = Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.pending
          ? 'Starting audio'
          : (widget.playing ? 'Pause' : 'Play'),
      child: ExcludeSemantics(child: disc),
    );

    if (widget.onTap == null) return labelled;

    return Material(
      color: Colors.transparent,
      type: MaterialType.transparency,
      shape: const CircleBorder(),
      clipBehavior: Clip.none,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => _pressDown(),
        onTapUp: (_) => _pressUp(),
        onTapCancel: _pressUp,
        customBorder: const CircleBorder(),
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) => Transform.scale(
            scale: _press.value,
            child: child,
          ),
          child: labelled,
        ),
      ),
    );
  }
}
