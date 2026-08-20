import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../nas_stats_controller.dart';
import '../widgets/fluid_gauge.dart';
import '../widgets/stats_chrome.dart';
import 'history_range_switch.dart';
import 'live_sparkline.dart';
import 'stat_metric.dart';

/// Enlarged live chart for one series. Watches the same
/// [nasStatsControllerProvider] as the dashboard — it must not open a second
/// poll, WebSocket, or Dio client.
class StatDetailScreen extends ConsumerStatefulWidget {
  const StatDetailScreen({super.key, required this.metric});

  final StatMetric metric;

  @override
  ConsumerState<StatDetailScreen> createState() => _StatDetailScreenState();
}

class _StatDetailScreenState extends ConsumerState<StatDetailScreen> {
  StatsHistoryRange _range = StatsHistoryRange.now;
  StatsHistoryEnvelope? _history;
  bool _loadingHistory = false;
  Object? _historyError;
  int _historyGen = 0;

  StatMetric get _metric => widget.metric;

  @override
  void didUpdateWidget(covariant StatDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.metric == widget.metric) return;
    _historyGen++;
    _range = StatsHistoryRange.now;
    _history = null;
    _historyError = null;
    _loadingHistory = false;
  }

  Future<void> _loadHistory(StatsHistoryRange range) async {
    if (range == StatsHistoryRange.now) {
      _historyGen++;
      setState(() {
        _range = range;
        _historyError = null;
        _loadingHistory = false;
      });
      return;
    }
    final gen = ++_historyGen;
    setState(() {
      _range = range;
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final env = await ref.read(nasStatsServiceProvider).fetchHistory(
            range,
            metric: _metric,
          );
      if (!mounted || gen != _historyGen) return;
      setState(() {
        _history = env;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted || gen != _historyGen) return;
      setState(() {
        _history = StatsHistoryEnvelope.empty(range);
        _historyError = e;
        _loadingHistory = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final state = ref.watch(nasStatsControllerProvider);
    final latest = state.live.isEmpty ? null : state.live.last.valueOf(_metric);
    final wide = MediaQuery.sizeOf(context).width >= StatMetric.wideBreakpoint;

    final spots = _range == StatsHistoryRange.now
        ? spotsForMetric(state.live, _metric)
        : LiveSparkline.spotsFrom([
            for (final p in _history?.seriesFor(_metric) ?? const <StatsHistoryPoint>[])
              (at: p.at, value: p.value),
          ]);

    final emptyLabel = switch (true) {
      _ when _range == StatsHistoryRange.now =>
        'Collecting live readings\u2026 keep this screen open.',
      _ when _loadingHistory => 'Loading history\u2026',
      _ when _historyError != null =>
        'History could not be loaded. The live view is still running.',
      _ =>
        'Not enough history yet. 7D and 30D fill in while the ${_metric.isNas ? 'NAS' : 'VPS'} stays on — nothing is invented.',
    };

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          StatsHeader(
            title: _metric.title,
            subtitle: _range == StatsHistoryRange.now
                ? 'Live · last 3 minutes'
                : '${_range.label} · ${_metric.hostLabel}',
            live: state.isPolling && !state.isReconnecting,
            ageSeconds: state.envelope.ageS,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Center(
                  child: Hero(
                    tag: _metric.heroTag,
                    child: Material(
                      type: MaterialType.transparency,
                      child: FluidGauge(
                        value: latest,
                        label: _metric.label,
                        size: wide ? 168 : 148,
                        decimals: (latest ?? 100) < 10 ? 1 : 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                HistoryRangeSwitch(
                  value: _range,
                  onChanged: _loadHistory,
                ),
                const SizedBox(height: 16),
                StatsCard(
                  title: _range == StatsHistoryRange.now
                      ? 'Live fluctuation'
                      : '${_range.label} history',
                  child: LiveSparkline(
                    spots: spots,
                    height: wide ? 280 : 220,
                    interactive: true,
                    emptyLabel: emptyLabel,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _range == StatsHistoryRange.now
                      ? 'Fed by the same 1-second poll as the dashboard. Closing this screen does not start a second connection.'
                      : '7D and 30D are 60-second samples kept in memory on the server. They reset if the ${_metric.isNas ? 'NAS' : 'API'} restarts, and they never write a 1-second row to disk.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.text3,
                    height: 1.4,
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
