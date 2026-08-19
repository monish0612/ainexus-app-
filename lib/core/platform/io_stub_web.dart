/// Web stub for the subset of `dart:io` used by feature code.
///
/// All operations throw `UnsupportedError`. The web UI must guard every
/// call site with a `kIsWeb` / `PlatformCapabilities` check before
/// reaching this code. The stub exists *only* to keep the rest of the
/// codebase compilable on the web target without duplicating files.
library io_stub_web;

import 'dart:typed_data';

const String _kErr =
    'dart:io is not available on the web build. Guard the call site with '
    'PlatformCapabilities.isMobile or kIsWeb.';

class File {
  File(this.path);
  final String path;

  bool existsSync() => false;
  Future<bool> exists() async => false;

  Future<Uint8List> readAsBytes() async => throw UnsupportedError(_kErr);
  Uint8List readAsBytesSync() => throw UnsupportedError(_kErr);

  Future<String> readAsString() async => throw UnsupportedError(_kErr);

  Future<File> writeAsBytes(List<int> bytes,
      {bool flush = false}) async {
    throw UnsupportedError(_kErr);
  }

  Future<File> writeAsString(String contents, {bool flush = false}) async {
    throw UnsupportedError(_kErr);
  }

  Future<File> delete({bool recursive = false}) async {
    throw UnsupportedError(_kErr);
  }

  Future<int> length() async => throw UnsupportedError(_kErr);
  int lengthSync() => throw UnsupportedError(_kErr);

  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    throw UnsupportedError(_kErr);
  }

  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.error(UnsupportedError(_kErr));

  IOSink openWrite({FileMode mode = FileMode.write}) {
    throw UnsupportedError(_kErr);
  }
}

class IOSink {
  void add(List<int> data) => throw UnsupportedError(_kErr);
  Future<void> flush() async => throw UnsupportedError(_kErr);
  Future<void> close() async => throw UnsupportedError(_kErr);
}

class RandomAccessFile {
  Future<RandomAccessFile> setPosition(int position) async =>
      throw UnsupportedError(_kErr);
  Future<Uint8List> read(int bytes) async => throw UnsupportedError(_kErr);
  Future<void> close() async {}
}

enum FileMode { read, write, append, writeOnly, writeOnlyAppend }

class Directory {
  Directory(this.path);
  final String path;

  Future<bool> exists() async => false;
  bool existsSync() => false;

  Future<Directory> create({bool recursive = false}) async => this;
  void createSync({bool recursive = false}) {}
}

class Platform {
  static String get pathSeparator => '/';
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isFuchsia => false;
  static String get operatingSystem => 'web';
  static int get numberOfProcessors => 1;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Network exception stubs.
//
//  These mirror the `dart:io` exception types so that `is SocketException`
//  / `is HttpException` checks (used in retry logic, e.g. inside
//  `google_drive_service.dart`) compile on web. The web build never throws
//  these types — Dio surfaces network failures as `DioException` directly —
//  so the `is` checks simply evaluate to `false` and the surrounding logic
//  falls through to its string-based heuristics.
// ─────────────────────────────────────────────────────────────────────────────

class SocketException implements Exception {
  const SocketException(this.message, {this.osError, this.address, this.port});
  final String message;
  final OSError? osError;
  final InternetAddress? address;
  final int? port;

  @override
  String toString() => 'SocketException: $message';
}

class HttpException implements Exception {
  const HttpException(this.message, {this.uri});
  final String message;
  final Uri? uri;

  @override
  String toString() => 'HttpException: $message';
}

class OSError {
  const OSError([this.message = '', this.errorCode = 0]);
  final String message;
  final int errorCode;

  @override
  String toString() => 'OSError: $message';
}

class InternetAddress {
  const InternetAddress(this.address);
  final String address;
}
