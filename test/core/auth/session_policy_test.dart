import 'package:ai_nexus/core/auth/app_credentials.dart';
import 'package:ai_nexus/core/auth/session_policy.dart';
import 'package:ai_nexus/presentation/screens/auth/login_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppCredentials', () {
    test('username decodes to monish', () {
      expect(AppCredentials.username, 'monish');
    });

    test('password is rotated back to Chennaisuper.23', () {
      expect(AppCredentials.password, 'Chennaisuper.23');
    });

    test('does not still carry the previous rotated password', () {
      expect(AppCredentials.password, isNot('Tundra-Lantern-Zephyr-20'));
    });
  });

  group('SessionPolicy', () {
    final login = DateTime.utc(2026, 1, 1, 10);

    test('is valid just under 45 days', () {
      expect(
        SessionPolicy.isExpired(login, login.add(const Duration(days: 44, hours: 23))),
        isFalse,
      );
    });

    test('expires at exactly 45 days', () {
      expect(
        SessionPolicy.isExpired(login, login.add(const Duration(days: 45))),
        isTrue,
      );
    });

    test('stays expired after 45 days', () {
      expect(
        SessionPolicy.isExpired(login, login.add(const Duration(days: 60))),
        isTrue,
      );
    });

    test('a fresh login is not expired', () {
      expect(SessionPolicy.isExpired(login, login), isFalse);
    });
  });

  group('LoginCopy', () {
    test('fresh login uses sign-in wording', () {
      expect(LoginCopy.subtitle(sessionExpired: false), LoginCopy.signInSubtitle);
      expect(LoginCopy.actionLabel(sessionExpired: false), LoginCopy.signInLabel);
    });

    test('expired session asks to re-enter the same password', () {
      expect(
        LoginCopy.subtitle(sessionExpired: true),
        contains('same password'),
      );
      expect(LoginCopy.actionLabel(sessionExpired: true), LoginCopy.continueLabel);
    });
  });
}
