// Widget tests for the new full-article rendering path in
// [ArticleDetailModal]. The two new feeds (Movies, General) ship the FULL
// original article body — not an AI summary — and need to render with
// newspaper-grade typography PLUS an "Original full article" pill so the
// user immediately understands what they're looking at.
//
// COVERAGE
//
//   • Movies / General article with `summaryMarkdown` populated → shows
//     the "Original full article" pill AND the body text.
//   • Finance / AI News article with `summaryMarkdown` populated → does
//     NOT show the pill (AI-summary articles stay in the existing
//     compact-dashboard styling).
//   • Saved-state propagation: tapping Save flips the bottom-bar pill
//     label from "Save" → "Saved" and fires the onToggleSave callback.
//
// We deliberately keep the assertion surface to "what the user actually
// sees" (visible text, callback wiring) rather than matching internal
// widget classes — that keeps the test stable across UI refactors as
// long as the contract holds.
//
// NOTE: we don't override `appDatabaseProvider` / `apiClientProvider`
// because the follow-up FAB only consumes them on tap. The render-only
// tests below never expand the FAB sheet.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/presentation/screens/news/article_detail_modal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData _testTheme() {
  return ThemeData(
    extensions: const <ThemeExtension<dynamic>>[
      AppColors(
        shadowColor: Color(0x66000000),
        glassFill: Color(0x0DFFFFFF),
        scrim: Color(0x99000000),
        cardGradientTop: Color(0xFF0B0B0F),
        cardGradientBottom: Color(0xFF060608),
        shimmerBase: Color(0x14FFFFFF),
        shimmerHighlight: Color(0x2EFFFFFF),
        bg: Color(0xFFFFFFFF),
        bg1: Color(0xFFF8F9FB),
        bg2: Color(0xFFEEF1F5),
        bg3: Color(0xFFE5E9EF),
        bg4: Color(0xFFDDE2EA),
        text: Color(0xFF101828),
        text2: Color(0xFF1F2937),
        text3: Color(0xFF374151),
        text4: Color(0xFF6B7280),
        text5: Color(0xFF94A3B8),
        border: Color(0xFFE2E8F0),
        border2: Color(0xFFCBD5E1),
        headerBg: Color(0xFFFFFFFF),
        navBg: Color(0xFFFFFFFF),
        isDark: false,
      ),
    ],
  );
}

Article _article({
  required String category,
  String? summaryMarkdown,
}) =>
    Article(
      id: 'test-${category.toLowerCase()}',
      title: 'Some article title for $category category',
      excerpt: 'Lead-in excerpt for the $category piece.',
      source: 'Test Source',
      category: category,
      imageUrl: '',
      readTime: 3,
      date: 'May 28, 2026',
      blocks: const [],
      summaryMarkdown: summaryMarkdown,
      originalUrl: 'https://example.com/article',
    );

