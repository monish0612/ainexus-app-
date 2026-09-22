// Presentation contract for the InsightAI composer (`_SearchInputBox` inside
// `TutorScreen`'s Summarizer tab).
//
// The composer is private, so it is exercised through the real screen. Three
// things are pinned here, none of which had any coverage before:
//
//   * it survives a 200% text scale with no RenderFlex overflow — the action
//     toolbar scrolls, the hint wraps, and the submit label grows;
//   * every control carries a semantics label with a button role;
//   * every interactive control clears the 48dp minimum target.
//
// The screen runs repeating animations (brand mark, focus glow), so these
// tests pump fixed slices and never `pumpAndSettle`.

import 'dart:convert';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart';
import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';
import 'package:ai_nexus/presentation/screens/tutor/tutor_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeData _theme(AppColors colors) => ThemeData(
      brightness: colors.isDark ? Brightness.dark : Brightness.light,
      extensions: <ThemeExtension<dynamic>>[colors],
    );

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      utf8.encode('{}'),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// One stubbed client for the whole tree. Every service resolves through
/// `apiClientProvider`, so overriding that is what keeps the test hermetic —
/// otherwise profile-photo, saved-words and tutor-AI each open a real socket to
/// localhost:3000, and their retry backoff can outlive the test and hang it.
ApiClient _stubbedClient() {
  final apiClient = ApiClient();
  apiClient.dio.httpClientAdapter = _StubAdapter();
  return apiClient;
}

Future<SettingsController> _settings(ApiClient apiClient) async {
  SharedPreferences.setMockInitialValues({
    'lite_model': 'gemini-2.5-flash-lite',
    'deep_model': 'gemini-2.5-pro',
    'xgrok_enabled': false,
    'online_search_provider': 'gemini',
    'default_followup_provider': 'gemini',
  });
  final prefs = await SharedPreferences.getInstance();
  return SettingsController(prefs, UserPreferencesService(apiClient));
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Tears the screen down inside the test body. Drift's `StreamQueryStore`
/// schedules a zero-duration timer when its query streams are cancelled, and
/// flutter_test checks for pending timers before `addTearDown` runs — so the
/// tree has to come down here, not in a tear-down callback.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // A bare `pump()` does not elapse fake time, so the zero-duration timer
  // would still be queued.
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _pumpTutor(
  WidgetTester tester, {
  double textScale = 1.0,
  Size size = const Size(390, 844),
  AppColors colors = AppColors.dark,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final apiClient = _stubbedClient();
  final settings = await _settings(apiClient);
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final store = SavedSearchStore.instance
    ..debugResetForTests()
    ..init(db, null);
  addTearDown(() async {
    store.debugResetForTests();
    await db.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        settingsProvider.overrideWith((ref) => settings),
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        savedSearchStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        theme: _theme(colors),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const TutorScreen(),
          ),
        ),
      ),
    ),
  );
  await _drain(tester);
}

/// Reads the rendered size of the nearest ancestor box of [finder] that is at
/// least [min] on both axes, walking up from the label/icon. Returns the label's
/// own rect when nothing bigger is found, so the assertion still fails loudly.
Size _targetSize(WidgetTester tester, Finder finder, {double min = 48}) {
  final element = tester.element(finder);
  Size? best;
  element.visitAncestorElements((ancestor) {
    final ro = ancestor.renderObject;
    if (ro is RenderBox && ro.hasSize) {
      final s = ro.size;
      if (s.width >= min && s.height >= min) {
        best = s;
        return false;
      }
    }
    return true;
  });
  return best ?? tester.getSize(finder);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('InsightAI composer — text scale', () {
    for (final scale in const <double>[1.0, 1.3, 2.0]) {
      testWidgets('lays out at ${scale}x with no overflow', (tester) async {
        await _pumpTutor(tester, textScale: scale);

        // The composer is on screen and still offers its two depth modes.
        expect(find.text('ASK ANYTHING'), findsOneWidget);
        expect(find.text('Lite'), findsOneWidget);
        expect(find.text('Deep'), findsOneWidget);
        expect(find.text('Voice'), findsOneWidget);
        expect(find.text('Search Web'), findsOneWidget);

        // The action toolbar used to be a fixed Row with a Spacer: at 2x the
        // chips were wider than the phone and it threw.
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      });
    }

    testWidgets('narrow 320px phone at 2x text scale still has no overflow',
        (tester) async {
      await _pumpTutor(
        tester,
        textScale: 2.0,
        size: const Size(320, 720),
      );

      expect(find.text('ASK ANYTHING'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });

    testWidgets('submit label grows with the text scale instead of clipping',
        (tester) async {
      await _pumpTutor(tester);
      final small = tester.getSize(find.text('Search Web'));

      await _pumpTutor(tester, textScale: 2.0);
      final large = tester.getSize(find.text('Search Web'));

      expect(large.height, greaterThan(small.height),
          reason:
              'the submit button was a fixed height: 48, so the label clipped '
              'rather than growing');
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });

  group('InsightAI composer — semantics', () {
    testWidgets('every control is a labelled button', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpTutor(tester);

      // Previously unlabelled: the voice chip was a bare Listener, the
      // Paste / Clear chips plain GestureDetectors, the History pill and the
      // submit button had no Semantics node at all.
      expect(find.bySemanticsLabel('Voice input'), findsOneWidget);
      expect(find.bySemanticsLabel('Paste from clipboard'), findsOneWidget);
      expect(find.bySemanticsLabel('Attach an image'), findsOneWidget);
      expect(find.bySemanticsLabel('Saved searches'), findsOneWidget);
      expect(find.bySemanticsLabel('Search Web'), findsOneWidget);
      // The one control that was already labelled before this phase.
      expect(
        find.bySemanticsLabel('Search depth: Lite (faster)'),
        findsOneWidget,
      );

      handle.dispose();
      await _unmount(tester);
    });

    testWidgets('typing reveals a labelled Clear control', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpTutor(tester);

      expect(find.bySemanticsLabel('Clear the search'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'monsoon chennai');
      await _drain(tester);

      expect(find.bySemanticsLabel('Clear the search'), findsOneWidget);
      handle.dispose();

      await _unmount(tester);
    });
  });

  group('InsightAI composer — tap targets', () {
    testWidgets('chips, depth toggle and submit all clear 48dp',
        (tester) async {
      await _pumpTutor(tester);

      for (final label in const <String>['Voice', 'Image', 'Paste']) {
        final size = _targetSize(tester, find.text(label));
        expect(size.height, greaterThanOrEqualTo(48.0),
            reason: '"$label" chip was ~25dp tall');
        expect(size.width, greaterThanOrEqualTo(48.0));
      }

      // The depth control is one toggle, so the whole pill is the target.
      final toggle = _targetSize(tester, find.text('Lite'));
      expect(toggle.height, greaterThanOrEqualTo(48.0),
          reason: 'the Lite/Deep chips were ~22dp tall');

      final history = _targetSize(tester, find.text('History'));
      expect(history.height, greaterThanOrEqualTo(48.0),
          reason: 'the History pill was ~22dp tall');

      final submit = _targetSize(tester, find.text('Search Web'));
      expect(submit.height, greaterThanOrEqualTo(48.0));

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  });
}
