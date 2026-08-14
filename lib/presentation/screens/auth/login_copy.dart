/// Copy for the login gate. Kept separate so session-expiry wording can be
/// unit-tested without pumping the full visual login screen.
class LoginCopy {
  const LoginCopy._();

  static const signInSubtitle = 'Sign in to continue';
  static const sessionExpiredSubtitle =
      'Your 45-day session expired. Re-enter the same password to continue.';

  static const signInLabel = 'Sign In';
  static const continueLabel = 'Continue';

  static String subtitle({required bool sessionExpired}) =>
      sessionExpired ? sessionExpiredSubtitle : signInSubtitle;

  static String actionLabel({required bool sessionExpired}) =>
      sessionExpired ? continueLabel : signInLabel;
}
