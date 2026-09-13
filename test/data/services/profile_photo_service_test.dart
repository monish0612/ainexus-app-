import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_nexus/data/services/profile_photo_remote.dart';
import 'package:ai_nexus/data/services/profile_photo_service.dart';
import 'package:ai_nexus/presentation/providers/profile_photo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _rgbPng(int w, int h, {int r = 220, int g = 40, int b = 40}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodePng(im));
}

Uint8List _rgbJpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(10, 200, 30));
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

Uint8List _rgbGif(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(30, 30, 200));
  return Uint8List.fromList(img.encodeGif(im));
}

Future<ProfilePhotoService> _svc(Directory dir) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProfilePhotoService(
    prefs: prefs,
    documentsDirectory: () async => dir,
  );
}

void main() {
  test('encodeAvatarJpeg center-crops landscape, portrait, odd sizes', () {
    for (final src in [
      _rgbPng(400, 200),
      _rgbPng(120, 360, r: 10, g: 180, b: 80),
      _rgbPng(101, 51, r: 1, g: 2, b: 3),
      _rgbPng(51, 101),
    ]) {
      final decoded = img.decodeJpg(encodeAvatarJpeg(src))!;
      expect(decoded.width, kAvatarEdgePx);
      expect(decoded.height, kAvatarEdgePx);
    }
  });

  test('encodeAvatarJpeg accepts PNG, JPEG, GIF and exact 32px / 512px', () {
    for (final src in [
      _rgbPng(32, 32),
      _rgbPng(512, 512, r: 9, g: 9, b: 9),
      _rgbJpeg(80, 80),
      _rgbGif(64, 48),
    ]) {
      final decoded = img.decodeJpg(encodeAvatarJpeg(src))!;
      expect(decoded.width, kAvatarEdgePx);
      expect(decoded.height, kAvatarEdgePx);
    }
  });

  test('encodeAvatarJpeg rejects empty, garbage, tiny, and oversized', () {
    expect(() => encodeAvatarJpeg(Uint8List(0)), throwsFormatException);
    expect(
      () => encodeAvatarJpeg(Uint8List.fromList([1, 2, 3, 4])),
      throwsFormatException,
    );
    expect(() => encodeAvatarJpeg(_rgbPng(16, 16)), throwsFormatException);
    expect(() => encodeAvatarJpeg(_rgbPng(31, 100)), throwsFormatException);
    expect(() => encodeAvatarJpeg(_rgbPng(100, 31)), throwsFormatException);
    expect(
      () => encodeAvatarJpeg(Uint8List(kMaxAvatarSourceBytes + 1)),
      throwsFormatException,
    );
  });

  test('exactly 20 MB is allowed by the size guard', () {
    expect(kMaxAvatarSourceBytes, 20 * 1024 * 1024);
    expect(20 * 1024 * 1024 > kMaxAvatarSourceBytes, isFalse);
  });

  test('avatarPickerErrorMessage never leaks paths', () {
    expect(
      avatarPickerErrorMessage(const FormatException('Photo is too small.')),
      'Photo is too small.',
    );
    expect(
      avatarPickerErrorMessage(const FormatException('')),
      'Could not save that photo. Try another.',
    );
    expect(
      avatarPickerErrorMessage(Exception(r'C:\Users\secret\pic.jpg')),
      'Could not save that photo. Try another.',
    );
  });

  test('hasStoredProfilePhoto treats blank paths as unset', () {
    expect(hasStoredProfilePhoto(null), isFalse);
    expect(hasStoredProfilePhoto(''), isFalse);
    expect(hasStoredProfilePhoto('   '), isFalse);
    expect(hasStoredProfilePhoto(r'D:\a\profile_avatar.jpg'), isTrue);
  });

  test('ProfilePhotoService save, replace, missing file, nested dir, clear',
      () async {
    final dir = await Directory.systemTemp.createTemp('avatar_svc_');
    addTearDown(() => dir.delete(recursive: true));
    final nested = Directory('${dir.path}${Platform.pathSeparator}nested');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final svc = ProfilePhotoService(
      prefs: prefs,
      documentsDirectory: () async => nested,
    );

    expect(await svc.resolvedPath(), isNull);

    final path1 = await svc.saveFromBytes(_rgbPng(80, 80));
    expect(nested.existsSync(), isTrue);
    expect(File(path1).existsSync(), isTrue);
    expect(path1, endsWith(kProfilePhotoFileName));
    expect(await svc.resolvedPath(), path1);

    final firstBytes = await File(path1).readAsBytes();
    expect(
      () => svc.saveFromBytes(Uint8List(0)),
      throwsFormatException,
    );
    expect(await svc.resolvedPath(), path1, reason: 'failed save must not wipe');
    expect(await File(path1).readAsBytes(), firstBytes);

    final path2 = await svc.saveFromBytes(_rgbJpeg(90, 70));
    expect(path2, path1, reason: 'rolling file keeps the same name');
    expect(await File(path2).readAsBytes(), isNot(equals(firstBytes)));

    await File(path2).delete();
    expect(await svc.resolvedPath(), isNull);
    expect(prefs.getString(kProfilePhotoPrefsKey), isNull);

    final path3 = await svc.saveFromBytes(_rgbPng(80, 80, b: 255));
    await svc.clear();
    expect(File(path3).existsSync(), isFalse);
    expect(await svc.resolvedPath(), isNull);
    await svc.clear();
    expect(await svc.resolvedPath(), isNull);
  });

  test('resolvedPath ignores whitespace prefs and directory paths', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_edge_');
    addTearDown(() => dir.delete(recursive: true));
    SharedPreferences.setMockInitialValues(<String, Object>{
      kProfilePhotoPrefsKey: '   ',
    });
    var prefs = await SharedPreferences.getInstance();
    var svc = ProfilePhotoService(
      prefs: prefs,
      documentsDirectory: () async => dir,
    );
    expect(await svc.resolvedPath(), isNull);
    expect(prefs.getString(kProfilePhotoPrefsKey), isNull);

    SharedPreferences.setMockInitialValues(<String, Object>{
      kProfilePhotoPrefsKey: dir.path,
    });
    prefs = await SharedPreferences.getInstance();
    svc = ProfilePhotoService(
      prefs: prefs,
      documentsDirectory: () async => dir,
    );
    expect(await svc.resolvedPath(), isNull);
    expect(prefs.getString(kProfilePhotoPrefsKey), isNull);
  });

  test('ProfilePhotoController hydrates, sets, and clears', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_ctrl_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    await store.saveFromBytes(_rgbPng(80, 80, r: 1, g: 2, b: 3));

    final ctrl = ProfilePhotoController(store);
    addTearDown(ctrl.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(ctrl.state, isNotNull);
    expect(File(ctrl.state!).existsSync(), isTrue);

    await ctrl.setFromBytes(_rgbPng(80, 80, r: 9, g: 9, b: 9));
    expect(ctrl.state, isNotNull);

    expect(
      () => ctrl.setFromBytes(Uint8List(0)),
      throwsFormatException,
    );
    expect(ctrl.state, isNotNull, reason: 'failed pick must keep previous photo');

    await ctrl.clear();
    expect(ctrl.state, isNull);
  });

  test('controller save-then-clear leaves no photo on disk or in state',
      () async {
    final dir = await Directory.systemTemp.createTemp('avatar_race_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    final ctrl = ProfilePhotoController(store);
    addTearDown(ctrl.dispose);
    await Future<void>.delayed(Duration.zero);

    final pendingSet = ctrl.setFromBytes(_rgbPng(80, 80));
    final pendingClear = ctrl.clear();
    await pendingSet;
    await pendingClear;
    expect(ctrl.state, isNull);
    expect(await store.resolvedPath(), isNull);
  });

  test('controller dispose during hydrate does not throw', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_disp_');
    addTearDown(() => dir.delete(recursive: true));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final gate = Completer<void>();
    final store = _GatedService(
      prefs: prefs,
      documentsDirectory: () async => dir,
      hydrateGate: gate,
    );
    await store.saveFromBytes(_rgbPng(64, 64));
    final ctrl = ProfilePhotoController(store);
    ctrl.dispose();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('fresh install downloads the cloud photo', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_dl_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    final cloud = encodeAvatarJpeg(_rgbPng(80, 80, r: 1, g: 2, b: 3));
    final remote = _FakeRemote()
      ..meta = ProfilePhotoMeta(
        exists: true,
        sha256: sha256Hex(cloud),
        bytes: cloud.length,
      )
      ..jpeg = cloud;

    final path = await ProfilePhotoSynchronizer(store, remote).sync();
    expect(path, isNotNull);
    expect(await File(path!).readAsBytes(), cloud);
    expect(store.cloudSeen, isTrue);
    expect(store.localSha256, sha256Hex(cloud));
  });

  test('existing local photo migrates once when cloud is empty', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_mig_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    await store.saveFromBytes(_rgbPng(80, 80, r: 9, g: 8, b: 7));
    expect(store.cloudSeen, isFalse);
    final remote = _FakeRemote();

    await ProfilePhotoSynchronizer(store, remote).sync();
    expect(remote.uploads, 1);
    expect(store.pendingUpload, isFalse);
    expect(store.cloudSeen, isTrue);
    expect(await store.resolvedPath(), isNotNull);
  });

  test('after cloudSeen, a cloud delete clears the local cache', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_rm_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    await store.saveFromBytes(_rgbPng(80, 80));
    await store.markCloudSeen();
    final remote = _FakeRemote();

    final path = await ProfilePhotoSynchronizer(store, remote).sync();
    expect(path, isNull);
    expect(await store.resolvedPath(), isNull);
    expect(remote.uploads, 0);
  });

  test('pending upload is never overwritten by an older cloud photo', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_pend_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    await store.saveFromBytes(_rgbPng(80, 80, r: 255, g: 0, b: 0));
    await store.setPendingUpload(true);
    final stale = encodeAvatarJpeg(_rgbPng(80, 80, r: 0, g: 0, b: 255));
    final remote = _FakeRemote()
      ..uploadError = Exception('offline')
      ..meta = ProfilePhotoMeta(exists: true, sha256: sha256Hex(stale))
      ..jpeg = stale;

    final path = await ProfilePhotoSynchronizer(store, remote).sync();
    expect(store.pendingUpload, isTrue);
    expect(await File(path!).readAsBytes(), isNot(equals(stale)));
    expect(remote.fetches, 0);
  });

  test('pending delete removes the cloud copy', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_pdel_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    await store.setPendingDelete(true);
    final remote = _FakeRemote()
      ..meta = const ProfilePhotoMeta(exists: true, sha256: 'abc')
      ..jpeg = encodeAvatarJpeg(_rgbPng(64, 64));

    await ProfilePhotoSynchronizer(store, remote).sync();
    expect(remote.deletes, 1);
    expect(store.pendingDelete, isFalse);
  });

  test('matching sha skips download', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_sha_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    final path = await store.saveFromBytes(_rgbPng(80, 80, r: 4, g: 5, b: 6));
    final jpeg = await File(path).readAsBytes();
    await store.markCloudSeen();
    final remote = _FakeRemote()
      ..meta = ProfilePhotoMeta(exists: true, sha256: sha256Hex(jpeg))
      ..jpeg = jpeg;

    await ProfilePhotoSynchronizer(store, remote).sync();
    expect(remote.jpegReads, 0);
  });

  test('offline fetch keeps the local photo', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_off_');
    addTearDown(() => dir.delete(recursive: true));
    final store = await _svc(dir);
    final path = await store.saveFromBytes(_rgbPng(80, 80));
    await store.markCloudSeen();
    final remote = _FakeRemote()..fetchError = Exception('socket');

    expect(await ProfilePhotoSynchronizer(store, remote).sync(), path);
    expect(File(path).existsSync(), isTrue);
  });

  test('wipeLocalCache does not migrate the photo back after a nuke', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_nuke_');
    addTearDown(() => dir.delete(recursive: true));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = ProfilePhotoService(
      prefs: prefs,
      documentsDirectory: () async => dir,
    );
    await store.saveFromBytes(_rgbPng(80, 80));
    await ProfilePhotoService.wipeLocalCache(prefs, pendingDelete: true);
    expect(await store.resolvedPath(), isNull);
    expect(store.pendingUpload, isFalse);
    expect(store.pendingDelete, isTrue);
    expect(store.cloudSeen, isTrue);

    final remote = _FakeRemote();
    await ProfilePhotoSynchronizer(store, remote).sync();
    expect(remote.uploads, 0);
    expect(remote.deletes, 1);
  });

  test('ProfilePhotoMeta.fromJson is defensive', () {
    expect(ProfilePhotoMeta.fromJson(null).exists, isFalse);
    expect(ProfilePhotoMeta.fromJson('nope').exists, isFalse);
    expect(
      ProfilePhotoMeta.fromJson({'exists': true, 'sha256': 'ab', 'bytes': 9})
          .sha256,
      'ab',
    );
  });
}

