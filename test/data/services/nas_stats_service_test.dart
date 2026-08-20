// Hermetic tests for NasStatsService.
//
// A scripted HttpClientAdapter stands in for the network, so this exercises the
// real Dio stack — interceptors, JSON decoding and all — without a socket.
//
// The single distinction being protected here is the one the whole feature rests
// on: "the NAS is off" arrives as a healthy HTTP 200 and must parse into an
// envelope, while "your phone cannot reach the VPS" must throw. Collapsing the
// two would send the owner to the wrong room to fix the wrong thing.
//
// Retry backoff is real, so the give-up cases take a few seconds.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/nas_stats_service.dart';
import 'package:ai_nexus/domain/entities/nas_stats.dart';
import 'package:ai_nexus/presentation/screens/cloud/stats/live/stat_metric.dart';

class _Reply {
  _Reply.json(this.status, Object body)
      : payload = jsonEncode(body),
        error = null;
  _Reply.raw(this.status, this.payload) : error = null;
  _Reply.failure(this.error)
      : status = null,
        payload = null;

  final int? status;
  final String? payload;
  final DioExceptionType? error;
}

/// Serves replies in order, repeating the last one so a retrying client keeps
/// getting the same answer rather than falling off the end of the script.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<_Reply> script;
  int calls = 0;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final reply = script[calls < script.length ? calls : script.length - 1];
    calls += 1;
    final type = reply.error;
    if (type != null) {
      throw DioException(requestOptions: options, type: type);
    }
    return ResponseBody.fromString(
      reply.payload!,
      reply.status!,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({NasStatsService service, _ScriptedAdapter adapter}) build(
    List<_Reply> script,
  ) {
    final client = ApiClient();
    final adapter = _ScriptedAdapter(script);
    client.dio.httpClientAdapter = adapter;
    return (service: NasStatsService(client), adapter: adapter);
  }

  Map<String, dynamic> onlineBody() => {
        'online': true,
        'reason': null,
        'at': 1786944903,
        'age_s': 1,
        'last_seen_at': 1786944903,
        'snapshot': {
          'api': 1,
          'at': 1786944902,
          'host': 'truenas',
          'cpu': {'cores': 4, 'pct': 12.5},
          'memory': {'total_mb': 7363, 'available_mb': 2430, 'pressure': 'ok'},
          'movies': {'headline_free_gb': 275, 'avail_bytes': 295543554048},
          'pools': [
            {'name': 'Storage', 'health': 'ONLINE', 'used_pct': 37, 'role': 'main'},
          ],
        },
        'vps_live': {'cpu_pct': 9.2, 'mem_pct': 27.3, 'disk_pct': 11.0},
      };

  test('a 200 envelope parses, and the request goes to the cloud stats path',
      () async {
    final t = build([_Reply.json(200, onlineBody())]);

    final env = await t.service.fetch();

    expect(env.online, isTrue);
    expect(env.snapshot?.movies?.headlineFreeGb, 275);
    expect(env.snapshot?.cpu?.pct, 12.5);
    expect(env.vpsLive?.memPct, 27.3);
    expect(t.adapter.calls, 1);
    expect(t.adapter.paths.single, contains('/api/v1/cloud/stats'));
  });

  test('"the NAS is off" is a successful fetch, not an exception', () async {
    final t = build([
      _Reply.json(200, {
        'online': false,
        'reason': 'unreachable',
        'at': 1786944903,
        'last_seen_at': 1786940000,
        'snapshot': null,
        'vps_live': {'cpu_pct': 4.0, 'mem_pct': 22.0},
      }),
    ]);

    final env = await t.service.fetch();

    expect(env.online, isFalse);
    expect(env.reason, NasOfflineReason.unreachable);
    expect(env.snapshot, isNull);
    // The VPS half must survive, because the machine that answered is the VPS.
    expect(env.vpsLive?.cpuPct, 4.0);
    expect(env.lastSeenAt, isNotNull);
  });

  test('an expired session is reported as a session problem, not as a dead NAS',
      () async {
    final t = build([_Reply.json(401, {'error': 'unauthorised'})]);

    await expectLater(
      t.service.fetch(),
      throwsA(
        isA<NasStatsUnavailable>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.isAuthFailure, 'isAuthFailure', isTrue)
            .having((e) => e.message, 'message', contains('Sign in again')),
      ),
    );
    // A 401 is not transient, so retrying it would only delay the sign-in prompt.
    expect(t.adapter.calls, 1);
  });

  test('no network throws with a message about the connection', () async {
    final t = build([_Reply.failure(DioExceptionType.connectionError)]);

    await expectLater(
      t.service.fetch(),
      throwsA(
        isA<NasStatsUnavailable>()
            .having((e) => e.isAuthFailure, 'isAuthFailure', isFalse)
            .having((e) => e.message, 'message', contains('No connection')),
      ),
    );
    // A 1-second poll opts out of the client's 3-retry stack: a blip is the
    // next tick, not a 15-second freeze of the gauges.
    expect(t.adapter.calls, 1);
  });

  test('a body that is not an object is rejected rather than half-parsed',
      () async {
    final t = build([_Reply.raw(200, '"just a string"')]);

    await expectLater(
      t.service.fetch(),
      throwsA(isA<NasStatsUnavailable>()
          .having((e) => e.message, 'message', contains('unreadable'))),
    );
  });

  test('a timeout says so, so the owner does not go looking for the NAS',
      () async {
    final t = build([_Reply.failure(DioExceptionType.receiveTimeout)]);

    await expectLater(
      t.service.fetch(),
      throwsA(isA<NasStatsUnavailable>()
          .having((e) => e.message, 'message', contains('took too long'))),
    );
    expect(t.adapter.calls, 1);
  });

  test('a cancelled poll is distinguishable, so screen teardown is not an error',
      () async {
    final t = build([_Reply.failure(DioExceptionType.cancel)]);

    await expectLater(
      t.service.fetch(),
      throwsA(isA<NasStatsUnavailable>()
          .having((e) => e.message, 'message', 'Cancelled.')),
    );
  });

  test('a snapshot missing most of its sections still yields an envelope',
      () async {
    // The daemon nulls a section it could not collect, and the app must render
    // what did arrive. Anything else means one failing smartctl blanks the page.
    final t = build([
      _Reply.json(200, {
        'online': true,
        'at': 1786944903,
        'age_s': 2,
        'snapshot': {'api': 1, 'at': 1786944901, 'host': 'truenas'},
        'vps_live': null,
      }),
    ]);

    final env = await t.service.fetch();

    expect(env.online, isTrue);
    expect(env.snapshot?.host, 'truenas');
    expect(env.snapshot?.cpu, isNull);
    expect(env.snapshot?.pools, isEmpty);
    expect(env.vpsLive, isNull);
  });

  test('fetchHistory on 404 is empty history, not a crash', () async {
    final t = build([_Reply.json(404, {'error': 'not found'})]);
    final env = await t.service.fetchHistory(
      StatsHistoryRange.d7,
      metric: StatMetric.nasCpu,
    );
    expect(env.nas, isEmpty);
    expect(env.vps, isEmpty);
    expect(t.adapter.paths.single, contains('/api/v1/cloud/stats/history'));
    expect(t.adapter.paths.single, contains('range=7d'));
  });

  test('fetchHistory Now does not hit the network', () async {
    final t = build([_Reply.json(500, {'error': 'nope'})]);
    final env = await t.service.fetchHistory(
      StatsHistoryRange.now,
      metric: StatMetric.vpsCpu,
    );
    expect(env.range, StatsHistoryRange.now);
    expect(t.adapter.calls, 0);
  });

  test('fetchHistory parses NAS and VPS points for the requested metric', () async {
    final t = build([
      _Reply.json(200, {
        'range': '7d',
        'nas': {
          'online': true,
          'points': [
            {'t': 1786940000, 'cpu': 11.5, 'mem': 40.0, 'disk': 37},
          ],
        },
        'vps': {
          'points': [
            {'t': 1786940000, 'cpu': 9.2, 'mem': 27.3, 'disk': 11.0, 'steal': 3.9},
          ],
        },
      }),
    ]);

    final nas = await t.service.fetchHistory(
      StatsHistoryRange.d7,
      metric: StatMetric.nasCpu,
    );
    expect(nas.nasOnline, isTrue);
    expect(nas.seriesFor(StatMetric.nasCpu).single.value, 11.5);

    final vps = await t.service.fetchHistory(
      StatsHistoryRange.d7,
      metric: StatMetric.vpsSteal,
    );
    expect(vps.seriesFor(StatMetric.vpsSteal).single.value, 3.9);
  });
}
