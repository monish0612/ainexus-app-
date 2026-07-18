// Verifies the Add-Expense modal is driven by the user's CONFIGURED banks:
//  1. Newly added banks appear as selectable pills (reflected at entry time).
//  2. The AI/voice/scan parse path resolves the extracted bank against the
//     configured list and honors that bank's configured card type — so a brand
//     new card (e.g. KOTAK CC) is recognised and its CC repayment hint shows,
//     while a bank configured DB-only can't be coerced into a CC by the parser.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/ai_categorize_service.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:ai_nexus/presentation/screens/expense/modals/add_expense_modal.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';

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

// A user who has just added a KOTAK credit card (with a billing cycle) in
// Settings, alongside a debit-only ICICI and the built-in CASH. HDFC has BOTH
// a debit and a credit card under the same name (two entries).
final _configs = <Bank>[
  const Bank(id: 'kotak_cc', name: 'KOTAK', color: '#7C3AED', cardType: 'CC', statementDay: 5, dueDay: 25),
  const Bank(id: 'icici_db', name: 'ICICI', color: '#B02A2A', cardType: 'DB'),
  const Bank(id: 'hdfc_db', name: 'HDFC', color: '#004C8F', cardType: 'DB'),
  const Bank(id: 'hdfc_cc', name: 'HDFC', color: '#004C8F', cardType: 'CC', statementDay: 18, dueDay: 9),
  const Bank(id: 'cash', name: 'CASH', color: '#868E96', cardType: 'Cash'),
];

Future<void> _open(
  WidgetTester tester, {
  required SmartParseFunction smartParse,
  String text = 'spent 250 on kotak credit card',
}) async {
  tester.view.physicalSize = const Size(320, 900);
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
                bankConfigs: _configs,
                smartParse: smartParse,
                categorize: (desc, l) async => const AICategoryResult(
                  category: 'Food',
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
  await tester.pump();
  await tester.pump();
  // Advance through the scan/parse phases (sequential Future.delayed).
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('configured banks (incl. a newly added one) appear as pills',
      (tester) async {
    await _open(tester, smartParse: (_) async => null);
    expect(tester.takeException(), isNull);
    // The freshly added KOTAK card is selectable at log time.
    expect(find.text('KOTAK'), findsWidgets);
    expect(find.text('ICICI'), findsWidgets);
  });

  testWidgets(
      'AI parse recognises a newly added CC bank and shows its repayment hint',
      (tester) async {
    await _open(
      tester,
      // The AI returns the new bank with no explicit card type — the modal must
      // resolve it to that bank\'s only configured type (CC) and surface the
      // billing hint.
      smartParse: (_) async => const SmartParseResult(
        amount: 250,
        description: 'Lunch',
        bank: 'KOTAK',
        cardType: '',
        category: 'Food',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('250'), findsWidgets);
    // The CC repayment hint proves the bank was matched AND treated as CC.
    expect(find.textContaining('Repaid from your'), findsWidgets);
    expect(find.textContaining('KOTAK statement closes'), findsWidgets);
  });

  testWidgets('AI parse cannot coerce a DB-only bank into a credit card',
      (tester) async {
    await _open(
      tester,
      text: 'paid 800 icici',
      // AI wrongly says CC, but ICICI is configured debit-only → no CC hint.
      smartParse: (_) async => const SmartParseResult(
        amount: 800,
        description: 'Groceries',
        bank: 'ICICI',
        cardType: 'CC',
        category: 'Grocery',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('800'), findsWidgets);
    // ICICI has no CC config, so the credit-card hint must NOT appear.
    expect(find.textContaining('Repaid from your'), findsNothing);
  });

  testWidgets('an unconfigured bank from the AI falls back safely (no crash)',
      (tester) async {
    await _open(
      tester,
      text: 'paid 400 yesbank',
      // YES BANK is not in the user\'s configured list → must degrade to CASH.
      smartParse: (_) async => const SmartParseResult(
        amount: 400,
        description: 'Snacks',
        bank: 'YESBANK',
        cardType: 'CC',
        category: 'Food',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('400'), findsWidgets);
    // Unknown bank ⇒ CASH ⇒ no credit-card billing hint.
    expect(find.textContaining('Repaid from your'), findsNothing);
  });

  testWidgets('a bank with both DB+CC cards honors the spoken credit type',
      (tester) async {
    await _open(
      tester,
      text: 'spent 1200 hdfc credit card',
      smartParse: (_) async => const SmartParseResult(
        amount: 1200,
        description: 'Electronics',
        bank: 'HDFC',
        cardType: 'CC',
        category: 'Electronics',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('1200'), findsWidgets);
    // HDFC has a CC config (S18/D9) → the repayment hint must surface.
    expect(find.textContaining('Repaid from your'), findsWidgets);
    expect(find.textContaining('HDFC statement closes'), findsWidgets);
  });
}
