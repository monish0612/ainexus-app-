import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/nas_stats.dart';
import 'nas_stats_controller.dart';
import 'widgets/fluid_gauge.dart';
import 'widgets/stats_chrome.dart';

/// Live NAS dashboard.
///
/// Ordered by the question it answers, not by what is easiest to collect. The
/// first thing on screen is how much more film will fit, because that is the
/// only reason to open this page while standing in front of a copy dialog.
/// CPU and memory come next, then the things you look at when something feels
/// wrong: pool health, disk temperatures, what is running, what is playing.
///
/// When the NAS is off the whole body is wrapped in [StatsOfflineShroud] and
/// every gauge is fed zero. That is the requested behaviour and it is also the
/// honest one — the alternative, hiding the layout, loses the information that
/// these readings exist at all and would be back when the machine is.
class NasStatsScreen extends ConsumerWidget {
  const NasStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final state = ref.watch(nasStatsControllerProvider);
    final controller = ref.read(nasStatsControllerProvider.notifier);
    final snapshot = state.snapshot;
    final offline = !state.isOnline;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          StatsHeader(
            title: snapshot?.host == null ? 'NAS' : 'NAS · ${snapshot!.host}',
            subtitle: _subtitle(state),
            live: state.isOnline && state.isPolling && !state.isReconnecting,
            ageSeconds: state.envelope.ageS,
          ),
          Expanded(
            child: !state.hasLoaded
                ? const _StatsLoading()
                : RefreshIndicator(
                    onRefresh: controller.refreshNow,
                    color: AppColors.accent,
                    backgroundColor: colors.bg2,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        if (state.transportError case final err?) ...[
                          StatsOfflineBanner(
                            title: 'Can\'t reach the stats server',
                            message: err,
                            lastSeen: state.envelope.lastSeen,
                            isFault: true,
                            onRetry: controller.refreshNow,
                          ),
                          const SizedBox(height: 14),
                        ] else if (offline) ...[
                          StatsOfflineBanner(
                            title: 'Your NAS is off',
                            message: (state.envelope.reason ??
                                    NasOfflineReason.unreachable)
                                .message,
                            lastSeen: state.envelope.lastSeen,
                            isFault: state.envelope.reason ==
                                NasOfflineReason.auth,
                            onRetry: controller.refreshNow,
                          ),
                          const SizedBox(height: 14),
                        ] else if (state.envelope.isStalled) ...[
                          StatsNote(
                            text: 'Your NAS is answering but its readings have '
                                'stopped moving. The figures below are '
                                '${formatAgo(state.envelope.ageS)}.',
                            icon: Icons.pause_circle_outline_rounded,
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Everything below goes grey and inert together, so
                        // there is no chance of a live-looking widget sitting
                        // in a dead dashboard.
                        StatsOfflineShroud(
                          offline: offline,
                          child: Column(
                            children: [
                              _FilmSpaceHero(snapshot: snapshot),
                              const SizedBox(height: 14),
                              _LoadGauges(snapshot: snapshot),
                              const SizedBox(height: 14),
                              _PoolsCard(snapshot: snapshot),
                              const SizedBox(height: 14),
                              _DisksCard(snapshot: snapshot),
                              const SizedBox(height: 14),
                              _ServicesCard(snapshot: snapshot),
                              if (snapshot?.playback?.items.isNotEmpty ??
                                  false) ...[
                                const SizedBox(height: 14),
                                _NowPlayingCard(
                                  playback: snapshot!.playback!,
                                ),
                              ],
                              const SizedBox(height: 14),
                              _SystemCard(snapshot: snapshot),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(NasStatsState state) {
    if (state.transportError != null) return 'Not connected';
    if (!state.isOnline) return 'Switched off';
    final v = state.snapshot?.version;
    final up = formatDuration(state.snapshot?.uptimeS);
    return v == null ? 'Up $up' : 'TrueNAS $v · up $up';
  }
}

class _StatsLoading extends StatelessWidget {
  const _StatsLoading();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    // A spinner rather than the dull offline layout. Until the first response
    // arrives we do not know the NAS is off, and flashing "your NAS is off" for
    // 200 ms on every open would be a lie that erodes trust in the screen.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Reading your NAS\u2026',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The headline: free space for films.
///
/// Uses `movies.avail_bytes` on the media dataset rather than pool free space,
/// because that is the number that decides whether the next film fits. The
/// Backup pool is labelled as the USB backup disk and never added in — it is a
/// copy of what is already there, not extra room.
class _FilmSpaceHero extends StatelessWidget {
  const _FilmSpaceHero({required this.snapshot});

  final NasSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final movies = snapshot?.movies;
    final main = snapshot?.mainPool;
    final backup = snapshot?.backupPool;
    final freeGb = movies?.headlineFreeGb;
    final usedPct = movies?.usedPct ?? 0;
    final tint = FluidGauge.rampFor(
      // Colour off the pool, not the dataset: 80% is where ZFS write
      // performance degrades, and that is a property of the pool.
      (main?.usedPct ?? usedPct.round()).toDouble(),
    );

    return StatsCard(
      title: 'Free for films',
      trailing: main == null
          ? null
          : StatChip(
              label: main.isHealthy ? 'Healthy' : main.health ?? 'Unknown',
              tone: main.isHealthy ? StatTone.good : StatTone.bad,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Tweened so a copy finishing makes the number travel down
              // rather than blink to a new value.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (freeGb ?? 0).toDouble()),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  freeGb == null ? kUnknown : v.toStringAsFixed(0),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                    height: 1,
                    letterSpacing: -1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'GB',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.text3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FluidBar(fraction: usedPct / 100, color: tint, height: 11),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (main != null)
                StatChip(
                  label: '${main.name ?? 'Storage'} ${main.usedPct ?? 0}% used',
                  tone: main.isCritical
                      ? StatTone.bad
                      : main.isWarning
                          ? StatTone.warn
                          : StatTone.neutral,
                  icon: Icons.movie_outlined,
                ),
              if (backup != null)
                StatChip(
                  label: 'USB backup ${backup.usedPct ?? 0}% used',
                  tone: backup.isHealthy ? StatTone.neutral : StatTone.bad,
                  icon: Icons.usb_rounded,
                ),
            ],
          ),
          // The single most important sentence on the screen. Without it, the
          // free-space number looks wrong for a fortnight after a delete and
          // the whole dashboard loses credibility.
          if (snapshot?.snapshots?.isMeaningful ?? false) ...[
            const SizedBox(height: 12),
            StatsNote(
              text: 'Deleting a film does not free space for 14 days — '
                  'snapshots are currently holding '
                  '${snapshot!.snapshots!.heldGb.toStringAsFixed(1)} GB across '
                  '${snapshot!.snapshots!.countStorage ?? 0} snapshots. This is '
                  'your safety net, not wasted space.',
              icon: Icons.history_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

/// CPU and memory side by side.
class _LoadGauges extends StatelessWidget {
  const _LoadGauges({required this.snapshot});

  final NasSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final cpu = snapshot?.cpu;
    final mem = snapshot?.memory;

    final memColor = switch (mem?.pressure) {
      MemoryPressure.critical => FluidGauge.red,
      MemoryPressure.low => FluidGauge.amber,
      MemoryPressure.ok => FluidGauge.green,
      _ => null,
    };

    return StatsCard(
      title: 'Load',
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Two gauges side by side down to about 320 px, then stacked. A
          // fixed Row would overflow on the narrowest phones.
          final gaugeSize =
              ((constraints.maxWidth - 16) / 2).clamp(96.0, 132.0);
          final stack = constraints.maxWidth < 240;

          final cpuGauge = FluidGauge(
            // Zero rather than null when offline, so the arc visibly sweeps
            // down to empty instead of switching to a dash.
            value: snapshot == null ? 0 : cpu?.pct,
            label: 'CPU',
            size: gaugeSize,
            decimals: cpu?.pct != null && cpu!.pct! < 10 ? 1 : 0,
            subtitle: cpu?.cores == null ? null : '${cpu!.cores} cores',
          );
          final memGauge = FluidGauge(
            value: snapshot == null ? 0 : mem?.usedPct,
            label: 'RAM',
            size: gaugeSize,
            color: memColor,
            subtitle: mem?.availableMb == null
                ? null
                : '${mem!.availableMb} MB free',
          );

          return Column(
            children: [
              if (stack)
                Column(children: [
                  cpuGauge,
                  const SizedBox(height: 12),
                  memGauge,
                ])
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [cpuGauge, memGauge],
                ),
              const SizedBox(height: 14),
              Divider(color: colors.border, height: 1),
              const SizedBox(height: 6),
              StatRow(
                label: 'Load average (1 / 5 / 15 min)',
                value: cpu == null
                    ? kUnknown
                    : '${_load(cpu.load1)} · ${_load(cpu.load5)} · ${_load(cpu.load15)}',
                valueColor: (cpu?.loadPerCore ?? 0) >= 1
                    ? FluidGauge.amber
                    : null,
                icon: Icons.speed_rounded,
              ),
              StatRow(
                label: 'Total memory',
                value: mem?.totalMb == null
                    ? kUnknown
                    : '${(mem!.totalMb! / 1024).toStringAsFixed(1)} GB',
                icon: Icons.memory_rounded,
              ),
              // ARC is not a leak, and it looks like one on any dashboard that
              // does not name it: ZFS deliberately fills spare memory with
              // cache and hands it straight back when something needs it.
              StatRow(
                label: 'ZFS cache (ARC)',
                value: mem?.arcMb == null
                    ? kUnknown
                    : mem!.arcCapMb == null
                        ? '${mem.arcMb} MB'
                        : '${mem.arcMb} / ${mem.arcCapMb} MB',
                icon: Icons.dns_outlined,
              ),
              if (mem?.pressure == MemoryPressure.critical) ...[
                const SizedBox(height: 8),
                const StatsNote(
                  text: 'Memory is very tight. Playback can fail while it is '
                      'this low; a transcode is the usual cause.',
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _load(double? v) => v == null ? kUnknown : v.toStringAsFixed(2);
}

class _PoolsCard extends StatelessWidget {
  const _PoolsCard({required this.snapshot});

  final NasSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final pools = snapshot?.pools ?? const <NasPool>[];

    return StatsCard(
      title: 'Storage pools',
      child: pools.isEmpty
          ? Text(
              snapshot == null
                  ? 'Unavailable while the NAS is off.'
                  : 'No pools reported.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colors.text3,
              ),
            )
          : Column(
              children: [
                for (final (i, p) in pools.indexed) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 12),
                    Divider(color: colors.border, height: 1),
                    const SizedBox(height: 12),
                  ],
                  _PoolRow(pool: p),
                ],
              ],
            ),
    );
  }
}

class _PoolRow extends StatelessWidget {
  const _PoolRow({required this.pool});

  final NasPool pool;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final pct = pool.usedPct ?? 0;
    final tone = pool.isCritical
        ? StatTone.bad
        : pool.isWarning
            ? StatTone.warn
            : StatTone.good;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              pool.isBackup ? Icons.usb_rounded : Icons.storage_rounded,
              size: 15,
              color: colors.text3,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                // Naming Backup for what it is stops it being read as spare
                // capacity for films, which it is not.
                pool.isBackup
                    ? '${pool.name ?? 'Backup'} · USB backup disk'
                    : pool.name ?? 'Pool',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            StatChip(
              label: pool.health ?? 'Unknown',
              tone: pool.isHealthy ? StatTone.good : StatTone.bad,
            ),
          ],
        ),
        const SizedBox(height: 9),
        FluidBar(
          fraction: pct / 100,
          color: toneColor(tone, colors),
          height: 8,
        ),
        const SizedBox(height: 7),
        Text(
          '${formatBytes(pool.usedBytes)} used of '
          '${formatBytes(pool.sizeBytes)} · ${formatBytes(pool.freeBytes)} free',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: colors.text3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (pool.isCritical) ...[
          const SizedBox(height: 8),
          const StatsNote(
            text: 'Past 80% full, ZFS starts fragmenting writes and this pool '
                'gets slower. Worth freeing some space.',
            icon: Icons.warning_amber_rounded,
          ),
        ],
      ],
    );
  }
}

class _DisksCard extends StatelessWidget {
  const _DisksCard({required this.snapshot});

  final NasSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final disks = snapshot?.disks ?? const <NasDisk>[];

    return StatsCard(
      title: 'Disks',
      trailing: disks.isEmpty
          ? null
          : StatChip(
              label: disks.any((d) => d.isFailing)
                  ? 'Attention'
                  : disks.any((d) => d.isHot)
                      ? 'Hot'
                      : 'All well',
              tone: disks.any((d) => d.isFailing)
                  ? StatTone.bad
                  : disks.any((d) => d.isHot)
                      ? StatTone.warn
                      : StatTone.good,
            ),
      child: disks.isEmpty
          ? Text(
              snapshot == null
                  ? 'Unavailable while the NAS is off.'
                  : 'Disk health could not be read just now.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colors.text3,
              ),
            )
          : Column(
              children: [
                for (final d in disks)
                  StatRow(
                    label: '${d.name ?? '?'} · ${d.role ?? 'unknown role'}',
                    value: d.tempC == null ? kUnknown : '${d.tempC}\u00B0C',
                    valueColor: d.isFailing || d.isHot
                        ? FluidGauge.red
                        : d.isWarm
                            ? FluidGauge.amber
                            : null,
                    icon: d.isFailing
                        ? Icons.error_outline_rounded
                        : Icons.album_outlined,
                  ),
                if (disks.any((d) => d.isFailing)) ...[
                  const SizedBox(height: 8),
                  const StatsNote(
                    text: 'A disk is reporting a problem. Neither pool has a '
                        'second copy, so replace it before it fails.',
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
              ],
            ),
    );
  }
}

class _ServicesCard extends StatelessWidget {
  const _ServicesCard({required this.snapshot});

  final NasSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final s = snapshot?.services;

    if (s == null) {
      return StatsCard(
        title: 'Services',
        child: Text(
          snapshot == null
              ? 'Unavailable while the NAS is off.'
              : 'Service state could not be read just now.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: colors.text3,
          ),
        ),
      );
    }

    return StatsCard(
      title: 'Services',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _serviceChip('Jellyfin', s.jellyfin),
          _serviceChip('Nextcloud', s.nextcloud),
          _serviceChip('Caddy', s.caddy),
          _serviceChip('File sharing', s.smb),
          _serviceChip('Instant sync', s.mediaWatch),
          // Not a boolean, and shown as neutral rather than red. Live TV was
          // switched off deliberately; a red chip would read as a fault and get
          // "fixed" by someone starting Threadfin again.
          StatChip(
            label: s.liveTvOffByChoice ? 'Live TV off by choice' : 'Live TV on',
            tone: s.liveTvOffByChoice ? StatTone.neutral : StatTone.info,
            icon: Icons.live_tv_outlined,
          ),
        ],
      ),
    );
  }

  static Widget _serviceChip(String label, bool? up) => StatChip(
        label: label,
        tone: up == null
            ? StatTone.neutral
            : up
                ? StatTone.good
                : StatTone.bad,
        icon: up == null
            ? Icons.help_outline_rounded
            : up
                ? Icons.check_circle_outline_rounded
                : Icons.cancel_outlined,
      );
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.playback});

