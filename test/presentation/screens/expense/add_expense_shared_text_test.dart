// End-to-end widget tests for the "share text → Expense" flow. Pumps the
// REAL add-expense modal with `initialText` (a shared bank transaction SMS),
// running at a cramped 320px width to surface any UI/overflow/scaling issue,
// and validates the form auto-fills exactly like the bill scanner does — both
// through the AI smart-parse path AND through the offline local fallback.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/ai_categorize_service.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:ai_nexus/presentation/screens/expense/modals/add_expense_modal.dart';

ThemeData _theme() => ThemeData(
      extensions: const <ThemeExtension<dynamic>>[
        AppColors(
          shadowColor: Color(0x66000000),
          glassFill: Color(0x0DFFFFFF),
          scrim: Color(0x99000000),
          cardGradientTop: Color(0xFF0B0B0F),
          cardGradientBottom: Color(0xFF060608),
          shimmerBase: Color(0x14FFFFFF),
          shimmerHighlight: Color(0x2EFFFFFF),
          bg: Color(0xFF000000),
          bg1: Color(0xFF060608),
          bg2: Color(0xFF131316),
          bg3: Color(0xFF1B1B1F),
          bg4: Color(0xFF26262B),
          text: Color(0xFFF1F5F9),
          text2: Color(0xFF94A3B8),
          text3: Color(0xFF6B7280),
          text4: Color(0xFF4B5563),
          text5: Color(0xFF374151),
          border: Color(0xFF1F2937),
          border2: Color(0xFF111827),
          headerBg: Color(0xFF000000),
          navBg: Color(0xFF000000),
          isDark: true,
        ),
      ],
    );

// Long, realistic bank SMS — stresses the preview card's wrapping at 320px.
const _sampleSms =
    'Spent Rs.842 On HDFC Bank Card 5901 At SANTHOSH SUPER STORES '
    'On 2026-06-21:19:21:50.Not You? To Block+Reissue '
    'Call 18002586161/SMS BLOCK CC 5901 to 7308080808';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openModal(
    WidgetTester tester, {
    required SmartParseFunction? smartParse,
    String text = _sampleSms,
  }) async {
    // Cramped phone width to surface any horizontal-overflow / scaling bug.
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showAddExpenseModal(
                  ctx,
                  learnings: const <String, String>{},
                  smartParse: smartParse,
                  categorize: (desc, l) async => const AICategoryResult(
                    category: 'Grocery',
                    confidence: 'matched',
                    reasoning: 'test',
                    score: 0.82,
                  ),
                  initialText: text,
                  onAdd: (payload, isManual, meta) async {},
                  onTeachAI: (_, __) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Open the sheet + fire the post-frame callback that starts the pipeline.
    await tester.pump();
    await tester.pump();
    // Step the clock through the scan phases (~2.8s of sequential
    // Future.delayed). pumpAndSettle alone returns early in the gaps between
    // delays (a pending timer with no scheduled frame), so we pump explicit
    // slices to advance the fake clock past every delay.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.pump();
  }

  testWidgets('AI smart-parse path: auto-fills amount + merchant, no overflow',
      (tester) async {
    await openModal(
      tester,
      smartParse: (_) async => const SmartParseResult(
        amount: 842,
        description: 'Santhosh Super Stores',
        bank: 'HDFC',
        cardType: 'CC',
        category: 'Grocery',
      ),
    );

    // No RenderFlex overflow or any other layout exception at 320px.
    expect(tester.takeException(), isNull);

    // Form is pre-filled from the parsed SMS.
    expect(find.text('842'), findsWidgets);
    expect(find.text('Santhosh Super Stores'), findsWidgets);
  });

  testWidgets('offline fallback: null smart-parse still fills from the SMS',
      (tester) async {
    await openModal(tester, smartParse: (_) async => null);

    expect(tester.takeException(), isNull);
    // Local bank-SMS parser recovered the amount + merchant without network.
    expect(find.text('842'), findsWidgets);
    expect(find.text('Santhosh Super Stores'), findsWidgets);
  });

  testWidgets('no smartParse provided: degrades gracefully, no crash',
      (tester) async {
    await openModal(tester, smartParse: null);
    expect(tester.takeException(), isNull);
    // Local fallback still recovers the fields offline.
    expect(find.text('842'), findsWidgets);
  });

  testWidgets('empty/whitespace shared text does not crash the pipeline',
      (tester) async {
    await openModal(
      tester,
      text: '   ',
      smartParse: (_) async => null,
    );
    expect(tester.takeException(), isNull);
  });
}