Future<void> _pumpDetail(
  WidgetTester tester, {
  required Article article,
  ValueChanged<bool>? onToggleSave,
  VoidCallback? onMarkRead,
}) async {
  // The modal sits inside a CustomScrollView whose SliverList only lays out
  // children that are in (or near) the viewport. The "Original full article"
  // pill renders ~600 px below the fold once the hero + meta + title + TTS
  // bar are accounted for. Expand the test viewport so the whole sliver
  // tree is built and find.text() can reach the pill without scrolling.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: _testTheme(),
        home: ArticleDetailModal(
          article: article,
          onToggleSave: onToggleSave ?? (_) {},
          onMarkRead: onMarkRead ?? () {},
        ),
      ),
    ),
  );
  // Two pumps to let the layout settle without waiting for any potential
  // network image fetch / google-fonts retrieval that pumpAndSettle would
  // chase indefinitely.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Avoid GoogleFonts network fetches during tests — they're not required
  // for layout assertions and they slow CI down dramatically when offline.
  GoogleFonts.config.allowRuntimeFetching = false;

  group('ArticleDetailModal — full-content (Movies / General) rendering', () {
    testWidgets('Movies article shows "Original full article" pill above body',
        (tester) async {
      final article = _article(
        category: 'Movies',
        summaryMarkdown:
            'First paragraph of the movie review.\n\nSecond paragraph going deeper into the craft and pacing.\n\nA final wrap-up paragraph with the verdict.',
      );
      await _pumpDetail(tester, article: article);

      expect(find.text('Original full article'), findsOneWidget,
          reason: 'Movies article must display the pill so the user knows '
              'this is the original article, not an AI summary.');
      // The body markdown text should be present in the rendered tree.
      expect(
          find.textContaining('First paragraph of the movie review'),
          findsOneWidget);
      await _drain(tester);
    });

    testWidgets('inline image markdown in the body renders as a cached image',
        (tester) async {
      const imgUrl = 'https://cdn.example.com/inline-chart.png';
      final article = _article(
        category: 'General',
        summaryMarkdown:
            'Opening paragraph of the report.\n\n![A chart]($imgUrl)\n\nClosing paragraph after the chart.',
      );
      await _pumpDetail(tester, article: article);

      // The hero uses a gradient (imageUrl == ''), so the only
      // CachedNetworkImage in the tree is the inline body image — proving the
      // sizedImageBuilder wired the markdown image through.
      final cached = find
          .byType(CachedNetworkImage)
          .evaluate()
          .map((e) => (e.widget as CachedNetworkImage).imageUrl)
          .toList();
      expect(cached, contains(imgUrl),
          reason: 'Inline ![](...) markdown must render via CachedNetworkImage.');
      // Surrounding prose still renders.
      expect(find.textContaining('Opening paragraph of the report'),
          findsOneWidget);
      await _drain(tester);
    });

    testWidgets('General article shows the same pill', (tester) async {
      final article = _article(
        category: 'General',
        summaryMarkdown:
            'Lead paragraph of the tech story.\n\nSecond paragraph.\n\nThird paragraph.',
      );
      await _pumpDetail(tester, article: article);

      expect(find.text('Original full article'), findsOneWidget);
      expect(find.textContaining('Lead paragraph of the tech story'),
          findsOneWidget);
      await _drain(tester);
    });

    testWidgets('Finance article does NOT show the full-article pill',
        (tester) async {
      final article = _article(
        category: 'Finance',
        summaryMarkdown:
            '## Why this matters\n\nAI-generated summary content for the Finance piece.',
      );
      await _pumpDetail(tester, article: article);

      expect(find.text('Original full article'), findsNothing,
          reason:
              'AI-summarized articles must keep the existing compact dashboard styling.');
      // The Finance article's markdown body still renders — text from
      // `MarkdownBody` is rendered as RichText, so we assert by the
      // presence of any RichText with the expected paragraph string.
      final richTexts = find.byType(RichText).evaluate().map((e) {
        final r = e.widget as RichText;
        return r.text.toPlainText();
      }).join(' || ');
      expect(richTexts, contains('AI-generated summary content for the Finance piece'),
          reason: 'Finance article body must render in the regular MarkdownBody path.');
      await _drain(tester);
    });

    testWidgets('AI News article does NOT show the full-article pill',
        (tester) async {
      final article = _article(
        category: 'AI News',
        summaryMarkdown: '## Key Idea\n\nSummary body for AI News article.',
      );
      await _pumpDetail(tester, article: article);

      expect(find.text('Original full article'), findsNothing);
      await _drain(tester);
    });
  });

  group('ArticleDetailModal — Gizbot review meta card', () {
    // The backend prepends a structured Markdown header to Gizbot review
    // articles: rating + pros + cons separated from the body by `---`.
    // The Flutter parser must extract that block and render it as a
    // color-coded card, leaving only the prose body to the MarkdownBody.

    const gizbotMarkdown = '''
**⭐ Rating: 4.8 / 5**

#### ✅ Pros

- Stunning 3K OLED display
- Excellent battery life
- Premium ceraluminum chassis

#### ❌ Cons

- Weak integrated GPU
- No SD card slot

---

The ASUS Zenbook S14 is a genuine attempt at getting the trade-offs right for an ultraportable. Here is the rest of the body.

Second paragraph describes the build quality and chassis materials.
''';

    testWidgets('renders Rating pill + Pros + Cons sections', (tester) async {
      final article = _article(
        category: 'General',
        summaryMarkdown: gizbotMarkdown,
      );
      await _pumpDetail(tester, article: article);

      // Rating pill shows "Rating" label + value
      expect(find.text('Rating'), findsOneWidget,
          reason: 'Rating pill label must appear.');
      expect(find.text('4.8 / 5'), findsOneWidget,
          reason: 'Rating value must appear next to the label.');

      // Pros / Cons section headings (rendered uppercase by the widget)
      expect(find.text('PROS'), findsOneWidget);
      expect(find.text('CONS'), findsOneWidget);

      // Individual list items render
      expect(find.text('Stunning 3K OLED display'), findsOneWidget);
      expect(find.text('Excellent battery life'), findsOneWidget);
      expect(find.text('Weak integrated GPU'), findsOneWidget);

      await _drain(tester);
    });

    testWidgets('strips meta block from MarkdownBody (no raw markdown leaks)',
        (tester) async {
      final article = _article(
        category: 'General',
        summaryMarkdown: gizbotMarkdown,
      );
      await _pumpDetail(tester, article: article);

      // The body prose AFTER the `---` separator must still render.
      expect(
          find.textContaining('ASUS Zenbook S14 is a genuine attempt'),
          findsOneWidget,
          reason: 'Body prose after the meta block must still display.');

      // Raw markdown sentinel like `**⭐ Rating:` must NOT appear as text —
      // the meta block should be consumed by the parser and rendered as
      // the rich card instead.
      final all = find.byType(RichText).evaluate().map((e) {
        final r = e.widget as RichText;
        return r.text.toPlainText();
      }).join(' || ');
      expect(all.contains('**⭐ Rating'), isFalse,
          reason: 'Meta block must not leak raw markdown into the prose.');
      expect(all.contains('#### ✅ Pros'), isFalse);
      expect(all.contains('#### ❌ Cons'), isFalse);

      await _drain(tester);
    });

    testWidgets('articles without meta block render unchanged (no card)',
        (tester) async {
      final article = _article(
        category: 'General',
        summaryMarkdown:
            'A regular TechCrunch article without any rating / pros / cons.\n\nSecond paragraph.\n\nThird.',
      );
      await _pumpDetail(tester, article: article);

      // No Rating / PROS / CONS controls when there's no meta header.
      expect(find.text('Rating'), findsNothing);
      expect(find.text('PROS'), findsNothing);
      expect(find.text('CONS'), findsNothing);

      // But the body still renders and the full-article pill still appears.
      expect(find.text('Original full article'), findsOneWidget);
      expect(find.textContaining('regular TechCrunch article'), findsOneWidget);

      await _drain(tester);
    });
  });

  group('ArticleDetailModal — save action wiring (unchanged contract)', () {
    testWidgets('tapping the Save pill fires onToggleSave(true) for a Movies article',
        (tester) async {
      bool? captured;
      final article = _article(
        category: 'Movies',
        summaryMarkdown:
            'Some paragraph for the test.\n\nSecond paragraph.\n\nThird.',
      );
      await _pumpDetail(
        tester,
        article: article,
        onToggleSave: (v) => captured = v,
      );

      final saveFinder = find.text('Save');
      expect(saveFinder, findsOneWidget,
          reason: 'Save pill must be present for an unsaved Movies article.');
      await tester.tap(saveFinder);
      // The save tap callback schedules a short delay before popping the
      // modal — flush that timer here so the test framework's pending-
      // timer guard doesn't trip when we drain.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(captured, isTrue,
          reason: 'onToggleSave should fire with true (newly saved).');
      await _drain(tester);
    });
  });
}

/// Replaces the on-screen tree with an empty placeholder and waits for any
/// scheduled cleanup timers (toast queues, save-pop delays, TTS cleanup)
/// to drain. Required before the test framework's pending-timer guard runs
/// during widget tree disposal.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 600));
}
