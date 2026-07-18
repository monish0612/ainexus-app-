import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/user_preferences_service.dart';

// ── Data models ──────────────────────────────────────────────────────────────

/// The card type a configured bank entry represents. Mirrors the expense
/// `cardType` values ('DB' = debit, 'CC' = credit, 'Cash').
const String kCardTypeDebit = 'DB';
const String kCardTypeCredit = 'CC';
const String kCardTypeCash = 'Cash';
const List<String> kBankCardTypes = [
  kCardTypeDebit,
  kCardTypeCredit,
  kCardTypeCash,
];

/// A configured payment instrument: a bank name paired with a single card type
/// (DB / CC / Cash). Credit-card entries additionally carry their billing cycle
/// — [statementDay] (the day the statement closes) and [dueDay] (the day the
/// bill is due, in the month after it closes). Both are null for non-CC cards.
///
/// Stored as JSON inside the synced `app_banks` preference, so adding fields
/// here automatically round-trips across devices and the web.
@immutable
class Bank {
  const Bank({
    required this.id,
    required this.name,
    required this.color,
    this.cardType = kCardTypeDebit,
    this.statementDay,
    this.dueDay,
  });

  final String id;
  final String name;
  final String color;

  /// One of [kBankCardTypes]. Drives which payment options this bank exposes
  /// in the expense entry form and whether it participates in CC forecasting.
  final String cardType;

  /// Day-of-month (1-31) the credit-card statement closes. CC only; null
  /// otherwise.
  final int? statementDay;

  /// Day-of-month (1-31) the credit-card bill is due, in the month after the
  /// statement closes. CC only; null otherwise.
  final int? dueDay;

  /// Whether this entry is a credit card with a usable billing cycle.
  bool get isCreditCard =>
      cardType == kCardTypeCredit && statementDay != null && dueDay != null;

  Bank copyWith({
    String? id,
    String? name,
    String? color,
    String? cardType,
    int? statementDay,
    int? dueDay,
    bool clearBillingCycle = false,
  }) {
    return Bank(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      cardType: cardType ?? this.cardType,
      statementDay:
          clearBillingCycle ? null : (statementDay ?? this.statementDay),
      dueDay: clearBillingCycle ? null : (dueDay ?? this.dueDay),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'cardType': cardType,
        if (statementDay != null) 'statementDay': statementDay,
        if (dueDay != null) 'dueDay': dueDay,
      };

  factory Bank.fromJson(Map<String, dynamic> json) {
    final rawType = (json['cardType'] ?? kCardTypeDebit).toString();
    final cardType =
        kBankCardTypes.contains(rawType) ? rawType : kCardTypeDebit;
    int? asDay(dynamic v) {
      final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
      if (n == null || n < 1 || n > 31) return null;
      return n;
    }

    return Bank(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String,
      cardType: cardType,
      statementDay: cardType == kCardTypeCredit ? asDay(json['statementDay']) : null,
      dueDay: cardType == kCardTypeCredit ? asDay(json['dueDay']) : null,
    );
  }
}

// ── Defaults ─────────────────────────────────────────────────────────────────

const kDefaultDeepModel = 'gemini-3.1-pro-preview';
const kDefaultLiteModel = 'gemini-3.1-flash-lite-preview';
const kDefaultXGrokLiteModel = 'grok-4-1-fast-non-reasoning';
const kDefaultXGrokDeepModel = 'grok-4-0709';
const kDefaultXGrokThinkingModel = 'grok-4-1-fast-reasoning';

// ── State ────────────────────────────────────────────────────────────────────

@immutable
class SettingsState {
  const SettingsState({
    this.theme = 'dark',
    this.banks = const [],
    this.settingsOpen = false,
    this.deepModel = kDefaultDeepModel,
    this.liteModel = kDefaultLiteModel,
    this.xgrokEnabled = false,
    this.xgrokLiteModel = kDefaultXGrokLiteModel,
    this.xgrokDeepModel = kDefaultXGrokDeepModel,
    this.xgrokThinkingModel = kDefaultXGrokThinkingModel,
    this.summarizeOverride = 'gemini',
    this.defaultFollowUpProvider = 'gemini',
    this.onlineSearchProvider = 'gemini',
  });

