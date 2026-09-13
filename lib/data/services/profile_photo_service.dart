import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_photo_remote.dart';

const kAvatarEdgePx = 512;
const kAvatarJpegQuality = 88;
const kMinAvatarEdgePx = 32;
const kMaxAvatarSourceBytes = 20 * 1024 * 1024;

const kProfilePhotoPrefsKey = 'nxs_profile_photo_path';
const kProfilePhotoFileName = 'profile_avatar.jpg';
const kProfilePhotoShaKey = 'nxs_profile_photo_sha256';
const kProfilePhotoPendingUploadKey = 'nxs_profile_photo_pending_upload';
const kProfilePhotoPendingDeleteKey = 'nxs_profile_photo_pending_delete';
const kProfilePhotoCloudSeenKey = 'nxs_profile_photo_cloud_seen';

/// Center-crop to a square and JPEG-encode a small avatar. Pure — no I/O —
/// so unit tests can cover decode failures without a device.
Uint8List encodeAvatarJpeg(Uint8List source) {
  if (source.isEmpty) {
    throw const FormatException('Photo is empty');
  }
  if (source.lengthInBytes > kMaxAvatarSourceBytes) {
    throw const FormatException('Photo is too large. Pick one under 20 MB.');
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException("Couldn't read that photo. Try another.");
  }
  final side =
      decoded.width < decoded.height ? decoded.width : decoded.height;
  if (side < kMinAvatarEdgePx) {
    throw const FormatException('Photo is too small.');
  }
  final x = ((decoded.width - side) / 2).floor();
  final y = ((decoded.height - side) / 2).floor();
  var square = img.copyCrop(
    decoded,
    x: x,
    y: y,
    width: side,
    height: side,
  );
  if (side != kAvatarEdgePx) {
    square = img.copyResize(
      square,
      width: kAvatarEdgePx,
      height: kAvatarEdgePx,
      interpolation: img.Interpolation.linear,
    );
  }
  return Uint8List.fromList(
    img.encodeJpg(square, quality: kAvatarJpegQuality),
  );
}

/// Snackbar copy for a failed camera/gallery save. Never includes paths.
String avatarPickerErrorMessage(Object error) {
  if (error is FormatException) {
    final m = error.message.trim();
    if (m.isNotEmpty) return m;
  }
  return 'Could not save that photo. Try another.';
}

bool hasStoredProfilePhoto(String? path) {
  return path != null && path.trim().isNotEmpty;
}

/// Persists one rolling avatar JPEG under app documents and remembers the
/// path in SharedPreferences. Missing files are treated as "no photo".
class ProfilePhotoService {
  ProfilePhotoService({
    required SharedPreferences prefs,
    Future<Directory> Function()? documentsDirectory,
  })  : _prefs = prefs,
        _documents = documentsDirectory ?? getApplicationDocumentsDirectory;

  final SharedPreferences _prefs;
  final Future<Directory> Function() _documents;

  bool get pendingUpload =>
      _prefs.getBool(kProfilePhotoPendingUploadKey) ?? false;
  bool get pendingDelete =>
      _prefs.getBool(kProfilePhotoPendingDeleteKey) ?? false;
  bool get cloudSeen => _prefs.getBool(kProfilePhotoCloudSeenKey) ?? false;
  String? get localSha256 {
    final s = _prefs.getString(kProfilePhotoShaKey);
    if (s == null || s.isEmpty) return null;
    return s;
  }

  Future<void> setPendingUpload(bool v) async {
    if (v) {
      await _prefs.setBool(kProfilePhotoPendingUploadKey, true);
      await _prefs.setBool(kProfilePhotoPendingDeleteKey, false);
    } else {
      await _prefs.remove(kProfilePhotoPendingUploadKey);
    }
  }

  Future<void> setPendingDelete(bool v) async {
    if (v) {
      await _prefs.setBool(kProfilePhotoPendingDeleteKey, true);
      await _prefs.remove(kProfilePhotoPendingUploadKey);
    } else {
      await _prefs.remove(kProfilePhotoPendingDeleteKey);
    }
  }

  Future<void> markCloudSeen() async {
    await _prefs.setBool(kProfilePhotoCloudSeenKey, true);
  }

  Future<void> setSha(String sha) async {
    await _prefs.setString(kProfilePhotoShaKey, sha);
  }

