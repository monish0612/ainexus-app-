import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/domain/entities/nas_stats.dart';
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

  test('offline envelope records NAS zeros so the chart matches the gauges', () {
    const env = NasStatsEnvelope(online: false);
    final s = LiveStatSample.fromEnvelope(env, DateTime.utc(2026, 8, 20));
    expect(s.nasCpu, 0);
    expect(s.nasRam, 0);
    expect(s.nasDisk, 0);
  });
}
