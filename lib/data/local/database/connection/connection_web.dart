import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

/// Web (browser) connection backed by sqlite3 compiled to WebAssembly.
///
/// `WasmDatabase.open` auto-detects the best persistence implementation
/// supported by the current browser (in order of preference):
///   1. `opfsShared`   — Origin-Private FS in a shared worker (Firefox)
///   2. `opfsLocks`    — OPFS with COOP/COEP headers (Chrome/Edge/Safari)
///   3. `sharedIndexedDb` — IndexedDB via shared worker
///   4. `unsafeIndexedDb` — direct IndexedDB (legacy fallback)
///   5. `inMemory`     — last-resort, no persistence
///
/// The supporting assets `web/sqlite3.wasm` and `web/drift_worker.dart.js`
/// must be present (downloaded into the `web/` folder at build time —
/// see `tool/web/fetch_drift_assets.ps1` and the Dockerfile.web).
QueryExecutor openAppConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: 'ai_nexus',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.dart.js'),
      );

      if (result.missingFeatures.isNotEmpty) {
        debugPrint(
          '[Drift/Web] Using ${result.chosenImplementation} due to missing '
          'browser features: ${result.missingFeatures}. '
          'Persistence may be limited — recommend a modern browser.',
        );
      }

      return result.resolvedExecutor;
    }),
  );
}

/// On the web there are no background isolates, so the "background"
/// connection just returns the same delayed connection. The DB itself is
/// hosted in the drift worker, which already runs off the main thread.
QueryExecutor openBackgroundConnection() => openAppConnection();
