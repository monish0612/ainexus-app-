import 'dart:async';
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../domain/entities/expense_entities.dart';
import '../../repositories/expense_repository.dart';
import '../expense_category_memory.dart';
import 'sms_intake_policy.dart';
import 'sms_merchant_category.dart';
import 'sms_models.dart';
import 'sms_parser.dart';
import 'sms_spend_dedupe.dart';

class SmsExpenseStatus {
  const SmsExpenseStatus({
    required this.enabled,
    required this.mode,
    required this.permissionGranted,
    required this.batteryUnrestricted,
    required this.notificationGranted,
  });

  const SmsExpenseStatus.unknown()
      : enabled = false,
        mode = 'ask',
        permissionGranted = false,
        batteryUnrestricted = false,
        notificationGranted = false;

  final bool enabled;
  final String mode;
  final bool permissionGranted;
  final bool batteryUnrestricted;
  final bool notificationGranted;

  bool get auto => mode == 'auto';
  bool get ready => enabled && permissionGranted;
}

class SmsReview {
  const SmsReview({
    required this.item,
    required this.category,
    required this.description,
    required this.comments,
    required this.stamp,
  });

  final SmsPendingItem item;
  final String category;
  final String description;
  final String comments;
  final String stamp;

  ParsedSmsDebit get debit => item.debit;

  SmsReview copyWith({String? category, String? description}) {
    return SmsReview(
      item: item,
      category: category ?? this.category,
      description: description ?? this.description,
      comments: comments,
      stamp: stamp,
    );
  }
}

class SmsToast {
  const SmsToast({
    required this.expenseId,
    required this.amount,
    required this.description,
    required this.category,
  });

  final String expenseId;
  final double amount;
  final String description;
  final String category;
}

class SmsExpenseUiState {
  const SmsExpenseUiState({
    this.review,
    this.toast,
    this.busy = false,
    this.saveError,
    this.waitingCount = 0,
  });

  final SmsReview? review;
  final SmsToast? toast;
  final bool busy;
  final String? saveError;
  final int waitingCount;

  SmsExpenseUiState copyWith({
    SmsReview? review,
    SmsToast? toast,
    bool? busy,
    String? saveError,
    int? waitingCount,
    bool clearReview = false,
    bool clearToast = false,
    bool clearError = false,
  }) {
    return SmsExpenseUiState(
      review: clearReview ? null : (review ?? this.review),
      toast: clearToast ? null : (toast ?? this.toast),
      busy: busy ?? this.busy,
      saveError: clearError ? null : (saveError ?? this.saveError),
      waitingCount: waitingCount ?? this.waitingCount,
    );
  }
}

/// Bumped when a SMS notification tap should land on the Expense tab.
final smsOpenExpenseTabTickProvider = StateProvider<int>((ref) => 0);

class SmsAutoExpenseController extends StateNotifier<SmsExpenseUiState> {
  SmsAutoExpenseController(this._ref) : super(const SmsExpenseUiState()) {
    _bind();
  }

  final Ref _ref;
  static const _channel = MethodChannel('app.ainexus.ai_nexus/sms_expense');

  Timer? _toastTimer;
  bool _alive = true;
  Future<void> _gate = Future<void>.value();
  Future<void> _saveGate = Future<void>.value();
  final Map<String, Future<bool>> _inflightSaves = {};
  final Set<String> _protectedIds = <String>{};

  ExpenseRepository get _repo => _ref.read(expenseRepositoryProvider);

