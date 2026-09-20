import 'package:ai_nexus/data/services/price_watch/price_models.dart';
import 'package:ai_nexus/data/services/price_watch/store_url.dart';
import 'package:ai_nexus/data/services/price_watch/watch_policy.dart';
import 'package:flutter_test/flutter_test.dart';

WatchItem _item({
  double price = 1000,
  double? target,
  bool dec = true,
  bool inc = false,
  bool tgt = true,
}) {
  final now = DateTime(2026, 9, 10, 12);
  return WatchItem(
    id: 'p1',
    name: 'Widget',
    url: 'https://www.amazon.in/dp/B0CXXXXXXX',
    canonicalUrl: 'https://www.amazon.in/dp/B0CXXXXXXX',
    store: WatchStore.amazon,
    currentPrice: price,
    basePrice: price,
    lastChecked: now,
    createdAt: now,
    checkIntervalMinutes: 60,
    targetPrice: target,
    notifyOnDecrease: dec,
    notifyOnIncrease: inc,
    notifyOnTarget: tgt,
  );
}

void main() {
  group('decideCheck', () {
    test('empty price fails', () {
      expect(
        decideCheck(
          newPrice: null,
          lastPrice: 100,
          score: 90,
          confirming: false,
        ).failed,
        isTrue,
      );
    });

    test('low score is quarantined', () {
      final d = decideCheck(
        newPrice: 999,
        lastPrice: 1000,
        score: 40,
        confirming: false,
      );
      expect(d.pending, isTrue);
      expect(d.price, 999);
    });

    test('jump >= 35% is quarantined', () {
      final d = decideCheck(
        newPrice: 650,
        lastPrice: 1000,
        score: 90,
        confirming: false,
      );
      expect(d.pending, isTrue);
    });

    test('small move is accepted', () {
      final d = decideCheck(
        newPrice: 980,
        lastPrice: 1000,
        score: 90,
        confirming: false,
      );
      expect(d.pending, isFalse);
      expect(d.failed, isFalse);
      expect(d.price, 980);
    });

    test('confirm agrees within 8%', () {
      final d = decideCheck(
        newPrice: 660,
        lastPrice: 1000,
        score: 90,
        confirming: true,
        pendingPrice: 650,
      );
      expect(d.pending, isFalse);
      expect(d.failed, isFalse);
      expect(d.price, 660);
    });

    test('confirm disagrees > 8% fails', () {
      final d = decideCheck(
        newPrice: 900,
        lastPrice: 1000,
        score: 90,
        confirming: true,
        pendingPrice: 650,
      );
      expect(d.failed, isTrue);
    });
  });

  group('decideAlerts', () {
    test('decrease only by default', () {
      final r = decideAlerts(
        product: _item(),
        oldPrice: 1000,
        newPrice: 800,
        globalDecrease: true,
        globalIncrease: false,
        globalTarget: true,
      );
      expect(r, [AlertReason.decrease]);
    });

    test('target hit', () {
      final r = decideAlerts(
        product: _item(target: 900),
        oldPrice: 1000,
        newPrice: 850,
        globalDecrease: true,
        globalIncrease: false,
        globalTarget: true,
      );
      expect(r, containsAll([AlertReason.target, AlertReason.decrease]));
    });

    test('increase ignored unless enabled', () {
      expect(
        decideAlerts(
          product: _item(inc: true),
          oldPrice: 1000,
          newPrice: 1100,
          globalDecrease: true,
          globalIncrease: false,
          globalTarget: true,
        ),
        isEmpty,
      );
      expect(
        decideAlerts(
          product: _item(inc: true),
          oldPrice: 1000,
          newPrice: 1100,
          globalDecrease: true,
          globalIncrease: true,
          globalTarget: true,
        ),
        [AlertReason.increase],
      );
    });
  });

  group('inQuietHours', () {
    test('disabled is never quiet', () {
      expect(
        inQuietHours(DateTime(2026, 9, 10, 23), enabled: false),
        isFalse,
      );
    });

    test('wraps midnight 22-08', () {
      expect(
        inQuietHours(DateTime(2026, 9, 10, 23), enabled: true),
        isTrue,
      );
      expect(
        inQuietHours(DateTime(2026, 9, 10, 7), enabled: true),
        isTrue,
      );
      expect(
        inQuietHours(DateTime(2026, 9, 10, 8), enabled: true),
        isFalse,
      );
      expect(
        inQuietHours(DateTime(2026, 9, 10, 12), enabled: true),
        isFalse,
      );
    });
  });
}
