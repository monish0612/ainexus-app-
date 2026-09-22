import 'dart:io';

import 'package:ai_nexus/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  late String pubspec;
  late String mainSrc;
  late String overlaySrc;
  late String appSrc;
  late String themeSrc;

  setUpAll(() {
    pubspec = File('pubspec.yaml').readAsStringSync();
    mainSrc = File('lib/main.dart').readAsStringSync();
    overlaySrc = File('lib/bubble/overlay/overlay_app.dart').readAsStringSync();
    appSrc = File('lib/app.dart').readAsStringSync();
    themeSrc = File('lib/core/theme/app_theme.dart').readAsStringSync();
  });

  group('4.1 bundled fonts', () {
    const files = [
      'PlusJakartaSans-Regular.ttf',
      'PlusJakartaSans-Medium.ttf',
      'PlusJakartaSans-SemiBold.ttf',
      'PlusJakartaSans-Bold.ttf',
      'PlusJakartaSans-ExtraBold.ttf',
      'PlusJakartaSans-Italic.ttf',
      'PlusJakartaSans-MediumItalic.ttf',
      'JetBrainsMono-Regular.ttf',
      'JetBrainsMono-Bold.ttf',
      'Lora-Regular.ttf',
      'Lora-Bold.ttf',
      'Lora-Italic.ttf',
      'DMSans-Regular.ttf',
      'DMSans-Bold.ttf',
    ];

    test('runtime fetching is disabled in both isolates', () {
      expect(
        mainSrc,
        contains('GoogleFonts.config.allowRuntimeFetching = false'),
      );
      expect(
        overlaySrc,
        contains('GoogleFonts.config.allowRuntimeFetching = false'),
      );
    });

    test('pubspec ships google_fonts/ and a fonts: family block', () {
      expect(pubspec, contains('- google_fonts/'));
      expect(pubspec, contains('family: PlusJakartaSans'));
      expect(pubspec, contains('family: JetBrainsMono'));
      expect(pubspec, contains('family: Lora'));
      expect(pubspec, contains('family: DMSans'));
    });

    test('only the used weights are on disk, with OFL files', () {
      for (final name in files) {
        expect(File('google_fonts/$name').existsSync(), isTrue, reason: name);
      }
      expect(File('google_fonts/PlusJakartaSans-Light.ttf').existsSync(), isFalse);
      expect(File('google_fonts/PlusJakartaSans-Black.ttf').existsSync(), isFalse);
      expect(File('google_fonts/OFL-PlusJakartaSans.txt').existsSync(), isTrue);
      expect(File('google_fonts/OFL-JetBrainsMono.txt').existsSync(), isTrue);
      expect(File('google_fonts/OFL-Lora.txt').existsSync(), isTrue);
      expect(File('google_fonts/OFL-DMSans.txt').existsSync(), isTrue);
    });

    test('main registers the OFL licenses', () {
      expect(mainSrc, contains("rootBundle.loadString('google_fonts/"));
      expect(mainSrc, contains('LicenseRegistry.addLicense'));
    });

    test('widget tests preload fonts without a global test config', () {
      expect(File('test/flutter_test_config.dart').existsSync(), isFalse);
      expect(
        File('test/android/preload_bundled_google_fonts.dart').existsSync(),
        isTrue,
      );
    });
  });

  group('4.2 theme construction', () {
    test('whiteTheme and darkTheme are static finals, not getters', () {
      expect(themeSrc, contains('static final ThemeData whiteTheme'));
      expect(themeSrc, contains('static final ThemeData darkTheme'));
      expect(themeSrc, isNot(contains('static ThemeData get whiteTheme')));
      expect(themeSrc, isNot(contains('static ThemeData get darkTheme')));
    });

    test('the two palettes are built once and stay distinct', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      GoogleFonts.config.allowRuntimeFetching = false;
      expect(identical(AppTheme.whiteTheme, AppTheme.whiteTheme), isTrue);
      expect(identical(AppTheme.darkTheme, AppTheme.darkTheme), isTrue);
      expect(AppTheme.whiteTheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
    });
  });

  group('4.3 system overlay', () {
    test('build uses AnnotatedRegion instead of a platform-channel call', () {
      expect(appSrc, contains('AnnotatedRegion<SystemUiOverlayStyle>'));
      expect(appSrc, isNot(contains('SystemChrome.setSystemUIOverlayStyle')));
    });
  });
}
