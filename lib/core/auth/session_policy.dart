/// 45-day local session clock shared by the login gate.
///
/// After this window the user is signed out and asked to re-enter the **same**
/// password. A successful re-entry mints a fresh 45-day session — the password
/// itself never changes.
class SessionPolicy {
  const SessionPolicy._();

  static const int maxDays = 45;

  /// True when [loginTime] is at least [maxDays] calendar-days before [now].
  /// Uses truncated day-diff (same as the original gate) so a login at 10:00
  /// is still valid at 09:59 on day 45, and expired at 10:00 on day 45.
  static bool isExpired(DateTime loginTime, DateTime now) =>
      now.difference(loginTime).inDays >= maxDays;
}
