import 'package:flutter/foundation.dart';

/// One file in the NAS `Cloud Storage` folder.
///
/// Deliberately thinner than [DriveFileInfo]. A WebDAV folder has no notion of
/// starring, no server-generated thumbnails and no opaque file id — the name
/// *is* the identity, because that is what it is on the share. Pretending
/// otherwise would mean inventing state the NAS does not hold and cannot keep
/// in step with what the owner sees in Explorer.
@immutable
class NasFile {
  const NasFile({
    required this.name,
    required this.sizeBytes,
    this.modified,
    this.mimeType,
    this.etag,
  });

  factory NasFile.fromJson(Map<String, dynamic> json) {
    final rawSize = json['size'];
    final rawModified = json['modified'];
    return NasFile(
      name: (json['name'] as String?) ?? '',
      sizeBytes: rawSize is num ? rawSize.toInt() : 0,
      modified:
          rawModified is String ? DateTime.tryParse(rawModified)?.toLocal() : null,
      mimeType: json['mimeType'] as String?,
      etag: json['etag'] as String?,
    );
  }

  final String name;
  final int sizeBytes;
  final DateTime? modified;
  final String? mimeType;
  final String? etag;

  String get ext {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }
}

/// Why the NAS destination is or is not usable right now.
///
/// The distinction between [notConfigured] and [unreachable] is the whole point
/// of this type. One is "the server has no password for the NAS, and no amount
/// of waiting will change that" — an owner-action, fixed in Coolify. The other
/// is "the NAS is switched off", fixed by walking over and turning it on.
/// Collapsing them into "unavailable" sends the owner to the wrong room.
enum NasStorageState {
  /// Reachable, writable, ready.
  ready,

  /// No app password is set on the server. The option is offered as visibly
  /// disabled with this explanation rather than failing at upload time.
  notConfigured,

  /// The server has a credential but the NAS did not answer — almost always
  /// because it is switched off.
  unreachable,

  /// Nextcloud rejected the credential. Nothing the phone can do; the server's
  /// app password needs replacing.
  badCredential,

  /// Not asked yet.
  unknown,
}

@immutable
class NasStorageStatus {
  const NasStorageStatus({
    required this.state,
    this.root = '',
  });

  factory NasStorageStatus.fromJson(Map<String, dynamic> json) {
    final configured = json['configured'] == true;
    final reachable = json['reachable'] == true;
    final reason = json['reason'] as String?;

    NasStorageState state;
    if (!configured) {
      state = NasStorageState.notConfigured;
    } else if (reachable) {
      state = NasStorageState.ready;
    } else if (reason == 'auth') {
      state = NasStorageState.badCredential;
    } else {
      state = NasStorageState.unreachable;
    }

    return NasStorageStatus(
      state: state,
      root: (json['root'] as String?) ?? '',
    );
  }

  static const unknown = NasStorageStatus(state: NasStorageState.unknown);

  final NasStorageState state;

  /// e.g. `Code/Cloud Storage` — shown to the owner so he knows exactly where on
  /// the share a file will land, rather than trusting a label that says "NAS".
  final String root;

  bool get isReady => state == NasStorageState.ready;

  /// Whether the app should let the owner *select* this destination. An
  /// unreachable NAS is still selectable — he may be about to switch it on, and
  /// the screen explains itself. A NAS with no credential on the server is not,
  /// because nothing he does on the phone can make it work.
  bool get selectable =>
      state == NasStorageState.ready ||
      state == NasStorageState.unreachable ||
      state == NasStorageState.unknown;

  /// One line, written for the person holding the phone.
  String get explanation {
    switch (state) {
      case NasStorageState.ready:
        return root.isEmpty ? 'Ready' : 'Saving to $root';
      case NasStorageState.notConfigured:
        return 'Not set up on the server yet';
      case NasStorageState.unreachable:
        return 'Not responding — it may be switched off';
      case NasStorageState.badCredential:
        return 'The server\'s NAS password was rejected';
      case NasStorageState.unknown:
        return 'Checking…';
    }
  }
}
