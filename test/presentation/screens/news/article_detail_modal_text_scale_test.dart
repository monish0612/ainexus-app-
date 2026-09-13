// Article-reader text size (A− / A+) — behaviour, wrap, overflow, chrome.
//
// The control lives on [ArticleDetailModal]. Search results reuse the same
// provider via [SearchAnswerTextSizeControl] with distinct keys.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/presentation/screens/news/article_detail_modal.dart';
import 'package:ai_nexus/presentation/screens/news/news_reader_text_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeData _darkTheme() => ThemeData(
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

Article _article({
  required String category,
  String title = 'Readable article title for the news reader',
  String? summaryMarkdown,
  bool isFullContent = false,
  List<ArticleBlock> blocks = const [],
}) =>
    Article(
      id: 'scale-$category',
      title: title,
      excerpt: 'UNIQUE-EXCERPT-SENTINEL that should never be rendered.',
      source: 'Test Source',
      category: category,
      imageUrl: '',
      readTime: 5,
      date: 'Aug 18, 2026',
      blocks: blocks,
      summaryMarkdown: summaryMarkdown,
      originalUrl: 'https://example.com/article',
      isFullContent: isFullContent,
    );

const _prose = '''
The monsoon arrived overnight and the streets of Chennai filled with the
smell of wet earth. Shopkeepers pulled canvas awnings over their stalls
while office workers waited under bus shelters, talking about the match
and the price of tomatoes.

A second paragraph keeps the column flowing so line wrapping can be
measured: every word here is a normal English token that must stay
intact at the margin instead of splitting mid-word.
''';

