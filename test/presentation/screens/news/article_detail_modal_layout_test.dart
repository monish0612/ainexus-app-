// Layout / scaling stress tests for [ArticleDetailModal]'s full-content
// reader. The new "beautify" pipeline emits rich markdown — inline images,
// fenced code (with long lines), tables, headings, lists — from 17 different
// RSS feeds whose HTML shapes vary wildly. This suite guarantees that NONE
// of those shapes produce a RenderFlex / RenderBox overflow at narrow phone
// widths (the classic "yellow-black stripes" scaling bug).
//
// Strategy: pump the modal at a deliberately cramped 320 px logical width
// with worst-case content and assert `tester.takeException()` stays null —
// Flutter reports overflow as a thrown FlutterError during paint, so an
// overflow anywhere in the tree fails the test.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/presentation/screens/news/article_detail_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData _testTheme() => ThemeData(
      extensions: const <ThemeExtension<dynamic>>[
        AppColors(
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

Article _fullContentArticle(String markdown, {String category = 'AI News'}) =>
    Article(
      id: 'layout-test',
      title:
          'A deliberately long article headline that should wrap across multiple lines without ever overflowing horizontally on a narrow device',
      excerpt: 'Stress-test excerpt.',
      source: 'Test Source',
      category: category,
      imageUrl: '',
      readTime: 7,
      date: 'Jun 25, 2026',
      blocks: const [],
      summaryMarkdown: markdown,
      originalUrl: 'https://example.com/article',
      isFullContent: true,
    );

Future<void> _pumpNarrow(WidgetTester tester, Article article) async {
  // 320 logical px wide — smaller than almost any real device — tall enough
  // to lay out the whole sliver tree so every widget actually paints.
  tester.view.physicalSize = const Size(320, 5200);
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

  group('ArticleDetailModal — layout has no overflow at 320px', () {
    testWidgets('long code line + inline images + headings + lists',
        (tester) async {
      const md = '''
## A heading that is itself quite long and needs to wrap gracefully on small screens

Opening paragraph with a very-long-unbreakable-token: https://example.com/some/extremely/long/path/that/cannot/be/broken/midway/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa?q=1

![Inline chart](https://cdn.example.com/chart.png)

Here is a fenced code block with an intentionally very long single line:

```python
def compute(a, b, c, d, e):  # a long comment that runs well beyond the viewport width to force a horizontal scroll region rather than an overflow error in the layout
    return a + b + c + d + e
```

- A bullet item that is reasonably long and should wrap to a new line within the available width without clipping
- Another bullet

![Second image](https://cdn.example.com/photo.jpg)

> A blockquote that is also long enough to wrap across more than a single line in the narrow viewport.

Closing paragraph.
''';
      await _pumpNarrow(tester, _fullContentArticle(md));
      expect(tester.takeException(), isNull,
          reason: 'Rich full-content markdown must not overflow at 320px.');
    });

    testWidgets('markdown table does not overflow', (tester) async {
      const md = '''
## Comparison

| Model | Context Window | Tokens/sec | Notes |
| --- | --- | --- | --- |
| Alpha-7B | 128k | 84 | Strong general reasoning performance overall |
| Beta-13B | 32k | 41 | Better at code generation and refactoring tasks |

Body paragraph after the table to keep the reader flowing.
''';
      await _pumpNarrow(tester, _fullContentArticle(md));
      expect(tester.takeException(), isNull,
          reason: 'Wide tables must not overflow at 320px.');
    });

    testWidgets('image-heavy newsletter body (Substack-shape) is stable',
        (tester) async {
      final imgs = List.generate(
        8,
        (i) =>
            '![Figure $i](https://substackcdn.com/image/fetch/w_1456,c_limit/$i.png)\n\nParagraph number $i with enough text to read like a real newsletter body and exercise the layout.',
      ).join('\n\n');
      await _pumpNarrow(tester, _fullContentArticle(imgs, category: 'Finance'));
      expect(tester.takeException(), isNull,
          reason: 'Image-heavy Substack bodies must lay out cleanly.');
    });
  });
}
