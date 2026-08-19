import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/nas_stats.dart';
import 'nas_stats_controller.dart';
import 'widgets/fluid_gauge.dart';
import 'widgets/stats_chrome.dart';

/// Live VPS dashboard.
///
/// Two structural points, and they pull in opposite directions.
///
/// **A switched-off NAS barely affects this screen.** CPU, memory, disk, load
/// and uptime are measured by the API process itself, on the VPS, and the
/// machine that answered the request is self-evidently running. So a NAS that is
/// off costs this screen only the handful of fields that genuinely cannot be
/// measured from inside a container: steal, throttling, the container count and
/// Hostinger's own view of the machine, all of which arrive via the NAS from
/// `vps-watch.py`. Those are also the fields that go stale, because that script
/// samples every five minutes; past fifteen the screen says so rather than
/// presenting old figures as current, and it never substitutes zero for a
/// reading it does not have.
///
/// **A switched-off VPS is the hard case, and cannot be reported by the VPS.**
/// The API that would say "this machine is stopped" is running *on* the machine,
/// so when it stops there is nothing left to say it. The only symptom is
/// silence, and silence is also what a phone in a lift produces. There is no
/// honest way to close that gap from here — the one credential that could ask
/// Hostinger directly is an account-wide token that can stop, rebuild and
/// re-firewall the machine and rewrite DNS, and it deliberately never leaves the
/// NAS, let alone reaches a phone that can be lost.
///
/// So the screen does the next best thing: it checks the handset's own
/// connectivity, and if the phone plainly has a network then the silence is at
/// the far end. That earns the dull stopped-looking treatment the owner asked
/// for, worded as "not responding — it may be stopped" rather than a flat
/// assertion, because a running host with a dead API container looks identical
/// from here. The last known figures stay on screen, dimmed and timestamped,
/// which is more use than a blank page.
class VpsStatsScreen extends ConsumerWidget {
  const VpsStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final state = ref.watch(nasStatsControllerProvider);
    final controller = ref.read(nasStatsControllerProvider.notifier);
    final vps = state.vps;

