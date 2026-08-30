import 'package:intl/intl.dart';

import 'stat_metric.dart';

/// Axis / tooltip labels for the enlarged live chart.
///
/// Compact dashboard sparklines stay unlabeled. Now is clock time, 7D is
/// weekday + hour, 30D is calendar day — so a month of samples is readable
/// without crowding the 1-second view.
String formatChartAxisLabel(DateTime at, StatsHistoryRange range) {
  final d = at.toLocal();
  switch (range) {
    case StatsHistoryRange.now:
      return DateFormat('HH:mm:ss').format(d);
    case StatsHistoryRange.d7:
      return DateFormat('E HH:mm').format(d);
    case StatsHistoryRange.d30:
      return DateFormat('d MMM').format(d);
  }
}

/// First sample that can actually be plotted. Must match [LiveSparkline.spotsFrom]
/// so tooltip/axis times line up with x=0.
DateTime? firstDatedAt(Iterable<({DateTime at, double? value})> samples) {
  DateTime? earliest;
  for (final s in samples) {
    final v = s.value;
    if (v == null || !v.isFinite) continue;
    if (earliest == null || s.at.isBefore(earliest)) earliest = s.at;
  }
  return earliest;
}

/// Evenly spaced x values between the first and last sample, in the same
/// "seconds from origin" units [LiveSparkline] plots.
List<double> chartAxisTicks(double minX, double maxX, {int count = 4}) {
  if (!minX.isFinite || !maxX.isFinite) return const [];
  if (maxX <= minX) return [minX];
  final n = count < 2 ? 2 : count;
  return [
    for (var i = 0; i < n; i++) minX + (maxX - minX) * i / (n - 1),
  ];
}
