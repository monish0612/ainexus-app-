import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/services/telegram_logger.dart';
import '../../../../data/services/nas_stats_service.dart';
import '../../../../domain/entities/nas_stats.dart';
import 'live/stat_metric.dart';

const _tag = 'NasStats';

final nasStatsServiceProvider = Provider<NasStatsService>((ref) {
  return NasStatsService(ref.watch(apiClientProvider));
});

/// Everything the Stats screens render from.
@immutable
class NasStatsState {
  const NasStatsState({
    this.envelope = NasStatsEnvelope.unknown,
    this.hasLoaded = false,
    this.isPolling = false,
    this.consecutiveFailures = 0,
    this.transportError,
    this.lastSuccessAt,
    this.phoneOffline,
    this.live = const [],
  });

  final NasStatsEnvelope envelope;

  /// False until the first response of any kind. The screens use this to show a
  /// neutral loading state instead of flashing the "NAS is off" treatment for a
  /// few hundred milliseconds on every open, which would look like a fault.
  final bool hasLoaded;

  final bool isPolling;

  /// Consecutive *transport* failures — the phone could not reach the API. A
  /// NAS that is switched off is a successful response and resets this to 0.
  final int consecutiveFailures;

  /// Set only when the phone cannot reach the API. Distinct from
  /// `envelope.online == false`, which means the NAS is off; conflating the two
  /// would send the owner to the wrong room to fix the wrong thing.
  final String? transportError;

  final DateTime? lastSuccessAt;

  /// Whether the *phone* had no network at the moment the request failed. Null
  /// until a failure has been diagnosed.
  ///
  /// This exists to answer a question the API cannot: the API runs on the VPS,
  /// so if the VPS is stopped there is nothing left to report that it is
  /// stopped. Silence is the only symptom, and silence is also what a phone in
  /// a tunnel produces. Checking the handset's own connectivity separates the
  /// two, which is the difference between "start your server" and "wait for a
  /// signal" — two very different pieces of advice to give someone.
  final bool? phoneOffline;

  /// Rolling 1-second samples for the live sparkline. Trimmed to three minutes
  /// so the detail screen cannot grow without bound if it is left open.
  final List<LiveStatSample> live;

  bool get isOnline => envelope.online;
  NasSnapshot? get snapshot => envelope.snapshot;
  VpsLive? get vps => envelope.vpsLive;

  /// The phone could not reach the API at all.
  bool get vpsUnreachable => transportError != null;

  /// Unreachable *and* the phone demonstrably has a network — so the silence is
  /// at the far end. Still not proof the machine is stopped (the API container
  /// could be down on a running host), which is why the wording it drives says
  /// "not responding" and offers stopped as the likely cause rather than a fact.
  bool get vpsProbablyStopped => vpsUnreachable && phoneOffline == false;

  /// True while showing figures we know are no longer being refreshed. The
  /// screens dim the last known values rather than blanking them, because a
  /// two-second gap in a poll is not worth destroying the whole screen over.
  bool get isReconnecting => consecutiveFailures > 0 && hasLoaded;

  NasStatsState copyWith({
    NasStatsEnvelope? envelope,
    bool? hasLoaded,
    bool? isPolling,
    int? consecutiveFailures,
    Object? transportError = _sentinel,
    DateTime? lastSuccessAt,
    Object? phoneOffline = _sentinel,
    List<LiveStatSample>? live,
  }) {
    return NasStatsState(
      envelope: envelope ?? this.envelope,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      isPolling: isPolling ?? this.isPolling,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      transportError: transportError == _sentinel
          ? this.transportError
          : transportError as String?,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      phoneOffline:
          phoneOffline == _sentinel ? this.phoneOffline : phoneOffline as bool?,
      live: live ?? this.live,
    );
  }

  static const Object _sentinel = Object();
}