  /// Path currently on disk, or null if unset / file was deleted.
  Future<String?> resolvedPath() async {
    final raw = _prefs.getString(kProfilePhotoPrefsKey);
    if (raw == null) return null;
    final path = raw.trim();
    if (path.isEmpty) {
      await _prefs.remove(kProfilePhotoPrefsKey);
      return null;
    }
    final type = FileSystemEntity.typeSync(path, followLinks: true);
    if (type == FileSystemEntityType.file) return path;
    await _prefs.remove(kProfilePhotoPrefsKey);
    await _prefs.remove(kProfilePhotoShaKey);
    return null;
  }

  Future<Uint8List?> readLocalJpeg() async {
    final path = await resolvedPath();
    if (path == null) return null;
    try {
      final bytes = await File(path).readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<String> saveFromBytes(Uint8List source) async {
    return saveEncodedJpeg(encodeAvatarJpeg(source));
  }

  /// Writes an already-encoded JPEG (camera crop or a cloud download).
  Future<String> saveEncodedJpeg(Uint8List jpeg) async {
    if (jpeg.isEmpty) {
      throw const FormatException('Photo is empty');
    }
    final dir = await _documents();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dest =
        File('${dir.path}${Platform.pathSeparator}$kProfilePhotoFileName');
    await dest.writeAsBytes(jpeg, flush: true);
    await _prefs.setString(kProfilePhotoPrefsKey, dest.path);
    await _prefs.setString(kProfilePhotoShaKey, sha256Hex(jpeg));
    return dest.path;
  }

  Future<void> clear() async {
    final path = _prefs.getString(kProfilePhotoPrefsKey);
    await _prefs.remove(kProfilePhotoPrefsKey);
    await _prefs.remove(kProfilePhotoShaKey);
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Full-nuke / remote-reset: drop the cache so we cannot re-upload a
  /// deleted photo as a "first install migration".
  static Future<void> wipeLocalCache(
    SharedPreferences prefs, {
    bool pendingDelete = false,
  }) async {
    final path = prefs.getString(kProfilePhotoPrefsKey);
    await prefs.remove(kProfilePhotoPrefsKey);
    await prefs.remove(kProfilePhotoShaKey);
    await prefs.remove(kProfilePhotoPendingUploadKey);
    if (pendingDelete) {
      await prefs.setBool(kProfilePhotoPendingDeleteKey, true);
    } else {
      await prefs.remove(kProfilePhotoPendingDeleteKey);
    }
    await prefs.setBool(kProfilePhotoCloudSeenKey, true);
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Cloud is source of truth except for in-flight local mutations and a
/// one-time migrate of a photo that existed before this sync shipped.
class ProfilePhotoSynchronizer {
  ProfilePhotoSynchronizer(this.store, this.remote);

  final ProfilePhotoService store;
  final ProfilePhotoRemote remote;

  Future<String?> sync() async {
    if (store.pendingDelete) {
      try {
        await remote.delete();
        await store.setPendingDelete(false);
        await store.markCloudSeen();
      } catch (_) {
        return store.resolvedPath();
      }
      return store.resolvedPath();
    }

    final local = await store.resolvedPath();
    if (!store.cloudSeen && local != null) {
      await store.setPendingUpload(true);
    }

    if (store.pendingUpload) {
      final bytes = await store.readLocalJpeg();
      if (bytes == null) {
        await store.setPendingUpload(false);
      } else {
        try {
          final meta = await remote.upload(bytes);
          if (meta.sha256 != null && meta.sha256!.isNotEmpty) {
            await store.setSha(meta.sha256!);
          }
          await store.setPendingUpload(false);
          await store.markCloudSeen();
        } catch (_) {
          // Keep local; retry next launch. Never download over a newer local.
        }
        return store.resolvedPath();
      }
    }

    try {
      final meta = await remote.fetchMeta();
      await store.markCloudSeen();
      if (!meta.exists) {
        await store.clear();
        return null;
      }
      final localPath = await store.resolvedPath();
      final localSha = store.localSha256;
      if (localPath != null &&
          localSha != null &&
          meta.sha256 != null &&
          localSha == meta.sha256) {
        return localPath;
      }
      final jpeg = await remote.fetchJpeg(ifNoneMatch: localSha);
      if (jpeg == null) return localPath;
      return store.saveEncodedJpeg(jpeg);
    } catch (_) {
      return store.resolvedPath();
    }
  }
}
