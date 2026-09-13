import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local "listened" badges. The audio file may already be gone after 95%;
/// the article stays in the feed with a checkmark until it ages out.
class NarrationCompletionStore extends ChangeNotifier {
  NarrationCompletionStore._();
  static final NarrationCompletionStore instance = NarrationCompletionStore._();

  static const _kKey = 'narration.completed_ids';
  static const _kSpeedKey = 'narration.playback_speed';

  SharedPreferences? _prefs;
  final Set<String> _ids = <String>{};
  double _speed = 1.0;

  double get speed => _speed;

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    _ids
      ..clear()
      ..addAll(prefs.getStringList(_kKey) ?? const <String>[]);
    _speed = prefs.getDouble(_kSpeedKey) ?? 1.0;
    if (_speed < 0.5) _speed = 0.5;
    if (_speed > 2.0) _speed = 2.0;
    notifyListeners();
  }

  bool isCompleted(String articleId) => _ids.contains(articleId);

  Future<void> mark(String articleId) async {
    if (articleId.trim().isEmpty) return;
    if (!_ids.add(articleId)) return;
    await _prefs?.setStringList(_kKey, _ids.toList());
    notifyListeners();
  }

  Future<void> setSpeed(double speed) async {
    final next = speed.clamp(0.5, 2.0);
    if (_speed == next) return;
    _speed = next;
    await _prefs?.setDouble(_kSpeedKey, next);
    notifyListeners();
  }
}
