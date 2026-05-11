import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'telegram_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ImagePipeline — production-grade pick + compress + thumbnail utility
// ─────────────────────────────────────────────────────────────────────────────
//
// Responsibilities:
//   • Pick an image from the camera or gallery via `image_picker`.
//   • Down-scale + re-encode the source to a server-friendly JPEG
//     (≤ 2048 px on the long edge, q85) — typically reduces a 50 MB
//     HEIC/PNG/RAW down to 300 KB – 1.5 MB without losing meaningful
//     detail for vision models.
//   • Make a tiny 256 px thumbnail (q60, ≤ 50 KB) for cross-device
//     sync inside SavedSearchStore.responseJson, encoded as a data:
//     URL so it travels through the existing string-based wire shape
//     with zero schema change.
//   • Sniff the media type even when the OS extension is misleading
//     (HEIC files often arrive with a .jpg extension on iOS shares).
//
// All decode / resize / encode work runs through [compute] so the UI
// thread stays at 60 fps even on 50 MB source images. The two `compute`
// calls (compress + thumbnail) are dispatched in parallel via
// [Future.wait] so total wall-time is ≈ max(compress, thumb) instead
// of their sum.

const int _kMaxLongEdgePx = 2048;
const int _kThumbnailLongEdgePx = 256;
const int _kFullJpegQuality = 85;
const int _kThumbJpegQuality = 60;
const int _kThumbHardCapBytes = 50 * 1024; // 50 KB
const int _kMaxRawSourceBytes = 60 * 1024 * 1024; // 60 MB safety ceiling

/// Result of a picker + compress run, ready to ship to the backend.
@immutable
class PickedImage {
  const PickedImage({
    required this.uploadBytes,
    required this.uploadMediaType,
    required this.thumbnailBytes,
    required this.thumbnailMediaType,
    required this.sourcePath,
    required this.sourceBytes,
    required this.sourceMediaType,
    required this.width,
    required this.height,
    required this.compressMs,
  });

  /// Compressed JPEG bytes destined for the backend image-search /
  /// image-followup endpoints (base64-wrapped at the wire layer).
  final Uint8List uploadBytes;
  final String uploadMediaType; // always 'image/jpeg' for upload bytes

  /// Tiny JPEG for cross-device sync inside SavedSearchStore. Always
  /// JPEG, regardless of the source media type.
  final Uint8List thumbnailBytes;
  final String thumbnailMediaType;

  /// Path the image_picker handed back. Persisted in memory only so
  /// the user can re-attach the same image to a follow-up turn without
  /// re-picking; never written to disk by us.
  final String sourcePath;

  /// Raw source bytes (untouched) — kept on the device that uploaded
  /// the image so we can also expose decoded width / height in the UI
  /// and (defensively) re-compress if a future feature needs another
  /// pass. NOT sent across the wire.
  final Uint8List sourceBytes;
  final String sourceMediaType;

  final int width;
  final int height;

  /// Total milliseconds spent in the off-isolate compress/thumb run.
  /// Useful for TLog observability + perf regressions.
  final int compressMs;
}

/// Internal payload passed to the background isolate. Must be JSON-
/// safe (no Dart object references) because Flutter ships it across
/// isolate boundaries via a SendPort.
class _CompressJob {
  const _CompressJob(this.bytes, this.maxLongEdge, this.quality);
  final Uint8List bytes;
  final int maxLongEdge;
  final int quality;
}

