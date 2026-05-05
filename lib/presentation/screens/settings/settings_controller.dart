import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/user_preferences_service.dart';

// ── Data models ──────────────────────────────────────────────────────────────

@immutable
class Bank {
  const Bank({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final String color;

  Bank copyWith({String? id, String? name, String? color}) {
    return Bank(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
        id: json['id'] as String,
        name: json['name'] as String,
        color: json['color'] as String,
      );
}

// ── Defaults ─────────────────────────────────────────────────────────────────

const kDefaultDeepModel = 'gemini-3.1-pro-preview';
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
  static const xgrokEnabled = 'xgrok_enabled';
  static const xgrokLiteModel = 'xgrok_lite_model';
  static const xgrokDeepModel = 'xgrok_deep_model';
  static const xgrokThinkingModel = 'xgrok_thinking_model';
  static const summarizeOverride = 'summarize_override';
  static const defaultFollowUp = 'default_followup_provider';
  static const onlineSearch = 'online_search_provider';
  static const banks = 'app_banks';
}

// ── Default banks ────────────────────────────────────────────────────────────

const _defaultBanks = <Bank>[
  Bank(id: 'b1', name: 'HDFC Bank', color: '#0D59F2'),
  Bank(id: 'b2', name: 'SBI', color: '#059669'),
  Bank(id: 'b3', name: 'ICICI Bank', color: '#DC2626'),
  Bank(id: 'b4', name: 'Axis Bank', color: '#7C3AED'),
  Bank(id: 'b5', name: 'Kotak Mahindra', color: '#D97706'),
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
    unawaited(_syncFromServer());
  }

  final SharedPreferences _prefs;
  final UserPreferencesService _remote;

  static const _tag = 'Settings';
  static const _pushDebounce = Duration(milliseconds: 600);
  static const _syncCooldown = Duration(seconds: 15);

  final Map<String, String> _pendingPush = {};
  Timer? _pushTimer;
  bool _syncing = false;
  DateTime? _lastSyncAt;

  // ── Phase 1: instant local hydration ───────────────────────────────────

  void _hydrateFromPrefs() {
    final theme = _prefs.getString(_PK.theme) ?? 'dark';
    final deepModel = _prefs.getString(_PK.deepModel) ?? kDefaultDeepModel;
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

    final banksRaw = _prefs.getStringList(_PK.banks);
    List<Bank> banks;
    if (banksRaw != null) {
      banks = banksRaw.map((b) {
        final parts = b.split('|');
        if (parts.length == 3) {
          return Bank(id: parts[0], name: parts[1], color: parts[2]);
        }
        return null;
      }).whereType<Bank>().toList();
    } else {
      banks = _defaultBanks;
    }

    state = SettingsState(
      theme: theme,
      banks: banks,
      deepModel: deepModel,
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
  void resyncFromServer() {
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

  void addBank(String name) {
    if (name.trim().isEmpty) return;
    final colorIndex = state.banks.length % AppColors.bankPalette.length;
    final color = AppColors.bankPalette[colorIndex];
    final hexColor =
        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    final bank = Bank(
      id: 'b${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      color: hexColor,
    );
    state = state.copyWith(banks: [...state.banks, bank]);
    _saveBanks();
  }

  void deleteBank(String id) {
    state = state.copyWith(
      banks: state.banks.where((b) => b.id != id).toList(),
    );
    _saveBanks();
  }

  // ── Push queue (debounced batch) ───────────────────────────────────────

  void _queuePush(String key, String value) {
    _pendingPush[key] = value;
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDebounce, () => unawaited(_flushPush()));
  }

  Future<void> _flushPush() async {
    if (_pendingPush.isEmpty) return;
    final batch = Map<String, String>.from(_pendingPush);
    _pendingPush.clear();
    await _remote.pushBatch(batch);
  }

  void _pushAllToServer() {
    unawaited(_remote.pushBatch(_buildFullSnapshot()));
  }

  // ── Persistence helpers ────────────────────────────────────────────────

  void _saveBanks() {
    _prefs.setStringList(
      _PK.banks,
      state.banks.map((b) => '${b.id}|${b.name}|${b.color}').toList(),
    );
    _queuePush(_PK.banks, _encodeBanksJson(state.banks));
  }

  void _persistAllToPrefs() {
    final s = state;
    _prefs.setString(_PK.theme, s.theme);
    _prefs.setString(_PK.deepModel, s.deepModel);
    _prefs.setBool(_PK.xgrokEnabled, s.xgrokEnabled);
    _prefs.setString(_PK.xgrokLiteModel, s.xgrokLiteModel);
    _prefs.setString(_PK.xgrokDeepModel, s.xgrokDeepModel);
    _prefs.setString(_PK.xgrokThinkingModel, s.xgrokThinkingModel);
    _prefs.setString(_PK.summarizeOverride, s.summarizeOverride);
    _prefs.setString(_PK.defaultFollowUp, s.defaultFollowUpProvider);
    _prefs.setString(_PK.onlineSearch, s.onlineSearchProvider);
    _prefs.setStringList(
      _PK.banks,
      s.banks.map((b) => '${b.id}|${b.name}|${b.color}').toList(),
    );
  }

  Map<String, String> _buildFullSnapshot() {
    final s = state;
    return {
      _PK.theme: s.theme,
      _PK.deepModel: s.deepModel,
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
      final batch = Map<String, String>.from(_pendingPush);
      _pendingPush.clear();
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
