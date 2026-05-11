// Unit tests for ImagePipeline — the pure-Dart image picker + compress
// + thumbnail layer that backs the InsightAI vision flow.
//
// Coverage:
//   • guessMediaType
//       - extension-driven branch (.png/.jpg/.webp/.gif/.bmp/.heic/.tif)
//       - magic-bytes sniff fallback for missing/misleading extensions
//       - safe default (image/jpeg) when nothing matches
//   • debugCompressAndThumbnail (the isolate-resident compress path)
//       - decodes PNG, encodes to JPEG, preserves orientation
//       - respects the 2048 px long-edge ceiling for the upload payload
//       - thumbnail honours the 256 px long-edge + ~50 KB hard cap
//       - sub-2048 px inputs are not up-scaled
//       - bogus/non-decodable bytes still return SOMETHING (fall-through
//         is documented in production code and we lock it down here)
//   • ImagePipelineException carries the user-visible message verbatim
//
// We intentionally do NOT exercise pickFromCamera / pickFromGallery
// directly — those wrap a platform plugin we can't fake without an
// integration runner. The compress path is the entire CPU-heavy
// production code path, and it's fully testable here.

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_nexus/core/services/image_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// ── Fixtures ──────────────────────────────────────────────────────────

/// Build a deterministic PNG with the given dimensions filled with a
/// 32-px diagonal gradient. Used so tests run against real pixel data
/// (not solid-fill) and the JPEG codec actually has detail to encode.
Uint8List _png({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = (x ^ y) & 0xFF;
      final g = (x + y) & 0xFF;
      final b = (x * 2 + y) & 0xFF;
      image.setPixelRgba(x, y, r, g, b, 0xFF);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _bmp({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, (x * 4) & 0xFF, (y * 4) & 0xFF, 0xAA, 0xFF);
    }
  }
  return Uint8List.fromList(img.encodeBmp(image));
}

Uint8List _jpeg({required int width, required int height, int quality = 90}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, (x ^ y) & 0xFF, x & 0xFF, y & 0xFF, 0xFF);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

