import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../notifications/android_status_bar_icon.dart';
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

  /// True while [HoldToSpeakController] (or any caller) is actually using
  /// the microphone. Does **not** start the FGS on its own — recording in
  /// a visible activity does not need one — but if the FGS is already
  /// running for AI work, Android 14+ requires the `microphone` type.
  bool _microphoneInUse = false;

  bool _taskDataListening = false;

  /// Types last passed to [FlutterForegroundTask.startService].
  List<ForegroundServiceTypes> _startedTypes = const [];

  /// Initialises the underlying `flutter_foreground_task` configuration.
  /// Safe to call multiple times — the plugin just re-stores the options.
  void init() {
    initBackgroundForegroundTask();
    _listenForTaskIsolate();
  }

  void _listenForTaskIsolate() {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    if (_taskDataListening) return;
    _taskDataListening = true;
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback(onTaskIsolateData);
    } catch (e, st) {
      TLog.w('BgCoord', 'task-isolate listen failed: $e', error: e, st: st);
    }
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
  ///
  /// [needsMicrophone] is for slots that record while they are held. Do
  /// not set it for post-recording network work (smart-parse, STT upload);
  /// Android 14+ requires the microphone FGS type only while the mic is
  /// actually in use. Live recording uses [setMicrophoneInUse] instead.
  Future<void> acquire(
    String slotId, {
    required String label,
    bool needsMicrophone = false,
  }) async {
    if (!PlatformCapabilities.canUseForegroundTask) return;

    final wasEmpty = _slots.isEmpty;
    final existing = _slots[slotId];
    _slots[slotId] = _Slot(
      label: label,
      since: existing?.since ?? DateTime.now(),
      needsMicrophone: needsMicrophone,
    );

    if (wasEmpty) {
      await _startService();
    } else {
      await _reconcileRunningServiceTypes();
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
      await _reconcileRunningServiceTypes();
      _scheduleNotificationRefresh();
    }
  }

  /// Update the label of an already-acquired slot. No-ops if [slotId] is
  /// not currently held.
  void updateLabel(String slotId, String label) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    final slot = _slots[slotId];
    if (slot == null) return;
    _slots[slotId] = _Slot(
      label: label,
      since: slot.since,
      needsMicrophone: slot.needsMicrophone,
    );
    _scheduleNotificationRefresh();
  }

  /// Tell the coordinator the process is using the microphone right now.
  ///
  /// Does not start a foreground service (that would flash a notification
  /// on every hold-to-speak). If the AI FGS is already running, it is
  /// restarted with `dataSync|microphone` so API 34+ does not kill the
  /// recording. Clearing the flag drops back to `dataSync` only.
  Future<void> setMicrophoneInUse(bool inUse) async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    if (_microphoneInUse == inUse) return;
    _microphoneInUse = inUse;
    if (!_serviceActive) return;
    await _reconcileRunningServiceTypes();
  }

  /// Handles messages from the FGS Dart isolate. [kFgsTimeoutEvent] means
  /// Android 15+ stopped the `dataSync` service (6-hour cap or type
  /// timeout). Slots are dropped so callers do not think the notification
  /// is still up; in-flight HTTP on the main isolate keeps running and
  /// uses its existing error paths.
  @visibleForTesting
  void onTaskIsolateData(Object data) {
    if (data != kFgsTimeoutEvent) return;
    TLog.w(
      'BgCoord',
      'foreground service stopped by OS timeout — work continues without FGS',
    );
    _pendingRefresh?.cancel();
    _pendingRefresh = null;
    _slots.clear();
    _serviceActive = false;
    _startedTypes = const [];
  }

  @visibleForTesting
  bool get debugMicrophoneInUse => _microphoneInUse;

  @visibleForTesting
  bool get debugServiceTypesIncludeMicrophone =>
      _computeTypes().contains(ForegroundServiceTypes.microphone);

  @visibleForTesting
  void debugReset() {
    _pendingRefresh?.cancel();
    _pendingRefresh = null;
    _slots.clear();
    _serviceActive = false;
    _microphoneInUse = false;
    _startedTypes = const [];
  }

  // ── Internals ─────────────────────────────────────────────────────────

  List<ForegroundServiceTypes> _computeTypes() {
    final needMic = _microphoneInUse ||
        _slots.values.any((slot) => slot.needsMicrophone);
    if (needMic) {
      return const [
        ForegroundServiceTypes.dataSync,
        ForegroundServiceTypes.microphone,
      ];
    }
    return const [ForegroundServiceTypes.dataSync];
  }

  bool _sameTypes(
    List<ForegroundServiceTypes> a,
    List<ForegroundServiceTypes> b,
  ) {
    if (a.length != b.length) return false;
    final aVals = a.map((e) => e.rawValue).toSet();
    final bVals = b.map((e) => e.rawValue).toSet();
    return aVals.length == bVals.length && aVals.containsAll(bVals);
  }

  Future<void> _reconcileRunningServiceTypes() async {
    if (!_serviceActive || _slots.isEmpty) return;
    final desired = _computeTypes();
    if (_sameTypes(desired, _startedTypes)) return;
    TLog.d(
      'BgCoord',
      'restarting FGS to apply service types (mic=${desired.contains(ForegroundServiceTypes.microphone)})',
    );
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      TLog.w('BgCoord', 'reconcile stop threw: $e', error: e);
    }
    _serviceActive = false;
    _startedTypes = const [];
    await _startService();
  }

  Future<void> _startService() async {
    if (_serviceActive) return;
    try {
      final already = await FlutterForegroundTask.isRunningService;
      if (already) {
        _serviceActive = true;
        _startedTypes = _computeTypes();
        await _refreshNotificationNow();
        return;
      }
      final body = _buildBody();
      final types = _computeTypes();
      final result = await FlutterForegroundTask.startService(
        serviceTypes: types,
        notificationTitle: _kNotifTitle,
        notificationText: body,
        notificationIcon: const NotificationIcon(
          metaDataName: AndroidStatusBarIcon.manifestMeta,
          backgroundColor: AndroidStatusBarIcon.accent,
        ),
        callback: aiBackgroundStartCallback,
      );
      if (result is ServiceRequestSuccess) {
        _serviceActive = true;
        _startedTypes = types;
        _lastNotifAt = DateTime.now();
        TLog.i(
            'BgCoord', 'foreground service started (${_slots.length} slot(s))');
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
    _startedTypes = const [];
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
        notificationIcon: const NotificationIcon(
          metaDataName: AndroidStatusBarIcon.manifestMeta,
          backgroundColor: AndroidStatusBarIcon.accent,
        ),
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
  const _Slot({
    required this.label,
    required this.since,
    this.needsMicrophone = false,
  });

  final String label;
  final DateTime since;
  final bool needsMicrophone;
}