    // Unreachable only when the *phone* cannot reach the API. A VPS that
    // answered is up, whatever the NAS is doing.
    final unreachable = state.vpsUnreachable || vps == null;
    final probablyStopped = state.vpsProbablyStopped;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          StatsHeader(
            title: 'VPS',
            subtitle: switch (true) {
              _ when probablyStopped => 'Not responding',
              _ when unreachable => 'Not connected',
              _ => 'Up ${formatDuration(vps.uptimeS)}',
            },
            live: !unreachable && state.isPolling && !state.isReconnecting,
            ageSeconds: state.envelope.ageS,
          ),
          Expanded(
            child: !state.hasLoaded
                ? const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.accent,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refreshNow,
                    color: AppColors.accent,
                    backgroundColor: colors.bg2,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        if (state.vpsUnreachable) ...[
                          _VpsUnreachableBanner(
                            phoneOffline: state.phoneOffline,
                            lastSeen: state.lastSuccessAt,
                            lastState: vps?.state,
                            onRetry: controller.refreshNow,
                          ),
                          const SizedBox(height: 14),
                        ],
                        // The subscription sits outside the shroud on purpose.
                        // A renewal date is exactly what the owner wants when
                        // the machine has gone quiet — "did I forget to pay for
                        // it?" is the first question — and unlike a CPU reading
                        // it does not become a lie by being a few hours old.
                        if (vps?.billing case final b? when !b.isEmpty) ...[
                          _VpsSubscriptionCard(
                            billing: b,
                            planName: vps?.planName,
                            vcpus: vps?.vcpus,
                            ramMb: vps?.planRamMb,
                            diskMb: vps?.planDiskMb,
                          ),
                          const SizedBox(height: 14),
                        ],
                        StatsOfflineShroud(
                          offline: unreachable,
                          child: Column(
                            children: [
                              if ((vps?.throttled ?? false) &&
                                  !unreachable) ...[
                                const _ThrottleWarning(),
                                const SizedBox(height: 14),
                              ],
                              _VpsResourcesCard(
                                vps: vps,
                                offline: unreachable,
                              ),
                              const SizedBox(height: 14),
                              _VpsLoadCard(vps: vps, offline: unreachable),
                              const SizedBox(height: 14),
                              _VpsPlatformCard(
                                vps: vps,
                                nasOnline: state.isOnline,
                                offline: unreachable,
                              ),
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
}

/// The one thing on this screen that has to be worded very carefully.
///
/// It is tempting to say "your VPS is off", and it would be wrong: the same
/// silence is produced by a stopped machine, a crashed API container on a
/// perfectly healthy machine, an expired certificate, and a phone with one bar.
/// So the banner states the fact it actually has — nothing answered — and then
/// names the most likely cause for the situation it can distinguish, with the
/// last time it did answer as the anchor.
class _VpsUnreachableBanner extends StatelessWidget {
  const _VpsUnreachableBanner({
    required this.phoneOffline,
    required this.lastSeen,
    required this.lastState,
    required this.onRetry,
  });

  final bool? phoneOffline;
  final DateTime? lastSeen;
  final String? lastState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // A phone with no signal is not a server fault, and must not be dressed as
    // one — the owner would go and check a machine that was never broken.
    if (phoneOffline == true) {
      return StatsOfflineBanner(
        title: 'This phone is offline',
        message: 'There is no network connection, so the VPS cannot be reached. '
            'Nothing here says anything about the server itself.',
        lastSeen: lastSeen,
        isFault: false,
        onRetry: onRetry,
      );
    }

    if (phoneOffline == false) {
      return StatsOfflineBanner(
        title: 'The VPS is not responding',
        message: 'This phone has a connection, so the silence is at the other '
            'end: the machine is most likely stopped. It could also be running '
            'with its API container down. Check it at hpanel.hostinger.com — '
            'nothing on the phone can start it, and nothing here has tried.',
        lastSeen: lastSeen,
        isFault: true,
        onRetry: onRetry,
      );
    }

    return StatsOfflineBanner(
      title: 'Can\'t reach the VPS',
      message: 'Either the machine is stopped or this phone has no usable '
          'connection — there is not enough information here to say which.',
      lastSeen: lastSeen,
      isFault: true,
      onRetry: onRetry,
    );
  }
}

/// The loudest thing on this screen, and deliberately so.
///
/// On 15 August the VPS was throttled and then stopped by Hostinger's abuse
/// system one second apart, and remote access was gone for 9h44m before anyone
/// noticed. Throttling is the early warning for exactly that, so it gets a red
/// banner at the top rather than a chip somewhere in a list.
class _ThrottleWarning extends StatelessWidget {
  const _ThrottleWarning();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    const red = FluidGauge.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: red, size: 22),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hostinger is throttling this VPS',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: red,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sustained high CPU has triggered a limit. If it continues, '
                  'the machine can be stopped — which takes the websites and '
                  'remote access with it.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: colors.text3,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CPU, RAM and disk as three arcs, deliberately the same vocabulary the NAS
/// screen uses.
///
/// The previous version drew memory and disk as horizontal bars, which made the
/// two screens read as different products for no reason: the same question
/// ("how full is it?") answered in two visual languages. Three gauges also make
/// the comparison the owner actually makes — is it CPU or memory that is tight —
/// possible at a glance instead of by scrolling between a ring and a bar.
///
/// The width arithmetic exists because three gauges do not fit on a 320 px
/// phone. Rather than a fixed Row that overflows, it decides how many fit and
/// lets Wrap place the remainder, so the layout degrades to 2+1 and then to a
/// single column instead of throwing.
class _VpsResourcesCard extends StatelessWidget {
  const _VpsResourcesCard({required this.vps, required this.offline});

  final VpsLive? vps;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final v = vps;

    return StatsCard(
      title: 'Resources',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final w = constraints.maxWidth;
          final perRow = w >= 3 * 92 + 2 * gap ? 3 : (w >= 2 * 92 + gap ? 2 : 1);
          final size =
              ((w - (perRow - 1) * gap) / perRow).clamp(88.0, 130.0);

          // Zero rather than null when offline, so the arcs visibly sweep down
          // to empty — the dull, everything-at-zero treatment — instead of
          // quietly switching to dashes, which reads as a rendering bug.
          double? val(double? x) => offline ? 0 : x;

          return Wrap(
            alignment: WrapAlignment.center,
            spacing: gap,
            runSpacing: gap,
            children: [
              FluidGauge(
                value: val(v?.cpuPct),
                label: 'CPU',
                size: size,
                decimals: (v?.cpuPct ?? 100) < 10 ? 1 : 0,
                subtitle: v?.cores == null ? null : '${v!.cores} vCPU',
              ),
              FluidGauge(
                value: val(v?.memPct),
                label: 'RAM',
                size: size,
                decimals: 1,
                subtitle: v?.memTotalGb == null
                    ? null
                    : '${formatGb(v!.memFreeGb)} free',
              ),
              FluidGauge(
                value: val(v?.diskPct),
                label: 'DISK',
                size: size,
                decimals: 1,
                subtitle: v?.diskTotalGb == null
                    ? null
                    : '${formatGb(v!.diskFreeGb)} free',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VpsLoadCard extends StatelessWidget {
  const _VpsLoadCard({required this.vps, required this.offline});

  final VpsLive? vps;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final v = vps;

    return StatsCard(
      title: 'Load and steal',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = (constraints.maxWidth / 2 - 8).clamp(96.0, 132.0);

          // Steal keeps a gauge of its own rather than becoming a row, because
          // it is the single most diagnostic number here: high steal means the
          // host is taking processor time away, which no amount of local tuning
          // will fix. It is the shape the 15 August incident had.
          final steal = FluidGauge(
            value: offline ? 0 : v?.stealPct,
            label: 'STEAL',
            size: size,
            color: (v?.stealIsHigh ?? false) ? FluidGauge.red : null,
            decimals: 1,
            subtitle: v?.stealPct == null ? 'via NAS' : null,
          );

          return Column(
            children: [
              steal,
              const SizedBox(height: 14),
              Divider(color: colors.border, height: 1),
              const SizedBox(height: 6),
              StatRow(
                label: 'Load average (1 / 5 / 15 min)',
                value: v == null || offline
                    ? kUnknown
                    : '${_n(v.load1)} · ${_n(v.load5)} · ${_n(v.load15)}',
                icon: Icons.speed_rounded,
              ),
              StatRow(
                label: 'Uptime',
                value: offline ? kUnknown : formatDuration(v?.uptimeS),
                icon: Icons.schedule_rounded,
              ),
              if ((v?.stealIsHigh ?? false) && !offline) ...[
                const SizedBox(height: 8),
                const StatsNote(
                  text: 'Steal above 20% means the host is holding this machine '
                      'back. This is not something the server can fix itself.',
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _n(double? v) => v == null ? kUnknown : v.toStringAsFixed(2);
}

/// When the machine renews, and what it costs.
///
/// The whole reason this card is careful rather than a date in a row: Hostinger
/// reports the date in one of two mutually exclusive fields depending on
/// auto-renewal, and the two mean opposite things. "Renews on 18 September" is
/// reassurance. "Expires on 18 September" is a deadline. `vps-watch.py` resolves
/// which it is and sends the verb along with the date, and this card renders that
/// verb rather than picking its own — so the only way to show the wrong word is
/// to change the resolver, which has a self-test pinning it.
class _VpsSubscriptionCard extends StatelessWidget {
  const _VpsSubscriptionCard({
    required this.billing,
    required this.planName,
    required this.vcpus,
    required this.ramMb,
    required this.diskMb,
  });

  final VpsBilling billing;
  final String? planName;
  final int? vcpus;
  final int? ramMb;
  final int? diskMb;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final sub = billing.vps;
    final attention = sub?.needsAttention ?? false;
    final tone = attention ? FluidGauge.amber : AppColors.accent;

    return StatsCard(
      title: 'Subscription',
      trailing: sub?.status == null
          ? null
          : StatChip(
              label: sub!.status!.replaceAll('_', ' '),
              tone: switch (sub.status) {
                'active' => StatTone.good,
                'non_renewing' || 'pending' => StatTone.warn,
                _ => StatTone.bad,
              },
              icon: Icons.receipt_long_outlined,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sub?.verb case final verb?) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  sub!.isExpiring
                      ? Icons.event_busy_outlined
                      : Icons.autorenew_rounded,
                  color: tone,
                  size: 26,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$verb ${_date(sub.dueLocal)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: colors.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (sub.daysLeft case final d?)
                        Text(
                          _relative(d, sub.isExpiring),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: attention ? tone : colors.text3,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: 6),
          ],
          StatRow(
            label: 'Plan',
            value: planName ?? sub?.name ?? kUnknown,
            icon: Icons.dns_outlined,
          ),
          if (_spec() case final spec?)
            StatRow(
              label: 'Allocated',
              value: spec,
              icon: Icons.memory_outlined,
            ),
          if (sub?.priceLabel case final price?)
            StatRow(
              label: sub!.isExpiring ? 'Renewal price' : 'Billed',
              value: price,
              icon: Icons.payments_outlined,
            ),
          if (sub?.autoRenew case final auto?)
            StatRow(
              label: 'Auto-renew',
              value: auto ? 'On' : 'Off',
              valueColor: auto ? null : FluidGauge.amber,
              icon: auto ? Icons.check_circle_outline : Icons.cancel_outlined,
            ),
          // The domain, because monishlabs.com lapsing would take the site, the
          // cloud and this very API down as completely as the machine stopping,
          // and nothing else in the system watches for it.
          for (final other in billing.others)
            if (other.verb case final v?)
              StatRow(
                label: other.name ?? 'Other subscription',
                value: '$v ${_date(other.dueLocal)}',
                valueColor: other.needsAttention ? FluidGauge.amber : null,
                icon: Icons.language_outlined,
              ),
          const SizedBox(height: 10),
          if (billing.error case final err?)
            StatsNote(
              text: 'The last billing lookup failed ($err), so this may be out '
                  'of date. It is retried twice a day.',
              icon: Icons.error_outline_rounded,
            )
          else if (billing.fromCache)
            StatsNote(
              // Honest about provenance: this is a remembered answer, not a
              // fresh one, because the NAS that relays it is off.
              text: 'Remembered from ${formatAgo(billing.ageS)} — your NAS '
                  'relays this and is currently off. Renewal dates move once a '
                  'month, so it is almost certainly still right.',
              icon: Icons.history_rounded,
            )
          else if (sub == null)
            const StatsNote(
              text: 'No subscription for this machine was found on the account.',
              icon: Icons.help_outline_rounded,
            )
          else
            StatsNote(
              text: 'Checked ${formatAgo(billing.ageS)}. Billing is read twice a '
                  'day, not continuously.',
              icon: Icons.info_outline_rounded,
            ),
        ],
      ),
    );
  }

  /// What Hostinger says is allocated, which is a different claim from what the
  /// machine currently reports and is shown next to the plan for that reason.
  String? _spec() {
    final parts = <String>[
      if (vcpus != null) '$vcpus vCPU',
      if (ramMb != null) '${_gb(ramMb!)} RAM',
      if (diskMb != null) '${_gb(diskMb!)} disk',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _gb(int mb) {
    final gb = mb / 1024;
    return gb >= 10 || gb == gb.roundToDouble()
        ? '${gb.round()} GB'
        : '${gb.toStringAsFixed(1)} GB';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime? d) =>
      d == null ? kUnknown : '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// Reads as a sentence rather than a number, and never says "in -3 days".
  static String _relative(int days, bool expiring) {
    if (days < 0) {
      final n = -days;
      return expiring
          ? '$n ${_plural(n, 'day')} overdue'
          : 'the date passed $n ${_plural(n, 'day')} ago';
    }
    if (days == 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  static String _plural(int n, String word) => n == 1 ? word : '${word}s';
}

class _VpsPlatformCard extends StatelessWidget {
  const _VpsPlatformCard({
    required this.vps,
    required this.nasOnline,
    required this.offline,
  });

  final VpsLive? vps;
  final bool nasOnline;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final v = vps;
    final stale = v?.stale ?? false;

    return StatsCard(
      title: 'Platform',
      trailing: offline
          // The state chip must not keep saying "running" over a screen that
          // has just explained the machine is not answering.
          ? const StatChip(
              label: 'not responding',
              tone: StatTone.bad,
              icon: Icons.cloud_off_outlined,
            )
          : v?.state == null
              ? null
              : StatChip(
                  label: v!.state!,
                  tone: v.state == 'running' ? StatTone.good : StatTone.warn,
                  icon: Icons.cloud_outlined,
                ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatRow(
            label: 'Containers running',
            value: v?.containers == null
                ? kUnknown
                : '${v!.running ?? 0} of ${v.containers}',
            valueColor:
                (v?.containersDegraded ?? false) ? FluidGauge.amber : null,
            icon: Icons.widgets_outlined,
          ),
          StatRow(
            label: 'Reported by',
            // Being explicit about provenance matters here: "running" inferred
            // from our own probes is a different claim from Hostinger saying so,
            // and the screen should not blur the two.
            value: switch (v?.stateFrom) {
              'hostinger' => 'Hostinger API',
              'probe' => 'Our own probes',
              _ => kUnknown,
            },
            icon: Icons.verified_outlined,
          ),
          if ((v?.conditions ?? const []).isNotEmpty)
            StatRow(
              label: 'Conditions',
              value: v!.conditions.join(', '),
              valueColor: FluidGauge.amber,
              icon: Icons.report_problem_outlined,
            ),
          const SizedBox(height: 10),
          if (offline)
            const StatsNote(
              text: 'These are the last figures received. Nothing here is '
                  'live while the VPS is not answering.',
              icon: Icons.pause_circle_outline_rounded,
            )
          else if (!nasOnline)
            const StatsNote(
              // The honest explanation for why part of this card is blank.
              text: 'Steal, throttling and the container count come from your '
                  'NAS, which is currently off. Everything above is measured on '
                  'the VPS itself and is live.',
              icon: Icons.link_off_rounded,
            )
          else if (stale)
            StatsNote(
              text: 'These platform figures are ${formatAgo(v?.ageS)} — they '
                  'are collected every five minutes, not continuously.',
              icon: Icons.update_rounded,
            )
          else
            StatsNote(
              text: 'Platform figures refresh every five minutes '
                  '(${formatAgo(v?.ageS)}). CPU, memory and disk above are live.',
              icon: Icons.info_outline_rounded,
            ),
          if (v?.containersDegraded ?? false) ...[
            const SizedBox(height: 8),
            Text(
              'Some containers are not running.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: FluidGauge.amber,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
