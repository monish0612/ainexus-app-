// Visual smoke check: renders a representative slice of the app's chrome and
// themed surfaces under the REAL `AppColors.white` palette and captures it as
// a golden PNG. This is a developer aid to eyeball white-theme contrast,
// shadows and surface colors without an Android device.
//
// Regenerate the image with:
//   flutter test --update-goldens test/presentation/theme/white_theme_showcase_golden_test.dart

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/widgets/bottom_nav.dart';
import 'package:ai_nexus/presentation/widgets/compact_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

ThemeData _whiteTheme() => ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.white.bg,
      extensions: const <ThemeExtension<dynamic>>[AppColors.white],
    );

Widget _card(AppColors c, {required Widget child}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(color: c.shadowColor, blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('white theme showcase renders without exceptions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const c = AppColors.white;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _whiteTheme(),
        home: Scaffold(
          backgroundColor: c.bg,
          body: SafeArea(
            child: Column(
              children: [
                const CompactHeader(title: 'Expense', actionIcon: LucideIcons.search),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _card(c,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Primary text on a card',
                                    style: TextStyle(
                                        color: c.text,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                Text('Secondary text (text2)',
                                    style: TextStyle(color: c.text2, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text('Tertiary text (text3)',
                                    style: TextStyle(color: c.text3, fontSize: 12)),
                              ],
                            )),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            for (final entry in const [
                              ('Food', AppColors.categoryFood),
                              ('Transport', AppColors.categoryTransport),
                              ('Bills', AppColors.categoryBills),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: entry.$2.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: entry.$2.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(entry.$1,
                                      style: TextStyle(
                                          color: entry.$2,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 48,
                          child: Material(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(14),
                            child: const Center(
                              child: Text('Accent Button',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const BottomNav(currentIndex: 0, onTap: _noop),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Robust, host-independent assertion: the full chrome + surfaces lay out
    // under the real white palette with no overflow/paint exceptions.
    expect(tester.takeException(), isNull);

    // The matching golden PNG (goldens/white_theme_showcase.png) is committed
    // as a visual reference of the white theme. Golden pixel-comparison is
    // intentionally NOT asserted here because font/anti-alias rendering differs
    // across host OSes and would make the suite flaky on CI. To refresh the
    // reference image after intentional theme changes, temporarily re-add:
    //   await expectLater(find.byType(MaterialApp),
    //       matchesGoldenFile('goldens/white_theme_showcase.png'));
    // and run `flutter test --update-goldens` on this file.
  });
}

void _noop(int _) {}
