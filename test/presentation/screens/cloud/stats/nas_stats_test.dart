// Tests for the Cloud > Stats dashboard.
//
// The behaviour worth locking down here is not "does it draw a gauge" — it is
// the set of promises the screen makes about honesty:
//
//   • when the NAS is off, everything is zeroed, greyed and untappable;
//   • an unknown reading shows an em dash, never a zero;
//   • a partially-null snapshot still renders the sections that arrived;
//   • the VPS screen stays live when the NAS is off, because the VPS is the
//     machine answering the request;
//   • the 1-second timer dies with the screen and backs off on failure;
//   • nothing overflows at 320 px.
//
// The service is faked at the ProviderScope boundary, so no test touches Dio or
// the network.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/network/network_info.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/nas_stats_service.dart';
import 'package:ai_nexus/domain/entities/nas_stats.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/live/history_range_switch.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/live/stat_detail_screen.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/live/stat_metric.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/nas_stats_controller.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/nas_stats_screen.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/vps_stats_screen.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/widgets/fluid_gauge.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/widgets/stats_chrome.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/widgets/stats_launcher.dart';

ThemeData _testTheme({bool white = false}) {
  final palette = white ? AppColors.white : AppColors.dark;
  return ThemeData(
    brightness: palette.isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: palette.bg,
    extensions: <ThemeExtension<dynamic>>[palette],
  );
}

// ── a fake service ──────────────────────────────────────────────────────────

/// Returns whatever it is told to, and counts calls so the polling behaviour
/// can be asserted on rather than assumed.
///
/// The real [ApiClient] handed to `super` is never touched, because every code
/// path that would use it is overridden here — so no test opens a socket.
class _FakeStatsService extends NasStatsService {
  _FakeStatsService(this._next) : super(ApiClient());

  final NasStatsEnvelope Function(int call) _next;
  Object? throwThis;
  StatsHistoryEnvelope Function(StatsHistoryRange range, StatMetric metric)?
      history;
  int calls = 0;
  int historyCalls = 0;

  @override
  Future<NasStatsEnvelope> fetch({CancelToken? cancelToken}) async {
    calls += 1;
    final err = throwThis;
    if (err != null) throw err;
    return _next(calls);
  }

  @override
  Future<StatsHistoryEnvelope> fetchHistory(
    StatsHistoryRange range, {
    required StatMetric metric,
    CancelToken? cancelToken,
  }) async {
    historyCalls += 1;
    final h = history;
    if (h != null) return h(range, metric);
    return StatsHistoryEnvelope.empty(range);
  }
}

/// Stands in for the handset's own connectivity.
///
/// This is what lets the VPS screen tell "the machine is stopped" apart from
/// "this phone is in a lift" — the API cannot answer that, because it is running
/// on the machine in question. Faked rather than mocked at the platform channel
/// so the two opposite messages can both be asserted.
class _FakeNetworkInfo extends NetworkInfo {
  _FakeNetworkInfo(this._connected);

  final bool? _connected;

  @override
  Future<bool> get isConnected async {
    final c = _connected;
    if (c == null) throw StateError('connectivity unavailable');
    return c;
  }
}

// ── fixtures ────────────────────────────────────────────────────────────────

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// The live account's real shape: an auto-renewing VPS whose date lives in
/// `next_billing_at`, alongside a non-renewing domain whose date lives in
/// `expires_at`. Getting these two the same way round is the whole point.
Map<String, dynamic> _billingJson({
  String dueKind = 'renews',
  String dueAt = '2026-09-18T03:37:38Z',
  int daysLeft = 29,
  bool autoRenew = true,
  String status = 'active',
  bool fromCache = false,
  String? error,
  bool withDomain = true,
}) {
  return <String, dynamic>{
    'at': _now() - 600,
    'error': error,
    'age_s': 600,
    'from_cache': fromCache,
    'vps': {
      'name': 'KVM 2',
      'status': status,
      'auto_renew': autoRenew,
      'due_at': dueAt,
      'due_kind': dueKind,
      'days_left': daysLeft,
      'period': 1,
      'period_unit': 'month',
      'renewal_price': 209900,
      'currency': 'INR',
    },
    'others': withDomain
        ? [
            {
              'name': '.COM Domain',
              'status': 'non_renewing',
              'auto_renew': false,
              'due_at': '2029-06-27T09:31:38Z',
              'due_kind': 'expires',
              'days_left': 1043,
              'period': 3,
              'period_unit': 'year',
              'renewal_price': 454934,
              'currency': 'INR',
            }
          ]
        : <Map<String, dynamic>>[],
  };
}

