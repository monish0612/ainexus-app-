import 'dart:io';
import 'dart:typed_data';

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/narration_download.dart';
import 'package:ai_nexus/data/services/narration_download_store.dart';
import 'package:ai_nexus/presentation/screens/news/widgets/narration_listen_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _ogg() =>
    Uint8List.fromList(<int>[0x4F, 0x67, 0x67, 0x53, ...List<int>.filled(300, 1)]);

Future<void> _pumpDisc(WidgetTester tester, {required VoidCallback onTap}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const <ThemeExtension<dynamic>>[AppColors.dark]),
      home: Scaffold(
        body: NewsListenDownloadDisc(
          accentColor: const Color(0xFF3B82F6),
          articleId: 'disc-1',
          onTap: onTap,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tmp = await Directory.systemTemp.createTemp('nar-disc-');
    NarrationDownloadStore.debugRootOverride = tmp;
    NarrationDownloadStore.debugGetBytes = null;
    NarrationDownloadStore.instance.resetForTest();
    await NarrationDownloadStore.instance.hydrate();
  });

  tearDown(() async {
    NarrationDownloadStore.debugGetBytes = null;
    NarrationDownloadStore.debugRootOverride = null;
    NarrationDownloadStore.instance.resetForTest();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('idle disc is labeled Download audio and fires onTap',
      (tester) async {
    var taps = 0;
    await _pumpDisc(tester, onTap: () => taps += 1);
    expect(find.byKey(kNewsListenDownloadKey), findsOneWidget);
    expect(find.bySemanticsLabel('Download audio'), findsOneWidget);
    await tester.tap(find.byKey(kNewsListenDownloadKey));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('ready disc stays tappable so a vanished file can be retried',
      (tester) async {
    var taps = 0;
    NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
      return (status: 200, body: _ogg());
    };
    await tester.runAsync(
      () => NarrationDownloadStore.instance.download('disc-1'),
    );
    await _pumpDisc(tester, onTap: () => taps += 1);
    expect(find.bySemanticsLabel('Audio downloaded'), findsOneWidget);
    await tester.tap(find.byKey(kNewsListenDownloadKey));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('error disc is labeled Retry download and fires onTap',
      (tester) async {
    var taps = 0;
    NarrationDownloadStore.debugGetBytes = (url, headers, resume) async {
      return (status: 401, body: <int>[]);
    };
    await tester.runAsync(
      () => NarrationDownloadStore.instance.download('disc-1'),
    );
    await _pumpDisc(tester, onTap: () => taps += 1);
    expect(find.bySemanticsLabel('Retry download'), findsOneWidget);
    await tester.tap(find.byKey(kNewsListenDownloadKey));
    await tester.pump();
    expect(taps, 1);
  });
}
