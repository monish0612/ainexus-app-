// Cross-platform widget that renders an image stored at a local file path.
//
// On native (Android/iOS/desktop) this delegates to Flutter's
// `Image.file(File(path))`. On the web build, file paths from `dart:io`
// don't exist, so the widget returns the supplied fallback (a
// `SizedBox.shrink()` by default).
//
// In practice the receipt-scan UI is hidden on web, so this widget is
// only ever asked to render with a `null` path on the web target.
export 'local_file_image_native.dart'
    if (dart.library.js_interop) 'local_file_image_web.dart';