Map<String, dynamic> _snapshotJson({
  Object? disks = _keep,
  Object? playback = _keep,
  Object? services = _keep,
  Object? memory = _keep,
  Object? snapshots = _keep,
}) {
  return <String, dynamic>{
    'api': 1,
    'at': _now(),
    'host': 'truenas',
    'version': '25.04.2.6',
    'uptime_s': 141353,
    'cpu': {'cores': 4, 'pct': 12.5, 'load1': 0.4, 'load5': 0.3, 'load15': 0.2},
    'memory': memory == _keep
        ? {
            'total_mb': 7363,
            'available_mb': 2430,
            'free_mb': 1814,
            'arc_mb': 1491,
            'arc_cap_mb': 1536,
            'pressure': 'ok',
          }
        : memory,
    'pools': [
      {
        'name': 'Storage',
        'health': 'ONLINE',
        'size_bytes': 493921239040,
        'used_bytes': 183078453248,
        'free_bytes': 310842785792,
        'used_pct': 37,
        'role': 'main',
      },
      {
        'name': 'Backup',
        'health': 'ONLINE',
        'size_bytes': 996432412672,
        'used_bytes': 172655915008,
        'free_bytes': 823776497664,
        'used_pct': 17,
        'role': 'backup_usb',
      },
    ],
    'movies': {
      'dataset': 'Storage/media',
      'path': '/mnt/Storage/media',
      'used_bytes': 156145664000,
      'avail_bytes': 295543554048,
      'refer_bytes': 86350766080,
      'headline_free_gb': 275,
      'note': 'Deleting a film does not free this number for 14 days.',
    },
    'snapshots': snapshots == _keep
        ? {'count_storage': 325, 'held_bytes': 60786593792}
        : snapshots,
    'disks': disks == _keep
        ? [
            {'name': 'sda', 'role': 'Storage', 'temp_c': 42, 'ok': true},
            {'name': 'sdb', 'role': 'Backup', 'temp_c': 34, 'ok': true},
            {'name': 'nvme0n1', 'role': 'boot', 'temp_c': 56, 'ok': true},
          ]
        : disks,
    'services': services == _keep
        ? {
            'jellyfin': true,
            'nextcloud': true,
            'caddy': true,
            'smb': true,
            'media_watch': true,
            'livetv': 'off_by_choice',
          }
        : services,
    'playback': playback == _keep ? {'count': 0, 'items': []} : playback,
    'vps': {
      'state': 'running',
      'state_from': 'probe',
      'reachable': true,
      'steal_pct': 3.9,
      'age_s': 120,
    },
    'health': {'stages_ok': 16, 'stages_total': 16, 'failing': []},
  };
}

const Object _keep = Object();

Map<String, dynamic> _vpsLiveJson({
  bool throttled = false,
  double steal = 3.9,
  int? age = 120,
  bool nasOff = false,
  Map<String, dynamic>? billing,
}) {
  return <String, dynamic>{
    'cpu_pct': 9.2,
    'cores': 2,
    'load1': 0.69,
    'load5': 0.47,
    'load15': 0.46,
    'mem_pct': 27.3,
    'mem_total_gb': 7.8,
    'mem_free_gb': 5.6,
    'disk_pct': 11.0,
    'disk_total_gb': 96.7,
    'disk_free_gb': 85.4,
    'uptime_s': 90000,
    'state': nasOff ? null : 'running',
    'state_from': nasOff ? null : 'probe',
    'steal_pct': nasOff ? null : steal,
    'throttled': nasOff ? null : throttled,
    'conditions': <String>[],
    'containers': nasOff ? null : 13,
    'running': nasOff ? null : 13,
    'vps_age_s': nasOff ? null : age,
    'vps_stale': nasOff ? null : (age != null && age > 900),
    'plan_name': nasOff ? null : 'KVM 2',
    'vcpus': nasOff ? null : 2,
    'plan_ram_mb': nasOff ? null : 8192,
    'plan_disk_mb': nasOff ? null : 102400,
    'hostname': nasOff ? null : 'srv1499325',
    'billing': billing,
  };
}

NasStatsEnvelope _online({Map<String, dynamic>? snapshot}) =>
    NasStatsEnvelope.fromJson({
      'online': true,
      'reason': null,
      'at': _now(),
      'age_s': 1,
      'last_seen_at': _now(),
      'snapshot': snapshot ?? _snapshotJson(),
      'vps_live': _vpsLiveJson(),
    });

NasStatsEnvelope _offline({String reason = 'unreachable'}) =>
    NasStatsEnvelope.fromJson({
      'online': false,
      'reason': reason,
      'at': _now(),
      'age_s': null,
      'last_seen_at': _now() - 400,
      'snapshot': null,
      'vps_live': _vpsLiveJson(nasOff: true),
    });

// ── harness ─────────────────────────────────────────────────────────────────

