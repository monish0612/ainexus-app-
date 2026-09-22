import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/screens/auth/login_screen.dart';
import 'package:ai_nexus/presentation/screens/landing/landing_screen.dart';
import 'package:ai_nexus/presentation/widgets/nexus_brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../android/preload_bundled_google_fonts.dart';

ThemeData _theme(AppColors p) => ThemeData(
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: p.bg,
      extensions: <ThemeExtension<dynamic>>[p],
    );

Future<void> _pumpMark(
  WidgetTester tester, {
  required AppColors palette,
  double size = 80,
  Size surface = const Size(390, 760),
  bool tickers = true,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(palette),
      home: Scaffold(
        backgroundColor: palette.bg,
        body: Center(
          child: TickerMode(
            enabled: tickers,
            child: NexusBrandMark(size: size),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(preloadBundledGoogleFonts);

  group('NexusBrandMark', () {
    testWidgets('renders the logo asset without exceptions', (tester) async {
      await _pumpMark(tester, palette: AppColors.dark);
      expect(tester.takeException(), isNull);
      expect(find.byType(NexusBrandMark), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      var provider = image.image;
      if (provider is ResizeImage) {
        provider = provider.imageProvider;
      }
      expect(provider, isA<AssetImage>());
      expect(
        (provider as AssetImage).assetName,
        NexusBrandMark.assetPath,
      );
    });

    testWidgets('white theme still uses the charcoal plate (brand, not white)',
        (tester) async {
      await _pumpMark(tester, palette: AppColors.white);
      expect(tester.takeException(), isNull);
      final box = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(ClipOval),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(box.color, NexusBrandMark.plateColor);
    });

    testWidgets('holds 48 / 80 / 128 / 200 sizes without overflow',
        (tester) async {
      for (final size in [48.0, 80.0, 128.0, 200.0]) {
        await _pumpMark(tester, palette: AppColors.dark, size: size);
        expect(tester.takeException(), isNull, reason: 'size $size');
        final box = tester.getSize(find.byType(NexusBrandMark));
        expect(box.width, size);
        expect(box.height, size);
      }
    });

    testWidgets('fits a 320px-wide surface (small-phone login)',
        (tester) async {
      await _pumpMark(
        tester,
        palette: AppColors.dark,
        size: 80,
        surface: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes a Nexus AI semantics label', (tester) async {
      await _pumpMark(tester, palette: AppColors.dark, tickers: false);
      expect(find.bySemanticsLabel('Nexus AI'), findsOneWidget);
    });

    testWidgets('disabled tickers do not hang pumpAndSettle', (tester) async {
      await _pumpMark(tester, palette: AppColors.dark, tickers: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose of the spinning ring does not leak', (tester) async {
      await _pumpMark(tester, palette: AppColors.dark);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(NexusBrandMark), findsNothing);
    });
  });

  group('pre-auth screens host the brand mark', () {
    Future<void> pumpScreen(
        WidgetTester tester, Widget child, AppColors p) async {
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: _theme(p), home: child),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('LoginScreen shows the brand mark in dark and white',
        (tester) async {
      for (final p in const [AppColors.dark, AppColors.white]) {
        await pumpScreen(tester, const LoginScreen(), p);
        expect(find.byType(NexusBrandMark), findsOneWidget,
            reason: '${p.isDark}');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('LandingScreen shows the brand mark in dark and white',
        (tester) async {
      for (final p in const [AppColors.dark, AppColors.white]) {
        await pumpScreen(tester, const LandingScreen(), p);
        expect(find.byType(NexusBrandMark), findsOneWidget,
            reason: '${p.isDark}');
        expect(tester.takeException(), isNull);
      }
    });
  });
}
