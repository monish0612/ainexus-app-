import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native (Android/iOS/desktop) connection. This preserves the **exact**
/// original behaviour the Android app shipped with:
///   - File at `getApplicationDocumentsDirectory()/ai_nexus.db`
///   - WAL journal mode enabled at `setup` time
///   - LazyDatabase wrapper for asynchronous open
///
/// Existing Android user data continues to load from the same file path
/// after the upgrade — no migration needed.
QueryExecutor openAppConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'ai_nexus.db'));
    return NativeDatabase(file, setup: (db) {
      db.execute('PRAGMA journal_mode=WAL');
    });
  });
}

QueryExecutor openBackgroundConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'ai_nexus.db'));
    return NativeDatabase(file, setup: (db) {
      db.execute('PRAGMA journal_mode=WAL');
    });
  });
}
