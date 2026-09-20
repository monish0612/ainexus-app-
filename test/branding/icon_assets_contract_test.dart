import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Production contracts for the payment-glyph launcher / splash /
/// notification set. These catch the exact regressions that produced the
/// original white blob (missing padding, opaque notification glyph,
/// leftover `@mipmap/ic_launcher` status-bar icons, R8 stripping).
void main() {
  const densities = {
    'drawable-mdpi': 24,
    'drawable-hdpi': 36,
    'drawable-xhdpi': 48,
    'drawable-xxhdpi': 72,
    'drawable-xxxhdpi': 96,
  };

  const mipmapDensities = [
    'mipmap-mdpi',
    'mipmap-hdpi',
    'mipmap-xhdpi',
    'mipmap-xxhdpi',
    'mipmap-xxxhdpi',
  ];

  img.Image decodePng(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'missing $path');
    final decoded = img.decodePng(file.readAsBytesSync());
    expect(decoded, isNotNull, reason: 'could not decode $path');
    return decoded!;
  }

  group('source brand PNGs', () {
    test('launcher is flattened RGB (no alpha hole on older APIs)', () {
      final im = decodePng('assets/icon/ic_launcher.png');
      expect(im.width, 1024);
      expect(im.height, 1024);
      expect(im.numChannels, 3);
    });

    test('foreground / splash / monochrome are transparent at the corners', () {
      for (final name in [
        'ic_foreground.png',
        'ic_splash.png',
        'ic_monochrome.png',
        'ic_notification.png',
      ]) {
        final im = decodePng('assets/icon/$name');
        expect(im.width, 1024);
        expect(im.height, 1024);
        expect(im.numChannels, greaterThanOrEqualTo(4), reason: name);
        for (final p in [
          im.getPixel(0, 0),
          im.getPixel(im.width - 1, 0),
          im.getPixel(0, im.height - 1),
          im.getPixel(im.width - 1, im.height - 1),
        ]) {
          expect(p.a, 0, reason: '$name corner must be fully transparent');
        }
      }
    });

    test('foreground glyph stays inside the adaptive-icon safe zone', () {
      final im = decodePng('assets/icon/ic_foreground.png');
      var minX = im.width, minY = im.height, maxX = 0, maxY = 0;
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          if (im.getPixel(x, y).a > 8) {
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
          }
        }
      }
      // 66/108 of the canvas — content must sit inside this inner square.
      final margin = (im.width * (1 - 66 / 108) / 2).round();
      expect(minX, greaterThanOrEqualTo(margin));
      expect(minY, greaterThanOrEqualTo(margin));
      expect(maxX, lessThan(im.width - margin));
      expect(maxY, lessThan(im.height - margin));
    });

    test('notification source is a white silhouette (status-bar tintable)', () {
      final im = decodePng('assets/icon/ic_notification.png');
      var opaque = 0;
      var colored = 0;
      for (var y = 0; y < im.height; y += 4) {
        for (var x = 0; x < im.width; x += 4) {
          final p = im.getPixel(x, y);
          if (p.a < 16) continue;
          opaque++;
          if (p.r < 240 || p.g < 240 || p.b < 240) colored++;
        }
      }
      expect(opaque, greaterThan(0));
      expect(colored / opaque, lessThan(0.02),
          reason: 'status-bar icons must be near-white or they become a blob');
    });
  });

  group('generated Android densities', () {
    test('notification drawables exist at every density and stay tiny', () {
      densities.forEach((folder, px) {
        final im =
            decodePng('android/app/src/main/res/$folder/ic_notification.png');
        expect(im.width, px, reason: folder);
        expect(im.height, px, reason: folder);
        expect(im.getPixel(0, 0).a, 0, reason: '$folder corner');
        var opaque = 0;
        for (var y = 0; y < im.height; y++) {
          for (var x = 0; x < im.width; x++) {
            if (im.getPixel(x, y).a > 32) opaque++;
          }
        }
        // A 24dp "$" that only fills ~5% of the canvas is unreadable.
        expect(opaque / (px * px), greaterThan(0.12), reason: folder);
      });
    });

    test('legacy + round launcher mipmaps exist at every density', () {
      for (final folder in mipmapDensities) {
        expect(
          File('android/app/src/main/res/$folder/ic_launcher.png').existsSync(),
          isTrue,
          reason: folder,
        );
        expect(
          File('android/app/src/main/res/$folder/ic_launcher_round.png')
              .existsSync(),
          isTrue,
          reason: folder,
        );
      }
    });

    test('adaptive layers exist at every density', () {
      for (final folder in densities.keys) {
        expect(
          File('android/app/src/main/res/$folder/ic_launcher_foreground.png')
              .existsSync(),
          isTrue,
        );
        expect(
          File('android/app/src/main/res/$folder/ic_launcher_monochrome.png')
              .existsSync(),
          isTrue,
        );
        expect(
          File('android/app/src/main/res/$folder/splash.png').existsSync(),
          isTrue,
        );
        expect(
          File('android/app/src/main/res/$folder/android12splash.png')
              .existsSync(),
          isTrue,
        );
      }
    });

    test('splash fill pixel is charcoal, not white', () {
      final im = decodePng('android/app/src/main/res/drawable/background.png');
      final p = im.getPixel(0, 0);
      expect(p.r, lessThan(20));
      expect(p.g, lessThan(20));
      expect(p.b, lessThan(25));
    });
  });

  group('XML / pubspec wiring', () {
    String read(String path) => File(path).readAsStringSync();

    test('adaptive launcher xml has background, foreground, monochrome', () {
      for (final name in ['ic_launcher.xml', 'ic_launcher_round.xml']) {
        final xml = read('android/app/src/main/res/mipmap-anydpi-v26/$name');
        expect(xml, contains('<background'));
        expect(xml, contains('<foreground'));
        expect(xml, contains('<monochrome'));
        expect(xml, contains('android:inset="0%"'));
        expect(xml, contains('@color/ic_launcher_background'));
      }
    });

    test('manifest points at launcher, round, and status-bar meta-data', () {
      final xml = read('android/app/src/main/AndroidManifest.xml');
      expect(xml, contains('android:icon="@mipmap/ic_launcher"'));
      expect(xml, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
      expect(xml, contains('@drawable/ic_notification'));
      expect(xml, contains('app.ainexus.NOTIFICATION_ICON'));
      expect(xml, contains('notification_accent'));
    });

    test('keep.xml protects the Dart-string status-bar drawable', () {
      final xml = read('android/app/src/main/res/raw/keep.xml');
      expect(xml, contains('@drawable/ic_notification'));
    });

    test('colors match the AMOLED + accent tokens', () {
      final xml = read('android/app/src/main/res/values/colors.xml');
      expect(xml, contains('#0B0B0D'));
      expect(xml, contains('#0D59F2'));
    });

    test('LaunchTheme / NormalTheme stay charcoal (no white flash)', () {
      for (final path in [
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final xml = read(path);
        expect(xml, contains('Theme.Black.NoTitleBar'), reason: path);
        expect(xml, isNot(contains('?android:colorBackground')), reason: path);
      }
    });

    test('pubspec registers assets and zero extra adaptive inset', () {
      final yaml = read('pubspec.yaml');
      expect(yaml, contains('- assets/icon/'));
      expect(yaml, contains('adaptive_icon_foreground_inset: 0'));
      expect(yaml, contains('adaptive_icon_monochrome:'));
      expect(yaml, contains('color: "#0B0B0D"'));
    });
  });

  group('Dart / Kotlin status-bar icon contracts', () {
    test('no leftover launcher mipmap as a notification init icon', () {
      final hits = <String>[];
      for (final f
          in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains(
                "AndroidInitializationSettings('@mipmap/ic_launcher')") ||
            src.contains("androidNotificationIcon: 'mipmap/ic_launcher'")) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
    });

    test('every local-notification init uses the white status-bar glyph', () {
      final inits = <String>[];
      for (final f
          in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        final matches = RegExp(r"AndroidInitializationSettings\('([^']+)'\)")
            .allMatches(src);
        for (final m in matches) {
          inits.add('${f.path}: ${m.group(1)}');
          expect(m.group(1), 'ic_notification', reason: f.path);
        }
      }
      expect(inits, isNotEmpty);
    });

    test('foreground-service start/update always pass the status-bar icon', () {
      for (final path in [
        'lib/core/services/background_task_coordinator.dart',
        'lib/core/services/transfer_notification.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, contains('notificationIcon:'));
        expect(src, contains('AndroidStatusBarIcon.manifestMeta'));
        expect(
          src.contains('FlutterForegroundTask.startService') &&
              !src.contains('notificationIcon:'),
          isFalse,
        );
      }
    });

    test('narration media notification uses the white drawable', () {
      final src = File('lib/data/services/narration_audio_handler.dart')
          .readAsStringSync();
      expect(src, contains('AndroidStatusBarIcon.audioServiceRes'));
      expect(src,
          isNot(contains("androidNotificationIcon: 'mipmap/ic_launcher'")));
    });

    test('SMS native notification uses the white drawable + accent', () {
      final src = File(
        'android/app/src/main/kotlin/app/ainexus/ai_nexus/sms/SmsBridge.kt',
      ).readAsStringSync();
      expect(src, contains('R.drawable.ic_notification'));
      expect(src, contains('#0D59F2'));
      expect(src, isNot(contains('R.mipmap.ic_launcher')));
    });
  });
}
