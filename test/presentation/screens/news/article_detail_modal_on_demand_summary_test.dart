// Widget tests for the on-demand "AI Summarize" flow in [ArticleDetailModal].
//
// Behaviour under test (the new full-content-first model):
//   * A full-content article (isFullContent = true) with no cached summary
//     renders its original body AND offers an "AI Summarize" call-to-action.
//   * A full-content article that ALREADY has a cached summary
//     (Article.summaryShort) shows the Article/AI-Summary segmented toggle
//     and flips to the cached summary WITHOUT any network call when tapped.
//   * A legacy AI-summary article (isFullContent = false, e.g. Finance)
//     shows neither the CTA nor the toggle — its content is already a
//     summary, so the existing compact rendering is preserved.
//
// These tests never override apiClient/database providers: the cached-toggle
// path returns before touching them, and the CTA is only rendered (not
// tapped) so no AI request is issued.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/presentation/screens/news/article_detail_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData _testTheme() {
  return ThemeData(
    extensions: const <ThemeExtension<dynamic>>[
      AppColors(
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
  String? summaryShort,
  bool isFullContent = false,
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
      summaryShort: summaryShort,
      originalUrl: 'https://example.com/article',
      isFullContent: isFullContent,
    );

Future<void> _pumpDetail(
  WidgetTester tester, {
  required Article article,
}) async {
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
          onToggleSave: (_) {},
          onMarkRead: () {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('ArticleDetailModal — on-demand AI summarize', () {
    testWidgets(
        'full-content article without a cached summary shows the AI Summarize CTA + full body',
        (tester) async {
      final article = _article(
        category: 'AI News',
        isFullContent: true,
        summaryMarkdown:
            'Full original first paragraph of the AI News story.\n\nSecond paragraph going deeper.\n\nThird wrap-up paragraph.',
      );
      await _pumpDetail(tester, article: article);

      expect(find.text('AI Summarize'), findsOneWidget,
          reason: 'Full-content article must offer an on-demand summarize CTA.');
      expect(
        find.textContaining('Full original first paragraph'),
        findsOneWidget,
        reason: 'The original article body must render by default.',
      );
      await _drain(tester);
    });

    testWidgets(
        'cached summary toggles to the interactive summary view with no network call',
        (tester) async {
      final article = _article(
        category: 'AI News',
        isFullContent: true,
        summaryMarkdown:
            'Full original body paragraph one.\n\nFull original body paragraph two.',
        summaryShort:
            'This is the cached lede summary.\n\nA second body paragraph for the cached summary.',
      );
      await _pumpDetail(tester, article: article);

      // With a cached summary present, the segmented toggle is shown.
      expect(find.text('Article'), findsOneWidget);
      expect(find.text('AI Summary'), findsOneWidget);

      // Tap the AI Summary segment -> cached path, pure setState, no network.
      await tester.tap(find.text('AI Summary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('QUICK SUMMARY'), findsOneWidget,
          reason: 'Cached summary should render via the shared summary view.');
      expect(find.textContaining('cached lede summary'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets(
        'legacy AI-summary article (Finance) shows neither the CTA nor the toggle',
        (tester) async {
      final article = _article(
        category: 'Finance',
        summaryMarkdown: '## Why this matters\n\nAI-generated summary content.',
      );
      await _pumpDetail(tester, article: article);

      expect(find.text('AI Summarize'), findsNothing);
      expect(find.text('AI Summary'), findsNothing);
      expect(find.text('Original full article'), findsNothing);
      await _drain(tester);
    });
  });
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 600));
}
