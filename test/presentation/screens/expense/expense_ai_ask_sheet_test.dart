import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/screens/expense/modals/expense_ai_ask_sheet.dart';

/// Scaling / overflow coverage for the redesigned "Ask AI" expense search
/// sheet. The sheet runs repeating animations (rotating glow ring, pulsing
/// orb), so these tests pump fixed durations rather than [pumpAndSettle].
void main() {
  ThemeData theme(AppColors colors) => ThemeData(
        brightness: colors.isDark ? Brightness.dark : Brightness.light,
        extensions: <ThemeExtension<dynamic>>[colors],
      );

  Widget host(ThemeData theme) => ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showExpenseAiAskSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump(); // kick off the bottom-sheet entrance
    await tester.pump(const Duration(milliseconds: 400)); // sheet settled in
  }

  for (final entry in <String, ThemeData>{
    'dark': theme(AppColors.dark),
    'light': theme(AppColors.white),
  }.entries) {
    testWidgets('opens without overflow at a cramped 320px (${entry.key})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(entry.value));
      await openSheet(tester);

      expect(find.text('Ask AI'), findsOneWidget);
      // The suggestion rail is shown while the field is empty.
      expect(find.text('TRY ASKING'), findsOneWidget);
      expect(find.text("Today's expenses"), findsWidgets);
      // No RenderFlex overflow or other layout exception was thrown.
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('suggestion rail collapses once the user starts typing',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(theme(AppColors.dark)));
    await openSheet(tester);

    expect(find.text('TRY ASKING'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'when did I last buy petrol');
    await tester.pump(); // setState -> begin collapse animation
    await tester.pump(const Duration(milliseconds: 350)); // animation done

    // Rail (and its header) is gone once there is text.
    expect(find.text('TRY ASKING'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles an extremely narrow 240px width without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(240, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(theme(AppColors.dark)));
    await openSheet(tester);

    expect(find.text('Ask AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
