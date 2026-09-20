import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cold start does not bind AudioService before runApp', () {
    final src = File('lib/main.dart').readAsStringSync();
    final runAppAt = src.indexOf('runApp(');
    expect(runAppAt, greaterThan(0));
    final before = src.substring(0, runAppAt);
    expect(before.contains('initNarrationAudio'), isFalse);
    expect(before.contains('HoldToSpeakController.warmUp'), isFalse);
    expect(before.contains('AppTokenStore.instance.load'), isFalse);
    expect(src.contains('initNarrationAudio'), isTrue);
    expect(src.contains('_afterFirstFrame'), isTrue);
    expect(src.contains('markStartupReady'), isTrue);
    expect(
      src.indexOf('markStartupReady'),
      greaterThan(src.indexOf('runApp(')),
    );
    expect(src.contains('AuthService.instance.init().timeout'), isTrue);
    expect(src.contains('Duration(milliseconds: 1800)'), isTrue);
    expect(src.contains('void overlayMain()'), isTrue);
    expect(src.contains('SharedPreferences.getInstance()'), isTrue);
    expect(src.contains('Duration(seconds: 3)'), isTrue);
    expect(
      src.indexOf('HoldToSpeakController.warmUp'),
      greaterThan(src.indexOf('_afterFirstFrame')),
    );
    expect(
      src.indexOf('initNarrationAudio'),
      greaterThan(src.indexOf('await Future<void>.delayed')),
    );
  });

  test('Listen can bind AudioService after first frame if splash deferred it',
      () {
    final bar = File(
      'lib/presentation/screens/news/widgets/narration_listen_bar.dart',
    ).readAsStringSync();
    expect(bar.contains('narrationHandler ??'), isTrue);
    expect(bar.contains('initNarrationAudio'), isTrue);
    final handler =
        File('lib/data/services/narration_audio_handler.dart').readAsStringSync();
    expect(handler.contains('_initInFlight'), isTrue);
    expect(handler.contains('Duration(seconds: 8)'), isTrue);
  });
}
