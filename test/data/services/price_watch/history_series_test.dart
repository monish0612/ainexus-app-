import 'package:ai_nexus/data/services/price_watch/history_series.dart';
import 'package:ai_nexus/data/services/price_watch/price_models.dart';
import 'package:flutter_test/flutter_test.dart';

WatchPricePoint _p(int i, double price, {int daysAgo = 0}) {
  return WatchPricePoint(
    id: 'p$i',
    productId: 'prod',
    price: price,
    checkedAt: DateTime.utc(2026, 9, 11).subtract(Duration(days: daysAgo)),
  );
}

void main() {
  test('0 points is empty, 1 point is not a line', () {
    expect(HistorySeries.of(const []).isEmpty, isTrue);
    expect(HistorySeries.of(const []).hasEnoughForLine, isFalse);

    final one = HistorySeries.of([_p(0, 100)]);
    expect(one.isSingle, isTrue);
    expect(one.hasEnoughForLine, isFalse);
    expect(one.min, 100);
    expect(one.max, 100);
    expect(one.avg, 100);
    expect(one.points, hasLength(1));
  });

  test('stats use raw points, not the downsampled polyline', () {
    final all = [
      for (var i = 0; i < 400; i++) _p(i, 100 + (i == 50 ? 1 : 0), daysAgo: 400 - i),
    ];
    final series = HistorySeries.of(all, maxDraw: 40);
    expect(series.points.length, lessThanOrEqualTo(40));
    expect(series.rawCount, 400);
    expect(series.min, 100);
    expect(series.max, 101);
    expect(series.points.first.id, all.first.id);
    expect(series.points.last.id, all.last.id);
  });

  test('range slice hides 1W when both points are old', () {
    final now = DateTime.utc(2026, 9, 11);
    final pts = [
      _p(0, 200, daysAgo: 40),
      _p(1, 180, daysAgo: 39),
    ];
    expect(
      HistorySeries.rangeEnabled(pts, HistoryRange.week, now: now),
      isFalse,
    );
    expect(HistorySeries.rangeEnabled(pts, HistoryRange.all, now: now), isTrue);
    final week = HistorySeries.of(pts, range: HistoryRange.week, now: now);
    expect(week.rawCount, 0);
    final all = HistorySeries.of(pts, range: HistoryRange.all, now: now);
    expect(all.rawCount, 2);
    expect(all.hasEnoughForLine, isTrue);
    expect(all.avg, 190);
  });

  test('nearestRaw snaps to timestamp, not draw index', () {
    final a = _p(0, 10, daysAgo: 2);
    final b = _p(1, 20, daysAgo: 1);
    final c = _p(2, 30, daysAgo: 0);
    final series = HistorySeries.of([a, b, c]);
    final hit = series.nearestRaw(b.checkedAt.millisecondsSinceEpoch.toDouble());
    expect(hit?.id, 'p1');
    expect(hit?.price, 20);
  });

  test('yBounds expands for a target off the series', () {
    final series = HistorySeries.of([
      _p(0, 1000, daysAgo: 1),
      _p(1, 1100, daysAgo: 0),
    ]);
    final bounds = series.yBounds(target: 500);
    expect(bounds.$1, lessThan(500));
    expect(bounds.$2, greaterThan(1100));
  });
}
