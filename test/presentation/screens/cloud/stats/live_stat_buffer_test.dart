import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/nas_stats.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/live/chart_time.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/live/live_sparkline.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/live/stat_metric.dart';

void main() {
  test('appendLiveSample drops points older than the window and caps length', () {
    final t0 = DateTime.utc(2026, 8, 20, 10);
    final first = LiveStatSample(at: t0, nasCpu: 10);
    var buf = appendLiveSample(const [], first);

    buf = appendLiveSample(
      buf,
      LiveStatSample(at: t0.add(const Duration(seconds: 30)), nasCpu: 20),
    );
    expect(buf.length, 2);

    buf = appendLiveSample(
      buf,
      LiveStatSample(at: t0.add(const Duration(minutes: 4)), nasCpu: 30),
      window: const Duration(minutes: 3),
    );
    expect(buf.length, 1);
    expect(buf.single.nasCpu, 30);

    var many = <LiveStatSample>[];
    for (var i = 0; i < 200; i++) {
      many = appendLiveSample(
        many,
        LiveStatSample(at: t0.add(Duration(seconds: i)), nasCpu: i.toDouble()),
        cap: 180,
      );
    }
    expect(many.length, 180);
    expect(many.first.nasCpu, 20);
    expect(many.last.nasCpu, 199);
  });

  test('two samples in the same second replace rather than twin', () {
    final t0 = DateTime.utc(2026, 8, 20, 10);
    var buf = appendLiveSample(const [], LiveStatSample(at: t0, nasCpu: 10));
    buf = appendLiveSample(
      buf,
      LiveStatSample(at: t0.add(const Duration(milliseconds: 200)), nasCpu: 22),
    );
    expect(buf.length, 1);
    expect(buf.single.nasCpu, 22);
  });

  test('downsample keeps the ends and stays under the cap', () {
    final spots = [
      for (var i = 0; i < 180; i++) FlSpot(i.toDouble(), i / 2),
    ];
    final out = LiveSparkline.downsample(spots, max: 60);
    expect(out.length, lessThanOrEqualTo(60));
    expect(out.first.x, 0);
    expect(out.last.x, 179);
  });

  test('offline envelope records NAS zeros so the chart matches the gauges', () {
    const env = NasStatsEnvelope(online: false);
    final s = LiveStatSample.fromEnvelope(env, DateTime.utc(2026, 8, 20));
    expect(s.nasCpu, 0);
    expect(s.nasRam, 0);
    expect(s.nasDisk, 0);
  });

  test('chart axis labels: Now is clock, 7D weekday+hour, 30D calendar day', () {
    final at = DateTime(2026, 8, 30, 17, 16, 13);
    expect(formatChartAxisLabel(at, StatsHistoryRange.now), '17:16:13');
    expect(formatChartAxisLabel(at, StatsHistoryRange.d7), contains('17:16'));
    expect(formatChartAxisLabel(at, StatsHistoryRange.d30), contains('Aug'));
    expect(formatChartAxisLabel(at, StatsHistoryRange.d30), contains('30'));
  });

  test('chartAxisTicks spaces four labels from first to last sample', () {
    expect(chartAxisTicks(0, 90), [0, 30, 60, 90]);
    expect(chartAxisTicks(5, 5), [5]);
    expect(chartAxisTicks(double.nan, 10), isEmpty);
    expect(chartAxisTicks(0, double.infinity), isEmpty);
    expect(chartAxisTicks(-10, 20, count: 1).length, 2);
  });

  test('spotsFrom drops null/NaN, sorts time, and origin is the first dated', () {
    final t0 = DateTime(2026, 8, 30, 12);
    final samples = [
      (at: t0.add(const Duration(seconds: 30)), value: 40.0),
      (at: t0, value: null),
      (at: t0.add(const Duration(seconds: 10)), value: double.nan),
      (at: t0.add(const Duration(seconds: 20)), value: 10.0),
      (at: t0.add(const Duration(seconds: 40)), value: double.infinity),
    ];
    expect(firstDatedAt(samples), t0.add(const Duration(seconds: 20)));
    final spots = LiveSparkline.spotsFrom(samples);
    expect(spots, hasLength(2));
    expect(spots.first.x, 0);
    expect(spots.first.y, 10);
    expect(spots.last.x, 10);
    expect(spots.last.y, 40);
  });

  test('downsample of a month of 60s samples stays under 360 and keeps the ends', () {
    const n = 30 * 24 * 60; // 43_200
    final spots = [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), (i % 100).toDouble())];
    final sw = Stopwatch()..start();
    final out = LiveSparkline.downsample(spots, max: 360);
    sw.stop();
    expect(out.length, lessThanOrEqualTo(360));
    expect(out.first.x, 0);
    expect(out.last.x, (n - 1).toDouble());
    expect(sw.elapsedMilliseconds, lessThan(80),
        reason: '30D downsample must stay off the 1s UI path');
  });

  ThemeData sparkTheme() => ThemeData(
        brightness: Brightness.dark,
        extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
      );

  Future<void> pumpSpark(
    WidgetTester t, {
    required List<FlSpot> spots,
    required double height,
    StatsHistoryRange? range,
    DateTime? axisOrigin,
    bool interactive = true,
  }) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await t.pumpWidget(
      MaterialApp(
        theme: sparkTheme(),
        home: Scaffold(
          body: LiveSparkline(
            spots: spots,
            height: height,
            interactive: interactive,
            range: range,
            axisOrigin: axisOrigin,
          ),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('30D enlarged sparkline shows calendar-day ticks', (t) async {
    final origin = DateTime(2026, 8, 1, 12);
    final spots = LiveSparkline.spotsFrom([
      for (var i = 0; i < 30; i++)
        (at: origin.add(Duration(days: i)), value: 20.0 + i),
    ]);
    await pumpSpark(
      t,
      spots: spots,
      height: 220,
      range: StatsHistoryRange.d30,
      axisOrigin: origin,
    );
    expect(find.textContaining('Aug'), findsWidgets);
  });

  testWidgets('7D enlarged sparkline shows a clock, not only a weekday', (t) async {
    final origin = DateTime(2026, 8, 24, 9, 15);
    final spots = LiveSparkline.spotsFrom([
      for (var i = 0; i < 8; i++)
        (at: origin.add(Duration(days: i)), value: 30.0 + i),
    ]);
    await pumpSpark(
      t,
      spots: spots,
      height: 220,
      range: StatsHistoryRange.d7,
      axisOrigin: origin,
    );
    expect(find.textContaining('09:15'), findsWidgets);
  });

  testWidgets('Now enlarged sparkline shows HH:mm:ss', (t) async {
    final origin = DateTime(2026, 8, 30, 17, 16, 13);
    final spots = LiveSparkline.spotsFrom([
      for (var i = 0; i < 6; i++)
        (at: origin.add(Duration(seconds: i * 20)), value: 12.0 + i),
    ]);
    await pumpSpark(
      t,
      spots: spots,
      height: 220,
      range: StatsHistoryRange.now,
      axisOrigin: origin,
    );
    expect(find.textContaining('17:16'), findsWidgets);
  });

  testWidgets('compact sparkline stays unlabeled even for 30D data', (t) async {
    final origin = DateTime(2026, 8, 1, 12);
    final spots = LiveSparkline.spotsFrom([
      for (var i = 0; i < 30; i++)
        (at: origin.add(Duration(days: i)), value: 20.0 + i),
    ]);
    await pumpSpark(
      t,
      spots: spots,
      height: 88,
      interactive: false,
      range: StatsHistoryRange.d30,
      axisOrigin: origin,
    );
    expect(find.textContaining('Aug'), findsNothing);
  });

  testWidgets('without axisOrigin the enlarged chart stays unlabeled', (t) async {
    final origin = DateTime(2026, 8, 1, 12);
    final spots = LiveSparkline.spotsFrom([
      for (var i = 0; i < 8; i++)
        (at: origin.add(Duration(days: i)), value: 20.0),
    ]);
    await pumpSpark(
      t,
      spots: spots,
      height: 220,
      range: StatsHistoryRange.d30,
    );
    expect(find.textContaining('Aug'), findsNothing);
  });

  testWidgets('one sample is an empty state, not a degenerate axis', (t) async {
    await pumpSpark(
      t,
      spots: [const FlSpot(0, 12)],
      height: 220,
      range: StatsHistoryRange.now,
      axisOrigin: DateTime(2026, 8, 30),
    );
    expect(find.textContaining('Collecting live readings'), findsOneWidget);
  });
}
