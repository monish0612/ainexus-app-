import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../data/services/expense_category_memory.dart';
import '../../../domain/entities/expense_entities.dart';

final learningsProvider =
    StateNotifierProvider<LearningsCtrl, CategoryLearning>((ref) {
  return LearningsCtrl(ref);
});

class LearningsCtrl extends StateNotifier<CategoryLearning> {
  LearningsCtrl(this._ref) : super({}) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final repo = _ref.read(expenseRepositoryProvider);
      state = await repo.getLearnings();
      unawaited(repo.syncLearningsFromServer().then((_) async {
        state = await repo.getLearnings();
      }));
    } catch (e) {
      TLog.w('Learnings', 'Failed to load learnings', error: e);
    }
  }

  /// Instant in-memory update, then SQLite + server + local VPA labels.
  Future<void> learnFromDescription(
    String description,
    String category,
  ) async {
    final keys = ExpenseCategoryMemory.keysFor(description);
    if (keys.isEmpty) return;
    final updated = Map<String, String>.from(state);
    for (final word in keys) {
      updated[word] = category;
    }
    state = updated;

    final repo = _ref.read(expenseRepositoryProvider);
    for (final word in keys) {
      await repo.saveLearning(word, category);
      unawaited(repo.syncLearning(word, category));
    }
    await _rememberSmsHandle(description, category);
    TLog.i(
      'Learnings',
      'Taught "$category" ← ${keys.take(4).join(', ')}',
    );
  }

  Future<void> _rememberSmsHandle(String description, String category) async {
    if (!description.contains('@')) return;
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final raw = prefs.getString(kSmsMerchantLabelsKey);
      final map = <String, String>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            map[e.key.toString()] = e.value.toString();
          }
        }
      }
      ExpenseCategoryMemory.rememberExact(map, description, category);
      await prefs.setString(kSmsMerchantLabelsKey, jsonEncode(map));
    } catch (e) {
      TLog.w('Learnings', 'SMS label remember failed', error: e);
    }
  }
}
