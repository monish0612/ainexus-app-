// Deep edge-case tests for the article-reader UX changes:
//
//   1. The redundant standalone RSS excerpt is no longer rendered in the
//      detail view (it duplicated the lead of the body for every article).
//   2. A scroll-driven reading-progress bar appears in the sticky header
//      once the user scrolls past the title, tracks the read-through
//      fraction, and never causes a horizontal overflow at any width.
//   3. The TTS narration subtitle reads "On-device voice narration"
//      (the stray "AI" wording was dropped).
//   4. The listen / Play control sits directly under AI Summarize (or at the
//      top of legacy summaries) so it is reachable without scrolling the body.
//
// The suite is intentionally adversarial: short bodies, empty bodies,
// extremely long titles, the narrowest realistic phone (320 px) and a
// taller body, plus every content path (full-content, legacy AI summary,
// block-list, Gizbot review). Flutter surfaces a layout overflow as a
// thrown FlutterError during paint, so `tester.takeException()` staying
// null is the overflow guard.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/presentation/screens/news/article_detail_modal.dart';
import 'package:ai_nexus/presentation/screens/news/widgets/narration_listen_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _progressKey = ValueKey('reading_progress_bar');

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
  String excerpt = 'UNIQUE-EXCERPT-SENTINEL that should never be rendered.',
  String? summaryMarkdown,
  String? summaryShort,
  bool isFullContent = false,
  String title = 'A reasonably sized article title for the reader',
  List<ArticleBlock> blocks = const [],
}) =>
    Article(
      id: 'reader-${category.toLowerCase()}',
      title: title,
      excerpt: excerpt,
      source: 'Test Source',
      category: category,
      imageUrl: '',
      readTime: 5,
      date: 'Jun 26, 2026',
      blocks: blocks,
      summaryMarkdown: summaryMarkdown,
      summaryShort: summaryShort,
      originalUrl: 'https://example.com/article',
      isFullContent: isFullContent,
    );

/// A long markdown body so the [CustomScrollView] actually has scroll extent
/// at a phone-sized viewport (needed to exercise the sticky header + progress
/// bar).
String _longBody() => List.generate(
      40,
      (i) =>
          'Paragraph $i: this is a meaningful chunk of article prose that takes '
          'up real vertical space so the reader has something to scroll '
          'through and the reading-progress affordance has a range to track.',
    ).join('\n\n');

