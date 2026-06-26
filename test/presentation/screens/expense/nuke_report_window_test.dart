// Widget tests for the futuristic "nuke" result window (NukeEasterEgg.showReport)
// and confirmation dialog (NukeEasterEgg.confirm).
//
// The window runs an always-repeating pulse animation, so these tests advance
// the clock with fixed `pump(duration)` calls (pumpAndSettle would hang forever)
// and assert on render output, the count-up ticker, scope-aware copy, the empty
// state, dismissal, and the interactive shockwave replay.

import 'package:ai_nexus/core/services/nuke_report.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/nuke_easter_egg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(void Function(BuildContext) onReady) => MaterialApp(
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => onReady(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

const _fullReport = NukeReport(
  scope: NukeScope.full,
  elapsedMs: 123,
  fullySynced: true,
  lines: [
    NukeLine(label: 'Expenses', emoji: '💸', count: 5, cloudSynced: true),
    NukeLine(label: 'Salary', emoji: '💰', count: 7, cloudSynced: true),
    NukeLine(label: 'Saved words', emoji: '📖', count: 3),
    NukeLine(label: 'Empty domain', emoji: '📦', count: 0),
  ],
);

const _expenseQueued = NukeReport(
  scope: NukeScope.expense,
  elapsedMs: 50,
  fullySynced: false,
  lines: [
    NukeLine(label: 'Expenses', emoji: '💸', count: 9, cloudSynced: false),
  ],
);

const _emptyReport = NukeReport(
  scope: NukeScope.full,
  elapsedMs: 7,
  fullySynced: true,
  lines: [
    NukeLine(label: 'Expenses', emoji: '💸', count: 0, cloudSynced: true),
  ],
);

void main() {
  Future<void> open(WidgetTester tester, NukeReport report) async {
    await tester.pumpWidget(
      _host((context) => NukeEasterEgg.showReport(context, report)),
    );
    await tester.tap(find.text('go'));
    // Transition (360ms) + intro (1500ms) + headroom; one big pump completes
    // the once-only count-up without trying to settle the repeating pulse.
    await tester.pump(); // start the route
    await tester.pump(const Duration(seconds: 2));
  }

  group('result window', () {
    testWidgets('full scope renders headline, rows, meta and CTA',
        (tester) async {
      await open(tester, _fullReport);

      expect(find.text('SYSTEM WIPED'), findsOneWidget);
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Saved words'), findsOneWidget);
      // Zero-count domain is hidden from the animated list.
      expect(find.text('Empty domain'), findsNothing);
      // Meta bar + CTA.
      expect(find.text('CLEARED'), findsOneWidget);
      expect(find.text('Start Fresh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('count-up ticker reaches the final per-row value',
        (tester) async {
      await open(tester, _fullReport);
      expect(find.text('−5'), findsOneWidget); // expenses
      expect(find.text('−7'), findsOneWidget); // salary
    });

    testWidgets('synced rows show a SYNCED badge; total CLEARED is correct',
        (tester) async {
      await open(tester, _fullReport);
      // SYNCED appears on synced rows + the meta CLOUD stat.
      expect(find.text('SYNCED'), findsWidgets);
      // 5 + 7 + 3 + 0 = 15
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('expense scope uses its own headline + QUEUED state',
        (tester) async {
      await open(tester, _expenseQueued);
      expect(find.text('EXPENSES NUKED'), findsOneWidget);
      expect(find.text('SYSTEM WIPED'), findsNothing);
      expect(find.text('QUEUED'), findsWidgets);
      expect(find.text('−9'), findsOneWidget);
    });

    testWidgets('empty report shows the pristine state', (tester) async {
      await open(tester, _emptyReport);
      expect(find.textContaining('Already pristine'), findsOneWidget);
      expect(find.text('0'), findsWidgets); // CLEARED 0
      expect(tester.takeException(), isNull);
    });

    testWidgets('Start Fresh dismisses the window', (tester) async {
      await open(tester, _fullReport);
      expect(find.text('SYSTEM WIPED'), findsOneWidget);

      await tester.tap(find.text('Start Fresh'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('SYSTEM WIPED'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the reactor core replays the shockwave (no crash)',
        (tester) async {
      await open(tester, _fullReport);
      // The glyph emoji sits at the centre of the tappable shockwave canvas.
      await tester.tap(find.text('☢️'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(find.text('SYSTEM WIPED'), findsOneWidget);
    });
  });

  group('confirm dialog', () {
    testWidgets('full scope copy + Cancel returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((context) async {
          result = await NukeEasterEgg.confirm(context, NukeScope.full);
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Nuke the entire app?'), findsOneWidget);
      expect(find.text('Nuke all'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('expense scope copy + confirm returns true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((context) async {
          result = await NukeEasterEgg.confirm(context, NukeScope.expense);
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Nuke expenses?'), findsOneWidget);
      expect(find.text('Nuke it'), findsOneWidget);

      await tester.tap(find.text('Nuke it'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });
}
