import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/network/api_client.dart';
import '../../data/services/profile_photo_remote.dart';
import '../../data/services/profile_photo_service.dart';

final profilePhotoServiceProvider = Provider<ProfilePhotoService>((ref) {
  return ProfilePhotoService(prefs: ref.watch(sharedPreferencesProvider));
});

final profilePhotoRemoteProvider = Provider<ProfilePhotoRemote>((ref) {
  return DioProfilePhotoRemote(ref.watch(apiClientProvider));
});

/// Local path of the user's avatar JPEG, or null when using the fallback glyph.
final profilePhotoPathProvider =
    StateNotifierProvider<ProfilePhotoController, String?>((ref) {
  return ProfilePhotoController(
    ref.watch(profilePhotoServiceProvider),
    remote: ref.watch(profilePhotoRemoteProvider),
  );
});

class ProfilePhotoController extends StateNotifier<String?> {
  ProfilePhotoController(this._store, {ProfilePhotoRemote? remote})
      : _remote = remote,
        super(null) {
    _serialized(() async {
      final path = await _store.resolvedPath();
      if (!mounted) return;
      state = path;
      if (_remote != null) {
        final synced = await ProfilePhotoSynchronizer(_store, _remote).sync();
        if (!mounted) return;
        state = synced;
      }
    });
  }

  final ProfilePhotoService _store;
  final ProfilePhotoRemote? _remote;
  Future<void> _busy = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() job) {
    final next = _busy.then((_) => job());
    _busy = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> syncFromCloud() {
    final remote = _remote;
    if (remote == null) return Future<void>.value();
    return _serialized(() async {
      final path = await ProfilePhotoSynchronizer(_store, remote).sync();
      if (!mounted) return;
      state = path;
    });
  }

  Future<void> setFromBytes(Uint8List source) {
    return _serialized(() async {
      final path = await _store.saveFromBytes(source);
      if (!mounted) return;
      state = path;
      await _store.setPendingUpload(true);
      final remote = _remote;
      if (remote == null) return;
      try {
        final bytes = await _store.readLocalJpeg();
        if (bytes == null) return;
        await remote.upload(bytes);
        await _store.setPendingUpload(false);
        await _store.markCloudSeen();
      } catch (_) {
        // Local photo stays; syncFromCloud retries the PUT.
      }
    });
  }

  Future<void> clear() {
    return _serialized(() async {
      await _store.clear();
      if (!mounted) return;
      state = null;
      await _store.setPendingDelete(true);
      final remote = _remote;
      if (remote == null) return;
      try {
        await remote.delete();
        await _store.setPendingDelete(false);
        await _store.markCloudSeen();
      } catch (_) {}
    });
  }
}