Future<_FakeStatsService> _pump(
  WidgetTester tester,
  Widget screen, {
  required NasStatsEnvelope Function(int call) responses,
  Object? throwThis,
  StatsHistoryEnvelope Function(StatsHistoryRange range, StatMetric metric)?
      history,
  Size size = const Size(320, 2400),
  double textScale = 1.0,
  bool white = false,
  bool? phoneConnected = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final fake = _FakeStatsService(responses)
    ..throwThis = throwThis
    ..history = history;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nasStatsServiceProvider.overrideWithValue(fake),
        // Always overridden, even on the happy paths: the real one would reach
        // for a platform channel that does not exist under flutter test.
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo(phoneConnected)),
      ],
      child: MaterialApp(
        theme: _testTheme(white: white),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          );
        },
        home: screen,
      ),
    ),
  );
  // One frame for the first fetch to resolve, then a slice of the 700 ms gauge
  // tween. Deliberately not pumpAndSettle: the live pulse repeats for ever and
  // would never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  return fake;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NasStatsScreen online', () {
    testWidgets('renders the headline free space and the pools', (t) async {
      await _pump(t, const NasStatsScreen(), responses: (_) => _online());

      expect(find.text('275'), findsOneWidget);
      expect(find.text('GB'), findsOneWidget);
      expect(find.textContaining('Storage 37% used'), findsOneWidget);
      expect(find.textContaining('USB backup 17% used'), findsOneWidget);
      expectNoOverflow();
    });

    testWidgets('shows the 14-day snapshot note, which stops the free-space '
        'figure looking wrong after a delete', (t) async {
      await _pump(t, const NasStatsScreen(), responses: (_) => _online());

      expect(
        find.textContaining('does not free space for 14 days'),
        findsOneWidget,
      );
      expect(find.textContaining('56.6 GB'), findsOneWidget);
    });

    testWidgets('draws CPU and RAM gauges with real values', (t) async {
      await _pump(t, const NasStatsScreen(), responses: (_) => _online());

      final gauges = t.widgetList<FluidGauge>(find.byType(FluidGauge)).toList();
      expect(gauges.length, 2);
      expect(gauges[0].label, 'CPU');
      expect(gauges[0].value, 12.5);
      expect(gauges[1].label, 'RAM');
      // 7363 total, 2430 available → 67% used, from MemAvailable not MemFree.
      expect(gauges[1].value, closeTo(67.0, 0.5));
    });

    testWidgets('labels Live TV as off by choice, never as a fault', (t) async {
      await _pump(t, const NasStatsScreen(), responses: (_) => _online());
      expect(find.text('Live TV off by choice'), findsOneWidget);
    });

    testWidgets('is not shrouded and not ignoring pointers', (t) async {
      await _pump(t, const NasStatsScreen(), responses: (_) => _online());

      final shroud = t.widget<StatsOfflineShroud>(
        find.byType(StatsOfflineShroud),
      );
      expect(shroud.offline, isFalse);
      expect(find.byType(ColorFiltered), findsNothing);
    });
  });

  group('NasStatsScreen offline', () {
    testWidgets('greys out, zeroes the gauges and blocks interaction',
        (t) async {
      await _pump(t, const NasStatsScreen(), responses: (_) => _offline());

      expect(find.text('Your NAS is off'), findsOneWidget);
      expect(
        find.textContaining('switched off or off the network'),
        findsOneWidget,
      );

      final shroud = t.widget<StatsOfflineShroud>(
        find.byType(StatsOfflineShroud),
      );
      expect(shroud.offline, isTrue);

      // The three halves of the dull state, each asserted separately because
      // any one of them silently regressing would leave a live-looking screen.
      expect(find.byType(ColorFiltered), findsWidgets);
      // The outermost IgnorePointer under the shroud is the shroud's own; the
      // tree has several others (IconButton, the scroll view) that say nothing
      // about whether the dashboard is inert.
      final ignore = t.widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(StatsOfflineShroud),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isTrue);

      for (final g in t.widgetList<FluidGauge>(find.byType(FluidGauge))) {
        expect(g.value, 0, reason: '${g.label} must read zero when off');
      }
    });

    testWidgets('says when it last saw the NAS instead of implying never',
        (t) async {
      await _pump(t, const NasStatsScreen(), responses: (_) => _offline());
      expect(find.textContaining('Last seen'), findsOneWidget);
    });

    testWidgets('a rejected token reads as a fault to fix, not as "it is off"',
        (t) async {
      await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _offline(reason: 'auth'),
      );
      expect(find.textContaining('status token needs updating'), findsOneWidget);
    });

    testWidgets('the live pulse stops claiming to be live', (t) async {
      await _pump(t, const NasStatsScreen(), responses: (_) => _offline());
      final pulse = t.widget<LivePulse>(find.byType(LivePulse));
      expect(pulse.live, isFalse);
    });
  });

  group('degraded snapshots', () {
    testWidgets('a snapshot with null sections still renders the good ones',
        (t) async {
      await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(
          snapshot: _snapshotJson(
            disks: null,
            playback: null,
            services: null,
            snapshots: null,
          ),
        ),
      );

      // The point of the whole null-tolerant contract: a failing smartctl must
      // cost one card, not the screen.
      expect(find.text('275'), findsOneWidget);
      expect(
        find.textContaining('Disk health could not be read'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Service state could not be read'),
        findsOneWidget,
      );
      expectNoOverflow();
    });

    testWidgets('a null memory block shows a dash, never a zero', (t) async {
      await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(snapshot: _snapshotJson(memory: null)),
      );

      final ram = t
          .widgetList<FluidGauge>(find.byType(FluidGauge))
          .firstWhere((g) => g.label == 'RAM');
      expect(ram.value, isNull, reason: 'unknown is not zero');
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('a transcode is called out', (t) async {
      await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(
          snapshot: _snapshotJson(
            playback: {
              'count': 1,
              'items': [
                {'title': 'Dune', 'where': 'home', 'method': 'Transcode'},
              ],
            },
          ),
        ),
      );

      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Transcode'), findsOneWidget);
      expect(find.textContaining('expensive way'), findsOneWidget);
    });
  });

  group('VpsStatsScreen', () {
    testWidgets('stays live when the NAS is off, because the VPS answered',
        (t) async {
      await _pump(t, const VpsStatsScreen(), responses: (_) => _offline());

      // Locally measured figures are present...
      expect(find.textContaining('0.69'), findsOneWidget);
      expect(find.text('27.3%'), findsOneWidget);
      final shroud = t.widget<StatsOfflineShroud>(
        find.byType(StatsOfflineShroud),
      );
      expect(shroud.offline, isFalse, reason: 'the VPS is up; do not grey it');

      // ...and the relayed ones are explained rather than faked.
      expect(
        find.textContaining('come from your NAS, which is currently off'),
        findsOneWidget,
      );
      final steal = t
          .widgetList<FluidGauge>(find.byType(FluidGauge))
          .firstWhere((g) => g.label == 'STEAL');
      expect(steal.value, isNull);
    });

    testWidgets('throttling gets a loud banner at the top', (t) async {
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => NasStatsEnvelope.fromJson({
          'online': true,
          'at': _now(),
          'age_s': 1,
          'last_seen_at': _now(),
          'snapshot': _snapshotJson(),
          'vps_live': _vpsLiveJson(throttled: true, steal: 41.0),
        }),
      );

      expect(find.text('Hostinger is throttling this VPS'), findsOneWidget);
      expect(find.textContaining('can be stopped'), findsOneWidget);
      expect(find.textContaining('Steal above 20%'), findsOneWidget);
      expectNoOverflow();
    });

    testWidgets('stale platform figures are flagged, not presented as current',
        (t) async {
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => NasStatsEnvelope.fromJson({
          'online': true,
          'at': _now(),
          'age_s': 1,
          'last_seen_at': _now(),
          'snapshot': _snapshotJson(),
          'vps_live': _vpsLiveJson(age: 1800),
        }),
      );

      expect(
        find.textContaining('collected every five minutes, not continuously'),
        findsOneWidget,
      );
    });

    testWidgets('shows how the state was determined', (t) async {
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => _online(),
      );
      expect(find.text('Our own probes'), findsOneWidget);
      expect(find.text('13 of 13'), findsOneWidget);
    });

    testWidgets('draws CPU, RAM and disk as gauges, matching the NAS screen',
        (t) async {
      await _pump(t, const VpsStatsScreen(), responses: (_) => _online());

      final labels = t
          .widgetList<FluidGauge>(find.byType(FluidGauge))
          .map((g) => g.label)
          .toList();
      expect(labels, containsAll(<String>['CPU', 'RAM', 'DISK', 'STEAL']));

      final byLabel = {
        for (final g in t.widgetList<FluidGauge>(find.byType(FluidGauge)))
          g.label: g,
      };
      expect(byLabel['CPU']!.value, 9.2);
      expect(byLabel['RAM']!.value, 27.3);
      expect(byLabel['DISK']!.value, 11.0);
      expectNoOverflow();
    });
  });

  // The rule under test is inverted and easy to get backwards: Hostinger reports
  // a healthy auto-renewing VPS with expires_at null and the date in
  // next_billing_at. Saying "expires" there would tell the owner his server is
  // about to stop on the day it is in fact about to be paid for.
  group('subscription', () {
    Future<void> pumpBilling(WidgetTester t, Map<String, dynamic> billing,
        {bool nasOff = false}) async {
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => NasStatsEnvelope.fromJson({
          'online': !nasOff,
          'at': _now(),
          'age_s': 1,
          'last_seen_at': _now(),
          'snapshot': nasOff ? null : _snapshotJson(),
          'vps_live': _vpsLiveJson(nasOff: nasOff, billing: billing),
        }),
      );
    }

    testWidgets('an auto-renewing plan says Renews, never Expires', (t) async {
      await pumpBilling(t, _billingJson());

      expect(find.text('Renews 18 Sep 2026'), findsOneWidget);
      expect(find.textContaining('Expires 18 Sep'), findsNothing);
      expect(find.text('in 29 days'), findsOneWidget);
      expectNoOverflow();
    });

    testWidgets('with auto-renewal off the same date says Expires', (t) async {
      await pumpBilling(t, _billingJson(
        dueKind: 'expires',
        autoRenew: false,
        status: 'non_renewing',
      ));

      expect(find.text('Expires 18 Sep 2026'), findsOneWidget);
      expect(find.textContaining('Renews'), findsNothing);
      // Off is worth flagging; on is not.
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('the plan, its allocation and its price are shown', (t) async {
      await pumpBilling(t, _billingJson());

      expect(find.text('KVM 2'), findsOneWidget);
      expect(find.text('2 vCPU · 8 GB RAM · 100 GB disk'), findsOneWidget);
      // 209900 minor units of INR is ₹2,099 a month, not 209900 of anything.
      expect(find.text('\u20B92099 / month'), findsOneWidget);
    });

    testWidgets('the domain is shown alongside, since it expiring would take '
        'everything down too', (t) async {
      await pumpBilling(t, _billingJson());

      expect(find.text('.COM Domain'), findsOneWidget);
      expect(find.text('Expires 27 Jun 2029'), findsOneWidget);
    });

    testWidgets('a date already past reads as overdue, never "in -3 days"',
        (t) async {
      await pumpBilling(t, _billingJson(
        dueKind: 'expires',
        autoRenew: false,
        daysLeft: -3,
      ));

      expect(find.text('3 days overdue'), findsOneWidget);
      expect(find.textContaining('-3'), findsNothing);
    });

    testWidgets('a remembered date says so rather than implying it is fresh',
        (t) async {
      await pumpBilling(t, _billingJson(fromCache: true), nasOff: true);

      expect(find.text('Renews 18 Sep 2026'), findsOneWidget);
      expect(find.textContaining('Remembered from'), findsOneWidget);
    });

    testWidgets('a failed lookup is admitted, not silently shown as current',
        (t) async {
      await pumpBilling(t, _billingJson(error: 'HTTP 500'));

      expect(find.textContaining('last billing lookup failed'), findsOneWidget);
    });

    testWidgets('no billing block means no card at all, not an empty one',
        (t) async {
      await _pump(t, const VpsStatsScreen(), responses: (_) => _online());
      expect(find.text('Subscription'), findsNothing);
    });
  });

  // The hardest honest problem on this screen: the API that would report "this
  // machine is stopped" runs *on* that machine, so a stopped VPS produces only
  // silence — and so does a phone with no signal. These pin the two apart.
  group('an unreachable VPS', () {
    testWidgets('with the phone online, points at the server', (t) async {
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => _online(),
        throwThis: const NasStatsUnavailable('No connection.'),
        phoneConnected: true,
      );
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('The VPS is not responding'), findsOneWidget);
      expect(find.textContaining('most likely stopped'), findsOneWidget);
      expect(find.text('Not responding'), findsOneWidget);
      // It must not overstate: a running host with a dead container looks the
      // same from here.
      expect(find.textContaining('could also be running'), findsOneWidget);
      expectNoOverflow();
    });

    testWidgets('with the phone offline, blames nothing on the server',
        (t) async {
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => _online(),
        throwThis: const NasStatsUnavailable('No connection.'),
        phoneConnected: false,
      );
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('This phone is offline'), findsOneWidget);
      expect(
        find.textContaining('says anything about the server itself'),
        findsOneWidget,
      );
      expect(find.textContaining('most likely stopped'), findsNothing);
    });

    testWidgets('when connectivity cannot be read, names both causes',
        (t) async {
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => _online(),
        throwThis: const NasStatsUnavailable('No connection.'),
        phoneConnected: null,
      );
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('Can\'t reach the VPS'), findsOneWidget);
      expect(find.textContaining('not enough information'), findsOneWidget);
    });

    testWidgets('greys the screen, zeroes the gauges and stops claiming '
        '"running"', (t) async {
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => _online(),
        throwThis: const NasStatsUnavailable('No connection.'),
        phoneConnected: true,
      );
      await t.pump(const Duration(milliseconds: 900));

      final shroud = t.widget<StatsOfflineShroud>(
        find.byType(StatsOfflineShroud),
      );
      expect(shroud.offline, isTrue);

      for (final g in t.widgetList<FluidGauge>(find.byType(FluidGauge))) {
        expect(g.value, 0, reason: '${g.label} should sweep to empty, not dash');
      }
      expect(find.text('not responding'), findsOneWidget);
      expect(find.text('running'), findsNothing);
    });
  });

  group('polling', () {
    testWidgets('polls about every second while visible', (t) async {
      final fake = await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(),
      );
      final after = fake.calls;

      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(fake.calls, greaterThan(after));
    });

    testWidgets('the CPU meter tracks a new sample without a pull-to-refresh',
        (t) async {
      await _pump(
        t,
        const NasStatsScreen(),
        responses: (n) {
          final snap = Map<String, dynamic>.from(_snapshotJson());
          snap['cpu'] = {
            'cores': 4,
            'pct': 10.0 * n,
            'load1': 0.4,
            'load5': 0.3,
            'load15': 0.2,
          };
          return _online(snapshot: snap);
        },
      );

      expect(
        t.widget<FluidGauge>(find.byKey(const ValueKey('nas-cpu'))).value,
        10,
      );
      expect(find.byType(RefreshIndicator), findsNothing);

      await t.pump(const Duration(seconds: 1));
      await t.pump();

      expect(
        t.widget<FluidGauge>(find.byKey(const ValueKey('nas-cpu'))).value,
        20,
        reason: 'the second poll must move the arc; the user does not pull',
      );
    });

    testWidgets('opening the notification shade does not freeze the meters',
        (t) async {
      final fake = await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(),
      );
      final afterOpen = fake.calls;

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(
        fake.calls,
        greaterThan(afterOpen),
        reason: 'inactive is a shade, not a background; polling must continue',
      );
    });

    testWidgets('a real background pause stops the poll', (t) async {
      final fake = await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(),
      );

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      final settled = fake.calls;

      await t.pump(const Duration(seconds: 10));
      expect(fake.calls, settled);
    });

    testWidgets('the timer dies with the screen', (t) async {
      final fake = await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(),
      );

      // Replace the whole tree, disposing the autoDispose provider with it.
      await t.pumpWidget(MaterialApp(theme: _testTheme(), home: const SizedBox()));
      await t.pump();
      final settled = fake.calls;

      await t.pump(const Duration(seconds: 10));
      expect(fake.calls, settled,
          reason: 'a popped screen must not keep polling the NAS');
    });

    testWidgets('tapping CPU opens the live chart on the same poll', (t) async {
      final fake = await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(),
      );
      final afterDash = fake.calls;

      await t.tap(find.byKey(const ValueKey('nas-cpu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.byType(StatDetailScreen), findsOneWidget);
      expect(find.byType(HistoryRangeSwitch), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('7D'), findsOneWidget);
      expect(find.text('30D'), findsOneWidget);

      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(
        fake.calls,
        greaterThan(afterDash),
        reason: 'the detail view must keep the existing poll alive',
      );

      await t.tap(find.text('7D'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(fake.historyCalls, 1);
      expect(find.textContaining('Not enough history yet'), findsOneWidget);

      await t.pageBack();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(StatDetailScreen), findsNothing);
      expect(find.byKey(const ValueKey('nas-cpu')), findsOneWidget);
    });

    testWidgets('tapping VPS CPU opens the VPS live chart', (t) async {
      await _pump(t, const VpsStatsScreen(), responses: (_) => _online());

      await t.tap(find.byKey(const ValueKey('vps-cpu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.byType(StatDetailScreen), findsOneWidget);
      expect(find.text('VPS CPU'), findsWidgets);
      expect(find.byType(HistoryRangeSwitch), findsOneWidget);
    });

    testWidgets('30D history shows calendar-day ticks on the enlarged NAS chart', (t) async {
      final origin = DateTime.utc(2026, 8, 1);
      final pts = [
        for (var i = 0; i < 8; i++)
          StatsHistoryPoint(
            at: origin.add(Duration(days: i * 4)),
            value: 10 + i.toDouble(),
          ),
      ];
      await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(),
        size: const Size(400, 2400),
        history: (range, metric) => StatsHistoryEnvelope(
          range: range,
          nasOnline: true,
          nas: pts,
          vps: pts,
        ),
      );

      await t.tap(find.byKey(const ValueKey('nas-cpu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('30D'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Aug'), findsWidgets);
    });

    testWidgets('30D history shows calendar-day ticks on the enlarged VPS chart', (t) async {
      final origin = DateTime.utc(2026, 8, 1);
      final pts = [
        for (var i = 0; i < 8; i++)
          StatsHistoryPoint(
            at: origin.add(Duration(days: i * 4)),
            value: 10 + i.toDouble(),
          ),
      ];
      await _pump(
        t,
        const VpsStatsScreen(),
        responses: (_) => _online(),
        size: const Size(400, 2400),
        history: (range, metric) => StatsHistoryEnvelope(
          range: range,
          nasOnline: true,
          nas: pts,
          vps: pts,
        ),
      );

      await t.tap(find.byKey(const ValueKey('vps-cpu')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('30D'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Aug'), findsWidgets);
    });

    testWidgets('a transport failure reports it as unreachable, not as "off"',
        (t) async {
      await _pump(
        t,
        const NasStatsScreen(),
        responses: (_) => _online(),
        throwThis: const NasStatsUnavailable('No connection to the stats server.'),
      );

      expect(find.text('Can\'t reach the stats server'), findsOneWidget);
      expect(find.text('Your NAS is off'), findsNothing);
    });
  });

  group('backoff arithmetic', () {
    test('doubles from 1s and caps at 15s', () {
      const at = NasStatsController.backoffFor;

      expect(at(0), const Duration(seconds: 1));
      expect(at(1), const Duration(seconds: 1));
      expect(at(2), const Duration(seconds: 2));
      expect(at(3), const Duration(seconds: 4));
      expect(at(4), const Duration(seconds: 8));
      // A dead network must not cost 3,600 requests an hour.
      expect(at(5), const Duration(seconds: 15));
      // A long outage must not shift past 64 bits into a nonsense interval.
      expect(at(60), const Duration(seconds: 15));
    });
  });

  group('StatsLauncher', () {
    testWidgets('starts collapsed and expands into NAS and VPS', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });

      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: _testTheme(),
            home: const Scaffold(body: Column(children: [StatsLauncher()])),
          ),
        ),
      );

      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('NAS'), findsNothing);
      expect(find.text('VPS'), findsNothing);

      await t.tap(find.text('Stats'));
      await t.pumpAndSettle();

      expect(find.text('NAS'), findsOneWidget);
      expect(find.text('VPS'), findsOneWidget);
      expectNoOverflow();

      await t.tap(find.text('Stats'));
      await t.pumpAndSettle();
      expect(find.text('NAS'), findsNothing);
    });
  });

  group('layout across sizes, type scale and palettes', () {
    const sizes = <Size>[
      Size(320, 640),
      Size(360, 800),
      Size(411, 891),
    ];
    const scales = <double>[1.0, 1.3, 2.0];

    testWidgets('NAS never overflows or paints the wrong background',
        (t) async {
      for (final size in sizes) {
        for (final scale in scales) {
          for (final white in const [false, true]) {
            await _pump(
              t,
              const NasStatsScreen(),
              responses: (_) => _online(),
              size: size,
              textScale: scale,
              white: white,
            );
            expectNoOverflow();
            expect(find.byType(RefreshIndicator), findsNothing);
            final scaffold = t.widget<Scaffold>(find.byType(Scaffold));
            expect(
              scaffold.backgroundColor,
              white ? AppColors.white.bg : AppColors.dark.bg,
              reason: '${white ? 'white' : 'dark'} ${size.width}px @${scale}x',
            );
            await t.pumpWidget(const SizedBox());
            await t.pump();
          }
        }
      }
    });

    testWidgets('VPS never overflows, including the subscription card',
        (t) async {
      for (final size in sizes) {
        for (final scale in scales) {
          for (final white in const [false, true]) {
            await _pump(
              t,
              const VpsStatsScreen(),
              responses: (_) => NasStatsEnvelope.fromJson({
                'online': true,
                'at': _now(),
                'age_s': 1,
                'last_seen_at': _now(),
                'snapshot': _snapshotJson(),
                'vps_live': _vpsLiveJson(billing: _billingJson()),
              }),
              size: size,
              textScale: scale,
              white: white,
            );
            expectNoOverflow();
            expect(find.byType(RefreshIndicator), findsNothing);
            expect(find.text('Renews 18 Sep 2026'), findsOneWidget);
            await t.pumpWidget(const SizedBox());
            await t.pump();
          }
        }
      }
    });

    testWidgets('the launcher stays inside 320 px at 2x type', (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });

      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: _testTheme(),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              );
            },
            home: const Scaffold(body: Column(children: [StatsLauncher()])),
          ),
        ),
      );
      await t.tap(find.text('Stats'));
      await t.pumpAndSettle();
      expect(find.text('NAS'), findsOneWidget);
      expectNoOverflow();
    });
  });

  group('formatting refuses to invent numbers', () {
    test('null is a dash, not a zero', () {
      expect(formatBytes(null), '—');
      expect(formatGb(null), '—');
      expect(formatPct(null), '—');
      expect(formatDuration(null), '—');
    });

    test('bytes read naturally at each scale', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024 * 900), '900 KB');
      expect(formatBytes(1024 * 1024 * 1024 * 3 + 500000000), '3.5 GB');
    });

    test('durations are coarse enough to read at a glance', () {
      expect(formatDuration(45), '45s');
      expect(formatDuration(600), '10m');
      expect(formatDuration(3660), '1h 01m');
      expect(formatDuration(141353), '1d 15h');
    });

    test('the gauge ramp matches the ZFS thresholds', () {
      expect(FluidGauge.rampFor(10), FluidGauge.green);
      expect(FluidGauge.rampFor(69.9), FluidGauge.green);
      expect(FluidGauge.rampFor(70), FluidGauge.amber);
      expect(FluidGauge.rampFor(79.9), FluidGauge.amber);
      expect(FluidGauge.rampFor(80), FluidGauge.red);
    });
  });

  group('model parsing', () {
    test('online:false forces the snapshot away even if one is present', () {
      // Belt and braces against a server that ever sends both: a half-live,
      // half-dull screen would be worse than either.
      final env = NasStatsEnvelope.fromJson({
        'online': false,
        'reason': 'timeout',
        'snapshot': _snapshotJson(),
      });
      expect(env.snapshot, isNull);
      expect(env.reason, NasOfflineReason.timeout);
    });

    test('ints and doubles are both accepted for the same field', () {
      final a = NasCpu.fromJson(const {'pct': 12, 'load1': 1});
      expect(a.pct, 12.0);
      expect(a.load1, 1.0);
    });

    test('load per core is what actually means something', () {
      expect(NasCpu.fromJson(const {'cores': 4, 'load1': 2.0}).loadPerCore, 0.5);
      expect(NasCpu.fromJson(const {'load1': 2.0}).loadPerCore, isNull);
    });

    test('the billing verb is read, never re-derived from the fields', () {
      final renews = VpsSubscription.fromJson(const {
        'due_kind': 'renews',
        'due_at': '2026-09-18T03:37:38Z',
        'auto_renew': true,
      });
      expect(renews.verb, 'Renews');
      expect(renews.isRenewing, isTrue);
      expect(renews.isExpiring, isFalse);

      final expires = VpsSubscription.fromJson(const {'due_kind': 'expires'});
      expect(expires.verb, 'Expires');
      expect(expires.isExpiring, isTrue);
    });

    test('an unrecognised verb produces no wording at all', () {
      // The card leads with this word. A guess would be worse than silence.
      final s = VpsSubscription.fromJson(const {'due_kind': 'perhaps'});
      expect(s.verb, isNull);
      final none = VpsSubscription.fromJson(const {});
      expect(none.verb, isNull);
      expect(none.dueLocal, isNull);
    });

    test('only a real deadline demands attention', () {
      VpsSubscription s(String kind, int days) =>
          VpsSubscription.fromJson({'due_kind': kind, 'days_left': days});

      // An auto-renewing plan three days from billing is not news.
      expect(s('renews', 3).needsAttention, isFalse);
      expect(s('renews', 400).needsAttention, isFalse);
      // One that expires in three days is the whole screen.
      expect(s('expires', 3).needsAttention, isTrue);
      expect(s('expires', 31).needsAttention, isFalse);
      // Anything overdue matters either way.
      expect(s('renews', -1).needsAttention, isTrue);
      expect(VpsSubscription.fromJson(const {}).needsAttention, isFalse);
    });

    test('money is formatted from minor units, or not at all', () {
      VpsSubscription s(Map<String, dynamic> m) => VpsSubscription.fromJson(m);

      expect(
        s(const {'renewal_price': 209900, 'currency': 'INR',
          'period': 1, 'period_unit': 'month'}).priceLabel,
        '\u20B92099 / month',
      );
      expect(
        s(const {'renewal_price': 454934, 'currency': 'INR',
          'period': 3, 'period_unit': 'year'}).priceLabel,
        '\u20B94549.34 / 3 years',
      );
      // An unknown currency keeps its code rather than borrowing a symbol.
      expect(
        s(const {'renewal_price': 1000, 'currency': 'XYZ'}).priceLabel,
        '10 XYZ',
      );
      // A number with no currency is meaningless, so it is not shown.
      expect(s(const {'renewal_price': 1000}).priceLabel, isNull);
      expect(s(const {'currency': 'INR'}).priceLabel, isNull);
    });

    test('the VPS and the other subscriptions stay separate', () {
      final b = VpsBilling.fromJson(_billingJson());
      expect(b.vps?.name, 'KVM 2');
      expect(b.others.single.name, '.COM Domain');
      expect(b.isEmpty, isFalse);
      expect(VpsBilling.fromJson(const {}).isEmpty, isTrue);
    });

    test('the plan block survives a snapshot with no billing', () {
      final v = VpsLive.fromJson(_vpsLiveJson());
      expect(v.planName, 'KVM 2');
      expect(v.vcpus, 2);
      expect(v.planRamMb, 8192);
      expect(v.billing, isNull, reason: 'none was supplied');
    });

    test('an unknown offline reason still produces a readable sentence', () {
      final env = NasStatsEnvelope.fromJson(const {'online': false});
      expect(env.reason, NasOfflineReason.unknown);
      expect(env.reason!.message, isNotEmpty);
    });

    test('a stalled NAS is detected from the sample age', () {
      expect(
        NasStatsEnvelope.fromJson({'online': true, 'age_s': 2, 'at': _now()})
            .isStalled,
        isFalse,
      );
      expect(
        NasStatsEnvelope.fromJson({'online': true, 'age_s': 90, 'at': _now()})
            .isStalled,
        isTrue,
      );
    });
  });
}

/// Fails if the widget tree reported a layout overflow.
///
/// A RenderFlex overflow is surfaced as a caught exception rather than a test
/// failure, so without an explicit check a screen could overflow at 320 px and
/// the test would still pass. Anything that is not an overflow is rethrown, so
/// this cannot mask a real error either.
void expectNoOverflow() {
  final err = TestWidgetsFlutterBinding.instance.takeException();
  if (err == null) return;
  fail('Layout error during render: $err');
}
