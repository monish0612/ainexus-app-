import 'package:drift/drift.dart';

/// Stub used when neither `dart.library.ffi` nor `dart.library.js_interop`
/// is available. In practice this is never picked up — Flutter on Android
/// has `dart.library.ffi`, Flutter Web has `dart.library.js_interop`. It
/// exists only to satisfy the conditional-export contract.
QueryExecutor openAppConnection() {
  throw UnsupportedError(
    'No drift connection implementation is available for this platform.',
  );
}

QueryExecutor openBackgroundConnection() {
  throw UnsupportedError(
    'No drift connection implementation is available for this platform.',
  );
}
