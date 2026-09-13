import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/services/article_tts_service.dart';
import '../../../../data/services/narration_api.dart';
import '../../../../data/services/narration_audio_handler.dart';
import '../../../../data/services/narration_completion_store.dart';
import '../../../../data/services/narration_models.dart';
import '../../../../domain/entities/news_entities.dart';

/// Server narration first; on-device [ArticleTtsService] if the pipeline
/// is down, timed out, or the breaker is open.
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
  bool _starting = false;

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
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    // Never setState from the initState call stack (the widget-test
    // shortcut used to do that and left the bar stuck on "Checking").
    await Future<void>.value();
    if (!mounted) return;
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
    final job = await _api.status(widget.article.id).timeout(
          const Duration(seconds: 5),
          onTimeout: () => const NarrationJob(
            status: NarrationJobStatus.fallback,
            configured: false,
            reason: 'timeout',
          ),
        );
    if (!mounted) return;
    if (job.useOnDevice && job.configured) {
      final ensured = await _api.ensure(widget.article);
      if (!mounted) return;
      setState(() {
        _job = ensured;
        _booted = true;
      });
      if (ensured.isPreparing) _startPoll();
      return;
    }
    setState(() {
      _job = job;
      _booted = true;
    });
    if (job.isPreparing) _startPoll();
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final job = await _api.status(widget.article.id);
      if (!mounted) return;
      setState(() => _job = job);
      if (job.isReady || job.useOnDevice) {
        _poll?.cancel();
      }
    });
    Future<void>.delayed(const Duration(minutes: 8), () {
      if (!mounted) return;
      if (_job.isPreparing) {
        _poll?.cancel();
        setState(() {
          _job = const NarrationJob(
            status: NarrationJobStatus.fallback,
            reason: 'timeout',
          );
        });
      }
    });
  }

  Future<bool> _waitUntilReady() async {
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_job.isReady) return true;
      if (_job.useOnDevice && !_job.isPreparing) return false;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return _job.isReady;
  }

  Future<void> _playServer() async {
    if (_starting) return;
    _starting = true;
    try {
      if (!_job.isReady) {
        final ensured = await _api.ensure(widget.article);
        if (!mounted) return;
        setState(() => _job = ensured);
        if (ensured.isPreparing) {
          _startPoll();
          final ready = await _waitUntilReady();
          if (!ready || !mounted) return;
        } else if (!ensured.isReady) {
          return;
        }
      }
      final handler = narrationHandler ??
          await initNarrationAudio(NarrationApi(ref.read(apiClientProvider)));
      if (handler == null) {
        setState(() {
          _job = const NarrationJob(
            status: NarrationJobStatus.fallback,
            reason: 'no_audio_service',
          );
        });
        return;
      }
      await handler.playArticle(widget.article, queue: widget.queue);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _job = const NarrationJob(
          status: NarrationJobStatus.fallback,
          reason: 'play_failed',
        );
      });
    } finally {
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_booted) {
      return _PreparingCard(
        accentColor: widget.accentColor,
        colors: widget.colors,
        label: 'Checking audio…',
      );
    }
    if (_job.isPreparing) {
      return _PreparingCard(
        accentColor: widget.accentColor,
        colors: widget.colors,
        label: 'Preparing your audio…',
      );
    }
    if (_job.canReplay) {
      return _ServerPlayerCard(
        article: widget.article,
        accentColor: widget.accentColor,
        colors: widget.colors,
        isFullContent: widget.isFullContent,
        onPlay: _playServer,
      );
    }
    return widget.fallback;
  }
}

class _PreparingCard extends StatelessWidget {
  const _PreparingCard({
    required this.accentColor,
    required this.colors,
    required this.label,
  });

  final Color accentColor;
  final AppColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
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
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
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
    required this.onPlay,
  });

  final Article article;
  final Color accentColor;
  final AppColors colors;
  final bool isFullContent;
  final VoidCallback onPlay;

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
        final done =
            NarrationCompletionStore.instance.isCompleted(article.id);
        final speed = NarrationCompletionStore.instance.speed;
        return StreamBuilder<Duration>(
          stream: handler?.player.positionStream,
          builder: (context, _) {
            final playingThis = handler != null &&
                handler.mediaItem.valueOrNull?.id == article.id &&
                handler.player.processingState != ProcessingState.idle;
            final playing = playingThis && handler.player.playing;
            final position = playingThis
                ? handler.player.position
                : Duration.zero;
            final total = playingThis ? handler.player.duration : null;

            return Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentColor.withValues(alpha: 0.14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              LucideIcons.headphones,
                              size: 16,
                              color: accentColor,
                            ),
                          ),
                          if (done)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Icon(
                                LucideIcons.checkCircle2,
                                size: 14,
                                color: accentColor,
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
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: done
                                    ? colors.text.withValues(alpha: 0.55)
                                    : colors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              playingThis
                                  ? (playing ? 'Playing' : 'Paused')
                                  : (done
                                      ? 'Played · tap to hear again'
                                      : 'Narrated voice'),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: colors.text4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: accentColor.withValues(alpha: 0.14),
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: playingThis
                              ? () {
                                  final h = handler;
                                  if (h == null) return;
                                  if (h.player.playing) {
                                    h.pause();
                                  } else {
                                    h.play();
                                  }
                                }
                              : onPlay,
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(
                              playing ? LucideIcons.pause : LucideIcons.play,
                              size: 14,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (playingThis && total != null && total.inMilliseconds > 0) ...[
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
                          handler?.seek(
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
  }
}
