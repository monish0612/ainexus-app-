import 'price_models.dart';

enum HistoryRange {
  week,
  month,
  quarter,
  all;

  String get label {
    switch (this) {
      case HistoryRange.week:
        return '1W';
      case HistoryRange.month:
        return '1M';
      case HistoryRange.quarter:
        return '3M';
      case HistoryRange.all:
        return 'All';
    }
  }

  Duration? get window {
    switch (this) {
      case HistoryRange.week:
        return const Duration(days: 7);
      case HistoryRange.month:
        return const Duration(days: 30);
      case HistoryRange.quarter:
        return const Duration(days: 90);
      case HistoryRange.all:
        return null;
    }
  }
}

/// Pure graph input. Stats always use raw in-range points; [points] is the
/// downsampled polyline (LTTB, ~220 verts).
class HistorySeries {
  const HistorySeries({
    required this.points,
    required this.raw,
    required this.rawCount,
    this.min,
    this.max,
    this.avg,
    this.first,
    this.last,
    this.firstAt,
    this.lastAt,
  });

  final List<WatchPricePoint> points;
  final List<WatchPricePoint> raw;
  final int rawCount;
  final double? min;
  final double? max;
  final double? avg;
  final double? first;
  final double? last;
  final DateTime? firstAt;
  final DateTime? lastAt;

  bool get hasEnoughForLine => rawCount >= 2;
  bool get isEmpty => rawCount == 0;
  bool get isSingle => rawCount == 1;

  String get identity {
    final lastId = raw.isEmpty ? '' : raw.last.id;
    return '$rawCount:${firstAt?.millisecondsSinceEpoch}:$lastId';
  }

  /// Hide a chip when that window cannot draw a line.
  static bool rangeEnabled(
    List<WatchPricePoint> all,
    HistoryRange range, {
    DateTime? now,
  }) {
    return slice(all, range, now: now).length >= 2 || range == HistoryRange.all;
  }

  static List<WatchPricePoint> slice(
    List<WatchPricePoint> all,
    HistoryRange range, {
    DateTime? now,
  }) {
    final sorted = [...all]..sort((a, b) => a.checkedAt.compareTo(b.checkedAt));
    final window = range.window;
    if (window == null) return sorted;
    final end = now ?? DateTime.now().toUtc();
    final start = end.subtract(window);
    return [
      for (final p in sorted)
        if (!p.checkedAt.toUtc().isBefore(start)) p,
    ];
  }

  factory HistorySeries.of(
    List<WatchPricePoint> all, {
    HistoryRange range = HistoryRange.all,
    int maxDraw = 220,
    DateTime? now,
  }) {
    final raw = slice(all, range, now: now);
    if (raw.isEmpty) {
      return const HistorySeries(points: [], raw: [], rawCount: 0);
    }
    var min = raw.first.price;
    var max = raw.first.price;
    var sum = 0.0;
    for (final p in raw) {
      if (p.price < min) min = p.price;
      if (p.price > max) max = p.price;
      sum += p.price;
    }
    return HistorySeries(
      points: downsampleLttb(raw, maxDraw),
      raw: raw,
      rawCount: raw.length,
      min: min,
      max: max,
      avg: sum / raw.length,
      first: raw.first.price,
      last: raw.last.price,
      firstAt: raw.first.checkedAt,
      lastAt: raw.last.checkedAt,
    );
  }

  WatchPricePoint? nearestRaw(double xMillis) {
    if (raw.isEmpty) return null;
    WatchPricePoint best = raw.first;
    var bestDist = (best.checkedAt.millisecondsSinceEpoch - xMillis).abs();
    for (final p in raw) {
      final d = (p.checkedAt.millisecondsSinceEpoch - xMillis).abs();
      if (d < bestDist) {
        best = p;
        bestDist = d;
      }
    }
    return best;
  }

  /// Expand Y so a target / base line off the series still fits, plus 8%.
  (double, double) yBounds({double? target, double? base}) {
    final values = <double>[
      if (min != null) min!,
      if (max != null) max!,
      if (target != null && target > 0) target,
      if (base != null && base > 0) base,
    ];
    if (values.isEmpty) return (0, 1);
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (lo == hi) {
      lo = lo * 0.94;
      hi = hi * 1.06;
      if (lo == hi) {
        lo = 0;
        hi = hi + 1;
      }
    } else {
      final pad = (hi - lo) * 0.08;
      lo -= pad;
      hi += pad;
    }
    if (lo < 0) lo = 0;
    return (lo, hi);
  }
}

/// Largest-Triangle-Three-Buckets. First and last points are always kept.
List<WatchPricePoint> downsampleLttb(List<WatchPricePoint> data, int threshold) {
  if (data.length <= threshold || threshold < 3) return data;
  final sampled = <WatchPricePoint>[data.first];
  final bucketSize = (data.length - 2) / (threshold - 2);
  var a = 0;
  for (var i = 0; i < threshold - 2; i++) {
    final avgRangeStart = ((i + 1) * bucketSize).floor() + 1;
    var avgRangeEnd = ((i + 2) * bucketSize).floor() + 1;
    if (avgRangeEnd > data.length) avgRangeEnd = data.length;
    var avgX = 0.0;
    var avgY = 0.0;
    final avgRangeLength = avgRangeEnd - avgRangeStart;
    for (var j = avgRangeStart; j < avgRangeEnd; j++) {
      avgX += data[j].checkedAt.millisecondsSinceEpoch.toDouble();
      avgY += data[j].price;
    }
    if (avgRangeLength > 0) {
      avgX /= avgRangeLength;
      avgY /= avgRangeLength;
    }
    final rangeOffs = (i * bucketSize).floor() + 1;
    var rangeTo = ((i + 1) * bucketSize).floor() + 1;
    if (rangeTo > data.length - 1) rangeTo = data.length - 1;
    final pointAx = data[a].checkedAt.millisecondsSinceEpoch.toDouble();
    final pointAy = data[a].price;
    var maxArea = -1.0;
    var nextA = rangeOffs;
    for (var j = rangeOffs; j < rangeTo; j++) {
      final area = ((pointAx - avgX) * (data[j].price - pointAy) -
              (pointAx - data[j].checkedAt.millisecondsSinceEpoch) *
                  (avgY - pointAy))
          .abs();
      if (area > maxArea) {
        maxArea = area;
        nextA = j;
      }
    }
    sampled.add(data[nextA]);
    a = nextA;
  }
  sampled.add(data.last);
  return sampled;
}
