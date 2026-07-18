// Verifies AppTokenStore persists the JWT through the (mocked) encrypted
// secure-storage channel: set → persisted, load → restored on a fresh launch,
// clear → wiped from both memory and storage. Also confirms graceful behavior
// when the platform channel is unavailable.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/auth/app_token_store.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final backing = <String, String>{};

  void installMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'write':
          backing[key!] = args['value'] as String;
          return null;
        case 'read':
          return backing[key];
        case 'delete':
          backing.remove(key);
          return null;
        case 'readAll':
          return Map<String, String>.from(backing);
        case 'deleteAll':
          backing.clear();
          return null;
        case 'containsKey':
          return backing.containsKey(key);
      }
      return null;
    });
  }

  void removeMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  setUp(() {
    backing.clear();
    installMock();
  });

  tearDown(() async {
    await AppTokenStore.instance.clear();
    removeMock();
  });

  test('setToken persists to secure storage and updates memory', () async {
    await AppTokenStore.instance.setToken('jwt-abc');
    expect(AppTokenStore.instance.token, 'jwt-abc');
    expect(AppTokenStore.instance.hasToken, isTrue);
    expect(backing['app_jwt'], 'jwt-abc'); // persisted
  });

  test('load() restores a token written by a previous launch', () async {
    backing['app_jwt'] = 'persisted-token';
    await AppTokenStore.instance.load();
    expect(AppTokenStore.instance.token, 'persisted-token');
  });

  test('clear() wipes both memory and storage', () async {
    await AppTokenStore.instance.setToken('to-be-cleared');
    await AppTokenStore.instance.clear();
    expect(AppTokenStore.instance.token, isNull);
    expect(AppTokenStore.instance.hasToken, isFalse);
    expect(backing.containsKey('app_jwt'), isFalse);
  });

  test('hasToken is false for null and empty strings', () async {
    await AppTokenStore.instance.clear();
    expect(AppTokenStore.instance.hasToken, isFalse);
    await AppTokenStore.instance.setToken('');
    expect(AppTokenStore.instance.hasToken, isFalse);
  });

  test('load() with no persisted token leaves it null', () async {
    backing.clear();
    await AppTokenStore.instance.clear();
    await AppTokenStore.instance.load();
    expect(AppTokenStore.instance.token, isNull);
  });

  test('platform channel failure is swallowed (best-effort persistence)',
      () async {
    // Simulate a device where secure storage throws.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    // Must not throw; in-memory value still set.
    await AppTokenStore.instance.setToken('mem-only');
    expect(AppTokenStore.instance.token, 'mem-only');
    await AppTokenStore.instance.load(); // swallows, keeps memory
    await AppTokenStore.instance.clear(); // swallows
    expect(AppTokenStore.instance.token, isNull);
  });
}
