// Cross-platform façade for `dart:io` types used by feature code.
//
// On native targets (Android/iOS/desktop) this re-exports the real
// `dart:io` library, so `File`, `Directory`, `Platform`, etc. behave as
// they always have on Android.
//
// On the web build it exports a minimal stub layer with the same surface
// area but every method throws `UnsupportedError` at runtime. Callers
// that touch these methods on web are expected to be guarded by
// `PlatformCapabilities.isMobile` / `kIsWeb` checks already, so the stub
// methods exist purely to keep the code compiling.
//
// Usage:
//   import '../../core/platform/io_stub.dart';
//   File? _capturedImage;          // works everywhere
//   _capturedImage = File(path);   // only call on mobile
export 'io_stub_native.dart'
    if (dart.library.js_interop) 'io_stub_web.dart';
