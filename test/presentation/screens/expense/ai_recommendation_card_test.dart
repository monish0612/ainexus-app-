// Widget tests for the generative AI recommendation card: the shimmer loading
// state, the rendered greeting/headline/tip/chips, and chip tap callbacks.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/expense_insight.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/ai_recommendation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
      ),
      home: Scaffold(body: child),
    );

const _rec = GroundedRecommendation(
  greeting: 'Hey Monish,',
  headline: 'Food is your biggest spend at ₹14,700 — 18% of ₹83,286.',
  tip: 'Trimming Food would save you the most.',
  tone: InsightTone.warning,
  chips: ['Break down Food', 'Compare to last month'],
  isTemplate: false,
);

void main() {
  testWidgets('loading shows shimmer, not the recommendation text',
      (tester) async {
    await tester.pumpWidget(_host(
      const AiRecommendationCard(
        colors: AppColors.dark,
        loading: true,
        recommendation: null,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Food'), findsNothing);
  });

  testWidgets('renders greeting, headline, tip and chips when ready',
      (tester) async {
    await tester.pumpWidget(_host(
      const AiRecommendationCard(
        colors: AppColors.dark,
        loading: false,
        recommendation: _rec,
      ),
    ));
    await tester.pump();
    expect(find.text('Hey Monish,'), findsOneWidget);
    expect(find.textContaining('₹14,700'), findsOneWidget);
    expect(find.text('Trimming Food would save you the most.'), findsOneWidget);
    expect(find.text('Break down Food'), findsOneWidget);
    expect(find.text('Compare to last month'), findsOneWidget);
  });

  testWidgets('tapping a chip fires the callback with its label',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(_host(
      AiRecommendationCard(
        colors: AppColors.dark,
        loading: false,
        recommendation: _rec,
        onChip: (c) => tapped = c,
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Break down Food'));
    expect(tapped, 'Break down Food');
  });
}
