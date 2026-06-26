// White-theme rendering + token sanity tests.
//
// The app ships two palettes: AMOLED `AppColors.dark` (default) and
// `AppColors.white`. The white theme was polished across every screen; these
// tests guard two things that are easy to regress:
//
//   1. The `AppColors.white` palette and its visual tokens are fully populated,
//      distinct from dark where it matters, and `lerp`/`copyWith` are total
//      (so an animated dark<->white theme switch never throws).
//   2. The rich article reader (the most layout-heavy surface — inline images,
//      fenced code, tables, headings, the AI-summarize shimmer loader) renders
//      under the REAL white palette at a cramped 320px width with ZERO render
//      exceptions (overflow / invisible-paint safety on light backgrounds).

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/presentation/screens/auth/login_screen.dart';
import 'package:ai_nexus/presentation/screens/landing/landing_screen.dart';
import 'package:ai_nexus/presentation/screens/news/article_detail_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData _themeFor(AppColors palette) => ThemeData(
      brightness: palette.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: palette.bg,
      extensions: <ThemeExtension<dynamic>>[palette],
    );

ThemeData _whiteTheme() => _themeFor(AppColors.white);

Article _fullContentArticle(String markdown, {String category = 'AI News'}) =>
    Article(
      id: 'white-theme-test',
      title:
          'A deliberately long article headline that should wrap across multiple lines without ever overflowing horizontally on a narrow device in white theme',
      excerpt: 'Stress-test excerpt.',
      source: 'Test Source',
      category: category,
      imageUrl: '',
      readTime: 7,
      date: 'Jun 26, 2026',
      blocks: const [],
      summaryMarkdown: markdown,
      originalUrl: 'https://example.com/article',
      isFullContent: true,
    );

Future<void> _pumpNarrowWhite(WidgetTester tester, Article article) async {
  tester.view.physicalSize = const Size(320, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: _whiteTheme(),
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

  group('AppColors palette + tokens', () {
    test('white palette is light and fully populated', () {
      const w = AppColors.white;
      expect(w.isDark, isFalse);
      expect(w.bg, const Color(0xFFFFFFFF));
      // Primary text must be dark on white (readable).
      expect(w.text.computeLuminance(), lessThan(0.3));
      expect(w.bg.computeLuminance(), greaterThan(0.9));
      // New visual tokens are all present.
      for (final c in <Color>[
        w.shadowColor,
        w.glassFill,
        w.scrim,
        w.cardGradientTop,
        w.cardGradientBottom,
        w.shimmerBase,
        w.shimmerHighlight,
      ]) {
        expect(c, isA<Color>());
      }
      // White shadow is a soft, low-alpha lift (not a heavy black halo).
      expect(w.shadowColor.a, lessThan(0.25));
    });

    test('dark and white differ on the key substrate fields', () {
      const d = AppColors.dark;
      const w = AppColors.white;
      expect(d.bg, isNot(w.bg));
      expect(d.text, isNot(w.text));
      expect(d.isDark, isNot(w.isDark));
      expect(d.shadowColor, isNot(w.shadowColor));
    });

    test('lerp is total and snaps isDark at the midpoint', () {
      const d = AppColors.dark;
      const w = AppColors.white;
      // Endpoints + midpoint must all produce a valid palette (no null deref).
      for (final t in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
        final mid = d.lerp(w, t);
        expect(mid, isA<AppColors>());
      }
      expect(d.lerp(w, 0.49).isDark, isTrue);
      expect(d.lerp(w, 0.5).isDark, isFalse);
    });

    test('copyWith overrides only the named token', () {
      final c = AppColors.white.copyWith(shadowColor: const Color(0xFFABCDEF));
      expect(c.shadowColor, const Color(0xFFABCDEF));
      expect(c.bg, AppColors.white.bg);
      expect(c.isDark, isFalse);
    });
  });

  group('Article reader renders cleanly in WHITE theme at 320px', () {
    testWidgets('rich markdown: code, images, headings, lists, long token',
        (tester) async {
      const md = '''
## A heading that is itself quite long and needs to wrap gracefully on small screens

Opening paragraph with a very-long-unbreakable-token: https://example.com/some/extremely/long/path/that/cannot/be/broken/midway/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa?q=1

![Inline chart](https://cdn.example.com/chart.png)

```python
def compute(a, b, c, d, e):  # a long comment that runs well beyond the viewport width to force a horizontal scroll region rather than an overflow error
    return a + b + c + d + e
```

- A bullet item that is reasonably long and should wrap to a new line within the available width without clipping
- Another bullet

> A blockquote that is also long enough to wrap across more than a single line in the narrow viewport.

Closing paragraph.
''';
      await _pumpNarrowWhite(tester, _fullContentArticle(md));
      expect(tester.takeException(), isNull,
          reason: 'Rich full-content markdown must not overflow on white.');
    });

    testWidgets('markdown table does not overflow on white', (tester) async {
      const md = '''
## Comparison

| Model | Context Window | Tokens/sec | Notes |
| --- | --- | --- | --- |
| Alpha-7B | 128k | 84 | Strong general reasoning performance overall |
| Beta-13B | 32k | 41 | Better at code generation and refactoring tasks |

Body paragraph after the table to keep the reader flowing.
''';
      await _pumpNarrowWhite(tester, _fullContentArticle(md));
      expect(tester.takeException(), isNull,
          reason: 'Wide tables must not overflow on white at 320px.');
    });
  });

  // Pre-auth screens were converted from hardcoded-black to theme-following.
  // Verify both render with zero exceptions under BOTH palettes (these screens
  // run infinite entrance/pulse animations, so we pump finite frames rather
  // than pumpAndSettle).
  group('Pre-auth screens follow the theme without exceptions', () {
    Future<void> pump(WidgetTester tester, Widget child, AppColors p) async {
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: _themeFor(p), home: child),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
    }

    for (final p in const [AppColors.white, AppColors.dark]) {
      final label = p.isDark ? 'dark' : 'white';
      testWidgets('LandingScreen renders in $label theme', (tester) async {
        await pump(tester, const LandingScreen(), p);
        expect(tester.takeException(), isNull);
        // Scaffold background tracks the palette (not a hardcoded black).
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, p.bg);
      });

      testWidgets('LoginScreen renders in $label theme', (tester) async {
        await pump(tester, const LoginScreen(), p);
        expect(tester.takeException(), isNull);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, p.bg);
      });
    }
  });
}
