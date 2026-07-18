// Live integration test: exercises the REAL Google Drive service through the
// backend token broker. Requires network + configured cloud credentials, so it
// is tagged `live` and skipped in the default `flutter test` run (see
// dart_test.yaml). Run explicitly with:
//   flutter test --tags live --run-skipped test/google_drive_integration_test.dart
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/data/services/google_drive_service.dart';
void main() {
  late GoogleDriveService service;
  late File tempFile;
  String? uploadedFileId;

  setUpAll(() {
    service = GoogleDriveService();
  });

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('gdrive_test_');
    tempFile = File('${dir.path}${Platform.pathSeparator}test_upload_${Random().nextInt(99999)}.txt');
    final content = 'Nexus AI Cloud test file – ${DateTime.now().toIso8601String()}\n'
        'Random payload: ${List.generate(200, (_) => Random().nextInt(256)).join(',')}';
    tempFile.writeAsStringSync(content);
  });

  tearDown(() async {
    if (uploadedFileId != null) {
      try {
        await service.deleteFile(uploadedFileId!);
      } catch (_) {}
      uploadedFileId = null;
    }
    if (tempFile.existsSync()) tempFile.deleteSync();
    final parent = tempFile.parent;
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  test('Upload small file → verify → delete', () async {
    final fileSize = tempFile.lengthSync();
    expect(fileSize, greaterThan(0));

    int lastSent = 0;
    final info = await service.uploadFile(
      tempFile,
      onProgress: (sent, total) {
        expect(sent, greaterThanOrEqualTo(lastSent));
        expect(total, equals(fileSize));
        lastSent = sent;
      },
    );

    uploadedFileId = info.id;

    expect(info.id, isNotEmpty);
    expect(info.name, contains('test_upload_'));
    expect(info.size, equals(fileSize));
    expect(info.mimeType, equals('text/plain'));

    final listing = await service.listFiles(pageSize: 10);
    final found = listing.files.any((f) => f.id == info.id);
    expect(found, isTrue, reason: 'Uploaded file should appear in listing');

    await service.deleteFile(info.id);
    uploadedFileId = null;
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Storage quota returns valid data', () async {
    final quota = await service.getStorageQuota();

    expect(quota.limitBytes, greaterThan(0));
    expect(quota.totalGb, greaterThan(0));
    expect(quota.fraction, greaterThanOrEqualTo(0));
    expect(quota.fraction, lessThanOrEqualTo(1));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('listFiles returns valid result', () async {
    final result = await service.listFiles(pageSize: 5);

    expect(result.files, isA<List<DriveFileInfo>>());
    for (final f in result.files) {
      expect(f.id, isNotEmpty);
      expect(f.name, isNotEmpty);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('maxUploadBytes constant is 10 GB', () {
    expect(GoogleDriveService.maxUploadBytes, equals(10 * 1024 * 1024 * 1024));
  });
}
