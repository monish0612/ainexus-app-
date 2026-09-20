import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/telegram_logger.dart';
import 'catalog/store_catalog.dart';
import 'page_harvest.dart';
import 'price_models.dart';
import 'store_url.dart';

/// Chrome 141 (Sep 2026). Stale Chrome/Windows UA from an Android app is a
/// WAF fingerprint — Amazon then serves goku/awsWaf interstitials.
const _kChrome = '141.0.7390.70';
const _kUaDesktop =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/$_kChrome Safari/537.36';
const _kUaAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/$_kChrome Mobile Safari/537.36';
const _kChUa =
    '"Google Chrome";v="141", "Chromium";v="141", "Not A(Brand";v="24"';

bool get _onAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Dedicated client — never the app [ApiClient]. Storefronts must not see
/// Nexus auth headers. Cookies are shared for the process so a WAF
/// interstitial's Set-Cookie is sent on the next GET (Amazon's normal flow).
class WatchHttpFetcher {
  WatchHttpFetcher({Dio? dio}) : _dio = dio ?? _sharedDio();

  final Dio _dio;

  static Dio? _shared;
  static final _WatchCookieJar _jar = _WatchCookieJar();

  static Dio _sharedDio() {
    return _shared ??= _newDio()..interceptors.insert(0, _jar);
  }

  static Dio _newDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 18),
        receiveTimeout: const Duration(seconds: 22),
        followRedirects: true,
        maxRedirects: 8,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-IN,en;q=0.9,hi-IN;q=0.8',
          'Upgrade-Insecure-Requests': '1',
        },
        validateStatus: (s) => s != null && s < 500,
      ),
    );
  }

  Future<ScrapeHit> scrape(String url, {WatchStore? store}) async {
    final canon = canonicalizeWatchUrl(url);
    final resolvedStore = store ?? canon?.store;
    if (resolvedStore == null) {
      throw WatchScrapeException('Unsupported store URL');
    }
    final target = canon?.url ?? url;

    Object? lastError;
    StackTrace? lastStack;
    for (var i = 0; i < 3; i++) {
      try {
        return await _once(
          _attemptUrl(target, resolvedStore, canon?.productId, i),
          resolvedStore,
          i,
        );
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        final msg = e.toString();
        if (_fatalFetch(msg)) {
          Error.throwWithStackTrace(e, st);
        }
        if (i < 2) {
          TLog.w(
            'Watch',
            'Retry fetch ${resolvedStore.id} ${i + 1}/3: $e',
            error: e,
          );
          await Future<void>.delayed(Duration(milliseconds: 450 * (i + 1)));
        }
      }
    }
    Error.throwWithStackTrace(
      _friendly(resolvedStore, lastError) ??
          WatchScrapeException('Fetch failed'),
      lastStack ?? StackTrace.current,
    );
  }

  Future<ScrapeHit> _once(String url, WatchStore store, int attempt) async {
    final mobile = _useMobileUa(store, attempt);
    final res = await _dio.get<String>(
      url,
      options: Options(
        headers: {
          'User-Agent': mobile ? _kUaAndroid : _kUaDesktop,
          'sec-ch-ua': _kChUa,
          'sec-ch-ua-mobile': mobile ? '?1' : '?0',
          'sec-ch-ua-platform': mobile ? '"Android"' : '"Windows"',
          'sec-fetch-dest': 'document',
          'sec-fetch-mode': 'navigate',
          'sec-fetch-site': attempt == 0 ? 'none' : 'same-origin',
          'sec-fetch-user': '?1',
          if (attempt > 0) 'Referer': 'https://${_referer(store)}/',
        },
        responseType: ResponseType.plain,
      ),
    );
    final status = res.statusCode ?? 0;
    if (status == 404) {
      throw WatchScrapeException('Product page not found (404)');
    }
    if (status == 403 || status == 401) {
      throw WatchScrapeException('Store blocked the fetch ($status)');
    }
    if (status == 202 || status == 429) {
      throw WatchScrapeException('Store showed a challenge page');
    }
    if (status >= 400) {
      throw WatchScrapeException('HTTP $status');
    }
    final html = res.data ?? '';
    if (html.length < 400) {
      throw WatchScrapeException('Empty store page');
    }
    final low = html.toLowerCase();
    final captcha = low.contains('validatecaptcha') ||
        low.contains('opfcaptcha') ||
        low.contains('captcha-show') ||
        low.contains('enter the characters you see');
    final wafShell = html.length < 16000 &&
        (low.contains('awswafcookiedomainlist') ||
            low.contains('gokuprops'));
    if (captcha || wafShell) {
      throw WatchScrapeException('Store showed a challenge page');
    }
    final finalUrl = res.realUri.toString();
    final page = PageHarvest(html: html, finalUrl: finalUrl);
    final detected = canonicalizeWatchUrl(finalUrl);
    final scrapeStore = store == WatchStore.other && detected != null
        ? detected.store
        : store;
    final hit = StoreCatalog.scrape(scrapeStore, page);
    if (hit == null) {
      TLog.w(
        'Watch',
        '${scrapeStore.id} parse miss host=${res.realUri.host} len=${html.length}',
      );
      throw WatchParseMissException(
        'Could not find a live price',
        excerpt: page.llmExcerpt(),
        finalUrl: finalUrl,
      );
    }
    TLog.i(
      'Watch',
      '${scrapeStore.id} ${hit.source} ₹${hit.price.toStringAsFixed(2)} '
          'score=${hit.score}',
    );
    return hit.withResolvedUrl(_resolvedForStore(scrapeStore, finalUrl, hit));
  }

  String _resolvedForStore(WatchStore store, String finalUrl, ScrapeHit hit) {
    if (store != WatchStore.flipkart) return finalUrl;
    final sku = hit.pageProductId;
    if (sku == null || sku.isEmpty) return finalUrl;
    final u = Uri.parse(finalUrl);
    if ((u.queryParameters['pid'] ?? '').isNotEmpty) return finalUrl;
    return u.replace(
      queryParameters: {...u.queryParameters, 'pid': sku},
    ).toString();
  }

  bool _useMobileUa(WatchStore store, int attempt) {
    return StoreCatalog.of(store).useMobileUa(
      attempt: attempt,
      onAndroid: _onAndroid,
    );
  }

  String _attemptUrl(
    String url,
    WatchStore store,
    String? productId,
    int attempt,
  ) {
    return StoreCatalog.of(store).attemptUrl(url, productId, attempt);
  }

  String _referer(WatchStore store) {
    final host = StoreCatalog.of(store).refererHost;
    return host.isEmpty ? 'www.google.com' : host;
  }
}