/// Polls `/cloud/stats` while a Stats screen is on top, and stops the moment it
/// is not.
///
/// Three rules shape this class, all of them about not being a nuisance:
///
/// 1. **The timer must die with the screen.** It is an `autoDispose` provider
///    and the timer is cancelled in `dispose()`, so navigating back cannot
///    leave a one-second poll running for the rest of the session.
///
/// 2. **Backgrounding stops the poll.** Without the lifecycle observer, putting
///    the phone in a pocket with this screen open would keep asking the VPS —
///    and the NAS behind it — every second, indefinitely, on mobile data.
///
/// 3. **Failures back off, and are announced once.** A dead network at a
///    one-second cadence is sixty requests and sixty Telegram messages a
///    minute. The interval grows to 15 s and only *transitions* are logged.
class NasStatsController extends StateNotifier<NasStatsState>
    with WidgetsBindingObserver {
  NasStatsController(this._service, {NetworkInfo? networkInfo})
      : _network = networkInfo ?? NetworkInfo(),
        super(const NasStatsState()) {
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  final NasStatsService _service;
  final NetworkInfo _network;

  static const Duration pollInterval = Duration(seconds: 1);
  static const Duration maxBackoff = Duration(seconds: 15);

  Timer? _timer;
  CancelToken? _inFlight;
  bool _disposed = false;

  /// Tracks online-ness so Telegram hears about changes, not about every poll.
  /// Null until the first result, so opening the screen while the NAS is off is
  /// not itself reported as the NAS going down.
  bool? _lastReportedOnline;
  bool _reportedTransportFailure = false;

  void start() {
    if (_disposed || state.isPolling) return;
    state = state.copyWith(isPolling: true);
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    // Cancelling the in-flight request matters as much as cancelling the timer:
    // without it, a request issued just before backgrounding would still land.
    _inFlight?.cancel('screen paused');
    _inFlight = null;
    if (!_disposed && state.isPolling) {
      state = state.copyWith(isPolling: false);
    }
  }

  /// Fetch now, resetting the backoff. Used by the retry control on an error
  /// banner and on resume, where the user is watching and expects the meters
  /// to move immediately rather than waiting out a timer.
  Future<void> refreshNow() async {
    _timer?.cancel();
    _timer = null;
    if (!_disposed) state = state.copyWith(consecutiveFailures: 0);
    await _tick();
  }

  Future<void> _tick() async {
    if (_disposed) return;

    // A resume or Retry tap must not leave the previous hop running: two
    // overlapping fetches would fight over state and double the NAS load.
    _inFlight?.cancel('superseded');
    final token = CancelToken();
    _inFlight = token;
    try {
      final envelope = await _service.fetch(cancelToken: token);
      if (_disposed) return;
      _onEnvelope(envelope);
    } on NasStatsUnavailable catch (e) {
      if (_disposed) return;
      if (token.isCancelled) return;
      _onTransportFailure(e);
    } catch (e, st) {
      if (_disposed) return;
      if (token.isCancelled) return;
      // Never let an unexpected parse bug end the poll loop: the screen would
      // freeze on stale figures with no indication it had stopped updating.
      TLog.e(_tag, 'Unexpected failure while polling', error: e, st: st);
      _onTransportFailure(const NasStatsUnavailable(
        'Something went wrong loading live stats.',
      ));
    } finally {
      if (identical(_inFlight, token)) _inFlight = null;
    }

    if (_disposed || token.isCancelled) return;
    _scheduleNext();
  }

  void _onEnvelope(NasStatsEnvelope envelope) {
    // A reply of any kind means the transport is healthy — including a reply
    // that says the NAS is off, which is a successful answer to the question.
    if (_reportedTransportFailure) {
      TLog.i(_tag, 'Reconnected to the stats server');
      _reportedTransportFailure = false;
    }

    state = state.copyWith(
      envelope: envelope,
      hasLoaded: true,
      consecutiveFailures: 0,
      transportError: null,
      lastSuccessAt: DateTime.now(),
      phoneOffline: null,
      live: appendLiveSample(
        state.live,
        LiveStatSample.fromEnvelope(envelope, _sampleTime(envelope)),
      ),
    );

    _reportOnlineTransition(envelope);
  }

  void _reportOnlineTransition(NasStatsEnvelope envelope) {
    final online = envelope.online;
    final previous = _lastReportedOnline;
    if (previous == online) return;
    _lastReportedOnline = online;
    // The first result is the starting position, not a change. Without this a
    // NAS that is simply switched off would announce itself every time the
    // screen was opened.
    if (previous == null) return;

    if (online) {
      TLog.i(_tag, 'NAS is back online');
      return;
    }
    final reason = envelope.reason ?? NasOfflineReason.unknown;
    if (reason == NasOfflineReason.auth) {
      // A configuration fault rather than an outage, and the only one here the
      // owner has to act on, so it is the only one raised as an error.
      TLog.e(_tag, 'NAS rejected the server\'s status token (auth)');
    } else {
      TLog.w(_tag, 'NAS went offline (${reason.name})');
    }
  }

  void _onTransportFailure(NasStatsUnavailable e) {
    final failures = state.consecutiveFailures + 1;
    state = state.copyWith(
      consecutiveFailures: failures,
      hasLoaded: true,
      transportError: e.message,
    );

    // Once per outage, not once per poll. At a 1-second cadence the alternative
    // is sixty messages a minute into a channel that also carries real alarms.
    if (!_reportedTransportFailure) {
      _reportedTransportFailure = true;
      TLog.w(_tag, 'Cannot reach the stats server: ${e.message}');
    }

    // Asked only on the first failure of a run. The answer decides which of two
    // opposite sentences the VPS screen shows, and re-asking it every two
    // seconds for the duration of an outage would be a platform channel call
    // per poll to learn something that does not change that fast.
    if (failures == 1) unawaited(_diagnosePhoneNetwork());
  }

  Future<void> _diagnosePhoneNetwork() async {
    try {
      final connected = await _network.isConnected;
      if (_disposed) return;
      // Discarded if a poll succeeded while this was in flight: by then the
      // question is moot and writing the answer would resurrect a stale
      // diagnosis onto a working screen.
      if (state.transportError == null) return;
      state = state.copyWith(phoneOffline: !connected);
    } catch (_) {
      // Unknown is a real answer here, and better than a wrong one. The screen
      // falls back to naming both possible causes.
      if (!_disposed && state.transportError != null) {
        state = state.copyWith(phoneOffline: null);
      }
    }
  }

  /// 1s, 2s, 4s, 8s, then 15s. Doubling keeps a healthy screen at full speed while
  /// making a dead network cost a request every 15 seconds rather than 3,600 an
  /// hour. Pure and static so the arithmetic can be tested without a live
  /// notifier and a real clock.
  static Duration backoffFor(int consecutiveFailures) {
    if (consecutiveFailures <= 0) return pollInterval;
    // Shift is capped before it is taken: 1 << 40 would overflow into nonsense
    // long before the cap ever applied.
    final steps = consecutiveFailures > 8 ? 8 : consecutiveFailures - 1;
    final ms = pollInterval.inMilliseconds * (1 << steps);
    return ms >= maxBackoff.inMilliseconds
        ? maxBackoff
        : Duration(milliseconds: ms);
  }

  /// Prefer the envelope's own clock so a cached reply in the same second
  /// replaces the last sparkline point instead of plotting a twin.
  static DateTime _sampleTime(NasStatsEnvelope envelope) {
    final at = envelope.at;
    if (at == null) return DateTime.now();
    return DateTime.fromMillisecondsSinceEpoch(at * 1000, isUtc: true).toLocal();
  }

  Duration get nextDelay => backoffFor(state.consecutiveFailures);

  void _scheduleNext() {
    if (_disposed || !state.isPolling) return;
    _timer?.cancel();
    _timer = Timer(nextDelay, _tick);
  }

  // Named `lifecycle` rather than the inherited `state`, which would shadow
  // StateNotifier.state inside this method and silently break every read and
  // assignment in the body.
  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (_disposed) return;
    switch (lifecycle) {
      // `inactive` is deliberately not paused. Android fires it for the
      // notification shade, an incoming-call banner, and a brief blip every
      // time this route is pushed — none of which should freeze the meters
      // or cancel the in-flight sample the user is watching.
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        stop();
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.resumed:
        if (!state.isPolling) {
          state = state.copyWith(isPolling: true);
          // Straight to a fetch rather than waiting out a timer: the screen is
          // in front of the user again and stale figures are the first thing
          // they would see.
          unawaited(refreshNow());
        }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// `autoDispose` is doing real work here, not decoration: it is what guarantees
/// the one-second timer cannot outlive the screen that started it.
final nasStatsControllerProvider =
    StateNotifierProvider.autoDispose<NasStatsController, NasStatsState>((ref) {
  return NasStatsController(
    ref.watch(nasStatsServiceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  );
});
