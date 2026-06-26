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

  testWidgets('loading → content transition stops the shimmer (settles)',
      (tester) async {
    Widget card(bool loading, GroundedRecommendation? rec) => _host(
          AiRecommendationCard(
            colors: AppColors.dark,
            loading: loading,
            recommendation: rec,
          ),
        );

    // Start in the loading state (shimmer running).
    await tester.pumpWidget(card(true, null));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hey Monish,'), findsNothing);

    // Content arrives — the shimmer must stop so the tree can reach a steady
    // state (pumpAndSettle would hang forever on an always-repeating shimmer).
    await tester.pumpWidget(card(false, _rec));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Hey Monish,'), findsOneWidget);
    expect(find.textContaining('₹14,700'), findsOneWidget);
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

  testWidgets('a very long tip stays bounded + scrollable (does not eat the page)',
      (tester) async {
    final longRec = GroundedRecommendation(
      greeting: 'Hey Monish,',
      headline: 'You reduced spending by 83% vs last month.',
      // Pathologically long tip — must NOT make the card grow unbounded.
      tip: List.filled(40, 'Consider reviewing your subscriptions to save more.')
          .join(' '),
      tone: InsightTone.positive,
      chips: const ['How can I save?', 'Review subscriptions'],
      isTemplate: false,
    );
    await tester.pumpWidget(_host(
      AiRecommendationCard(
        colors: AppColors.dark,
        loading: false,
        recommendation: longRec,
      ),
    ));
    await tester.pump();

    // The tip lives inside an internal scroll view (bounded region) with the
    // edge-fade hint applied.
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(ShaderMask), findsWidgets);

    // The whole card must stay well under the available 600px test surface
    // even with the huge tip (proves the height cap works).
    final cardHeight = tester.getSize(find.byType(AiRecommendationCard)).height;
    expect(cardHeight, lessThan(360),
        reason: 'card must not expand to fill the page');

    // The bounded region must actually be scrollable (content > viewport).
    final scrollable = find.byType(SingleChildScrollView);
    final posBefore = tester.widget<SingleChildScrollView>(scrollable);
    expect(posBefore.controller!.position.maxScrollExtent, greaterThan(0),
        reason: 'long tip overflows the cap, so it scrolls inside the card');

    // Dragging the inner region scrolls it without throwing / moving the page.
    await tester.drag(scrollable, const Offset(0, -80));
    await tester.pump();
    expect(tester.widget<SingleChildScrollView>(scrollable).controller!.position.pixels,
        greaterThan(0));

    // Chips remain present + tappable even with the overflowing tip.
    expect(find.text('Review subscriptions'), findsOneWidget);
  });
}
