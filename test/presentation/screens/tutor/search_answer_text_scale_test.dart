// Online-search A− / A+ — same steps and preference as the news reader.
//
// Only the answer markdown sits inside [ArticleReaderProse]. ANSWER / Copy /
// Expand chrome stays unscaled so the card cannot overflow at 1.70.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/screens/news/news_reader_text_scale.dart';
import 'package:ai_nexus/presentation/screens/tutor/search_answer_text_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

const _prose = 'SEARCH-PROSE-SENTINEL-CHENNAI monsoon streets and tomatoes.';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<Override> overrides = const [],
  double systemTextScale = 1.0,
  String markdown = _prose,
  Widget? trailing,
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
          textScaler: TextScaler.linear(systemTextScale),
        ),
        child: MaterialApp(
          theme: _darkTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchAnswerSectionHeader(
                    label: 'ANSWER',
                    labelStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    trailing: trailing ?? const Text('Copy'),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: ArticleReaderProse(
                        child: MarkdownBody(data: markdown),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _scalerOf(WidgetTester tester, Finder finder) {
  final ctx = tester.element(finder);
  return MediaQuery.textScalerOf(ctx).scale(1.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('A− / A+ sit on the answer header and scale only the body',
      (tester) async {
    await _pump(tester);

    expect(find.byKey(kSearchAnswerTextSizeBarKey), findsOneWidget);
    expect(find.byKey(kSearchAnswerTextIncreaseKey), findsOneWidget);
    expect(find.byKey(kSearchAnswerTextDecreaseKey), findsOneWidget);
    expect(find.byKey(kNewsReaderTextSizeBarKey), findsNothing);

    expect(_scalerOf(tester, find.textContaining('SEARCH-PROSE-SENTINEL')),
        closeTo(1.0, 0.01));
    expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
    expect(_scalerOf(tester, find.text('ANSWER')), closeTo(1.0, 0.01));

    await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
    await tester.pump();
    expect(_scalerOf(tester, find.textContaining('SEARCH-PROSE-SENTINEL')),
        closeTo(1.15, 0.01));
    expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
    expect(_scalerOf(tester, find.text('ANSWER')), closeTo(1.0, 0.01));

    await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
    await tester.pump();
    expect(_scalerOf(tester, find.textContaining('SEARCH-PROSE-SENTINEL')),
        closeTo(1.30, 0.01));

    await tester.tap(find.byKey(kSearchAnswerTextDecreaseKey));
    await tester.pump();
    expect(_scalerOf(tester, find.textContaining('SEARCH-PROSE-SENTINEL')),
        closeTo(1.15, 0.01));
  });

  testWidgets('shares the news-reader preference key', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kNewsReaderTextScalePrefKey), 1.15);
  });

  testWidgets('A+ is disabled at the largest size', (tester) async {
    await _pump(
      tester,
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
              of: find.byKey(kSearchAnswerTextIncreaseKey),
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
              of: find.byKey(kSearchAnswerTextDecreaseKey),
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring,
      isFalse,
    );
    expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
  });

  testWidgets('header + body do not overflow at 320px and max scale',
      (tester) async {
    await _pump(
      tester,
      size: const Size(320, 900),
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
    expect(find.byKey(kSearchAnswerTextSizeBarKey), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('ANSWER'), findsOneWidget);
  });

  testWidgets('A− is disabled at the smallest size', (tester) async {
    await _pump(
      tester,
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
              of: find.byKey(kSearchAnswerTextDecreaseKey),
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
              of: find.byKey(kSearchAnswerTextIncreaseKey),
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring,
      isFalse,
    );
  });

  testWidgets('A+ walks every discrete step up to max', (tester) async {
    await _pump(tester);
    for (final step in kNewsReaderTextScaleSteps.where((s) => s > 1.001)) {
      await tester.tap(find.byKey(kSearchAnswerTextIncreaseKey));
      await tester.pump();
      expect(
        _scalerOf(tester, find.textContaining('SEARCH-PROSE-SENTINEL')),
        closeTo(step, 0.01),
        reason: 'expected reader step $step',
      );
      expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
    }
    expect(
      tester
          .widget<IgnorePointer>(
            find.descendant(
              of: find.byKey(kSearchAnswerTextIncreaseKey),
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring,
      isTrue,
    );
  });

  testWidgets('system accessibility scale is clamped inside search prose',
      (tester) async {
    await _pump(
      tester,
      systemTextScale: 2.5,
      overrides: [
        newsReaderTextScaleProvider.overrideWith(
          (ref) => NewsReaderTextScale(
            initial: kNewsReaderTextScaleMax,
            hydrate: false,
          ),
        ),
      ],
    );

    // Combined scaler clamps to kNewsReaderTextScaleMax (1.70), never 2.5*1.7.
    expect(
      _scalerOf(tester, find.textContaining('SEARCH-PROSE-SENTINEL')),
      closeTo(kNewsReaderTextScaleMax, 0.01),
    );
    expect(_scalerOf(tester, find.text('Copy')), closeTo(1.0, 0.01));
    expect(_scalerOf(tester, find.text('ANSWER')), closeTo(1.0, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hydrates the saved news-reader step on first search paint',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{kNewsReaderTextScalePrefKey: 1.45},
    );
    await _pump(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      _scalerOf(tester, find.textContaining('SEARCH-PROSE-SENTINEL')),
      closeTo(1.45, 0.01),
    );
  });

  testWidgets('rich markdown + long Copy label do not overflow at 320px max',
      (tester) async {
    const md = '''
## LOOKUP-HEADING-SENTINEL that should wrap on a narrow phone

Opening paragraph SEARCH-PROSE-SENTINEL-CHENNAI with a long URL
https://example.com/some/extremely/long/path/that/cannot/be-broken/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa?q=1

```python
def compute(a, b, c, d, e):  # a long comment that runs well beyond the viewport width
    return a + b + c + d + e
```

| Model | Context Window | Notes |
| --- | --- | --- |
| Alpha-7B | 128k | Strong general reasoning performance overall |
| Beta-13B | 32k | Better at code generation and refactoring tasks |

- A bullet item that is reasonably long and should wrap to a new line
> A blockquote that is also long enough to wrap across more than a single line
''';
    await _pump(
      tester,
      size: const Size(320, 2400),
      markdown: md,
      trailing: const Text('Copy all results'),
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
    expect(find.text('ANSWER'), findsOneWidget);
    expect(find.text('Copy all results'), findsOneWidget);
    expect(find.byKey(kSearchAnswerTextSizeBarKey), findsOneWidget);
    expect(_scalerOf(tester, find.text('Copy all results')), closeTo(1.0, 0.01));
    expect(_scalerOf(tester, find.text('ANSWER')), closeTo(1.0, 0.01));
  });
}