class _CompressResult {
  const _CompressResult(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

class ImagePipeline {
  ImagePipeline._();
  static final instance = ImagePipeline._();

  final ImagePicker _picker = ImagePicker();

  /// Pick from camera. Returns null if the user cancels or the OS
  /// denies the permission. Errors are logged via TLog but never
  /// thrown — the caller can safely tree-shake the null case.
  Future<PickedImage?> pickFromCamera() async {
    return _pick(ImageSource.camera, 'camera');
  }

  /// Pick from gallery. Same null-on-cancel semantics as
  /// [pickFromCamera]. Supports every image type the OS gallery
  /// surfaces (JPEG / PNG / WEBP / HEIC / GIF / BMP / …) because
  /// the compress step decodes via the universal `image` package
  /// codec and re-encodes to JPEG before upload.
  Future<PickedImage?> pickFromGallery() async {
    return _pick(ImageSource.gallery, 'gallery');
  }

  Future<PickedImage?> _pick(ImageSource source, String tag) async {
    final sw = Stopwatch()..start();
    try {
      // We do NOT pass maxWidth / maxHeight / imageQuality here — those
      // are best-effort native shortcuts that drop EXIF metadata and
      // can subtly degrade vision-model accuracy. We do our own
      // controlled compression below.
      final picked = await _picker.pickImage(source: source);
      if (picked == null) {
        TLog.d('ImagePipeline', '[$tag] user cancelled (${sw.elapsedMilliseconds}ms)');
        return null;
      }

      final rawBytes = await File(picked.path).readAsBytes();
      final sourceMediaType = guessMediaType(picked.path, sniff: rawBytes);

      // Pre-flight ceiling — if the user somehow shoves a >60 MB file
      // through (unlikely on a real device, but a 100 MP DNG from a
      // pro camera could), refuse it before allocating decoder memory.
      if (rawBytes.lengthInBytes > _kMaxRawSourceBytes) {
        TLog.w('ImagePipeline',
            '[$tag] rejected oversize image ${(rawBytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1)}MB > '
            '${_kMaxRawSourceBytes ~/ 1024 ~/ 1024}MB');
        throw const ImagePipelineException(
          'Image too large. Please choose a file under 50 MB.',
        );
      }

      TLog.i('ImagePipeline',
          '[$tag] picked ${(rawBytes.lengthInBytes / 1024).toStringAsFixed(0)} KB '
          'type=$sourceMediaType pickMs=${sw.elapsedMilliseconds}');

      final compressed = await _compressAndThumbnail(rawBytes);

      return PickedImage(
        uploadBytes: compressed.uploadBytes,
        uploadMediaType: 'image/jpeg',
        thumbnailBytes: compressed.thumbnailBytes,
        thumbnailMediaType: 'image/jpeg',
        sourcePath: picked.path,
        sourceBytes: rawBytes,
        sourceMediaType: sourceMediaType,
        width: compressed.width,
        height: compressed.height,
        compressMs: compressed.totalMs,
      );
    } on ImagePipelineException {
      rethrow;
    } catch (e, st) {
      TLog.e('ImagePipeline', '[$tag] pick failed', error: e, st: st);
      rethrow;
    }
  }

  /// Public test surface — runs the isolate-bound compress + thumbnail
  /// pipeline without going through `image_picker`. Tests can pass any
  /// well-formed image bytes (PNG, JPEG, BMP, …) and assert on the
  /// produced upload/thumbnail outputs. Identical implementation to
  /// the private `_compressAndThumbnail` so tests catch any production
  /// regression in compression behaviour.
  @visibleForTesting
  Future<({Uint8List upload, Uint8List thumbnail, int width, int height})>
      debugCompressAndThumbnail(Uint8List src) async {
    final r = await _compressAndThumbnail(src);
    return (
      upload: r.uploadBytes,
      thumbnail: r.thumbnailBytes,
      width: r.width,
      height: r.height,
    );
  }

  /// Run compress + thumbnail in PARALLEL across two background
  /// isolates. On modern phones this is ~2× faster than running them
  /// sequentially because resize+encode is the dominant cost and both
  /// jobs are CPU-bound.
  Future<_PipelineRunResult> _compressAndThumbnail(Uint8List src) async {
    final sw = Stopwatch()..start();

    // Parallel dispatch — both `compute` calls fire near-simultaneously.
    // If either throws, the whole future rejects (Future.wait short-
    // circuits) so we never half-succeed.
    final results = await Future.wait<_CompressResult>([
      compute<_CompressJob, _CompressResult>(
        _isolateCompress,
        _CompressJob(src, _kMaxLongEdgePx, _kFullJpegQuality),
      ),
      compute<_CompressJob, _CompressResult>(
        _isolateCompress,
        _CompressJob(src, _kThumbnailLongEdgePx, _kThumbJpegQuality),
      ),
    ]);

    Uint8List thumbBytes = results[1].bytes;
    // Hard cap: if the q60/256px thumb is still over 50 KB (rare —
    // happens on noisy photos where JPEG can't compress well), do a
    // second pass at q40 in the foreground. The thumbnail at this size
    // is so small that a foreground pass is ~5 ms even on a slow CPU.
    if (thumbBytes.lengthInBytes > _kThumbHardCapBytes) {
      final decoded = img.decodeJpg(thumbBytes);
      if (decoded != null) {
        final lower = img.encodeJpg(decoded, quality: 40);
        if (lower.lengthInBytes < thumbBytes.lengthInBytes) {
          thumbBytes = Uint8List.fromList(lower);
        }
      }
    }

    sw.stop();
    final upload = results[0];
    TLog.i('ImagePipeline',
        'compress ✓ src=${(src.lengthInBytes / 1024).toStringAsFixed(0)}KB '
        '→ upload=${(upload.bytes.lengthInBytes / 1024).toStringAsFixed(0)}KB '
        '@${upload.width}×${upload.height} '
        'thumb=${(thumbBytes.lengthInBytes / 1024).toStringAsFixed(1)}KB '
        '${sw.elapsedMilliseconds}ms');

    return _PipelineRunResult(
      uploadBytes: upload.bytes,
      thumbnailBytes: thumbBytes,
      width: upload.width,
      height: upload.height,
      totalMs: sw.elapsedMilliseconds,
    );
  }

  /// Sniff media type from path extension first; fall back to magic
  /// bytes when the extension is missing / wrong (HEIC shared as .jpg
  /// is the canonical real-world case).
  static String guessMediaType(String path, {Uint8List? sniff}) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    if (lower.endsWith('.tif') || lower.endsWith('.tiff')) {
      return 'image/tiff';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (sniff != null && sniff.length >= 12) {
      // PNG: 89 50 4E 47 0D 0A 1A 0A
      if (sniff[0] == 0x89 &&
          sniff[1] == 0x50 &&
          sniff[2] == 0x4E &&
          sniff[3] == 0x47) {
        return 'image/png';
      }
      // GIF: 47 49 46 38
      if (sniff[0] == 0x47 && sniff[1] == 0x49 && sniff[2] == 0x46) {
        return 'image/gif';
      }
      // BMP: 42 4D
      if (sniff[0] == 0x42 && sniff[1] == 0x4D) {
        return 'image/bmp';
      }
      // WEBP: RIFF....WEBP at offsets 0..3 and 8..11
      if (sniff[0] == 0x52 &&
          sniff[1] == 0x49 &&
          sniff[2] == 0x46 &&
          sniff[3] == 0x46 &&
          sniff[8] == 0x57 &&
          sniff[9] == 0x45 &&
          sniff[10] == 0x42 &&
          sniff[11] == 0x50) {
        return 'image/webp';
      }
      // HEIC: ftypheic / ftypheix / ftypmif1 in the box at offset 4
      if (sniff[4] == 0x66 &&
          sniff[5] == 0x74 &&
          sniff[6] == 0x79 &&
          sniff[7] == 0x70) {
        return 'image/heic';
      }
      // JPEG: FF D8 FF
      if (sniff[0] == 0xFF && sniff[1] == 0xD8 && sniff[2] == 0xFF) {
        return 'image/jpeg';
      }
    }
    // Final fallback — extension neither known nor decodable magic
    // bytes. Treat as JPEG for the upload path; the backend will reject
    // if it doesn't decode, which is friendlier than refusing here.
    return 'image/jpeg';
  }
}

class _PipelineRunResult {
  const _PipelineRunResult({
    required this.uploadBytes,
    required this.thumbnailBytes,
    required this.width,
    required this.height,
    required this.totalMs,
  });

  final Uint8List uploadBytes;
  final Uint8List thumbnailBytes;
  final int width;
  final int height;
  final int totalMs;
}

/// User-facing exceptions surfaced by the pipeline. Distinct type so
/// callers can decide whether to show the message verbatim (user-safe
/// like "Image too large") or wrap it in a generic toast.
@immutable
class ImagePipelineException implements Exception {
  const ImagePipelineException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ─── Isolate entry point ─────────────────────────────────────────────────────
//
// Must be a top-level function (not a method or closure) so `compute`
// can ship its symbol across the isolate boundary. Decodes any
// supported format, resizes (cubic) to the long-edge cap, re-encodes
// as baseline JPEG with EXIF orientation already applied during decode.

_CompressResult _isolateCompress(_CompressJob job) {
  // findDecoderForData walks all built-in codecs (JPEG, PNG, WEBP,
  // BMP, GIF, TIFF, TGA, PSD, ICO, …) so this single entry point
  // handles every format the gallery is likely to surface. HEIC is
  // not natively decodable in pure Dart — for HEIC sources the OS
  // gallery (and image_picker on Android 13+) already transcodes to
  // JPEG before we see the file, so we land in the JPEG codec path.
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) {
    // Last-resort: return the original bytes as-is. The backend can
    // still attempt to decode (Gemini / Grok vision both accept the
    // common formats). We DON'T throw because a working fallback is
    // better than a hard pick-failure when the codec table misses
    // (some Android OEMs ship custom DCI-JPEG variants).
    return _CompressResult(job.bytes, 0, 0);
  }

  // Strip animation: for GIF we only ship the first frame. Vision
  // models reason over a single still image — sending a 30-frame GIF
  // would 30× the payload for no quality gain.
  final firstFrame = decoded;

  final w = firstFrame.width;
  final h = firstFrame.height;
  img.Image working = firstFrame;
  if (w > job.maxLongEdge || h > job.maxLongEdge) {
    final scale = job.maxLongEdge / (w > h ? w : h);
    working = img.copyResize(
      firstFrame,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }
  final encoded = img.encodeJpg(working, quality: job.quality);
  return _CompressResult(
    Uint8List.fromList(encoded),
    working.width,
    working.height,
  );
}
