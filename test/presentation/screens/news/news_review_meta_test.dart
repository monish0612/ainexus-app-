import 'package:ai_nexus/presentation/screens/news/news_review_meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gizbot = '''
**⭐ Rating: 4.8 / 5**

#### ✅ Pros

- Stunning 3K OLED display
- Excellent battery life

#### ❌ Cons

- Weak integrated GPU

---

The ASUS Zenbook S14 is a genuine attempt at getting the trade-offs right.
''';

  const kollywood = '''
**⭐ Rating: 3.75 / 5**

---

After Rocky, Saani Kaayidham and Captain Miller, director Arun Matheswaran returns.
''';

  const toi = '''
**⭐ Rating: 3.0 / 5**

---

Cole Reed is a former Royal Marine seeking revenge on a cargo ship.
''';

  test('parses Gizbot rating + pros + cons and strips the header', () {
    final meta = NewsReviewMeta.tryParse(gizbot);
    expect(meta, isNotNull);
    expect(meta!.rating, '4.8 / 5');
    expect(meta.score, 4.8);
    expect(meta.pros, ['Stunning 3K OLED display', 'Excellent battery life']);
    expect(meta.cons, ['Weak integrated GPU']);
    expect(meta.bodyAfter.startsWith('The ASUS Zenbook'), isTrue);
  });

  test('parses Only Kollywood rating-only reviews', () {
    final meta = NewsReviewMeta.tryParse(kollywood);
    expect(meta, isNotNull);
    expect(meta!.rating, '3.75 / 5');
    expect(meta.score, 3.75);
    expect(meta.pros, isEmpty);
    expect(meta.cons, isEmpty);
    expect(meta.bodyAfter.contains('Arun Matheswaran'), isTrue);
  });

  test('parses TOI critic score', () {
    final meta = NewsReviewMeta.tryParse(toi);
    expect(meta!.rating, '3.0 / 5');
    expect(meta.score, 3.0);
  });

  test('ratingLabelOf is null for AI summaries without a meta header', () {
    expect(NewsReviewMeta.ratingLabelOf('# Why this market moved'), isNull);
    expect(NewsReviewMeta.ratingLabelOf(null), isNull);
    expect(NewsReviewMeta.ratingLabelOf(''), isNull);
  });

  testWidgets('NewsRatingBadge shows the score on a compact chip', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NewsRatingBadge(rating: '3.75 / 5', compact: true),
        ),
      ),
    );
    expect(find.text('3.75'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('NewsRatingBadge onDark + full shows star row', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NewsRatingBadge(rating: '3.0 / 5', onDark: true),
        ),
      ),
    );
    expect(find.text('3.0 / 5'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsWidgets);
  });
}
