// The Cloud tab must show one destination at a time — wholesale.
//
// The decision this protects: when the target is the NAS, the Files tab lists the
// NAS folder and nothing else; when it is Drive, only Drive. One place a file can
// be. A merged view would look richer and would also make "where is my file?"
// unanswerable, because two rows with the same name would be two different files
// with no way to tell them apart.
//
// The accident being designed against is narrower than that, though: uploading to
// the wrong place because the current target was not visible at the moment the
// button was tapped. So the assertions below care as much about what the screen
// *says* as about which list it fetched.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/google_drive_service.dart';
import 'package:ai_nexus/data/services/nas_files_service.dart';
import 'package:ai_nexus/domain/entities/nas_file.dart';
import 'package:ai_nexus/presentation/screens/cloud/cloud_screen.dart';

class _FakeDrive implements GoogleDriveService {
  _FakeDrive(this.files);

  final List<DriveFileInfo> files;
  int listCalls = 0;

  @override
  Future<DriveFileListResult> listFiles({
    String? pageToken,
    int pageSize = 50,
    String? searchQuery,
  }) async {
    listCalls += 1;
    return DriveFileListResult(files: files, nextPageToken: null);
  }

  @override
  Future<DriveStorageQuota> getStorageQuota() async =>
      const DriveStorageQuota(usageBytes: 1073741824, limitBytes: 16106127360);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _FakeNas implements NasFilesService {
  _FakeNas({this.files = const [], this.state = NasStorageState.ready, this.error});

  final List<NasFile> files;
  final NasStorageState state;
  final NasUnavailable? error;
  int listCalls = 0;

  @override
  Future<NasStorageStatus> status({CancelToken? cancelToken}) async =>
      NasStorageStatus(state: state, root: 'Code/Cloud Storage');

  @override
  Future<List<NasFile>> listFiles({CancelToken? cancelToken}) async {
    listCalls += 1;
    final e = error;
    if (e != null) throw e;
    return files;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

DriveFileInfo _drive(String name) => DriveFileInfo(
      id: 'id-$name',
      name: name,
      size: 1024,
      mimeType: 'text/plain',
      createdTime: DateTime(2026, 8, 18),
      modifiedTime: DateTime(2026, 8, 18),
      starred: false,
    );

NasFile _nas(String name) => NasFile(
      name: name,
      sizeBytes: 2048,
      modified: DateTime(2026, 8, 19),
      mimeType: 'text/plain',
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

  Future<({_FakeDrive drive, _FakeNas nas})> pump(
    WidgetTester tester, {
    required _FakeDrive drive,
    required _FakeNas nas,
    String destination = 'drive',
  }) async {
    // Taller than the 800x600 default. The Files tab stacks a capacity card,
    // the upload zone, a search bar and the filter chips above the list, so on
    // the default surface the file rows sit below the fold and are never laid
    // out — every assertion here would then pass or fail for the wrong reason.
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({'cloud_destination': destination});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          googleDriveServiceProvider.overrideWithValue(drive),
          nasFilesServiceProvider.overrideWithValue(nas),
        ],
        child: MaterialApp(
          theme: _testTheme(),
          home: const Scaffold(body: CloudScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (drive: drive, nas: nas);
  }

  group('one destination at a time', () {
    testWidgets('Drive selected shows only Drive files', (tester) async {
      final h = await pump(
        tester,
        drive: _FakeDrive([_drive('drive-only.txt')]),
        nas: _FakeNas(files: [_nas('nas-only.txt')]),
      );

      expect(find.text('drive-only.txt'), findsOneWidget);
      expect(find.text('nas-only.txt'), findsNothing,
          reason: 'a merged list makes "where is my file?" unanswerable');
      expect(h.nas.listCalls, 0, reason: 'the NAS should not even be asked');
    });

    testWidgets('NAS selected shows only NAS files', (tester) async {
      final h = await pump(
        tester,
        drive: _FakeDrive([_drive('drive-only.txt')]),
        nas: _FakeNas(files: [_nas('nas-only.txt')]),
        destination: 'nas',
      );

      expect(find.text('nas-only.txt'), findsOneWidget);
      expect(find.text('drive-only.txt'), findsNothing);
      expect(h.drive.listCalls, 0);
    });

    testWidgets('flipping the switch replaces the list wholesale',
        (tester) async {
      final h = await pump(
        tester,
        drive: _FakeDrive([_drive('drive-only.txt')]),
        nas: _FakeNas(files: [_nas('nas-only.txt')]),
      );

      expect(find.text('drive-only.txt'), findsOneWidget);

      await tester.tap(find.text('NAS'));
      await tester.pumpAndSettle();

      expect(find.text('nas-only.txt'), findsOneWidget);
      expect(find.text('drive-only.txt'), findsNothing,
          reason: 'the previous destination\'s files must not linger');
      expect(h.nas.listCalls, 1);

      // ...and back again.
      await tester.tap(find.text('Google Drive'));
      await tester.pumpAndSettle();

      expect(find.text('drive-only.txt'), findsOneWidget);
      expect(find.text('nas-only.txt'), findsNothing);
    });
  });

  group('the target is legible at the moment of upload', () {
    testWidgets('the upload button itself names Google Drive', (tester) async {
      await pump(tester, drive: _FakeDrive([]), nas: _FakeNas());

      expect(find.text('Tap to upload files to Google Drive'), findsOneWidget,
          reason: 'this is the control the finger is on, and the last thing '
              'read before the file picker takes the screen');
    });

    testWidgets('and names the NAS folder when that is the target',
        (tester) async {
      await pump(
        tester,
        drive: _FakeDrive([]),
        nas: _FakeNas(),
        destination: 'nas',
      );

      expect(find.text('Tap to upload files to Code/Cloud Storage'),
          findsOneWidget);
    });

    testWidgets('the switch above it agrees with the button', (tester) async {
      await pump(
        tester,
        drive: _FakeDrive([]),
        nas: _FakeNas(),
        destination: 'nas',
      );

      // Both the pinned switch and the upload zone name the same place, so
      // there is no reading of the screen that gets it wrong.
      expect(find.text('Uploads go to Code/Cloud Storage'), findsOneWidget);
      expect(find.text('Tap to upload files to Code/Cloud Storage'),
          findsOneWidget);
    });
  });

  group('an empty or broken NAS explains itself', () {
    testWidgets('an empty NAS folder says which folder is empty',
        (tester) async {
      await pump(
        tester,
        drive: _FakeDrive([]),
        nas: _FakeNas(),
        destination: 'nas',
      );

      expect(find.text('Nothing in Code/Cloud Storage yet'), findsOneWidget,
          reason: 'an unnamed empty list is exactly what someone sees after '
              'uploading to the other destination and looking in the wrong one');
    });

    testWidgets('a switched-off NAS offers the fix, and the way back',
        (tester) async {
      await pump(
        tester,
        drive: _FakeDrive([]),
        nas: _FakeNas(
          state: NasStorageState.unreachable,
          error: const NasUnavailable(
            'Your NAS is not reachable — it may be switched off.',
            reason: 'unreachable',
          ),
        ),
        destination: 'nas',
      );

      expect(find.text('NAS Not Reachable'), findsOneWidget);
      expect(find.textContaining('Switch the NAS on'), findsOneWidget);
      expect(find.textContaining('switch back to Google Drive'), findsOneWidget,
          reason: 'he should not have to work out that Drive still works');
    });

    testWidgets('an unconfigured NAS names the setting, not a vague failure',
        (tester) async {
      await pump(
        tester,
        drive: _FakeDrive([]),
        nas: _FakeNas(
          state: NasStorageState.notConfigured,
          error: const NasUnavailable(
            'NAS storage is not set up on the server yet.',
            reason: 'not_configured',
          ),
        ),
        destination: 'nas',
      );

      expect(find.text('NAS Not Set Up'), findsOneWidget);
      expect(find.textContaining('NAS_WEBDAV_PASSWORD'), findsOneWidget,
          reason: 'the owner is also the operator here; telling him the exact '
              'variable saves a hunt');
      expect(find.textContaining('Google Drive is unaffected'), findsOneWidget);
    });
  });

  group('Drive-only affordances are absent on the NAS', () {
    testWidgets('no starring, because a WebDAV share cannot remember one',
        (tester) async {
      await pump(
        tester,
        drive: _FakeDrive([]),
        nas: _FakeNas(files: [_nas('a.txt')]),
        destination: 'nas',
      );

      expect(find.text('a.txt'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
      // The download and delete actions remain — those the NAS can do.
      expect(find.byTooltip('Star'), findsNothing);
    });

    testWidgets('no 15 GB quota ring, which would be a made-up number',
        (tester) async {
      await pump(
        tester,
        drive: _FakeDrive([]),
        nas: _FakeNas(files: [_nas('a.txt')]),
        destination: 'nas',
      );

      expect(find.textContaining('15.0 GB'), findsNothing,
          reason: 'the NAS has no per-user quota; the real free-space figure '
              'belongs to the Stats dashboard, which measures it');
    });
  });
}