WatchScrapeException? _friendly(WatchStore store, Object? lastError) {
  if (lastError == null) return null;
  if (lastError is WatchParseMissException) return lastError;
  if (lastError is WatchScrapeException && _fatalFetch(lastError.message)) {
    return lastError;
  }
  final m = lastError.toString().toLowerCase();
  if (m.contains('challenge') ||
      m.contains('blocked') ||
      m.contains('429')) {
    return WatchScrapeException(
      '${store.label} is checking this phone. Wait a few seconds '
      'and tap Preview again.',
    );
  }
  if (lastError is WatchScrapeException) return lastError;
  return WatchScrapeException('Fetch failed');
}

class WatchScrapeException implements Exception {
  WatchScrapeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Adapter miss after a successful GET. Excerpt is safe to send to Flash.
class WatchParseMissException extends WatchScrapeException {
  WatchParseMissException(
    super.message, {
    required this.excerpt,
    this.finalUrl,
  });

  final String excerpt;
  final String? finalUrl;
}

bool _fatalFetch(String msg) {
  final m = msg.toLowerCase();
  return m.contains('404') ||
      m.contains('unsupported') ||
      m.contains('not found') ||
      m.contains('empty store page');
}

/// In-process cookie jar so Amazon's WAF token from a 202/interstitial is
/// sent on the follow-up GET. Never logged.
class _WatchCookieJar extends Interceptor {
  final Map<String, Map<String, String>> _byStore = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final cookie = _headerFor(options.uri.host);
    if (cookie.isNotEmpty) {
      options.headers['Cookie'] = cookie;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _ingest(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final res = err.response;
    if (res != null) _ingest(res);
    handler.next(err);
  }

  void _ingest(Response response) {
    final set = response.headers['set-cookie'];
    if (set == null || set.isEmpty) return;
    final bucket =
        _byStore.putIfAbsent(_root(response.requestOptions.uri.host), () => {});
    for (final line in set) {
      final part = line.split(';').first;
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final name = part.substring(0, i).trim();
      final value = part.substring(i + 1).trim();
      if (name.isEmpty) continue;
      if (value.isEmpty || value.toLowerCase() == 'deleted') {
        bucket.remove(name);
      } else {
        bucket[name] = value;
      }
    }
  }

  String _headerFor(String host) {
    final bucket = _byStore[_root(host)];
    if (bucket == null || bucket.isEmpty) return '';
    return bucket.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  String _root(String host) => StoreCatalog.cookieBucket(host);
}
