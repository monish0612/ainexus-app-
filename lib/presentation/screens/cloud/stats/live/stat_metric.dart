import 'package:flutter/foundation.dart';

import '../../../../../domain/entities/nas_stats.dart';

/// One tappable series on the Stats dashboard.
///
/// Kept as a closed set so a new gauge cannot ship without a Hero tag, a
/// history field, and a detail title — the three things the enlarged view
/// needs to stay honest.
enum StatMetric {
  nasCpu,
  nasRam,
  nasDisk,
  vpsCpu,
  vpsRam,
  vpsDisk,
  vpsSteal;

  String get heroTag => 'stat-$name';

  String get label => switch (this) {
        nasCpu || vpsCpu => 'CPU',
        nasRam || vpsRam => 'RAM',
        nasDisk || vpsDisk => 'DISK',
        vpsSteal => 'STEAL',
      };

  String get hostLabel => switch (this) {
        nasCpu || nasRam || nasDisk => 'NAS',
        vpsCpu || vpsRam || vpsDisk || vpsSteal => 'VPS',
      };

  String get title => '$hostLabel $label';

  bool get isNas => switch (this) {
        nasCpu || nasRam || nasDisk => true,
        vpsCpu || vpsRam || vpsDisk || vpsSteal => false,
      };

  /// Below this width the compact dashboard only shows gauges; tap opens the
  /// enlarged live chart. At or above it, a sparkline sits under the gauges
  /// as well. One widget set, not a phone fork and a tablet fork.
  static const double wideBreakpoint = 720;
}

/// Now / 7D / 30D. "Now" is always the phone's rolling 1-second window from
/// the existing `/cloud/stats` poll. 7D and 30D are fetched on demand from
/// `/cloud/stats/history` and degrade to empty when that route or the NAS
/// rings have nothing yet — they never invent a line.
enum StatsHistoryRange {
  now,
  d7,
  d30;

  String get query => switch (this) {
        now => 'now',
        d7 => '7d',
        d30 => '30d',
      };

  String get label => switch (this) {
        now => 'Now',
        d7 => '7D',
        d30 => '30D',
      };
}

@immutable
class LiveStatSample {
  const LiveStatSample({
    required this.at,
    this.nasCpu,
    this.nasRam,
    this.nasDisk,
    this.vpsCpu,
    this.vpsRam,
    this.vpsDisk,
    this.vpsSteal,
  });

  final DateTime at;
  final double? nasCpu;
  final double? nasRam;
  final double? nasDisk;
  final double? vpsCpu;
  final double? vpsRam;
  final double? vpsDisk;
  final double? vpsSteal;

  factory LiveStatSample.fromEnvelope(NasStatsEnvelope env, DateTime at) {
    final snap = env.snapshot;
    final vps = env.vpsLive;
    // Offline NAS gauges are fed zero so they sweep down; the live chart has
    // to agree or tapping through would show a line that contradicts the ring.
    final nasOn = env.online;
    return LiveStatSample(
      at: at,
      nasCpu: nasOn ? snap?.cpu?.pct : 0,
      nasRam: nasOn ? snap?.memory?.usedPct : 0,
      nasDisk: nasOn
          ? (snap?.mainPool?.usedPct?.toDouble() ?? snap?.movies?.usedPct)
          : 0,
      vpsCpu: vps?.cpuPct,
      vpsRam: vps?.memPct,
      vpsDisk: vps?.diskPct,
      vpsSteal: vps?.stealPct,
    );
  }

  double? valueOf(StatMetric metric) => switch (metric) {
        StatMetric.nasCpu => nasCpu,
        StatMetric.nasRam => nasRam,
        StatMetric.nasDisk => nasDisk,
        StatMetric.vpsCpu => vpsCpu,
        StatMetric.vpsRam => vpsRam,
        StatMetric.vpsDisk => vpsDisk,
        StatMetric.vpsSteal => vpsSteal,
      };
}

@immutable
class StatsHistoryPoint {
  const StatsHistoryPoint({required this.at, this.value});

  final DateTime at;
  final double? value;

  factory StatsHistoryPoint.fromJson(Map<String, dynamic> m, StatMetric metric) {
    final t = m['t'];
    final epoch = t is num ? t.round() : int.tryParse('$t') ?? 0;
    final key = switch (metric) {
      StatMetric.vpsSteal => 'steal',
      StatMetric.nasCpu || StatMetric.vpsCpu => 'cpu',
      StatMetric.nasRam || StatMetric.vpsRam => 'mem',
      StatMetric.nasDisk || StatMetric.vpsDisk => 'disk',
    };
    final raw = m[key];
    return StatsHistoryPoint(
      at: DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true),
      value: raw is num ? raw.toDouble() : double.tryParse('$raw'),
    );
  }
}

@immutable
class StatsHistoryEnvelope {
  const StatsHistoryEnvelope({
    required this.range,
    this.nas = const [],
    this.vps = const [],
    this.nasOnline = false,
  });

  final StatsHistoryRange range;
  final List<StatsHistoryPoint> nas;
  final List<StatsHistoryPoint> vps;
  final bool nasOnline;

  factory StatsHistoryEnvelope.empty(StatsHistoryRange range) =>
      StatsHistoryEnvelope(range: range);

  factory StatsHistoryEnvelope.fromJson(
    Map<String, dynamic> m,
    StatMetric metric,
  ) {
    final range = switch (m['range']?.toString()) {
      '7d' => StatsHistoryRange.d7,
      '30d' => StatsHistoryRange.d30,
      _ => StatsHistoryRange.now,
    };
    List<StatsHistoryPoint> parse(Object? raw) {
      if (raw is! List) return const [];
      final out = <StatsHistoryPoint>[];
      for (final e in raw) {
        if (e is Map) {
          out.add(StatsHistoryPoint.fromJson(Map<String, dynamic>.from(e), metric));
        }
      }
      return out;
    }

    final nasBlock = m['nas'];
    final vpsBlock = m['vps'];
    return StatsHistoryEnvelope(
      range: range,
      nasOnline: nasBlock is Map && nasBlock['online'] == true,
      nas: parse(nasBlock is Map ? nasBlock['points'] : null),
      vps: parse(vpsBlock is Map ? vpsBlock['points'] : null),
    );
  }

  List<StatsHistoryPoint> seriesFor(StatMetric metric) =>
      metric.isNas ? nas : vps;
}

/// Rolling window of 1-second samples. Pure so the trim rules can be tested
/// without a widget or a clock.
List<LiveStatSample> appendLiveSample(
  List<LiveStatSample> prev,
  LiveStatSample next, {
  Duration window = const Duration(minutes: 3),
  int cap = 180,
}) {
  final cut = next.at.subtract(window);
  final kept = <LiveStatSample>[
    for (final p in prev)
      if (p.at.isAfter(cut) || p.at.isAtSameMomentAs(cut)) p,
    next,
  ];
  if (kept.length <= cap) return List<LiveStatSample>.unmodifiable(kept);
  return List<LiveStatSample>.unmodifiable(kept.sublist(kept.length - cap));
}