  Future<T> _enqueue<T>(Future<T> Function() body) {
    final done = Completer<T>();
    _gate = _gate.then((_) async {
      try {
        done.complete(await body());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  void _bind() {
    if (!PlatformCapabilities.canUseSmsAutoExpense) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSmsDebit') {
        final args = _asStringKeyMap(call.arguments);
        await _enqueue(() => _onNativeItem(args));
      } else if (call.method == 'onSmsOpen') {
        final id = call.arguments?.toString();
        if (id != null && id.isNotEmpty) {
          await _enqueue(() => _openId(id, fromNotification: true));
        }
      }
    });
    Future<void>.microtask(() async {
      try {
        await _channel.invokeMethod<void>('ready');
      } catch (_) {}
      await _enqueue(_drain);
    });
  }

  Future<void> drainOnResume() => _enqueue(_drain);

  Future<SmsExpenseStatus> status() async {
    if (!PlatformCapabilities.canUseSmsAutoExpense) {
      return const SmsExpenseStatus.unknown();
    }
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('status');
      if (map == null) return const SmsExpenseStatus.unknown();
      return SmsExpenseStatus(
        enabled: map['enabled'] == true,
        mode: (map['mode'] ?? 'ask').toString(),
        permissionGranted: map['permissionGranted'] == true,
        batteryUnrestricted: map['batteryUnrestricted'] == true,
        notificationGranted: map['notificationGranted'] != false,
      );
    } catch (_) {
      return const SmsExpenseStatus.unknown();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!PlatformCapabilities.canUseSmsAutoExpense) return;
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } catch (e) {
      TLog.w('SmsExpense', 'setEnabled failed', error: e);
    }
  }

  Future<void> setMode(String mode) async {
    if (!PlatformCapabilities.canUseSmsAutoExpense) return;
    try {
      await _channel.invokeMethod<void>('setMode', {'mode': mode});
    } catch (e) {
      TLog.w('SmsExpense', 'setMode failed', error: e);
    }
  }

  Future<bool> requestSmsPermission() async {
    if (!PlatformCapabilities.canUseSmsAutoExpense) return false;
    try {
      return await _channel.invokeMethod<bool>('requestSmsPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestBatteryUnrestricted() async {
    if (!PlatformCapabilities.canUseSmsAutoExpense) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  Future<void> openAppInfo() async {
    if (!PlatformCapabilities.canUseSmsAutoExpense) return;
    try {
      await _channel.invokeMethod<void>('openAppInfo');
    } catch (_) {}
  }

  Future<void> playSample() async {
    const body = 'Sent Rs.282.00\nFrom HDFC Bank A/C *7372\nTo Scapia\n'
        'On 10/09/26\nRef 859114032536\nNot You?\nSMS BLOCK UPI';
    final now = DateTime.now();
    final parsed = BankSmsParser.parse(
      body,
      smsReceivedAt: now.millisecondsSinceEpoch,
      sender: 'JM-HDFCBK',
    );
    if (parsed == null) return;
    final item = SmsPendingItem(
      id: 'sample-${now.millisecondsSinceEpoch}',
      sender: 'JM-HDFCBK',
      debit: parsed,
      receivedAt: now.millisecondsSinceEpoch,
    );
    final st = await status();
    if (st.auto) {
      await _save(item, fromUser: true);
    } else {
      state = state.copyWith(review: await _toReview(item));
    }
  }

  Future<void> approveCurrent({String? categoryOverride}) async {
    final review = state.review;
    if (review == null || state.busy) return;
    state = state.copyWith(busy: true);
    try {
      final ok = await _save(
        review.item,
        fromUser: true,
        categoryOverride: categoryOverride ?? review.category,
        descriptionOverride: review.description,
      );
      if (ok) {
        state = state.copyWith(busy: false, clearReview: true, clearError: true);
        await _drain();
        if (state.review != null) {
          state = state.copyWith(clearToast: true);
        }
      } else {
        state = state.copyWith(
          busy: false,
          saveError: "Couldn't save. Tap Approve to retry.",
        );
      }
    } catch (_) {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> rejectCurrent() async {
    final review = state.review;
    if (review == null) return;
    await _removeNative(review.item.id);
    state = state.copyWith(
      clearReview: true,
      clearError: true,
      waitingCount: 0,
    );
    await _drain();
  }

  void setReviewCategory(String category) {
    final review = state.review;
    if (review == null || category.trim().isEmpty) return;
    state = state.copyWith(review: review.copyWith(category: category.trim()));
  }

  /// Expense list edit — drop the Undo toast so it cannot delete the row.
  void noteUserEditing(String expenseId) {
    if (expenseId.isEmpty) return;
    _protectedIds.add(expenseId);
    if (state.toast?.expenseId == expenseId) {
      _toastTimer?.cancel();
      state = state.copyWith(clearToast: true);
    }
  }

  Future<void> undoToast() async {
    final toast = state.toast;
    if (toast == null) return;
    _toastTimer?.cancel();
    state = state.copyWith(clearToast: true);
    if (_protectedIds.contains(toast.expenseId)) return;
    try {
      final live = await _repo.getExpenseById(toast.expenseId);
      if (live != null &&
          !SmsIntakePolicy.undoStillValid(
            toastCategory: toast.category,
            toastDescription: toast.description,
            liveCategory: live.category,
            liveDescription: live.description,
            liveManualCategory: live.isManualCategory,
          )) {
        return;
      }
      await _repo.deleteExpense(toast.expenseId);
    } catch (e) {
      TLog.w('SmsExpense', 'undo failed', error: e);
    }
  }

  Future<void> _drain() async {
    if (!PlatformCapabilities.canUseSmsAutoExpense) return;
    try {
      String? focus;
      try {
        focus = await _channel.invokeMethod<String>('takeOpenId');
      } catch (_) {}
      if (focus != null && focus.isNotEmpty) _revealExpenseTab();
      await _processPending(focusId: focus);
    } catch (e) {
      TLog.w('SmsExpense', 'drain failed', error: e);
    }
  }

  Future<void> _openId(String id, {required bool fromNotification}) async {
    try {
      if (fromNotification) _revealExpenseTab();
      await _processPending(focusId: id);
    } catch (e) {
      TLog.w('SmsExpense', 'openId failed', error: e);
    }
  }

  Future<void> _processPending({String? focusId}) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('pending');
    if (raw == null) return;
    final st = await status();
    if (!st.enabled) return;

    final rows = <Map<String, dynamic>>[];
    for (final row in raw) {
      if (row is Map) rows.add(_asStringKeyMap(row));
    }

    if (st.auto) {
      for (final map in rows) {
        final qStatus = (map['status'] ?? 'pending').toString();
        final id = map['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (qStatus == 'rejected' || qStatus == 'saved') {
          await _removeNative(id);
          continue;
        }
        final item = await _takeQueued(map);
        if (item == null) continue;
        await _save(item, fromUser: qStatus == 'approved');
      }
      state = state.copyWith(waitingCount: 0);
      return;
    }

    if (focusId != null && focusId.isNotEmpty) {
      for (final map in rows) {
        if (map['id']?.toString() == focusId) {
          await _onNativeItem(map, notificationTap: true);
          break;
        }
      }
    }

    var waiting = 0;
    for (final map in rows) {
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final qStatus = (map['status'] ?? 'pending').toString();
      if (qStatus == 'rejected' || qStatus == 'saved') {
        await _removeNative(id);
        continue;
      }
      if (SmsIntakePolicy.shouldAutoSave(auto: false, status: qStatus)) {
        final item = await _takeQueued(map);
        if (item != null) await _save(item, fromUser: true);
        continue;
      }
      if (state.review?.item.id == id) continue;
      if (state.review == null) {
        final item = await _takeQueued(map);
        if (item != null) {
          state = state.copyWith(review: await _toReview(item));
        }
      } else {
        waiting++;
      }
    }
    state = state.copyWith(waitingCount: waiting);
  }

  Future<void> _onNativeItem(
    Map<String, dynamic> map, {
    bool notificationTap = false,
  }) async {
    final action = map['action']?.toString();
    if (action == 'rejected') {
      if (state.review?.item.id == map['id']?.toString()) {
        state = state.copyWith(clearReview: true);
      }
      return;
    }
    if (action == 'approved') {
      final id = map['id']?.toString();
      if (id == null) return;
      final item = await _takeQueued(map) ?? await _lookupPending(id);
      if (item != null) {
        await _save(item, fromUser: true);
      }
      return;
    }

    final resolved = await _takeQueued(map);
    if (resolved == null) return;

    final st = await status();
    if (!st.enabled && !notificationTap) return;

    if (st.auto ||
        SmsIntakePolicy.shouldAutoSave(
          auto: st.auto,
          status: resolved.status,
        )) {
      await _save(resolved, fromUser: resolved.status == 'approved');
      return;
    }

    if (SmsIntakePolicy.replaceReview(
      currentReviewId: state.review?.item.id,
      incomingId: resolved.id,
      notificationTap: notificationTap,
    )) {
      state = state.copyWith(
        review: await _toReview(resolved),
        clearError: true,
      );
    }
  }

  Future<SmsPendingItem?> _lookupPending(String id) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('pending');
      for (final row in raw ?? const <dynamic>[]) {
        if (row is Map && row['id']?.toString() == id) {
          return await _takeQueued(_asStringKeyMap(row));
        }
      }
    } catch (_) {}
    return null;
  }

  void _revealExpenseTab() {
    _ref.read(smsOpenExpenseTabTickProvider.notifier).update((n) => n + 1);
  }

  Future<SmsPendingItem?> _takeQueued(Map<String, dynamic> map) async {
    final id = map['id']?.toString() ?? '';
    final item = _parseItem(map);
    if (item == null) {
      if (id.isNotEmpty) await _removeNative(id);
      return null;
    }
    return item;
  }

  SmsPendingItem? _parseItem(Map<String, dynamic> map) {
    final item = SmsPendingItem.fromJson(map);
    if (item.id.isEmpty || item.debit.amount <= 0) return null;
    final debit = BankSmsParser.reconcileQueued(
      item.debit,
      smsReceivedAt: item.receivedAt,
      sender: item.sender,
    );
    if (debit == null) return null;
    return SmsPendingItem(
      id: item.id,
      sender: item.sender,
      debit: debit,
      receivedAt: item.receivedAt,
      status: item.status,
    );
  }

  Future<SmsReview> _toReview(SmsPendingItem item) async {
    final labels = await _labels();
    final learnings = await _repo.getLearnings();
    final category = suggestSmsCategory(
      item.debit.merchantRaw,
      labels: labels,
      learnings: learnings,
    );
    final received = DateTime.fromMillisecondsSinceEpoch(item.receivedAt);
    final stamp = autoDetectedStamp(received);
    final hasMerchant = item.debit.hasMerchant;
    return SmsReview(
      item: item,
      category: category,
      description: hasMerchant ? item.debit.merchantRaw : stamp,
      comments: hasMerchant ? stamp : '',
      stamp: stamp,
    );
  }

  Future<bool> _save(
    SmsPendingItem item, {
    required bool fromUser,
    String? categoryOverride,
    String? descriptionOverride,
  }) async {
    final existing = _inflightSaves[item.id];
    if (existing != null) return existing;
    final future = () async {
      final done = Completer<void>();
      final prev = _saveGate;
      _saveGate = done.future;
      await prev;
      try {
        return await _saveOnce(
          item,
          fromUser: fromUser,
          categoryOverride: categoryOverride,
          descriptionOverride: descriptionOverride,
        );
      } finally {
        done.complete();
      }
    }();
    _inflightSaves[item.id] = future;
    try {
      return await future;
    } finally {
      _inflightSaves.remove(item.id);
    }
  }

  Future<bool> _saveOnce(
    SmsPendingItem item, {
    required bool fromUser,
    String? categoryOverride,
    String? descriptionOverride,
  }) async {
    try {
      final labels = await _labels();
      final learnings = await _repo.getLearnings();
      final category = categoryOverride ??
          suggestSmsCategory(
            item.debit.merchantRaw,
            labels: labels,
            learnings: learnings,
          );
      final received = DateTime.fromMillisecondsSinceEpoch(item.receivedAt);
      final stamp = autoDetectedStamp(received);
      final hasMerchant = item.debit.hasMerchant;
      final description = descriptionOverride ??
          (hasMerchant ? item.debit.merchantRaw : stamp);
      final comments = hasMerchant ? stamp : '';
      final day = SmsIntakePolicy.expenseDay(item.debit.transactionDate, received);
      try {
        final recent = await _repo.getExpensesPage(
          startIso: received.subtract(const Duration(days: 1)).toIso8601String(),
          limit: 80,
          offset: 0,
        );
        final hit = SmsSpendDedupe.match(
          incoming: item.debit,
          incomingDescription: description,
          receivedAt: received,
          recent: recent,
        );
        if (hit != null) {
          await _removeNative(item.id);
          if (hit.upgrade && !hit.existing.isManualCategory) {
            final upgraded = hit.existing.copyWith(
              description: description,
              bank: item.debit.bank,
              cardType: item.debit.cardType,
              comments: comments.isNotEmpty ? comments : hit.existing.comments,
              category: SmsSpendDedupe.mayAutofillCategory(hit.existing)
                  ? category
                  : hit.existing.category,
            );
            try {
              await _repo.updateExpense(upgraded);
              TLog.i(
                'SmsExpense',
                'Collapsed duplicate SMS ₹${item.debit.amount.toStringAsFixed(0)} '
                '→ ${upgraded.description}',
              );
            } catch (e) {
              TLog.w('SmsExpense', 'duplicate upgrade failed', error: e);
            }
          } else {
            TLog.i(
              'SmsExpense',
              'Skipped duplicate SMS ₹${item.debit.amount.toStringAsFixed(0)} '
              '(already logged as ${hit.existing.description})',
            );
          }
          return true;
        }
      } catch (e) {
        TLog.w('SmsExpense', 'dedupe lookup failed (non-fatal)', error: e);
      }

      final expense = Expense(
        id: item.id.startsWith('sample-')
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : SmsIntakePolicy.expenseIdFor(item.id),
        amount: item.debit.amount,
        description: description,
        category: category,
        bank: item.debit.bank,
        cardType: item.debit.cardType,
        date: day.toIso8601String(),
        isManualCategory: fromUser && categoryOverride != null,
        comments: comments,
      );

      var attempts = 0;
      var synced = false;
      var duplicate = false;
      Object? lastError;
      while (attempts < 3) {
        attempts++;
        try {
          synced = await _repo.addExpense(expense);
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          final msg = e.toString().toLowerCase();
          if (msg.contains('unique') || msg.contains('constraint')) {
            duplicate = true;
            lastError = null;
            break;
          }
          await Future<void>.delayed(Duration(milliseconds: 400 * attempts));
        }
      }
      if (lastError != null) {
        TLog.e('SmsExpense', 'save failed after retries', error: lastError);
        return false;
      }

      await _removeNative(item.id);
      if (duplicate) return true;
      if (item.debit.hasMerchant && category != 'Others') {
        await _rememberLabel(item.debit.merchantRaw, category);
      }

      TLog.i(
        'SmsExpense',
        'Logged ₹${expense.amount.toStringAsFixed(0)} | ${expense.description} | '
        '${expense.category} synced=$synced user=$fromUser',
      );

      final foreground = SchedulerBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
      if (foreground) {
        _toastTimer?.cancel();
        state = state.copyWith(
          clearReview: true,
          toast: SmsToast(
            expenseId: expense.id,
            amount: expense.amount,
            description: expense.description,
            category: expense.category,
          ),
        );
        _toastTimer = Timer(const Duration(seconds: 8), () {
          if (_alive) state = state.copyWith(clearToast: true);
        });
      } else {
        await _showLoggedNotification(item, expense);
      }
      return true;
    } catch (e) {
      TLog.e('SmsExpense', 'save crashed', error: e);
      return false;
    }
  }

  Map<String, dynamic> _asStringKeyMap(dynamic raw) {
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries) e.key.toString(): e.value,
    };
  }

  Future<void> _removeNative(String id) async {
    if (id.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('remove', {'id': id});
    } catch (_) {}
  }

  Future<void> _showLoggedNotification(
    SmsPendingItem item,
    Expense expense,
  ) async {
    try {
      await _channel.invokeMethod<void>('showLogged', {
        'id': item.id,
        'amount': expense.amount,
        'merchant': expense.description,
      });
    } catch (_) {}
  }

  Future<Map<String, String>> _labels() async {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final raw = prefs.getString(kSmsMerchantLabelsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _rememberLabel(String merchant, String category) async {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final map = await _labels();
      ExpenseCategoryMemory.rememberExact(map, merchant, category);
      await prefs.setString(kSmsMerchantLabelsKey, jsonEncode(map));
    } catch (_) {}
  }

  @override
  void dispose() {
    _alive = false;
    _toastTimer?.cancel();
    super.dispose();
  }
}

final smsAutoExpenseProvider =
    StateNotifierProvider<SmsAutoExpenseController, SmsExpenseUiState>((ref) {
  return SmsAutoExpenseController(ref);
});