Future<void> _pump(
  WidgetTester tester, {
  required Article article,
  Size size = const Size(390, 844),
  ValueChanged<bool>? onToggleSave,
  VoidCallback? onMarkRead,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: _darkTheme(),
        home: ArticleDetailModal(
          article: article,
          onToggleSave: onToggleSave ?? (_) {},
          onMarkRead: onMarkRead ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _scrollBy(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

/// All RichText (rendered markdown + plain Text) flattened to a single
/// string — lets us assert that a sentinel string appears nowhere on screen.
String _allText(WidgetTester tester) {
  final rich = tester
      .widgetList<RichText>(find.byType(RichText))
      .map((r) => r.text.toPlainText());
  final editable = tester
      .widgetList<EditableText>(find.byType(EditableText))
      .map((e) => e.controller.text);
  return [...rich, ...editable].join(' || ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // ───────────────────────────────────────────────────────────────────────
  group('reader UX — redundant excerpt removed', () {
    testWidgets('full-content article does NOT render the standalone excerpt',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: 'Real body paragraph one.\n\nReal body paragraph two.',
        ),
      );

      expect(
        find.textContaining('UNIQUE-EXCERPT-SENTINEL'),
        findsNothing,
        reason: 'The standalone excerpt must no longer be rendered.',
      );
      expect(_allText(tester).contains('UNIQUE-EXCERPT-SENTINEL'), isFalse);
      // Body still renders.
      expect(find.textContaining('Real body paragraph one'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('legacy AI-summary (Finance) article does NOT render the excerpt',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'Finance',
          summaryMarkdown: '## Why this matters\n\nCondensed AI summary body.',
        ),
      );

      expect(find.textContaining('UNIQUE-EXCERPT-SENTINEL'), findsNothing);
      expect(_allText(tester).contains('Condensed AI summary body'), isTrue);
      await _drain(tester);
    });

    testWidgets('block-list article (no markdown) does NOT render the excerpt',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          summaryMarkdown: null,
          blocks: const [
            ArticleBlock(type: 'paragraph', content: 'A block-based paragraph.'),
          ],
        ),
      );

      expect(find.textContaining('UNIQUE-EXCERPT-SENTINEL'), findsNothing);
      expect(find.textContaining('A block-based paragraph'), findsOneWidget);
      await _drain(tester);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('reader UX — reading-progress bar', () {
    testWidgets('not shown at the top (offset 0)', (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: _longBody(),
        ),
      );

      expect(find.byKey(_progressKey), findsNothing,
          reason: 'Progress bar only appears after the reader scrolls.');
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });

    testWidgets('appears after scrolling past the threshold, no overflow',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: _longBody(),
        ),
      );

      await _scrollBy(tester, -400);

      expect(find.byKey(_progressKey), findsOneWidget,
          reason: 'Scrolling > 140px must reveal the sticky-header progress bar.');
      expect(tester.takeException(), isNull,
          reason: 'Sticky header + progress bar must not overflow.');
      await _drain(tester);
    });

    testWidgets('progress fraction grows from partial toward full as you scroll',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: _longBody(),
        ),
      );

      await _scrollBy(tester, -400);
      final early = _progressFactor(tester);
      expect(early, greaterThan(0.0));
      expect(early, lessThanOrEqualTo(1.0));

      // Fling all the way to the bottom.
      await _scrollBy(tester, -20000);
      final late = _progressFactor(tester);
      expect(late, greaterThanOrEqualTo(early),
          reason: 'Reading progress must be monotonic with downward scroll.');
      expect(late, lessThanOrEqualTo(1.0),
          reason: 'Progress fraction must be clamped to 1.0.');
      await _drain(tester);
    });

    testWidgets('narrowest device (320px) + long body: no overflow when scrolled',
        (tester) async {
      await _pump(
        tester,
        size: const Size(320, 640),
        article: _article(
          category: 'AI News',
          isFullContent: true,
          title:
              'An extremely long article headline that is engineered to wrap across many lines and stress the sticky header ellipsis on the very narrowest of phones',
          summaryMarkdown: _longBody(),
        ),
      );

      await _scrollBy(tester, -600);
      expect(find.byKey(_progressKey), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'No overflow at 320px with a long title + progress bar.');

      await _scrollBy(tester, -50000);
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });

    testWidgets('short article that fits the viewport never overflows / divides by zero',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: 'A single short paragraph.',
        ),
      );

      // Attempt to scroll even though there's little/no extent.
      await _scrollBy(tester, -50);
      expect(tester.takeException(), isNull,
          reason: 'maxScrollExtent==0 must not throw (no divide-by-zero).');
      await _drain(tester);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('reader UX — TTS narration label', () {
    testWidgets('idle TTS bar shows "On-device voice narration" (no "AI")',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: 'Body for narration test.\n\nSecond paragraph.',
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Listen to Article'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('On-device voice narration'), findsOneWidget);
      expect(find.text('On-device AI narration'), findsNothing);
      // Full-content articles narrate the article itself.
      expect(find.text('Listen to Article'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets(
        'listen control sits below AI Summarize and above the article body',
        (tester) async {
      await _pump(
        tester,
        size: const Size(390, 2400),
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown:
              'Picture a support inbox for a bank. Every message needs a category.\n\nSecond paragraph of the original article body.',
        ),
      );
      await tester.pump();

      expect(find.text('AI Summarize'), findsOneWidget);
      expect(find.text('Listen to Article'), findsOneWidget);
      expect(find.byKey(const ValueKey('article-listen-bar')), findsOneWidget);

      final titleY = tester
          .getTopLeft(find.text('A reasonably sized article title for the reader'))
          .dy;
      final summarizeY = tester.getTopLeft(find.text('AI Summarize')).dy;
      final listenY = tester.getTopLeft(find.text('Listen to Article')).dy;
      final bodyY = tester
          .getTopLeft(find.textContaining('Picture a support inbox for a bank'))
          .dy;
      final originalY = tester.getTopLeft(find.text('Read Original Article')).dy;

      expect(titleY, lessThan(summarizeY),
          reason: 'Title must lead, then Summarize.');
      expect(summarizeY, lessThan(listenY),
          reason: 'Listen sits directly under AI Summarize.');
      expect(listenY, lessThan(bodyY),
          reason: 'Listen must sit above the article body so Play is reachable.');
      expect(bodyY, lessThan(originalY));
      expect(listenY, lessThan(originalY));
      await _drain(tester);
    });

    testWidgets('phone viewport shows Listen under Summarize without scrolling',
        (tester) async {
      await _pump(
        tester,
        size: const Size(390, 844),
        article: _article(
          category: 'AI News',
          isFullContent: true,
          title: 'Short title',
          summaryMarkdown: 'Opening sentence of the original article body.',
        ),
      );
      await tester.pump();

      final listen = tester.getRect(find.text('Listen to Article'));
      expect(listen.top, greaterThan(0));
      expect(listen.bottom, lessThan(844),
          reason: 'Play must be on-screen on a typical phone, not below the fold.');
      expect(
        tester.getTopLeft(find.text('AI Summarize')).dy,
        lessThan(listen.top),
      );
      await _drain(tester);
    });

    testWidgets('exactly one listen control — never duplicated at the footer',
        (tester) async {
      await _pump(
        tester,
        size: const Size(390, 2400),
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown:
              'Body paragraph one.\n\nBody paragraph two that used to sit above Play.',
        ),
      );
      await tester.pump();

      expect(find.text('Listen to Article'), findsOneWidget);
      expect(find.byKey(const ValueKey('article-listen-bar')), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('legacy Finance summary: Listen sits above the body, no Summarize CTA',
        (tester) async {
      await _pump(
        tester,
        size: const Size(390, 2400),
        article: _article(
          category: 'Finance',
          summaryMarkdown:
              '## Why this matters\n\nLEGACY-FINANCE-BODY that the listen bar must sit above.',
        ),
      );
      await tester.pump();

      expect(find.text('AI Summarize'), findsNothing);
      expect(find.text('Listen to Summary'), findsOneWidget);
      expect(find.text('Listen to Article'), findsNothing);

      final listenY = tester.getTopLeft(find.text('Listen to Summary')).dy;
      final bodyY =
          tester.getTopLeft(find.textContaining('LEGACY-FINANCE-BODY')).dy;
      expect(listenY, lessThan(bodyY));
      await _drain(tester);
    });

    testWidgets('Movies: Listen sits under AI Summarize and above the review body',
        (tester) async {
      await _pump(
        tester,
        size: const Size(390, 2400),
        article: _article(
          category: 'Movies',
          isFullContent: true,
          summaryMarkdown:
              'MOVIE-BODY-SENTINEL after Rocky, the director returns with DC.',
        ),
      );
      await tester.pump();

      expect(find.text('AI Summarize'), findsOneWidget);
      expect(find.text('Listen to Article'), findsOneWidget);

      final summarizeY = tester.getTopLeft(find.text('AI Summarize')).dy;
      final listenY = tester.getTopLeft(find.text('Listen to Article')).dy;
      final bodyY =
          tester.getTopLeft(find.textContaining('MOVIE-BODY-SENTINEL')).dy;
      expect(summarizeY, lessThan(listenY));
      expect(listenY, lessThan(bodyY));
      await _drain(tester);
    });

    testWidgets('cached AI Summary toggle keeps Listen above the summary body',
        (tester) async {
      await _pump(
        tester,
        size: const Size(390, 2400),
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: 'FULL-BODY-SENTINEL original article paragraph.',
          summaryShort: 'CACHED-SUMMARY-SENTINEL lede for the toggle.',
        ),
      );
      await tester.pump();

      await tester.tap(find.text('AI Summary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Listen to Article'), findsOneWidget);
      final listenY = tester.getTopLeft(find.text('Listen to Article')).dy;
      final summaryY =
          tester.getTopLeft(find.textContaining('CACHED-SUMMARY-SENTINEL')).dy;
      expect(listenY, lessThan(summaryY));
      expect(find.text('FULL-BODY-SENTINEL original article paragraph.'),
          findsNothing);
      await _drain(tester);
    });

    testWidgets('narrow 320px phone: Listen under Summarize does not overflow',
        (tester) async {
      await _pump(
        tester,
        size: const Size(320, 2400),
        article: _article(
          category: 'AI News',
          isFullContent: true,
          title:
              'A deliberately long article headline that should wrap across multiple lines',
          summaryMarkdown: _longBody(),
        ),
      );
      await tester.pump();

      expect(find.text('AI Summarize'), findsOneWidget);
      expect(find.text('Listen to Article'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('AI Summarize')).dy,
        lessThan(tester.getTopLeft(find.text('Listen to Article')).dy),
      );
      expect(tester.takeException(), isNull,
          reason: 'Listen card + summarize CTA must not overflow at 320px.');
      await _drain(tester);
    });

    testWidgets('320x640 viewport can scroll a short way to reveal Play',
        (tester) async {
      await _pump(
        tester,
        size: const Size(320, 640),
        article: _article(
          category: 'AI News',
          isFullContent: true,
          title: 'Short title',
          summaryMarkdown: 'Opening sentence of the original article body.',
        ),
      );
      await tester.pump();

      expect(find.text('AI Summarize'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Listen to Article', skipOffstage: false),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Listen to Article'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });

    testWidgets('General: Listen sits under AI Summarize like other full-content',
        (tester) async {
      await _pump(
        tester,
        size: const Size(390, 2400),
        article: _article(
          category: 'General',
          isFullContent: true,
          summaryMarkdown: 'GENERAL-BODY-SENTINEL for the top listen placement.',
        ),
      );
      await tester.pump();

      expect(find.text('AI Summarize'), findsOneWidget);
      expect(find.text('Listen to Article'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('AI Summarize')).dy,
        lessThan(tester.getTopLeft(find.text('Listen to Article')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Listen to Article')).dy,
        lessThan(
          tester.getTopLeft(find.textContaining('GENERAL-BODY-SENTINEL')).dy,
        ),
      );
      await _drain(tester);
    });

    testWidgets('download control sits next to Listen without overflowing 320px',
        (tester) async {
      await _pump(
        tester,
        size: const Size(320, 2400),
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: 'Download-button body for the listen row.',
        ),
      );
      await tester.pump();

      expect(find.byKey(kNewsListenDownloadKey), findsOneWidget);
      expect(find.text('Listen to Article'), findsOneWidget);
      expect(find.byType(NewsListenPlayDisc), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(kNewsListenDownloadKey)).dx,
        lessThan(tester.getTopLeft(find.byType(NewsListenPlayDisc)).dx),
      );
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });

    testWidgets('download control is present for Movies and legacy Finance',
        (tester) async {
      await _pump(
        tester,
        size: const Size(390, 2400),
        article: _article(
          category: 'Movies',
          isFullContent: true,
          summaryMarkdown: 'Movie body for download placement.',
        ),
      );
      await tester.pump();
      expect(find.byKey(kNewsListenDownloadKey), findsOneWidget);

      await _pump(
        tester,
        size: const Size(390, 2400),
        article: _article(
          category: 'Finance',
          summaryMarkdown: '## Why\n\nLegacy finance summary for download.',
        ),
      );
      await tester.pump();
      expect(find.byKey(kNewsListenDownloadKey), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('empty speakable body does not crash the top listen slot',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          excerpt: '',
          isFullContent: true,
          summaryMarkdown: null,
          blocks: const [],
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('AI Summarize'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      await _drain(tester);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('reader UX — content edge cases (no crash / chrome intact)', () {
    testWidgets('empty excerpt + empty body still renders header chrome',
        (tester) async {
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          excerpt: '',
          isFullContent: true,
          summaryMarkdown: null,
          blocks: const [],
        ),
      );

      expect(tester.takeException(), isNull);
      // Title + bottom-bar actions remain reachable.
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Mark read'), findsOneWidget);
      // "Read Original Article" source card still offered.
      expect(find.text('Read Original Article'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('save wiring still fires after the excerpt removal',
        (tester) async {
      bool? captured;
      await _pump(
        tester,
        article: _article(
          category: 'AI News',
          isFullContent: true,
          summaryMarkdown: 'Body.\n\nMore body.',
        ),
        onToggleSave: (v) => captured = v,
      );

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(captured, isTrue);
      await _drain(tester);
    });

    testWidgets('mark-read wiring still fires', (tester) async {
      var marked = false;
      await _pump(
        tester,
        article: _article(
          category: 'Finance',
          summaryMarkdown: '## Heading\n\nSummary.',
        ),
        onMarkRead: () => marked = true,
      );

      await tester.tap(find.text('Mark read'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(marked, isTrue);
      await _drain(tester);
    });
  });
}

/// Reads the live width-factor of the reading-progress fill so tests can
/// assert it grows monotonically and stays clamped.
double _progressFactor(WidgetTester tester) {
  final fill = tester.widget<FractionallySizedBox>(
    find.descendant(
      of: find.byKey(_progressKey),
      matching: find.byType(FractionallySizedBox),
    ),
  );
  return fill.widthFactor ?? 0;
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 600));
}