Future<void> _pump(
  WidgetTester tester, {
  required Article article,
  Size size = const Size(390, 844),
  List<Override> overrides = const [],
  double? textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale ?? 1.0),
        ),
        child: MaterialApp(
          theme: _darkTheme(),
          home: ArticleDetailModal(
            article: article,
            onToggleSave: (_) {},
            onMarkRead: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

double _titleScaler(WidgetTester tester, String title) {
  final ctx = tester.element(find.text(title).first);
  return MediaQuery.textScalerOf(ctx).scale(1.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('A− / A+ controls', () {
    testWidgets('are visible on the article reader and scale the title',
        (tester) async {
      const title = 'Readable article title for the news reader';
      await _pump(
        tester,
        article: _article(
          category: 'Movies',
          title: title,
          isFullContent: true,
          summaryMarkdown: _prose,
        ),
      );

      expect(find.byKey(kNewsReaderTextSizeBarKey), findsOneWidget);
      expect(find.byKey(kNewsReaderTextIncreaseKey), findsOneWidget);
      expect(find.byKey(kNewsReaderTextDecreaseKey), findsOneWidget);
      expect(_titleScaler(tester, title), closeTo(1.0, 0.01));

      await tester.tap(find.byKey(kNewsReaderTextIncreaseKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(_titleScaler(tester, title), closeTo(1.15, 0.01));

      await tester.tap(find.byKey(kNewsReaderTextIncreaseKey));
      await tester.pump();
      expect(_titleScaler(tester, title), closeTo(1.30, 0.01));

      await tester.tap(find.byKey(kNewsReaderTextDecreaseKey));
      await tester.pump();
      expect(_titleScaler(tester, title), closeTo(1.15, 0.01));
    });

    testWidgets('chrome buttons keep their labels at max article scale',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'Movies',
          isFullContent: true,
          summaryMarkdown: _prose,
        ),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMax,
              hydrate: false,
            ),
          ),
        ],
      );

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Mark read'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Listen to Article'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Listen to Article'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A+ is disabled at the largest size', (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          summaryMarkdown: '## Short\n\nA compact AI summary paragraph.',
        ),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMax,
              hydrate: false,
            ),
          ),
        ],
      );

      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: find.byKey(kNewsReaderTextIncreaseKey),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        isTrue,
      );
      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: find.byKey(kNewsReaderTextDecreaseKey),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        isFalse,
      );
    });

    testWidgets('A− is disabled at the smallest size', (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          summaryMarkdown: '## Short\n\nA compact AI summary paragraph.',
        ),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMin,
              hydrate: false,
            ),
          ),
        ],
      );

      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: find.byKey(kNewsReaderTextDecreaseKey),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        isTrue,
      );
      expect(
        tester
            .widget<IgnorePointer>(
              find.descendant(
                of: find.byKey(kNewsReaderTextIncreaseKey),
                matching: find.byType(IgnorePointer),
              ),
            )
            .ignoring,
        isFalse,
      );
    });

    testWidgets('persists across a fresh reader open', (tester) async {
      const title = 'Readable article title for the news reader';
      await _pump(
        tester,
        article: _article(
          category: 'Movies',
          title: title,
          isFullContent: true,
          summaryMarkdown: _prose,
        ),
      );
      await tester.tap(find.byKey(kNewsReaderTextIncreaseKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kNewsReaderTextScalePrefKey), 1.15);

      await _pump(
        tester,
        article: _article(
          category: 'General',
          title: title,
          isFullContent: true,
          summaryMarkdown: _prose,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_titleScaler(tester, title), closeTo(1.15, 0.01));
    });
  });

  group('reflow + overflow', () {
    testWidgets('normal words wrap at 320px and largest size', (tester) async {
      const title =
          'A deliberately long article headline that should wrap across multiple lines without clipping the last word';
      await _pump(
        tester,
        size: const Size(320, 2800),
        article: _article(
          category: 'Movies',
          title: title,
          isFullContent: true,
          summaryMarkdown: _prose,
        ),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMax,
              hydrate: false,
            ),
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      final titleBox = tester.getRect(find.text(title).first);
      expect(titleBox.width, lessThanOrEqualTo(320));
      expect(titleBox.left, greaterThanOrEqualTo(-0.5));
      expect(titleBox.right, lessThanOrEqualTo(320.5));
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Original full article'), findsOneWidget);
    });

    testWidgets('rich markdown (code, table, long URL) at max scale 320px',
        (tester) async {
      const md = '''
## A heading that is itself quite long and needs to wrap gracefully on small screens

Opening paragraph with a very-long-unbreakable-token: https://example.com/some/extremely/long/path/that/cannot/be-broken/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa?q=1

Here is a fenced code block with an intentionally very long single line:

```python
def compute(a, b, c, d, e):  # a long comment that runs well beyond the viewport width to force wrapping or clipping rather than a yellow-black overflow
    return a + b + c + d + e
```

| Model | Context Window | Tokens/sec | Notes |
| --- | --- | --- | --- |
| Alpha-7B | 128k | 84 | Strong general reasoning performance overall |
| Beta-13B | 32k | 41 | Better at code generation and refactoring tasks |

- A bullet item that is reasonably long and should wrap to a new line within the available width without clipping
- Another bullet

> A blockquote that is also long enough to wrap across more than a single line in the narrow viewport.

Closing paragraph with everyday words that reflow when the type size changes.
''';
      await _pump(
        tester,
        size: const Size(320, 6400),
        article: _article(
          category: 'Movies',
          isFullContent: true,
          summaryMarkdown: md,
        ),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMax,
              hydrate: false,
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull,
          reason: 'Largest reader size must not overflow at 320px.');
    });

    testWidgets('legacy block list wraps at max scale', (tester) async {
      await _pump(
        tester,
        size: const Size(320, 2400),
        article: _article(
          category: 'Finance',
          blocks: const [
            ArticleBlock(
              type: 'heading',
              content:
                  'A heading that should wrap across lines on a narrow phone',
            ),
            ArticleBlock(
              type: 'paragraph',
              content:
                  'Paragraph words must remain whole at the edge of the screen while the column reflows at the largest reading size for this article.',
            ),
            ArticleBlock(
              type: 'quote',
              content:
                  'A quoted sentence that is long enough to wrap instead of overflowing the row.',
              label: 'Editor',
            ),
          ],
        ),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMax,
              hydrate: false,
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('compact AI-summary path at max scale on a 320px phone',
        (tester) async {
      await _pump(
        tester,
        size: const Size(320, 2400),
        article: _article(
          category: 'AI News',
          summaryMarkdown: '''
## Gemini ships a quieter on-device model

The update focuses on latency for summarization and translation. Everyday
words in this paragraph must wrap cleanly when the reader enlarges the type.

- First bullet with enough words to wrap on a small screen
- Second bullet stays inside the column
''',
        ),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMax,
              hydrate: false,
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sticky header with A−/A+ does not overflow after scroll',
        (tester) async {
      final body = List.generate(
        28,
        (i) =>
            'Paragraph $i of wrapping article prose used to create scroll extent so the sticky header appears with the text-size control.',
      ).join('\n\n');
      await _pump(
        tester,
        size: const Size(320, 640),
        article: _article(
          category: 'Movies',
          title:
              'Sticky header title that is long enough to ellipsize beside A plus A minus',
          isFullContent: true,
          summaryMarkdown: body,
        ),
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('reading_progress_bar')), findsOneWidget);
      expect(find.byKey(kNewsReaderTextSizeBarKey), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(kNewsReaderTextIncreaseKey));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('reader scale is clamped even when system text scale is huge',
        (tester) async {
      const title = 'Readable article title for the news reader';
      await _pump(
        tester,
        size: const Size(390, 2400),
        textScale: 2.0,
        article: _article(
          category: 'Movies',
          title: title,
          isFullContent: true,
          summaryMarkdown: _prose,
        ),
        overrides: [
          newsReaderTextScaleProvider.overrideWith(
            (ref) => NewsReaderTextScale(
              initial: kNewsReaderTextScaleMax,
              hydrate: false,
            ),
          ),
        ],
      );
      expect(_titleScaler(tester, title), kNewsReaderTextScaleMax);
      expect(find.text('Share'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
