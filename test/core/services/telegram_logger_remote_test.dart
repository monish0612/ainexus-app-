import 'package:ai_nexus/core/services/telegram_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote Telegram shipping is off unless TLOG_REMOTE is defined', () {
    expect(TLog.remoteEnabled, isFalse);
  });

  test('debug logs do not enqueue a Telegram batch when remote is off', () {
    TLog.d('Phase3', 'should stay local');
    TLog.e('Phase3', 'errors also stay local when remote is off');
    expect(TLog.debugQueueLength, 0);
  });

  test('debugOnLog still fires when remote dispatch is off', () {
    final seen = <String>[];
    TLog.debugOnLog = (level, tag, message, {error}) {
      seen.add('$level $tag $message');
    };
    addTearDown(() => TLog.debugOnLog = null);
    TLog.w('Phase3', 'observer still works');
    expect(seen, contains('warning Phase3 observer still works'));
    expect(TLog.debugQueueLength, 0);
  });
}
