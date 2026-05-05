import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/data/services/google_drive_service.dart';

/// Integration test that exercises the resumable (chunked) upload path.
/// This creates a ~6 MB file to exceed the 5 MB simple threshold.
/// Requires network access.
void main() {
  late GoogleDriveService service;
  late File largeFile;
  String? uploadedFileId;

  setUpAll(() {
    service = GoogleDriveService();
  });

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('gdrive_chunk_test_');
    largeFile = File('${dir.path}${Platform.pathSeparator}chunk_test_${Random().nextInt(99999)}.bin');
    final rng = Random(42);
    final bytes = Uint8List(6 * 1024 * 1024);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    largeFile.writeAsBytesSync(bytes);
  });

  tearDown(() async {
    if (uploadedFileId != null) {
      try {
        await service.deleteFile(uploadedFileId!);
      } catch (_) {}
      uploadedFileId = null;
    }
    if (largeFile.existsSync()) largeFile.deleteSync();
    final parent = largeFile.parent;
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  test('Resumable upload (6 MB chunked) → verify → delete', () async {
    final fileSize = largeFile.lengthSync();
    expect(fileSize, equals(6 * 1024 * 1024));

    final progressSnapshots = <double>[];

    final info = await service.uploadFile(
      largeFile,
      onProgress: (sent, total) {
        final pct = sent / total;
        progressSnapshots.add(pct);
      },
    );

    uploadedFileId = info.id;

    expect(info.id, isNotEmpty);
    expect(info.name, contains('chunk_test_'));
    expect(info.size, equals(fileSize));
    expect(info.mimeType, equals('application/octet-stream'));

    expect(progressSnapshots, isNotEmpty);
    expect(progressSnapshots.last, closeTo(1.0, 0.01));

    await service.deleteFile(info.id);
    uploadedFileId = null;
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('CancelToken cancels upload', () async {
    final cancelToken = CancelToken();

    Future.delayed(const Duration(milliseconds: 500), () {
      cancelToken.cancel('Test cancel');
    });

    try {
      await service.uploadFile(
        largeFile,
        cancelToken: cancelToken,
      );
      fail('Should have thrown on cancel');
    } on DioException catch (e) {
      expect(e.type, equals(DioExceptionType.cancel));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
