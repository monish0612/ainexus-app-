import 'package:ai_nexus/presentation/screens/news/news_reader_text_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('newsReaderTextScaler', () {
    test('default reader scale is identity when system is 1.0', () {
      final scaler = newsReaderTextScaler(
        system: TextScaler.noScaling,
        readerScale: 1.0,
      );
      expect(scaler.scale(16), 16);
    });

    test('reader 1.3 multiplies body size', () {
      final scaler = newsReaderTextScaler(
        system: TextScaler.noScaling,
        readerScale: 1.3,
      );
      expect(scaler.scale(17), closeTo(22.1, 0.01));
    });

    test('clamps combined system + reader so layout cannot explode', () {
      final scaler = newsReaderTextScaler(
        system: const TextScaler.linear(2.5),
        readerScale: 1.7,
      );
      expect(scaler.scale(1.0), kNewsReaderTextScaleMax);
    });

    test('system a11y is itself clamped before combining', () {
      final scaler = newsReaderTextScaler(
        system: const TextScaler.linear(1.5),
        readerScale: 1.0,
      );
      expect(scaler.scale(10), 12);
    });
  });

  group('snap / clamp', () {
    test('snaps to nearest discrete step', () {
      expect(snapNewsReaderTextScale(1.14), 1.15);
      expect(snapNewsReaderTextScale(0.9), 0.85);
      expect(snapNewsReaderTextScale(1.72), 1.70);
    });

    test('clamp bounds', () {
      expect(clampNewsReaderTextScale(0.1), kNewsReaderTextScaleMin);
      expect(clampNewsReaderTextScale(9), kNewsReaderTextScaleMax);
    });
  });

  group('NewsReaderTextScale notifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('increase / decrease walk the step list and persist', () async {
      final n = NewsReaderTextScale(hydrate: false);
      expect(n.state, 1.0);
      expect(n.canDecrease, isTrue);
      expect(n.canIncrease, isTrue);

      await n.increase();
      expect(n.state, 1.15);
      await n.increase();
      expect(n.state, 1.30);

      await n.decrease();
      expect(n.state, 1.15);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kNewsReaderTextScalePrefKey), 1.15);
    });

    test('increase is a no-op at max and disable flags flip', () async {
      final n = NewsReaderTextScale(initial: kNewsReaderTextScaleMax, hydrate: false);
      expect(n.canIncrease, isFalse);
      expect(n.canDecrease, isTrue);
      await n.increase();
      expect(n.state, kNewsReaderTextScaleMax);

      final minN =
          NewsReaderTextScale(initial: kNewsReaderTextScaleMin, hydrate: false);
      expect(minN.canDecrease, isFalse);
      await minN.decrease();
      expect(minN.state, kNewsReaderTextScaleMin);
    });

    test('hydrate restores the saved step', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{kNewsReaderTextScalePrefKey: 1.45},
      );
      final n = NewsReaderTextScale();
      await Future<void>.delayed(Duration.zero);
      expect(n.state, 1.45);
    });
  });
}
