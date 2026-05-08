import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../platform/platform_capabilities.dart';
import 'news_summarize_fg_task.dart';
import 'telegram_logger.dart';

/// Centralised owner of the Android foreground service used to keep
/// long-running AI tasks alive while the app is in the background, the
/// screen is off, or the device is locked.
///
/// ## Why
/// Android aggressively throttles backgrounded apps via App Standby / Doze,
/// usually killing in-flight HTTP sockets within 1–3 minutes of the screen
/// going off. The fix is the standard pattern: promote the work to a
/// foreground service (an ongoing notification telling the OS "this is a
/// user-visible job, do not throttle me"). With the service active, the
/// Dio HTTP calls fired from the main isolate keep running normally even
/// when the app is minimised / locked.
///
/// `flutter_foreground_task` only supports a single foreground service per
/// process — so we cannot let each feature start/stop the service
/// independently (a concurrent News-summarize + Search would race each
/// other). This coordinator solves that by tracking *slots*: a feature
/// acquires a slot when it starts work and releases it when done. The
/// service runs whenever ≥ 1 slot is held; it is stopped when the count
/// drops back to zero.
///
/// All public methods are no-ops on platforms that do not support a
/// foreground service (web today, possibly desktop in the future).
class BackgroundTaskCoordinator {
  BackgroundTaskCoordinator._();

  static final BackgroundTaskCoordinator instance =
      BackgroundTaskCoordinator._();

  /// Active slots keyed by stable id. Value is the human-readable label
  /// shown in the foreground notification.
  final Map<String, _Slot> _slots = <String, _Slot>{};

  /// Throttle window for service notification updates. The OS caps
  /// notification refresh frequency anyway; client-side throttling avoids
  /// hammering the binder with stale state when many slots churn in the
  /// same animation frame.
  static const Duration _kNotifThrottle = Duration(milliseconds: 800);

  bool _serviceActive = false;
  DateTime _lastNotifAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Outstanding refresh-after-throttle timer, if any. We coalesce updates
  /// so the latest label is always reflected, even if it arrived during
  /// the throttle window.
  Timer? _pendingRefresh;

  /// Initialises the underlying `flutter_foreground_task` configuration.
  /// Safe to call multiple times — the plugin just re-stores the options.
  void init() {
    initBackgroundForegroundTask();
  }

  /// True while the foreground service is (intended to be) running.
  bool get isServiceActive => _serviceActive;

  /// Number of currently-held slots. Useful for tests / diagnostics.
  int get activeSlotCount => _slots.length;

  /// Register a slot keyed by [slotId]. If this is the first slot, the
  /// foreground service is promoted; otherwise the service notification is
  /// refreshed (throttled) to reflect the new aggregate label.
  ///
  /// Calling [acquire] with an existing [slotId] simply updates the label
  /// — useful for "phase change" updates without releasing.
  Future<void> acquire(
    String slotId, {
    required String label,
  }) async {
    if (!PlatformCapabilities.canUseForegroundTask) return;

    final wasEmpty = _slots.isEmpty;
    final existing = _slots[slotId];
    _slots[slotId] = _Slot(
      label: label,
      since: existing?.since ?? DateTime.now(),
    );

    if (wasEmpty) {
      await _startService();
    } else {
      _scheduleNotificationRefresh();
    }
  }

  /// Release a slot. Last release stops the foreground service.
  Future<void> release(String slotId) async {
    if (!PlatformCapabilities.canUseForegroundTask) return;

    if (_slots.remove(slotId) == null) return;

    if (_slots.isEmpty) {
      await _stopService();
    } else {
      _scheduleNotificationRefresh();
    }
  }

  /// Update the label of an already-acquired slot. No-ops if [slotId] is
  /// not currently held.
  void updateLabel(String slotId, String label) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    final slot = _slots[slotId];
    if (slot == null) return;
    _slots[slotId] = _Slot(label: label, since: slot.since);
    _scheduleNotificationRefresh();
  }

  // ── Internals ─────────────────────────────────────────────────────────

  Future<void> _startService() async {
    if (_serviceActive) return;
    try {
      final already = await FlutterForegroundTask.isRunningService;
      if (already) {
        _serviceActive = true;
        await _refreshNotificationNow();
        return;
      }
      final body = _buildBody();
      final result = await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: _kNotifTitle,
        notificationText: body,
        callback: aiBackgroundStartCallback,
      );
      if (result is ServiceRequestSuccess) {
        _serviceActive = true;
        _lastNotifAt = DateTime.now();
        TLog.i('BgCoord',
            'foreground service started (${_slots.length} slot(s))');
        // Catch-up refresh: if any concurrent acquire/release/updateLabel
        // calls landed during the start-service await, their refresh was
        // skipped because `_serviceActive` was still false. Reflect the
        // current slot state now that the service is up.
        unawaited(_refreshNotificationNow());
      } else if (result is ServiceRequestFailure) {
        TLog.w(
          'BgCoord',
          'foreground service failed to start: ${result.error}',
        );
      }
    } catch (e, st) {
      TLog.w('BgCoord', 'startService threw: $e', error: e, st: st);
    }
  }

  Future<void> _stopService() async {
    if (!_serviceActive) return;
    _serviceActive = false;
    _pendingRefresh?.cancel();
    _pendingRefresh = null;
    try {
      final running = await FlutterForegroundTask.isRunningService;
      // Re-check after the await: if a new slot was acquired during the
      // window, a concurrent _startService is racing with us — leave the
      // service running and restore _serviceActive so it stays consistent.
      if (_slots.isNotEmpty) {
        _serviceActive = true;
        _scheduleNotificationRefresh();
        return;
      }
      if (running) {
        await FlutterForegroundTask.stopService();
        TLog.d('BgCoord', 'foreground service stopped');
      }
    } catch (e) {
      TLog.w('BgCoord', 'stopService threw: $e', error: e);
    }
  }

  /// Schedule a throttled notification refresh. If the throttle window has
  /// already elapsed we refresh immediately; otherwise we coalesce into a
  /// single delayed refresh so rapid-fire label changes don't spam the
  /// notification manager.
  void _scheduleNotificationRefresh() {
    if (!_serviceActive) return;
    final now = DateTime.now();
    final since = now.difference(_lastNotifAt);
    if (since >= _kNotifThrottle) {
      _lastNotifAt = now;
      unawaited(_refreshNotificationNow());
      return;
    }
    _pendingRefresh?.cancel();
    _pendingRefresh = Timer(_kNotifThrottle - since, () {
      _pendingRefresh = null;
      _lastNotifAt = DateTime.now();
      unawaited(_refreshNotificationNow());
    });
  }

  Future<void> _refreshNotificationNow() async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    if (!_serviceActive) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: _kNotifTitle,
        notificationText: _buildBody(),
      );
    } catch (e) {
      // Race with stopService is harmless — an updated body for an
      // already-stopped service simply has nowhere to land.
      TLog.d('BgCoord', 'updateService skipped: $e');
    }
  }

  String _buildBody() {
    if (_slots.isEmpty) return 'Working\u2026';
    if (_slots.length == 1) return _slots.values.first.label;
    // Multiple slots — summarise the count plus the most recent label so
    // the user sees what is currently happening without an exhaustive
    // listing.
    final mostRecent =
        _slots.values.reduce((a, b) => a.since.isAfter(b.since) ? a : b);
    return '${_slots.length} background tasks \u00B7 ${mostRecent.label}';
  }

  static const String _kNotifTitle = '\u2728 Nexus AI working';
}

@immutable
class _Slot {
  const _Slot({required this.label, required this.since});

  final String label;
  final DateTime since;
}
