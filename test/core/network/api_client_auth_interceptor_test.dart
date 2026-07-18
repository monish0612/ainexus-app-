// Tests the Dio _AuthInterceptor wired into [ApiClient]:
//   • attaches the stored JWT as a Bearer header
//   • on 401, re-mints the token via AppTokenStore.refresher and replays once
//   • never loops on the /auth/app-login call itself
//   • propagates the 401 when no refresher is configured
//
// A fake HttpClientAdapter stands in for the network so nothing leaves the box.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/auth/app_token_store.dart';
import 'package:ai_nexus/core/network/api_client.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.onFetch);
  final Future<ResponseBody> Function(RequestOptions options) onFetch;
  final List<RequestOptions> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    calls.add(options);
    return onFetch(options);
  }
}

ResponseBody _json(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await AppTokenStore.instance.clear();
    AppTokenStore.instance.refresher = null;
  });

  tearDown(() async {
    await AppTokenStore.instance.clear();
    AppTokenStore.instance.refresher = null;
  });

  test('attaches the stored token as a Bearer header', () async {
    await AppTokenStore.instance.setToken('tok123');
    final client = ApiClient();
    final adapter = _FakeAdapter((_) async => _json(200, {'ok': true}));
    client.dio.httpClientAdapter = adapter;

    final resp = await client.get<dynamic>('/api/v1/expenses');

    expect(resp.statusCode, 200);
    expect(adapter.calls.single.headers['Authorization'], 'Bearer tok123');
  });

  test('no token → no Authorization header (permissive backend unaffected)',
      () async {
    final client = ApiClient();
    final adapter = _FakeAdapter((_) async => _json(200, {'ok': true}));
    client.dio.httpClientAdapter = adapter;

    await client.get<dynamic>('/api/v1/expenses');

    expect(adapter.calls.single.headers.containsKey('Authorization'), isFalse);
  });

  test('401 → refreshes token and replays the request once with new token',
      () async {
    await AppTokenStore.instance.setToken('stale');
    var refreshCount = 0;
    AppTokenStore.instance.refresher = () async {
      refreshCount++;
      await AppTokenStore.instance.setToken('fresh');
      return true;
    };

    final client = ApiClient();
    var n = 0;
    final adapter = _FakeAdapter((options) async {
      n++;
      if (n == 1) return _json(401, {'error': 'Authentication required'});
      return _json(200, {'ok': true});
    });
    client.dio.httpClientAdapter = adapter;

    final resp = await client.get<dynamic>('/api/v1/expenses');

    expect(resp.statusCode, 200);
    expect(refreshCount, 1);
    expect(adapter.calls.length, 2);
    expect(adapter.calls[0].headers['Authorization'], 'Bearer stale');
    expect(adapter.calls[1].headers['Authorization'], 'Bearer fresh');
  });

  test('persistent 401 → retries exactly once, then surfaces the error',
      () async {
    await AppTokenStore.instance.setToken('stale');
    var refreshCount = 0;
    AppTokenStore.instance.refresher = () async {
      refreshCount++;
      await AppTokenStore.instance.setToken('fresh');
      return true;
    };

    final client = ApiClient();
    final adapter = _FakeAdapter((_) async => _json(401, {'error': 'nope'}));
    client.dio.httpClientAdapter = adapter;

    await expectLater(
      client.get<dynamic>('/api/v1/expenses'),
      throwsA(isA<DioException>()),
    );
    // One original + exactly one replay (the replay carries the retry flag).
    expect(adapter.calls.length, 2);
    expect(refreshCount, 1);
  });

  test('does NOT auto-retry the /auth/app-login call itself', () async {
    var refreshCount = 0;
    AppTokenStore.instance.refresher = () async {
      refreshCount++;
      return true;
    };
    final client = ApiClient();
    final adapter =
        _FakeAdapter((_) async => _json(401, {'error': 'Invalid credentials'}));
    client.dio.httpClientAdapter = adapter;

    await expectLater(
      client.post<dynamic>('/api/v1/auth/app-login',
          data: {'username': 'x', 'password': 'y'}),
      throwsA(isA<DioException>()),
    );
    expect(refreshCount, 0); // never tried to refresh
    expect(adapter.calls.length, 1); // no replay
  });

  test('401 with no refresher configured → error propagates, no retry',
      () async {
    await AppTokenStore.instance.setToken('stale');
    AppTokenStore.instance.refresher = null;

    final client = ApiClient();
    final adapter = _FakeAdapter((_) async => _json(401, {'error': 'nope'}));
    client.dio.httpClientAdapter = adapter;

    await expectLater(
      client.get<dynamic>('/api/v1/expenses'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.calls.length, 1);
  });

  test('two concurrent 401s both recover after refresh (no deadlock/corruption)',
      () async {
    await AppTokenStore.instance.setToken('stale');
    AppTokenStore.instance.refresher = () async {
      await AppTokenStore.instance.setToken('fresh');
      return true;
    };

    final client = ApiClient();
    // Adapter only accepts the refreshed token; anything else is rejected.
    final adapter = _FakeAdapter((options) async {
      final auth = options.headers['Authorization'];
      if (auth == 'Bearer fresh') return _json(200, {'ok': true});
      return _json(401, {'error': 'stale'});
    });
    client.dio.httpClientAdapter = adapter;

    final results = await Future.wait([
      client.get<dynamic>('/api/v1/expenses'),
      client.get<dynamic>('/api/v1/budget'),
    ]);

    expect(results[0].statusCode, 200);
    expect(results[1].statusCode, 200);
  });

  test('refresher returning false → original 401 surfaces without replay',
      () async {
    await AppTokenStore.instance.setToken('stale');
    var refreshCount = 0;
    AppTokenStore.instance.refresher = () async {
      refreshCount++;
      return false;
    };

    final client = ApiClient();
    final adapter = _FakeAdapter((_) async => _json(401, {'error': 'nope'}));
    client.dio.httpClientAdapter = adapter;

    await expectLater(
      client.get<dynamic>('/api/v1/expenses'),
      throwsA(isA<DioException>()),
    );
    expect(refreshCount, 1);
    expect(adapter.calls.length, 1); // refresh failed → no replay
  });
}
