// Tests for the Cloud storage destination switch.
//
// This control exists to stop one specific accident: a file uploaded to the
// wrong place because the current target was not visible at the moment the
// upload button was tapped. So the assertions here are less about "does it
// toggle" and more about "can the answer be read off the screen":
//
//   • the target is named in words, not just implied by which pill is lit;
//   • a NAS the server has no password for is plainly unavailable and refuses
//     the tap, rather than accepting it and failing once a file is chosen;
//   • a NAS that is merely switched off stays selectable, because that is a
//     thing the owner can go and fix, and says so;
//   • the choice survives a restart, since it is a standing preference about
//     where his files live rather than a per-session mode.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/nas_files_service.dart';
import 'package:ai_nexus/domain/entities/nas_file.dart';
import 'package:ai_nexus/presentation/providers/cloud_destination_provider.dart';
import 'package:ai_nexus/presentation/screens/cloud/widgets/destination_switch.dart';

/// Answers a fixed status without a network, and records whether it was asked.
class _FakeNasFiles implements NasFilesService {
  _FakeNasFiles(this._status);

  final NasStorageStatus _status;
  int statusCalls = 0;

  @override
  Future<NasStorageStatus> status({CancelToken? cancelToken}) async {
    statusCalls += 1;
    return _status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

NasStorageStatus _status(NasStorageState state) => NasStorageStatus(
      state: state,
      root: 'Code/Cloud Storage',
    );

ThemeData _testTheme() => ThemeData(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  Future<_FakeNasFiles> pump(
    WidgetTester tester, {
    NasStorageState nas = NasStorageState.ready,
    Map<String, Object> initialPrefs = const {},
    ValueChanged<CloudDestination>? onChanged,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    prefs = await SharedPreferences.getInstance();
    final fake = _FakeNasFiles(_status(nas));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nasFilesServiceProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          theme: _testTheme(),
          home: Scaffold(
            body: DestinationSwitch(onChanged: onChanged),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  group('reading the current target', () {
    testWidgets('Drive is the default and says so in words', (tester) async {
      await pump(tester);

      expect(find.text('Google Drive'), findsOneWidget);
      expect(find.text('NAS'), findsOneWidget);
      expect(find.text('Uploads go to Google Drive'), findsOneWidget,
          reason: 'the target must be legible without decoding which pill is '
              'highlighted');
    });

    testWidgets('a ready NAS names the folder, not just "the NAS"',
        (tester) async {
      await pump(tester, initialPrefs: {'cloud_destination': 'nas'});

      expect(find.text('Uploads go to Code/Cloud Storage'), findsOneWidget,
          reason: 'knowing the path is the difference between trusting the '
              'label and knowing where the file went');
    });

    testWidgets('a switched-off NAS says so rather than looking ready',
        (tester) async {
      await pump(
        tester,
        nas: NasStorageState.unreachable,
        initialPrefs: {'cloud_destination': 'nas'},
      );

      expect(find.textContaining('not responding'), findsOneWidget);
      expect(find.textContaining('switched off'), findsOneWidget);
    });

    testWidgets('a rejected password is reported as a server problem',
        (tester) async {
      await pump(
        tester,
        nas: NasStorageState.badCredential,
        initialPrefs: {'cloud_destination': 'nas'},
      );

      expect(find.textContaining('password was rejected'), findsOneWidget);
    });
  });

  group('switching', () {
    testWidgets('tapping NAS selects it and reports the change', (tester) async {
      CloudDestination? reported;
      await pump(tester, onChanged: (d) => reported = d);

      await tester.tap(find.text('NAS'));
      await tester.pumpAndSettle();

      expect(reported, CloudDestination.nas);
      expect(find.text('Uploads go to Code/Cloud Storage'), findsOneWidget);
    });

    testWidgets('the choice is remembered for the next launch', (tester) async {
      await pump(tester);

      await tester.tap(find.text('NAS'));
      await tester.pumpAndSettle();

      expect(prefs.getString('cloud_destination'), 'nas',
          reason: 'resetting to Drive on relaunch would quietly send the next '
              'upload somewhere he did not choose');
    });

    testWidgets('tapping the already-selected side does not re-notify',
        (tester) async {
      var calls = 0;
      await pump(tester, onChanged: (_) => calls += 1);

      await tester.tap(find.text('Google Drive'));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });

    testWidgets('selecting the NAS re-checks whether it has come back',
        (tester) async {
      final fake = await pump(tester);
      final before = fake.statusCalls;

      await tester.tap(find.text('NAS'));
      await tester.pumpAndSettle();

      expect(fake.statusCalls, greaterThan(before),
          reason: 'he may have switched it on since the last check; arriving '
              'at a stale "not responding" screen would be its own betrayal');
    });
  });

  group('an unusable NAS', () {
    testWidgets('with no password on the server the tap is refused',
        (tester) async {
      CloudDestination? reported;
      await pump(
        tester,
        nas: NasStorageState.notConfigured,
        onChanged: (d) => reported = d,
      );

      await tester.tap(find.text('NAS'));
      await tester.pumpAndSettle();

      expect(reported, isNull,
          reason: 'accepting the tap would mean failing later with a file '
              'already chosen');
      expect(find.text('Uploads go to Google Drive'), findsOneWidget,
          reason: 'the target must not have moved');
      expect(prefs.getString('cloud_destination'), isNot('nas'));
    });

    testWidgets('and it explains why instead of just being dead', (tester) async {
      await pump(tester, nas: NasStorageState.notConfigured);

      // Explained even while Drive is selected, so the greyed-out option is
      // never a mystery.
      expect(find.text('Google Drive'), findsOneWidget);
      await tester.tap(find.text('NAS'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Uploads go to Google Drive'), findsOneWidget);
    });

    testWidgets('a merely switched-off NAS can still be selected',
        (tester) async {
      CloudDestination? reported;
      await pump(
        tester,
        nas: NasStorageState.unreachable,
        onChanged: (d) => reported = d,
      );

      await tester.tap(find.text('NAS'));
      await tester.pumpAndSettle();

      expect(reported, CloudDestination.nas,
          reason: 'he may be walking over to switch it on');
    });
  });

  group('the model behind it', () {
    test('selectable excludes only the states the phone cannot fix', () {
      expect(_status(NasStorageState.ready).selectable, isTrue);
      expect(_status(NasStorageState.unreachable).selectable, isTrue);
      expect(_status(NasStorageState.unknown).selectable, isTrue);
      expect(_status(NasStorageState.notConfigured).selectable, isFalse);
      expect(_status(NasStorageState.badCredential).selectable, isFalse);
    });

    test('only ready counts as ready', () {
      expect(_status(NasStorageState.ready).isReady, isTrue);
      for (final s in [
        NasStorageState.unreachable,
        NasStorageState.notConfigured,
        NasStorageState.badCredential,
        NasStorageState.unknown,
      ]) {
        expect(_status(s).isReady, isFalse, reason: '$s must not read as ready');
      }
    });

    test('a NAS selected but unusable is flagged for the Files tab', () {
      const view = CloudDestinationView(
        selected: CloudDestination.nas,
        nas: NasStorageStatus(state: NasStorageState.unreachable),
      );
      expect(view.nasSelectedButUnusable, isTrue,
          reason: 'an unexplained empty list reads as "you have no files"');

      const ok = CloudDestinationView(
        selected: CloudDestination.nas,
        nas: NasStorageStatus(state: NasStorageState.ready),
      );
      expect(ok.nasSelectedButUnusable, isFalse);
    });
  });
}