class _FakeRemote implements ProfilePhotoRemote {
  ProfilePhotoMeta meta = const ProfilePhotoMeta(exists: false);
  Uint8List? jpeg;
  int uploads = 0;
  int deletes = 0;
  int fetches = 0;
  int jpegReads = 0;
  Object? uploadError;
  Object? fetchError;

  @override
  Future<ProfilePhotoMeta> fetchMeta() async {
    if (fetchError != null) throw fetchError!;
    fetches++;
    return meta;
  }

  @override
  Future<Uint8List?> fetchJpeg({String? ifNoneMatch}) async {
    jpegReads++;
    if (ifNoneMatch != null &&
        meta.sha256 != null &&
        ifNoneMatch == meta.sha256) {
      return null;
    }
    return jpeg;
  }

  @override
  Future<ProfilePhotoMeta> upload(Uint8List bytes) async {
    if (uploadError != null) throw uploadError!;
    uploads++;
    jpeg = bytes;
    meta = ProfilePhotoMeta(
      exists: true,
      sha256: sha256Hex(bytes),
      bytes: bytes.length,
    );
    return meta;
  }

  @override
  Future<void> delete() async {
    deletes++;
    jpeg = null;
    meta = const ProfilePhotoMeta(exists: false);
  }
}

class _GatedService extends ProfilePhotoService {
  _GatedService({
    required super.prefs,
    super.documentsDirectory,
    this.hydrateGate,
  });

  final Completer<void>? hydrateGate;

  @override
  Future<String?> resolvedPath() async {
    if (hydrateGate != null) await hydrateGate!.future;
    return super.resolvedPath();
  }
}
