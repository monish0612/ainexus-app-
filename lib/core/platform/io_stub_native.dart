// Native (Android/iOS/desktop) — re-export the real `dart:io` so all
// existing usages of `File`, `Directory`, `Platform.pathSeparator`, etc.
// work unchanged on Android. This file is only loaded when
// `dart.library.io` is available (i.e. NOT on Flutter Web).
export 'dart:io';
