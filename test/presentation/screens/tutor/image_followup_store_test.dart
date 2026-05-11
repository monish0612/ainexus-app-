// Public-surface tests for ImageFollowUpStore — verifies the session
// registration + bytes ownership contract that the FAB + chat sheet
// rely on for "image re-attaches to every turn" behaviour.
//
// _ChatMessage is private to the production file, so the heavier
// sendQuestion + history-mirror flow is exercised in the dedicated
// widget test where the chat sheet drives those calls. Here we lock
// down the parts that are reachable through public API alone:
//
//   • registerSession persists imageBytes + mediaType against the key.
//   • registerSession is idempotent (re-registering replaces bytes).
//   • clear drops every per-session datum for that key.
//   • Separate sessionKeys are isolated.
//   • hasPending / getCached return safe defaults for unknown keys.

import 'dart:typed_data';

import 'package:ai_nexus/presentation/screens/tutor/image_followup_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = ImageFollowUpStore.instance;

  setUp(() {
    // Singleton — drain any state left over from previous tests in the
    // same isolate by `clear`-ing the well-known keys this suite uses.
    for (final k in const ['k-A', 'k-B', 'k-test']) {
      store.clear(k);
    }
  });

  test('registerSession stores bytes + media type under the session key',
      () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    store.registerSession(
      sessionKey: 'k-test',
      query: 'a cat',
      initialAnswer: 'this is a cat',
      imageBytes: bytes,
      imageMediaType: 'image/png',
    );

    expect(store.hasSession('k-test'), isTrue);
    expect(store.sessionImageBytes('k-test'), equals(bytes));
    expect(store.sessionImageMediaType('k-test'), equals('image/png'));
  });

  test('registerSession is idempotent — re-registering replaces bytes',
      () {
    final first = Uint8List.fromList([1, 2]);
    final second = Uint8List.fromList([9, 9, 9, 9, 9, 9]);
    store.registerSession(
      sessionKey: 'k-test',
      query: 'q',
      initialAnswer: 'a',
      imageBytes: first,
      imageMediaType: 'image/jpeg',
    );
    store.registerSession(
      sessionKey: 'k-test',
      query: 'q',
      initialAnswer: 'a',
      imageBytes: second,
      imageMediaType: 'image/webp',
    );
    expect(store.sessionImageBytes('k-test'), equals(second),
        reason: 'second registration must replace the bytes');
    expect(store.sessionImageMediaType('k-test'), equals('image/webp'));
  });

  test('clear drops imageBytes + mediaType + cached chat', () {
    store.registerSession(
      sessionKey: 'k-test',
      query: 'q',
      initialAnswer: 'a',
      imageBytes: Uint8List.fromList([1, 2, 3]),
      imageMediaType: 'image/jpeg',
    );
    expect(store.hasSession('k-test'), isTrue);

    store.clear('k-test');
    expect(store.hasSession('k-test'), isFalse);
    expect(store.sessionImageBytes('k-test'), isNull);
    expect(store.sessionImageMediaType('k-test'), isNull);
    expect(store.getCached('k-test'), isEmpty);
    expect(store.hasPending('k-test'), isFalse);
  });

  test('two sessionKeys hold independent bytes', () {
    final bytesA = Uint8List.fromList([0xAA, 0xBB]);
    final bytesB = Uint8List.fromList([0xCC, 0xDD, 0xEE]);
    store.registerSession(
      sessionKey: 'k-A',
      query: 'q',
      initialAnswer: 'a',
      imageBytes: bytesA,
      imageMediaType: 'image/jpeg',
    );
    store.registerSession(
      sessionKey: 'k-B',
      query: 'q',
      initialAnswer: 'a',
      imageBytes: bytesB,
      imageMediaType: 'image/png',
    );
    expect(store.sessionImageBytes('k-A'), equals(bytesA));
    expect(store.sessionImageBytes('k-B'), equals(bytesB));
    // Clearing one must not touch the other.
    store.clear('k-A');
    expect(store.sessionImageBytes('k-A'), isNull);
    expect(store.sessionImageBytes('k-B'), equals(bytesB));
  });

  test('hasPending / getCached return safe defaults for unknown keys', () {
    expect(store.hasPending('no-such-key'), isFalse);
    expect(store.getCached('no-such-key'), isEmpty);
    expect(store.hasSession('no-such-key'), isFalse);
    expect(store.sessionImageBytes('no-such-key'), isNull);
    expect(store.sessionImageMediaType('no-such-key'), isNull);
  });

  test('cancelPending on an unknown key is a no-op (does not throw)', () {
    expect(() => store.cancelPending('no-such-key'), returnsNormally);
  });

  test('addListener + removeListener pair cleanly (no-op when missing)', () {
    void cb() {}
    store.addListener('k-test', cb);
    // Idempotent remove — must not throw or trip an assertion.
    store.removeListener('k-test', cb);
    store.removeListener('k-test', cb);
  });

  test(
      'kAutoDeepThreshold is documented as 10 — locked down so a future '
      'refactor doesn\'t silently shift the long-conversation behaviour',
      () {
    expect(ImageFollowUpStore.kAutoDeepThreshold, equals(10),
        reason: 'Lite→Deep auto-switch must trigger at 10 pairs');
  });
}