  final String theme;
  final List<Bank> banks;
  final bool settingsOpen;
  final String deepModel;
  final String liteModel;
  final bool xgrokEnabled;
  final String xgrokLiteModel;
  final String xgrokDeepModel;
  final String xgrokThinkingModel;
  final String summarizeOverride; // 'gemini' or 'xgrok'
  final String defaultFollowUpProvider; // 'gemini' or 'xgrok'
  final String onlineSearchProvider; // 'gemini' or 'xgrok'

  bool get isDark => theme == 'dark';

  bool get defaultFollowUpIsXGrok =>
      xgrokEnabled && defaultFollowUpProvider == 'xgrok';

  bool get onlineSearchIsXGrok =>
      xgrokEnabled && onlineSearchProvider == 'xgrok';

  SettingsState copyWith({
    String? theme,
    List<Bank>? banks,
    bool? settingsOpen,
    String? deepModel,
    String? liteModel,
    bool? xgrokEnabled,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    String? summarizeOverride,
    String? defaultFollowUpProvider,
    String? onlineSearchProvider,
  }) {
    return SettingsState(
      theme: theme ?? this.theme,
      banks: banks ?? this.banks,
      settingsOpen: settingsOpen ?? this.settingsOpen,
      deepModel: deepModel ?? this.deepModel,
      liteModel: liteModel ?? this.liteModel,
      xgrokEnabled: xgrokEnabled ?? this.xgrokEnabled,
      xgrokLiteModel: xgrokLiteModel ?? this.xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel ?? this.xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel ?? this.xgrokThinkingModel,
      summarizeOverride: summarizeOverride ?? this.summarizeOverride,
      defaultFollowUpProvider:
          defaultFollowUpProvider ?? this.defaultFollowUpProvider,
      onlineSearchProvider:
          onlineSearchProvider ?? this.onlineSearchProvider,
    );
  }
}

// ── Shared-preference keys ───────────────────────────────────────────────────

abstract final class _PK {
  static const theme = 'app_theme';
  static const deepModel = 'deep_model';
  static const liteModel = 'lite_model';
  static const xgrokEnabled = 'xgrok_enabled';
  static const xgrokLiteModel = 'xgrok_lite_model';
  static const xgrokDeepModel = 'xgrok_deep_model';
  static const xgrokThinkingModel = 'xgrok_thinking_model';
  static const summarizeOverride = 'summarize_override';
  static const defaultFollowUp = 'default_followup_provider';
  static const onlineSearch = 'online_search_provider';
  // Server preference key for the banks list (JSON-encoded). Also the legacy
  // LOCAL key, where banks used to be stored as a `id|name|color` StringList.
  static const banks = 'app_banks';
  // New LOCAL key: banks stored as a single JSON string so the richer model
  // (cardType + billing cycle) round-trips losslessly. Reads fall back to the
  // legacy [banks] StringList for one-time migration.
  static const banksJson = 'app_banks_v2';
  // Outbox for unsynced setting changes (survives app kills).
  static const outbox = '_settings_outbox_v1';
}

// ── Default banks ────────────────────────────────────────────────────────────

// Seeded to mirror the real payment instruments used in expense entry. Each
// entry is a (bank, cardType) card; CC cards carry their billing cycle. All of
// these are fully editable/removable from Settings.
const _defaultBanks = <Bank>[
  Bank(id: 'hdfc_db', name: 'HDFC', color: '#004C8F'),
  Bank(
    id: 'hdfc_cc',
    name: 'HDFC',
    color: '#004C8F',
    cardType: kCardTypeCredit,
    statementDay: 18,
    dueDay: 9,
  ),
  Bank(id: 'icici_db', name: 'ICICI', color: '#B02A2A'),
  Bank(id: 'axis_db', name: 'AXIS', color: '#97144D'),
  Bank(
    id: 'axis_cc',
    name: 'AXIS',
    color: '#97144D',
    cardType: kCardTypeCredit,
    statementDay: 24,
    dueDay: 13,
  ),
  Bank(
    id: 'scapia_cc',
    name: 'SCAPIA',
    color: '#6D28D9',
    cardType: kCardTypeCredit,
    statementDay: 26,
    dueDay: 15,
  ),
  Bank(id: 'cash', name: 'CASH', color: '#868E96', cardType: kCardTypeCash),
];

// ═════════════════════════════════════════════════════════════════════════════
//  SETTINGS CONTROLLER
//
//  Two-phase load:
//    1. _hydrateFromPrefs()  — synchronous, instant UI from SharedPreferences
//    2. _syncFromServer()    — async, merges remote state, seeds on first run
//
//  Every setter:
//    1. Updates in-memory state        (instant UI rebuild)
//    2. Writes to SharedPreferences    (instant local persist)
//    3. Queues a debounced server push (batched for throughput)
//
//  Push queue is flushed on dispose to avoid data loss.
// ═════════════════════════════════════════════════════════════════════════════

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._prefs, this._remote) : super(const SettingsState()) {
    _hydrateFromPrefs();
    _loadOutbox();
    unawaited(_syncFromServer());
    // Drain whatever survived the last app session before doing anything else.
    if (_pendingPush.isNotEmpty) {
      unawaited(_flushPush(reason: 'startup-outbox'));
    }
  }

  final SharedPreferences _prefs;
  final UserPreferencesService _remote;

  static const _tag = 'Settings';
  static const _pushDebounce = Duration(milliseconds: 600);
  static const _syncCooldown = Duration(seconds: 15);

  final Map<String, String> _pendingPush = {};
  Timer? _pushTimer;
  bool _syncing = false;
  bool _flushing = false;
  DateTime? _lastSyncAt;

  // ── Phase 1: instant local hydration ───────────────────────────────────

  void _hydrateFromPrefs() {
    final theme = _prefs.getString(_PK.theme) ?? 'dark';
    final deepModel = _prefs.getString(_PK.deepModel) ?? kDefaultDeepModel;
    final liteModel = _prefs.getString(_PK.liteModel) ?? kDefaultLiteModel;
    final xgrokEnabled = _prefs.getBool(_PK.xgrokEnabled) ?? false;
    final xgrokLiteModel =
        _prefs.getString(_PK.xgrokLiteModel) ?? kDefaultXGrokLiteModel;
    final xgrokDeepModel =
        _prefs.getString(_PK.xgrokDeepModel) ?? kDefaultXGrokDeepModel;
    final xgrokThinkingModel =
        _prefs.getString(_PK.xgrokThinkingModel) ?? kDefaultXGrokThinkingModel;
    final summarizeOverride =
        _prefs.getString(_PK.summarizeOverride) ?? 'gemini';
    final defaultFollowUp =
        _prefs.getString(_PK.defaultFollowUp) ?? 'gemini';
    final onlineSearch =
        _prefs.getString(_PK.onlineSearch) ?? 'gemini';

    final banks = _readBanksFromPrefs() ?? _defaultBanks;

    state = SettingsState(
      theme: theme,
      banks: banks,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokEnabled: xgrokEnabled,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
      summarizeOverride: summarizeOverride,
      defaultFollowUpProvider: defaultFollowUp,
      onlineSearchProvider: onlineSearch,
    );

    TLog.d(_tag, 'Hydrated from SharedPrefs (xgrok=$xgrokEnabled)');
  }

  // ── Phase 2: background server sync ────────────────────────────────────

  /// Public re-sync entry point — called on app resume and settings sheet open.
  /// Respects a cooldown to avoid hammering the server on rapid lifecycle events.
  /// Always drains the outbox first so any change that couldn't reach the
  /// server while offline gets delivered before we pull remote state down.
  void resyncFromServer() {
    if (_pendingPush.isNotEmpty) {
      unawaited(_flushPush(reason: 'resume'));
    }
    if (_syncing) return;
    if (_lastSyncAt != null &&
        DateTime.now().difference(_lastSyncAt!) < _syncCooldown) {
      TLog.d(_tag, 'resync skipped (cooldown)');
      return;
    }
    unawaited(_syncFromServer());
  }

  Future<void> _syncFromServer() async {
    _syncing = true;
    final sw = Stopwatch()..start();
    try {
      final remote = await _remote.fetchAll();
      sw.stop();
      if (!mounted) return;

      if (remote == null) {
        TLog.w(
          _tag,
          'Server unreachable (${sw.elapsedMilliseconds}ms), keeping local',
        );
        return;
      }

      if (remote.isEmpty) {
        TLog.i(
          _tag,
          'Server empty (${sw.elapsedMilliseconds}ms), seeding with local',
        );
        _pushAllToServer();
        return;
      }

      // Skip any keys that the user changed while fetch was in-flight
      final safeRemote = Map<String, String>.from(remote);
      for (final key in _pendingPush.keys) {
        safeRemote.remove(key);
      }

      final theme = safeRemote[_PK.theme] ?? state.theme;
      final deepModel = safeRemote[_PK.deepModel] ?? state.deepModel;
      final liteModel = safeRemote[_PK.liteModel] ?? state.liteModel;
      final xgrokEnabled = safeRemote.containsKey(_PK.xgrokEnabled)
          ? safeRemote[_PK.xgrokEnabled] == 'true'
          : state.xgrokEnabled;
      final xgrokLiteModel =
          safeRemote[_PK.xgrokLiteModel] ?? state.xgrokLiteModel;
      final xgrokDeepModel =
          safeRemote[_PK.xgrokDeepModel] ?? state.xgrokDeepModel;
      final xgrokThinkingModel =
          safeRemote[_PK.xgrokThinkingModel] ?? state.xgrokThinkingModel;
      final summarizeOverride =
          safeRemote[_PK.summarizeOverride] ?? state.summarizeOverride;
      final defaultFollowUp =
          safeRemote[_PK.defaultFollowUp] ?? state.defaultFollowUpProvider;
      final onlineSearch =
          safeRemote[_PK.onlineSearch] ?? state.onlineSearchProvider;

      List<Bank> banks = state.banks;
      if (safeRemote.containsKey(_PK.banks)) {
        banks = _decodeBanksJson(safeRemote[_PK.banks]!) ?? state.banks;
      }

      state = state.copyWith(
        theme: theme,
        banks: banks,
        deepModel: deepModel,
        liteModel: liteModel,
        xgrokEnabled: xgrokEnabled,
        xgrokLiteModel: xgrokLiteModel,
        xgrokDeepModel: xgrokDeepModel,
        xgrokThinkingModel: xgrokThinkingModel,
        summarizeOverride: summarizeOverride,
        defaultFollowUpProvider: defaultFollowUp,
        onlineSearchProvider: onlineSearch,
      );

      _persistAllToPrefs();

      // Seed any local-only keys that the server doesn't have yet
      final localOnly = _buildFullSnapshot();
      localOnly.removeWhere((k, _) => remote.containsKey(k));
      if (localOnly.isNotEmpty) {
        TLog.d(_tag, 'Seeding ${localOnly.length} local-only keys to server');
        unawaited(_remote.pushBatch(localOnly));
      }

      TLog.i(
        _tag,
        'Synced from server ✓ ${remote.length} keys '
            '(xgrok=${state.xgrokEnabled}) (${sw.elapsedMilliseconds}ms)',
      );
    } catch (e) {
      sw.stop();
      TLog.e(
        _tag,
        'Server sync failed (${sw.elapsedMilliseconds}ms)',
        error: e,
      );
    } finally {
      _syncing = false;
      _lastSyncAt = DateTime.now();
    }
  }

  // ── Setters (local + queue push) ───────────────────────────────────────

  void setTheme(String theme) {
    state = state.copyWith(theme: theme);
    _prefs.setString(_PK.theme, theme);
    _queuePush(_PK.theme, theme);
  }

  void toggleTheme() {
    setTheme(state.isDark ? 'white' : 'dark');
  }

  void setDeepModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(deepModel: trimmed);
    _prefs.setString(_PK.deepModel, trimmed);
    _queuePush(_PK.deepModel, trimmed);
  }

  void setLiteModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(liteModel: trimmed);
    _prefs.setString(_PK.liteModel, trimmed);
    _queuePush(_PK.liteModel, trimmed);
  }

  void setXGrokEnabled(bool enabled) {
    state = state.copyWith(xgrokEnabled: enabled);
    _prefs.setBool(_PK.xgrokEnabled, enabled);
    _queuePush(_PK.xgrokEnabled, enabled.toString());
  }

  void setXGrokLiteModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(xgrokLiteModel: trimmed);
    _prefs.setString(_PK.xgrokLiteModel, trimmed);
    _queuePush(_PK.xgrokLiteModel, trimmed);
  }

  void setXGrokDeepModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(xgrokDeepModel: trimmed);
    _prefs.setString(_PK.xgrokDeepModel, trimmed);
    _queuePush(_PK.xgrokDeepModel, trimmed);
  }

  void setXGrokThinkingModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(xgrokThinkingModel: trimmed);
    _prefs.setString(_PK.xgrokThinkingModel, trimmed);
    _queuePush(_PK.xgrokThinkingModel, trimmed);
  }

  void setSummarizeOverride(String provider) {
    state = state.copyWith(summarizeOverride: provider);
    _prefs.setString(_PK.summarizeOverride, provider);
    _queuePush(_PK.summarizeOverride, provider);
  }

  void setDefaultFollowUpProvider(String provider) {
    state = state.copyWith(defaultFollowUpProvider: provider);
    _prefs.setString(_PK.defaultFollowUp, provider);
    _queuePush(_PK.defaultFollowUp, provider);
  }

  void setOnlineSearchProvider(String provider) {
    state = state.copyWith(onlineSearchProvider: provider);
    _prefs.setString(_PK.onlineSearch, provider);
    _queuePush(_PK.onlineSearch, provider);
  }

  void openSettings() {
    state = state.copyWith(settingsOpen: true);
  }

  void closeSettings() {
    state = state.copyWith(settingsOpen: false);
  }

  /// Adds a new bank card. [cardType] is one of [kBankCardTypes]; [statementDay]
  /// and [dueDay] (1-31) are only meaningful for credit cards and are dropped
  /// otherwise. [color] defaults to the next palette swatch when omitted.
  void addBank(
    String name, {
    String cardType = kCardTypeDebit,
    int? statementDay,
    int? dueDay,
    String? color,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final type = kBankCardTypes.contains(cardType) ? cardType : kCardTypeDebit;
    final isCc = type == kCardTypeCredit;
    final hexColor = color ?? _nextBankColor();
    final bank = Bank(
      id: 'b${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed,
      color: hexColor,
      cardType: type,
      statementDay: isCc ? _clampDay(statementDay) : null,
      dueDay: isCc ? _clampDay(dueDay) : null,
    );
    state = state.copyWith(banks: [...state.banks, bank]);
    _saveBanks();
  }

  /// Updates an existing bank card in place (matched by [id]). Only non-null
  /// fields are changed. Switching [cardType] away from CC clears the billing
  /// cycle; switching to CC keeps/sets the provided days.
  void updateBank(
    String id, {
    String? name,
    String? cardType,
    int? statementDay,
    int? dueDay,
    String? color,
  }) {
    final type = cardType != null && kBankCardTypes.contains(cardType)
        ? cardType
        : null;
    state = state.copyWith(
      banks: state.banks.map((b) {
        if (b.id != id) return b;
        final resolvedType = type ?? b.cardType;
        final isCc = resolvedType == kCardTypeCredit;
        return b.copyWith(
          name: name?.trim().isNotEmpty == true ? name!.trim() : null,
          color: color,
          cardType: type,
          clearBillingCycle: !isCc,
          statementDay: isCc ? (_clampDay(statementDay) ?? b.statementDay) : null,
          dueDay: isCc ? (_clampDay(dueDay) ?? b.dueDay) : null,
        );
      }).toList(),
    );
    _saveBanks();
  }

  void deleteBank(String id) {
    state = state.copyWith(
      banks: state.banks.where((b) => b.id != id).toList(),
    );
    _saveBanks();
  }

  String _nextBankColor() {
    final colorIndex = state.banks.length % AppColors.bankPalette.length;
    final color = AppColors.bankPalette[colorIndex];
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  static int? _clampDay(int? day) {
    if (day == null) return null;
    return day.clamp(1, 31);
  }

  // ── Push queue (debounced batch + persistent outbox) ───────────────────
  //
  // The outbox is a JSON blob in SharedPreferences that mirrors `_pendingPush`.
  // It survives app kills and process death, so a setting the user changed
  // while offline is never lost — it gets retried on the next launch and on
  // every app resume (via [resyncFromServer]). The single inflight guard
  // (`_flushing`) prevents duplicate concurrent pushes.

  void _queuePush(String key, String value) {
    _pendingPush[key] = value;
    _persistOutbox();
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDebounce, () => unawaited(_flushPush(reason: 'debounced')));
  }

  Future<void> _flushPush({String reason = 'manual'}) async {
    if (_pendingPush.isEmpty) return;
    if (_flushing) {
      TLog.d(_tag, 'flush skipped — already in flight (reason=$reason)');
      return;
    }
    _flushing = true;
    final batch = Map<String, String>.from(_pendingPush);
    final sw = Stopwatch()..start();
    try {
      final ok = await _remote.pushBatch(batch);
      sw.stop();
      if (ok) {
        // Only clear keys that haven't been touched while the push was in
        // flight — otherwise the user's most recent edit would be silently
        // dropped from the outbox before being delivered.
        for (final entry in batch.entries) {
          if (_pendingPush[entry.key] == entry.value) {
            _pendingPush.remove(entry.key);
          }
        }
        _persistOutbox();
        TLog.i(_tag,
            'flush ✓ ${batch.length} keys (${sw.elapsedMilliseconds}ms, reason=$reason)');
      } else {
        TLog.w(_tag,
            'flush FAILED ${batch.length} keys (${sw.elapsedMilliseconds}ms, reason=$reason) — '
            'kept in outbox, will retry on resume/restart');
      }
    } catch (e) {
      sw.stop();
      TLog.e(_tag,
          'flush threw (${sw.elapsedMilliseconds}ms, reason=$reason) — kept in outbox',
          error: e);
    } finally {
      _flushing = false;
    }
  }

  void _pushAllToServer() {
    unawaited(_remote.pushBatch(_buildFullSnapshot()));
  }

  // ── Outbox persistence (survives app kills) ────────────────────────────

  void _loadOutbox() {
    final raw = _prefs.getString(_PK.outbox);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final v = entry.value;
          if (v is String) _pendingPush[entry.key.toString()] = v;
        }
        if (_pendingPush.isNotEmpty) {
          TLog.i(_tag,
              'Restored outbox with ${_pendingPush.length} unsynced keys '
              '[${_pendingPush.keys.join(', ')}]');
        }
      }
    } catch (e) {
      TLog.w(_tag, 'Outbox restore failed — clearing corrupted blob', error: e);
      _prefs.remove(_PK.outbox);
    }
  }

  void _persistOutbox() {
    if (_pendingPush.isEmpty) {
      _prefs.remove(_PK.outbox);
    } else {
      _prefs.setString(_PK.outbox, jsonEncode(_pendingPush));
    }
  }

  /// Public hook so the app shell can drain the outbox on resume / network
  /// recovery, even if no setter has been called recently.
  void retryPendingPushes() {
    if (_pendingPush.isEmpty) return;
    unawaited(_flushPush(reason: 'resume'));
  }

  // ── Persistence helpers ────────────────────────────────────────────────

  void _saveBanks() {
    final json = _encodeBanksJson(state.banks);
    _prefs.setString(_PK.banksJson, json);
    // Retire the legacy lossy StringList so a future read can't resurrect it.
    _prefs.remove(_PK.banks);
    _queuePush(_PK.banks, json);
  }

  /// Reads banks from local prefs, preferring the new JSON store and falling
  /// back to the legacy `id|name|color` StringList for one-time migration.
  /// Returns null only when neither has ever been written (first run).
  List<Bank>? _readBanksFromPrefs() {
    final json = _prefs.getString(_PK.banksJson);
    if (json != null && json.isNotEmpty) {
      final decoded = _decodeBanksJson(json);
      if (decoded != null) return decoded;
    }
    final legacy = _prefs.getStringList(_PK.banks);
    if (legacy != null) {
      return legacy
          .map((b) {
            final parts = b.split('|');
            if (parts.length >= 3) {
              return Bank(id: parts[0], name: parts[1], color: parts[2]);
            }
            return null;
          })
          .whereType<Bank>()
          .toList();
    }
    return null;
  }

  void _persistAllToPrefs() {
    final s = state;
    _prefs.setString(_PK.theme, s.theme);
    _prefs.setString(_PK.deepModel, s.deepModel);
    _prefs.setString(_PK.liteModel, s.liteModel);
    _prefs.setBool(_PK.xgrokEnabled, s.xgrokEnabled);
    _prefs.setString(_PK.xgrokLiteModel, s.xgrokLiteModel);
    _prefs.setString(_PK.xgrokDeepModel, s.xgrokDeepModel);
    _prefs.setString(_PK.xgrokThinkingModel, s.xgrokThinkingModel);
    _prefs.setString(_PK.summarizeOverride, s.summarizeOverride);
    _prefs.setString(_PK.defaultFollowUp, s.defaultFollowUpProvider);
    _prefs.setString(_PK.onlineSearch, s.onlineSearchProvider);
    _prefs.setString(_PK.banksJson, _encodeBanksJson(s.banks));
    _prefs.remove(_PK.banks);
  }

  Map<String, String> _buildFullSnapshot() {
    final s = state;
    return {
      _PK.theme: s.theme,
      _PK.deepModel: s.deepModel,
      _PK.liteModel: s.liteModel,
      _PK.xgrokEnabled: s.xgrokEnabled.toString(),
      _PK.xgrokLiteModel: s.xgrokLiteModel,
      _PK.xgrokDeepModel: s.xgrokDeepModel,
      _PK.xgrokThinkingModel: s.xgrokThinkingModel,
      _PK.summarizeOverride: s.summarizeOverride,
      _PK.defaultFollowUp: s.defaultFollowUpProvider,
      _PK.onlineSearch: s.onlineSearchProvider,
      _PK.banks: _encodeBanksJson(s.banks),
    };
  }

  // ── Banks JSON serialization (for server storage) ──────────────────────

  static String _encodeBanksJson(List<Bank> banks) {
    return jsonEncode(banks.map((b) => b.toJson()).toList());
  }

  static List<Bank>? _decodeBanksJson(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(Bank.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _pushTimer?.cancel();
    if (_pendingPush.isNotEmpty) {
      // Best-effort flush. Keep the outbox intact so the next app session
      // can pick up anything that doesn't make it before the process dies.
      final batch = Map<String, String>.from(_pendingPush);
      _persistOutbox();
      unawaited(_remote.pushBatch(batch));
    }
    super.dispose();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final settingsProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  throw UnimplementedError(
    'settingsProvider must be overridden with SharedPreferences + UserPreferencesService',
  );
});