  final NasPlayback playback;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return StatsCard(
      title: 'Playing now',
      trailing: StatChip(
        label: '${playback.count ?? playback.items.length}',
        tone: StatTone.info,
      ),
      child: Column(
        children: [
          for (final item in playback.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    item.isAtHome ? Icons.home_rounded : Icons.public_rounded,
                    size: 15,
                    color: colors.text3,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title ?? 'Unknown title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Transcoding is called out because this GPU struggles with
                  // HDR to SDR, and it is nearly always the answer to
                  // "why is it stuttering".
                  StatChip(
                    label: item.method ?? 'Playing',
                    tone: item.isTranscoding ? StatTone.warn : StatTone.good,
                  ),
                ],
              ),
            ),
          if (playback.anyTranscoding) ...[
            const SizedBox(height: 8),
            const StatsNote(
              text: 'Something is being transcoded, which is the expensive way '
                  'to play a file and the usual reason CPU is high.',
              icon: Icons.bolt_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.snapshot});

  final NasSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final health = snapshot?.health;
    return StatsCard(
      title: 'System',
      trailing: health == null
          ? null
          : StatChip(
              label: '${health.stagesOk ?? 0}/${health.stagesTotal ?? 16} checks',
              tone: health.allPassing ? StatTone.good : StatTone.warn,
            ),
      child: Column(
        children: [
          StatRow(
            label: 'Uptime',
            value: formatDuration(snapshot?.uptimeS),
            icon: Icons.schedule_rounded,
          ),
          StatRow(
            label: 'TrueNAS version',
            value: snapshot?.version ?? kUnknown,
            icon: Icons.info_outline_rounded,
          ),
          if (health != null && health.failing.isNotEmpty) ...[
            const SizedBox(height: 8),
            StatsNote(
              text: 'Failing checks: ${health.failing.join(', ')}. '
                  'The daily report has the detail.',
              icon: Icons.warning_amber_rounded,
            ),
          ],
        ],
      ),
    );
  }
}
