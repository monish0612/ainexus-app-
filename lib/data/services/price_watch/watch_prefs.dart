import 'package:shared_preferences/shared_preferences.dart';

import 'watch_policy.dart';

class WatchPrefs {
  WatchPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _kEnabled = 'watch_enabled';
  static const _kInterval = 'watch_interval_minutes';
  static const _kDec = 'watch_notify_decrease';
  static const _kInc = 'watch_notify_increase';
  static const _kTarget = 'watch_notify_target';
  static const _kQuiet = 'watch_quiet_hours';
  static const _kQuietStart = 'watch_quiet_start';
  static const _kQuietEnd = 'watch_quiet_end';

  bool get enabled => _prefs.getBool(_kEnabled) ?? true;

  int get intervalMinutes {
    final n = _prefs.getInt(_kInterval) ?? kDefaultIntervalMinutes;
    return n.clamp(kMinIntervalMinutes, kMaxIntervalMinutes);
  }

  bool get notifyDecrease => _prefs.getBool(_kDec) ?? true;
  bool get notifyIncrease => _prefs.getBool(_kInc) ?? false;
  bool get notifyTarget => _prefs.getBool(_kTarget) ?? true;
  bool get quietHours => _prefs.getBool(_kQuiet) ?? false;
  int get quietStart => _prefs.getInt(_kQuietStart) ?? 22;
  int get quietEnd => _prefs.getInt(_kQuietEnd) ?? 8;

  Future<void> setEnabled(bool v) => _prefs.setBool(_kEnabled, v);
  Future<void> setIntervalMinutes(int v) => _prefs.setInt(
        _kInterval,
        v.clamp(kMinIntervalMinutes, kMaxIntervalMinutes),
      );
  Future<void> setNotifyDecrease(bool v) => _prefs.setBool(_kDec, v);
  Future<void> setNotifyIncrease(bool v) => _prefs.setBool(_kInc, v);
  Future<void> setNotifyTarget(bool v) => _prefs.setBool(_kTarget, v);
  Future<void> setQuietHours(bool v) => _prefs.setBool(_kQuiet, v);
  Future<void> setQuietStart(int hour) =>
      _prefs.setInt(_kQuietStart, hour.clamp(0, 23));
  Future<void> setQuietEnd(int hour) =>
      _prefs.setInt(_kQuietEnd, hour.clamp(0, 23));
}
