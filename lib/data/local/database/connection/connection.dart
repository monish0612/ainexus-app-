import 'package:drift/drift.dart';

/// Conditional export — the implementation is selected at compile time:
///   - On native (dart.library.ffi): `connection_native.dart` opens the
///     existing `ai_nexus.db` SQLite file via `NativeDatabase` (identical
///     behaviour to the original Android implementation, WAL mode, same
///     file path — zero migration risk for installed users).
///   - On web (dart.library.js_interop): `connection_web.dart` opens a
///     `WasmDatabase` backed by sqlite3.wasm + drift_worker.dart.js,
///     persisting to OPFS (preferred) or IndexedDB (fallback).
///
/// All callers should depend on `openAppConnection()` /
/// `openBackgroundConnection()` only — never reach into the platform files.
export 'connection_unsupported.dart'
    if (dart.library.ffi) 'connection_native.dart'
    if (dart.library.js_interop) 'connection_web.dart';

/// Public type used by callers so they don't have to import drift internals.
typedef AppQueryExecutor = QueryExecutor;