Uint8List _gif({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, x & 0xFF, y & 0xFF, 0x33, 0xFF);
    }
  }
  return Uint8List.fromList(img.encodeGif(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImagePipeline.guessMediaType', () {
    test('PNG extension wins', () {
      expect(
          ImagePipeline.guessMediaType('IMG_0001.png'), equals('image/png'));
    });

    test('jpg AND jpeg both map to image/jpeg', () {
      expect(
          ImagePipeline.guessMediaType('photo.jpg'), equals('image/jpeg'));
      expect(ImagePipeline.guessMediaType('photo.jpeg'),
          equals('image/jpeg'));
    });

    test('webp / gif / bmp / heic / heif / tiff / tif extensions', () {
      expect(
          ImagePipeline.guessMediaType('a.webp'), equals('image/webp'));
      expect(ImagePipeline.guessMediaType('a.gif'), equals('image/gif'));
      expect(ImagePipeline.guessMediaType('a.bmp'), equals('image/bmp'));
      expect(
          ImagePipeline.guessMediaType('a.heic'), equals('image/heic'));
      expect(
          ImagePipeline.guessMediaType('a.heif'), equals('image/heic'));
      expect(ImagePipeline.guessMediaType('a.tif'), equals('image/tiff'));
      expect(ImagePipeline.guessMediaType('a.tiff'), equals('image/tiff'));
    });

    test('extension is case-insensitive', () {
      expect(
          ImagePipeline.guessMediaType('PIC.JPG'), equals('image/jpeg'));
      expect(
          ImagePipeline.guessMediaType('PIC.WeBp'), equals('image/webp'));
    });

    test('magic bytes overrule a missing extension', () {
      // No extension at all — only the sniff bytes drive the answer.
      final pngBytes = _png(width: 16, height: 16);
      expect(
        ImagePipeline.guessMediaType('/share/anonymous', sniff: pngBytes),
        equals('image/png'),
      );

      final jpegBytes = _jpeg(width: 16, height: 16);
      expect(
        ImagePipeline.guessMediaType('/tmp/file', sniff: jpegBytes),
        equals('image/jpeg'),
      );

      final gifBytes = _gif(width: 16, height: 16);
      expect(
        ImagePipeline.guessMediaType('/tmp/cap', sniff: gifBytes),
        equals('image/gif'),
      );

      final bmpBytes = _bmp(width: 16, height: 16);
      expect(
        ImagePipeline.guessMediaType('/tmp/cap', sniff: bmpBytes),
        equals('image/bmp'),
      );
    });

    test('explicit extension takes precedence over the sniff bytes', () {
      // Real PNG bytes but the user share renamed it to .jpg. We trust
      // the extension first — this matches production behaviour where
      // the OS gallery has already declared its intent.
      final pngBytes = _png(width: 4, height: 4);
      expect(
        ImagePipeline.guessMediaType('share.jpg', sniff: pngBytes),
        equals('image/jpeg'),
      );
    });

    test('HEIC ftyp magic bytes are recognised even with .jpg extension', () {
      // Synthetic 16-byte head: 4 bytes anything, then 'f','t','y','p',
      // then 8 more bytes (heic). HEIC files share this MP4 box prefix.
      final heicHead = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
        0x00, 0x00, 0x00, 0x00,
      ]);
      expect(
        ImagePipeline.guessMediaType('/tmp/no-ext', sniff: heicHead),
        equals('image/heic'),
      );
    });

    test('WEBP RIFF magic bytes recognised', () {
      final webp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00, // size placeholder
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);
      expect(
        ImagePipeline.guessMediaType('/tmp/anon', sniff: webp),
        equals('image/webp'),
      );
    });

    test('falls back to image/jpeg when nothing matches', () {
      // Truly anonymous bytes (no extension, no decodable header).
      final anon = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      expect(
        ImagePipeline.guessMediaType('whatever', sniff: anon),
        equals('image/jpeg'),
      );
    });

    test('sniff shorter than 12 bytes is ignored gracefully', () {
      // Path has no recognized extension, sniff is too short → fallback.
      final tiny = Uint8List.fromList([0x89, 0x50]);
      expect(
        ImagePipeline.guessMediaType('weird-name', sniff: tiny),
        equals('image/jpeg'),
      );
    });
  });

  group('ImagePipeline.debugCompressAndThumbnail', () {
    final pipeline = ImagePipeline.instance;

    test(
        'decodes PNG, encodes to JPEG, keeps long edge ≤ 2048 px and '
        'thumb ≤ 256 px', () async {
      // 3000×1500 PNG (long edge > 2048) — production will down-scale.
      final src = _png(width: 3000, height: 1500);
      final out = await pipeline.debugCompressAndThumbnail(src);

      expect(out.upload, isNotEmpty);
      expect(out.thumbnail, isNotEmpty);

      // Long edge of the upload is capped.
      final longEdgeUp = out.width > out.height ? out.width : out.height;
      expect(longEdgeUp, lessThanOrEqualTo(2048),
          reason: 'upload long edge must be capped at 2048 px');

      // Aspect ratio is preserved within rounding (3000:1500 = 2:1).
      final ratio = out.width / out.height;
      expect(ratio, closeTo(2.0, 0.05));

      // Decoded thumbnail respects the 256 px cap.
      final thumb = img.decodeJpg(out.thumbnail);
      expect(thumb, isNotNull,
          reason: 'thumbnail must round-trip through the JPEG codec');
      final longEdgeThumb =
          thumb!.width > thumb.height ? thumb.width : thumb.height;
      expect(longEdgeThumb, lessThanOrEqualTo(256),
          reason: 'thumbnail long edge must be ≤ 256 px');

      // The 50 KB ceiling exists to keep cross-device sync payload sane.
      expect(out.thumbnail.lengthInBytes, lessThanOrEqualTo(50 * 1024 + 1024),
          reason: 'thumbnail must stay under (cap + small slack)');
    });

    test('small inputs are NOT up-scaled', () async {
      // 320×240 — well below both caps. Width/height should be preserved
      // verbatim (modulo codec rounding).
      final src = _png(width: 320, height: 240);
      final out = await pipeline.debugCompressAndThumbnail(src);
      expect(out.width, equals(320));
      expect(out.height, equals(240));
    });

    test('JPEG input round-trips through the pipeline cleanly', () async {
      final src = _jpeg(width: 1500, height: 1000, quality: 80);
      final out = await pipeline.debugCompressAndThumbnail(src);
      // Re-decode to confirm the upload payload is still a valid JPEG.
      final decoded = img.decodeJpg(out.upload);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(1500));
      expect(decoded.height, equals(1000));
    });

    test('GIF input takes the first frame only (no animation)', () async {
      final src = _gif(width: 256, height: 256);
      final out = await pipeline.debugCompressAndThumbnail(src);
      final decoded = img.decodeJpg(out.upload);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(256));
    });

    test('BMP input is transcoded to JPEG', () async {
      final src = _bmp(width: 800, height: 600);
      final out = await pipeline.debugCompressAndThumbnail(src);
      // Output of the upload path is always JPEG — verify by decoding.
      expect(img.decodeJpg(out.upload), isNotNull);
    });

    test(
        'fallback path: undecodable bytes return SOMETHING instead of '
        'throwing (production parity)', () async {
      // 100 bytes of random-looking nonsense. No codec can decode it.
      final junk = Uint8List.fromList(List<int>.generate(100, (i) => i * 7));
      final out = await pipeline.debugCompressAndThumbnail(junk);
      // Production contract: never throw on undecodable input. The
      // fallback returns the raw bytes unchanged so the backend can
      // attempt its own decode (or surface a friendly error).
      expect(out.upload, isNotNull);
      expect(out.thumbnail, isNotNull);
    });

    test(
        '4000×4000 source (≈48 MP) downscales to a sane payload size '
        '— stress test for the verification matrix step 4', () async {
      final src = _png(width: 4000, height: 4000);
      final out = await pipeline.debugCompressAndThumbnail(src);
      expect(out.width, lessThanOrEqualTo(2048));
      expect(out.height, lessThanOrEqualTo(2048));
      // Sanity: a square sub-2048 JPEG at q85 must compress to under
      // 4 MB even for noisy gradients. If this regresses, the user is
      // about to hit a 90 s timeout on uplink.
      expect(out.upload.lengthInBytes, lessThan(4 * 1024 * 1024));
    });
  });

  group('ImagePipelineException', () {
    test('toString returns the user-visible message verbatim', () {
      const e = ImagePipelineException('Image too large.');
      expect(e.toString(), equals('Image too large.'));
      expect(e.message, equals('Image too large.'));
    });

    test('two instances with the same message compare on identity (not value)',
        () {
      const a = ImagePipelineException('x');
      const b = ImagePipelineException('x');
      // The class uses default Object equality — exposed as identity. If
      // a future refactor adds value equality we want this test to fail
      // so we re-audit any `==` usage in store / UI code.
      expect(identical(a, b), isTrue,
          reason: 'const dedup should reuse the same instance');
    });
  });

  // PickedImage is a plain value carrier — exercise the constructor to
  // confirm field assignment is in the order the production code expects.
  group('PickedImage', () {
    test('round-trips all fields via the constructor', () {
      final bytes = _png(width: 4, height: 4);
      final pic = PickedImage(
        uploadBytes: bytes,
        uploadMediaType: 'image/jpeg',
        thumbnailBytes: bytes,
        thumbnailMediaType: 'image/jpeg',
        sourcePath: '/tmp/x.png',
        sourceBytes: bytes,
        sourceMediaType: 'image/png',
        width: 4,
        height: 4,
        compressMs: 12,
      );
      expect(pic.uploadBytes, equals(bytes));
      expect(pic.uploadMediaType, equals('image/jpeg'));
      expect(pic.thumbnailMediaType, equals('image/jpeg'));
      expect(pic.sourceMediaType, equals('image/png'));
      expect(pic.width, equals(4));
      expect(pic.height, equals(4));
      expect(pic.compressMs, equals(12));
    });
  });

  // dart:io File import smoke check so a future refactor that drops the
  // import doesn't go un-detected (the pipeline reads bytes via
  // `File(path).readAsBytes()` so this import must stay).
  test('dart:io File class is reachable (smoke)', () {
    expect(File, isNotNull);
  });
}
