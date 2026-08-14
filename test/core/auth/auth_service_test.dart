import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/auth/auth_service.dart';

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

  setUp(() async {
    backing.clear();
    installMock();
    AuthService.debugTokenExchange = (_, __) async => true;
    await AuthService.instance.logout();
  });

  tearDown(() async {
    await AuthService.instance.logout();
    AuthService.debugTokenExchange = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('correct credentials mint a session and clear the expiry flag', () async {
    final ok = await AuthService.instance.authenticate('monish', 'Chennaisuper.23');
    expect(ok, isTrue);
    expect(AuthService.instance.isAuthenticated, isTrue);
    expect(AuthService.instance.didSessionExpire, isFalse);
    expect(AuthService.instance.username, 'Monish');
    expect(backing.containsKey('nxs_session_v2'), isTrue);
    expect(backing.containsKey('nxs_session_ts'), isTrue);
    expect(backing.containsKey('nxs_session_expired'), isFalse);
  });

  test('username is case- and whitespace-tolerant', () async {
    expect(
      await AuthService.instance.authenticate('  MONISH  ', 'Chennaisuper.23'),
      isTrue,
    );
  });

  test('wrong password is rejected and leaves no session', () async {
    expect(
      await AuthService.instance.authenticate('monish', 'Tundra-Lantern-Zephyr-20'),
      isFalse,
    );
    expect(AuthService.instance.isAuthenticated, isFalse);
    expect(backing.containsKey('nxs_session_v2'), isFalse);
  });

  test('unknown username is rejected', () async {
    expect(
      await AuthService.instance.authenticate('attacker', 'Chennaisuper.23'),
      isFalse,
    );
  });

  test('password is case-sensitive', () async {
    expect(
      await AuthService.instance.authenticate('monish', 'chennaisuper.23'),
      isFalse,
    );
  });

  test('45-day expiry signs out but keeps the username for re-entry', () async {
    expect(
      await AuthService.instance.authenticate('monish', 'Chennaisuper.23'),
      isTrue,
    );
    backing['nxs_session_ts'] =
        DateTime.now().subtract(const Duration(days: 46)).toIso8601String();

    await AuthService.instance.checkSessionValidity();

    expect(AuthService.instance.isAuthenticated, isFalse);
    expect(AuthService.instance.didSessionExpire, isTrue);
    expect(AuthService.instance.username, 'Monish');
    expect(backing['nxs_session_expired'], '1');
    expect(backing.containsKey('nxs_session_v2'), isFalse);
    expect(backing.containsKey('app_jwt'), isFalse);
  });

  test('re-entering the same password after expiry resets the 45-day clock',
      () async {
    await AuthService.instance.authenticate('monish', 'Chennaisuper.23');
    backing['nxs_session_ts'] =
        DateTime.now().subtract(const Duration(days: 46)).toIso8601String();
    await AuthService.instance.checkSessionValidity();
    expect(AuthService.instance.didSessionExpire, isTrue);

    final ok =
        await AuthService.instance.authenticate('monish', 'Chennaisuper.23');
    expect(ok, isTrue);
    expect(AuthService.instance.isAuthenticated, isTrue);
    expect(AuthService.instance.didSessionExpire, isFalse);
    expect(backing.containsKey('nxs_session_expired'), isFalse);

    final ts = DateTime.parse(backing['nxs_session_ts']!);
    expect(DateTime.now().difference(ts).inMinutes, lessThan(2));
  });

  test('cold start restores the expired-session flag without a live session',
      () async {
    backing['nxs_session_expired'] = '1';
    backing['nxs_username'] = 'Monish';

    await AuthService.instance.init();

    expect(AuthService.instance.isAuthenticated, isFalse);
    expect(AuthService.instance.didSessionExpire, isTrue);
    expect(AuthService.instance.username, 'Monish');
  });

  test('cold start with a fresh session stays logged in', () async {
    backing['nxs_session_v2'] = 'tok';
    backing['nxs_session_ts'] = DateTime.now().toIso8601String();
    backing['nxs_username'] = 'Monish';

    await AuthService.instance.init();

    expect(AuthService.instance.isAuthenticated, isTrue);
    expect(AuthService.instance.didSessionExpire, isFalse);
  });

  test('cold start with a 46-day-old session expires in place', () async {
    backing['nxs_session_v2'] = 'tok';
    backing['nxs_session_ts'] =
        DateTime.now().subtract(const Duration(days: 46)).toIso8601String();
    backing['nxs_username'] = 'Monish';

    await AuthService.instance.init();

    expect(AuthService.instance.isAuthenticated, isFalse);
    expect(AuthService.instance.didSessionExpire, isTrue);
    expect(AuthService.instance.username, 'Monish');
  });

  test('manual logout wipes username and the expiry flag', () async {
    await AuthService.instance.authenticate('monish', 'Chennaisuper.23');
    await AuthService.instance.logout();
    expect(AuthService.instance.isAuthenticated, isFalse);
    expect(AuthService.instance.didSessionExpire, isFalse);
    expect(AuthService.instance.username, isEmpty);
    expect(backing.containsKey('nxs_username'), isFalse);
    expect(backing.containsKey('nxs_session_expired'), isFalse);
  });
}
