import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/expense_entities.dart';
import '../platform/platform_capabilities.dart';
import 'telegram_logger.dart';

/// Writes today's expense summary to SharedPreferences so the native
/// Android ExpenseWidgetProvider can read it, then triggers a widget refresh.
///
/// Data freshness is guaranteed by:
///   1. A date stamp (`expense_widget_update_date`) stored alongside the data —
///      the native side zeros out today's totals if the stamp is stale.
///   2. A native AlarmManager fires at midnight to force a widget redraw.
///   3. [refreshOnAppStart] is called during app init so the widget gets
///      fresh data even if the user hasn't opened the expense tab yet.
///
/// Retry strategy: [_triggerNativeRefreshWithRetry] tries up to 3 times with
/// exponential backoff (500ms → 1s → 2s). This covers the startup race where
/// the MethodChannel may not be ready yet.
class ExpenseWidgetService {
  ExpenseWidgetService._();
  static final instance = ExpenseWidgetService._();

  static const _channel = MethodChannel('app.ainexus.ai_nexus/expense_widget');
  static const _maxRetries = 3;

  int _lastHash = 0;
  Timer? _debounce;

  /// Call whenever expenses or budget change.
  /// Debounces rapid calls (300ms) and skips if data hasn't changed.
  void scheduleUpdate({
    required List<Expense> expenses,
    required double monthBudget,
  }) {
    if (!PlatformCapabilities.canUseExpenseWidget) return;
    double amountSum = 0;
    for (final e in expenses) {
      amountSum += e.amount;
    }
    final hash = Object.hash(expenses.length, monthBudget, amountSum);
    if (hash == _lastHash) return;
    _lastHash = hash;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _doUpdate(expenses: expenses, monthBudget: monthBudget);
    });
  }

  /// Lightweight startup call: if the stored date is stale, immediately
  /// write zeros for today and trigger a native refresh so the widget
  /// doesn't show yesterday's data while the expense stream loads.
  Future<void> refreshOnAppStart() async {
    if (!PlatformCapabilities.canUseExpenseWidget) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedDate = prefs.getString('expense_widget_update_date') ?? '';
      final today = _todayDateString();

      if (storedDate == today) {
        _triggerNativeRefreshWithRetry('startup-fresh');
        TLog.d('ExpWidget', 'Startup: date fresh, triggered refresh');
        return;
      }

      final storedMonth = storedDate.length >= 7
          ? storedDate.substring(0, 7)
          : '';
      final currentMonth = today.substring(0, 7);
      final isMonthStale = storedMonth != currentMonth;

      final writes = <Future<bool>>[
        prefs.setString('expense_widget_today_total', '0.00'),
        prefs.setInt('expense_widget_today_count', 0),
        prefs.setString('expense_widget_update_date', today),
      ];

      if (isMonthStale) {
        writes.add(prefs.setString('expense_widget_month_spent', '0.00'));
      }

      await Future.wait(writes);
      _triggerNativeRefreshWithRetry('startup-stale');

      if (isMonthStale) {
        TLog.i('ExpWidget',
            'Startup: month boundary ($storedMonth→$currentMonth), zeroed today + month');
      } else {
        TLog.i('ExpWidget',
            'Startup: date stale ($storedDate→$today), zeroed today');
      }
    } catch (e, st) {
      TLog.e('ExpWidget', 'refreshOnAppStart failed', error: e, st: st);
    }
  }

  Future<void> _doUpdate({
    required List<Expense> expenses,
    required double monthBudget,
  }) async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final tomorrowStart = todayStart.add(const Duration(days: 1));
      final monthStart = DateTime(now.year, now.month, 1);

      double todayTotal = 0;
      int todayCount = 0;
      double monthSpent = 0;

      for (final e in expenses) {
        final d = DateTime.tryParse(e.date);
        if (d == null) continue;

        if (!d.isBefore(monthStart)) {
          monthSpent += e.amount;
        }
        if (!d.isBefore(todayStart) && d.isBefore(tomorrowStart)) {
          todayTotal += e.amount;
          todayCount++;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString('expense_widget_today_total', todayTotal.toStringAsFixed(2)),
        prefs.setInt('expense_widget_today_count', todayCount),
        prefs.setString('expense_widget_month_budget', monthBudget.toStringAsFixed(2)),
        prefs.setString('expense_widget_month_spent', monthSpent.toStringAsFixed(2)),
        prefs.setString('expense_widget_update_date', _todayDateString()),
      ]);

      _triggerNativeRefreshWithRetry('update');
      TLog.i('ExpWidget',
          'Widget synced: today=₹$todayTotal ($todayCount), budget=₹$monthBudget, month=₹$monthSpent');
    } catch (e, st) {
      TLog.e('ExpWidget', 'Failed to update expense widget data', error: e, st: st);
    }
  }

  /// Retry up to [_maxRetries] times with exponential backoff.
  /// Covers the startup race where the MethodChannel may not be wired yet.
  void _triggerNativeRefreshWithRetry(String reason, [int attempt = 1]) {
    if (!PlatformCapabilities.canUseExpenseWidget) return;
    _channel.invokeMethod<void>('updateExpenseWidget').then((_) {
      if (attempt > 1) {
        TLog.i('ExpWidget', 'Native refresh succeeded on attempt $attempt ($reason)');
      }
    }).catchError((Object e) {
      if (attempt < _maxRetries) {
        final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
        TLog.w('ExpWidget',
            'Native refresh attempt $attempt/$_maxRetries failed ($reason), retry in ${delay.inMilliseconds}ms',
            error: e);
        Timer(delay, () => _triggerNativeRefreshWithRetry(reason, attempt + 1));
      } else {
        TLog.e('ExpWidget',
            'Native refresh failed after $_maxRetries attempts ($reason)',
            error: e);
      }
    });
  }

  static String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
