// Article text selection is ONE document: drag handles extend across
// paragraphs, Select All copies the whole article / AI summary, and chrome
// (Share, AI Summarize, KEY FACTS labels) is never part of the selection.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/presentation/screens/news/article_detail_modal.dart';
import 'package:ai_nexus/presentation/screens/news/widgets/news_summary_view.dart';
import 'package:ai_nexus/presentation/widgets/block_selectable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

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

AppColors get _colors => _theme().extension<AppColors>()!;

Future<void> _pumpMarkdown(WidgetTester tester, String data) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: BlockSelectableMarkdown(data: data),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpDetail(WidgetTester tester, Article article) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: _theme(),
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

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 600));
}

Article _article({
  required String title,
  String? summaryMarkdown,
  String? summaryShort,
  List<ArticleBlock> blocks = const [],
  bool isFullContent = false,
  String category = 'Finance',
}) =>
    Article(
      id: 'sel-test',
      title: title,
      excerpt: 'Excerpt must not join Select All.',
      source: 'Test Source',
      category: category,
      imageUrl: '',
      readTime: 3,
      date: 'Sep 17, 2026',
      blocks: blocks,
      summaryMarkdown: summaryMarkdown,
      summaryShort: summaryShort,
      originalUrl: 'https://example.com/article',
      isFullContent: isFullContent,
    );

void _expectSharedSelection(WidgetTester tester, List<String> needles) {
  expect(find.byType(SelectionArea), findsWidgets,
      reason: 'A SelectionArea is what lets drag handles cross paragraphs.');
  expect(find.byType(EditableText), findsNothing,
      reason: 'SelectableText/EditableText traps selection in one paragraph.');
  final bodies = tester.widgetList<MarkdownBody>(find.byType(MarkdownBody));
  if (bodies.isNotEmpty) {
    expect(bodies.every((b) => !b.selectable), isTrue,
        reason: 'MarkdownBody.selectable must be false so blocks join the area.');
  }
  final area = find.byType(SelectionArea).first;
  for (final needle in needles) {
    expect(
      find.descendant(of: area, matching: find.textContaining(needle)),
      findsWidgets,
      reason: '"$needle" must live in the same SelectionArea as the rest of the article.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('BlockSelectableMarkdown — one document', () {
    testWidgets('paragraphs share a SelectionArea (not isolated SelectableText)',
        (tester) async {
      await _pumpMarkdown(
        tester,
        'Alpha block unique 111.\n\nBeta block unique 222.',
      );
      _expectSharedSelection(tester, [
        'Alpha block unique 111',
        'Beta block unique 222',
      ]);
    });
  });

  group('NewsSummaryView — AI summarize is one document', () {
    testWidgets('lede, body, and key facts share one SelectionArea',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: ArticleSelectionScope(
              child: NewsSummaryView(
                summary:
                    'Lede take unique AAA.\n\nBody take unique BBB.\n\n* Fact one unique CCC\n* Fact two unique DDD',
                colors: _colors,
                cat: const Color(0xFF6366F1),
                animate: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('QUICK SUMMARY'), findsOneWidget);
      expect(find.text('KEY FACTS'), findsOneWidget);
      _expectSharedSelection(tester, [
        'Lede take unique AAA',
        'Body take unique BBB',
        'Fact one unique CCC',
        'Fact two unique DDD',
      ]);
    });
  });

  group('ArticleDetailModal — select across the whole article', () {
    testWidgets('title and every body paragraph share one SelectionArea',
        (tester) async {
      await _pumpDetail(
        tester,
        _article(
          title: 'Headline unique XXX',
          category: 'Movies',
          isFullContent: true,
          summaryMarkdown:
              'Alpha body unique 111.\n\nBeta body unique 222.',
        ),
      );

      expect(find.text('Share'), findsWidgets);
      expect(find.text('AI Summarize'), findsOneWidget);
      _expectSharedSelection(tester, [
        'Headline unique XXX',
        'Alpha body unique 111',
        'Beta body unique 222',
      ]);
      await _drain(tester);
    });

    testWidgets('block-list paragraphs share one SelectionArea', (tester) async {
      await _pumpDetail(
        tester,
        _article(
          title: 'Headline unique XXX',
          category: 'Finance',
          blocks: const [
            ArticleBlock(type: 'paragraph', content: 'Block alpha unique 111.'),
            ArticleBlock(type: 'paragraph', content: 'Block beta unique 222.'),
            ArticleBlock(type: 'heading', content: 'Heading unique HHH'),
          ],
        ),
      );

      _expectSharedSelection(tester, [
        'Headline unique XXX',
        'Block alpha unique 111',
        'Block beta unique 222',
        'Heading unique HHH',
      ]);
      await _drain(tester);
    });

    testWidgets('AI Summary lede, body, and facts share one SelectionArea',
        (tester) async {
      await _pumpDetail(
        tester,
        _article(
          title: 'Headline unique XXX',
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown:
              'Full original body paragraph one unique.\n\nFull original body paragraph two unique.',
          summaryShort:
              'Lede take unique AAA.\n\nBody take unique BBB.\n\n* Fact one unique CCC\n* Fact two unique DDD',
        ),
      );

      await tester.tap(find.text('AI Summary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('QUICK SUMMARY'), findsOneWidget);
      _expectSharedSelection(tester, [
        'Lede take unique AAA',
        'Body take unique BBB',
        'Fact one unique CCC',
        'Fact two unique DDD',
      ]);
      await _drain(tester);
    });
  });
}
