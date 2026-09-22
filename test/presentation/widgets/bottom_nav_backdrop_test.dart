import 'dart:ui';

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/widgets/bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme(AppColors colors) => ThemeData(
      brightness: colors.isDark ? Brightness.dark : Brightness.light,
      extensions: <ThemeExtension<dynamic>>[colors],
    );

Future<void> _pumpNav(WidgetTester tester, AppColors colors) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(colors),
      home: Scaffold(
        bottomNavigationBar: BottomNav(
          currentIndex: 0,
          onTap: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('dark nav skips BackdropFilter', (tester) async {
    await _pumpNav(tester, AppColors.dark);
    expect(find.byType(BottomNav), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('light nav keeps the sigma-12 frost', (tester) async {
    await _pumpNav(tester, AppColors.white);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter, ImageFilter.blur(sigmaX: 12, sigmaY: 12));
  });
}
