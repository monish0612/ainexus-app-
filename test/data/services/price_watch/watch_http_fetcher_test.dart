import 'package:ai_nexus/data/services/price_watch/watch_http_fetcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Dio _stub(int status, String body, {Uri? uri}) {
  final dio = Dio(
    BaseOptions(
      followRedirects: true,
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<String>(
            requestOptions: options.copyWith(
              path: uri?.toString() ?? options.path,
            ),
            data: body,
            statusCode: status,
          ),
        );
      },
    ),
  );
  return dio;
}

String _pad(String html) => html.padRight(500, ' ');

void main() {
  test('unsupported host is rejected before fetch', () async {
    expect(
      () => WatchHttpFetcher(dio: _stub(200, _pad('<html></html>'))).scrape(
        'https://www.google.com/search?q=x',
      ),
      throwsA(
        isA<WatchScrapeException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported'),
        ),
      ),
    );
  });

  test('404 is not retried as a parse miss', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data: _pad('<html>missing</html>'),
              statusCode: 404,
            ),
          );
        },
      ),
    );
    await expectLater(
      WatchHttpFetcher(dio: dio).scrape('https://www.amazon.in/dp/B0CXXXXXXX'),
      throwsA(
        isA<WatchScrapeException>().having(
          (e) => e.message,
          'message',
          contains('404'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('202 WAF interstitial is retried then still fails', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data: _pad('<html>window.gokuProps = {}</html>'),
              statusCode: 202,
            ),
          );
        },
      ),
    );
    await expectLater(
      WatchHttpFetcher(dio: dio).scrape(
        'https://www.swiggy.com/instamart/item/abc?itemId=99',
      ),
      throwsA(
        isA<WatchScrapeException>().having(
          (e) => e.message,
          'message',
          contains('checking this phone'),
        ),
      ),
    );
    expect(calls, 3);
  });

  test('200 WAF body is retried then still fails', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data: _pad(
                '<html><script>window.awsWafCookieDomainList=[]</script>',
              ),
              statusCode: 200,
            ),
          );
        },
      ),
    );
    await expectLater(
      WatchHttpFetcher(dio: dio).scrape('https://www.amazon.in/dp/B0CXXXXXXX'),
      throwsA(
        isA<WatchScrapeException>().having(
          (e) => e.message,
          'message',
          contains('checking this phone'),
        ),
      ),
    );
    expect(calls, 3);
  });

  test('Amazon WAF 202 then PDP succeeds on retry', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          if (calls == 1) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 202,
                headers: Headers.fromMap({
                  'set-cookie': ['aws-waf-token=abc; Path=/'],
                }),
                data: _pad('<html>window.gokuProps = {}</html>'),
              ),
            );
            return;
          }
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: _pad('''
<html><head><title>The Alchemist</title></head><body>
<div id="corePriceDisplay_desktop_feature_div">
<span class="a-price reinventPricePriceToPayMargin priceToPay">
<span class="a-offscreen"> </span><span class="a-price-whole">259</span>
</span>
<div class="twister-plus-buying-options-price-data">{"desktop_buybox_group_1":[{"displayPrice":"₹259.00","priceAmount":259.00}]}</div>
</div>
</body></html>
'''),
            ),
          );
        },
      ),
    );
    final hit = await WatchHttpFetcher(dio: dio).scrape(
      'https://www.amazon.in/dp/8172234988',
    );
    expect(calls, 2);
    expect(hit.price, 259);
  });

  test('Flipkart scrape merges sku into pid on resolved URL', () async {
    const html = '''
<html><head>
<meta property="og:title" content="Apple iPhone 15 (Blue, 128 GB)">
<script type="application/ld+json">
[{"@type":"Product","sku":"MOBGTAGPAQNVFZZY","offers":{"price":59900}}]
</script>
</head><body></body></html>
''';
    final hit = await WatchHttpFetcher(
      dio: _stub(200, _pad(html)),
    ).scrape(
      'https://www.flipkart.com/apple-iphone-15-blue-128-gb/p/itm6ac6485515ae4',
    );
    expect(hit.price, 59900);
    expect(hit.pageProductId, 'MOBGTAGPAQNVFZZY');
    expect(hit.resolvedUrl, contains('pid=MOBGTAGPAQNVFZZY'));
  });

  test('Amazon buybox HTML returns 259 not MRP', () async {
    const html = '''
<html><head><title>The Alchemist</title></head><body>
<div id="corePriceDisplay_desktop_feature_div">
<span class="a-price reinventPricePriceToPayMargin priceToPay">
<span class="a-offscreen"> </span><span class="a-price-whole">259</span>
</span>
<div class="twister-plus-buying-options-price-data">{"desktop_buybox_group_1":[{"displayPrice":"₹259.00","priceAmount":259.00}]}</div>
</div>
</body></html>
''';
    final hit = await WatchHttpFetcher(
      dio: _stub(200, _pad(html)),
    ).scrape('https://www.amazon.in/dp/8172234988');
    expect(hit.price, 259);
    expect(hit.source, 'amazon.buybox');
  });

  test('gokuProps on a full PDP is not treated as a WAF interstitial', () async {
    final html = _pad('''
<html><head><title>The Alchemist</title>
<script>window.gokuProps = {}</script>
</head><body>
<div id="corePriceDisplay_desktop_feature_div">
<span class="a-price reinventPricePriceToPayMargin priceToPay">
<span class="a-offscreen"> </span><span class="a-price-whole">259</span>
</span>
<div class="twister-plus-buying-options-price-data">{"desktop_buybox_group_1":[{"displayPrice":"₹259.00","priceAmount":259.00}]}</div>
</div>
</body></html>
''').padRight(17000, 'x');
    final hit = await WatchHttpFetcher(
      dio: _stub(200, html),
    ).scrape('https://www.amazon.in/dp/8172234988');
    expect(hit.price, 259);
  });

  test('403 is retried then mapped to a phone-check message', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data: _pad('<html>no</html>'),
              statusCode: 403,
            ),
          );
        },
      ),
    );
    await expectLater(
      WatchHttpFetcher(dio: dio).scrape('https://www.amazon.in/dp/B0CXXXXXXX'),
      throwsA(
        isA<WatchScrapeException>().having(
          (e) => e.message,
          'message',
          contains('checking this phone'),
        ),
      ),
    );
    expect(calls, 3);
  });

  test('transient 500 is retried then succeeds', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          if (calls < 3) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 500),
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: _pad('''
<html><head>
<script type="application/ld+json">{"offers":{"price":"1299.00"}}</script>
<meta property="og:title" content="Sony">
</head><body></body></html>
'''),
            ),
          );
        },
      ),
    );
    final hit = await WatchHttpFetcher(dio: dio).scrape(
      'https://www.amazon.in/dp/B0CXXXXXXX',
    );
    expect(calls, 3);
    expect(hit.price, 1299);
  });

  test('Flipkart and Myntra keep desktop Chrome even on Android retry',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<List<String>> scrapeWithRetry(String url, String html) async {
      final uas = <String>[];
      final paths = <String>[];
      var n = 0;
      final dio =
          Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            n++;
            uas.add(options.headers['User-Agent'] as String);
            paths.add(options.uri.toString());
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: n == 1 ? 202 : 200,
                data: n == 1 ? _pad('<html><body>challenge</body></html>') : html,
              ),
            );
          },
        ),
      );
      await WatchHttpFetcher(dio: dio).scrape(url);
      expect(uas, hasLength(2));
      expect(uas, everyElement(contains('Windows NT')));
      expect(uas, everyElement(isNot(contains('Mobile Safari'))));
      expect(paths, everyElement(isNot(contains('/gp/aw/d/'))));
      return paths;
    }

    final fk = await scrapeWithRetry(
      'https://www.flipkart.com/x/p/itm1?pid=MOBGTAGPAQNVFZZY',
      _pad('''
<html><head>
<meta property="og:title" content="Apple iPhone 15">
<script type="application/ld+json">
[{"@type":"Product","sku":"MOBGTAGPAQNVFZZY","offers":{"price":59900}}]
</script>
</head><body></body></html>
'''),
    );
    expect(fk.last, contains('flipkart.com'));

    final my = await scrapeWithRetry(
      'https://www.myntra.com/18422728',
      _pad('''
<html><head>
<meta property="og:title" content="Lamp">
<script>window.__myx = {"pdpData":{"id":18422728,"name":"Lamp","price":{"mrp":7999,"discounted":3299}}}</script>
</head><body></body></html>
'''),
    );
    expect(my.last, contains('myntra.com'));
  });

  test('Swiggy always uses Android Chrome', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    String? ua;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          ua = options.headers['User-Agent'] as String;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: _pad(
                '<html><head><meta property="og:title" content="Amul">'
                '</head><body><script>{"offer_price":64}</script></body></html>',
              ),
            ),
          );
        },
      ),
    );
    await WatchHttpFetcher(dio: dio).scrape(
      'https://www.swiggy.com/instamart/item/abc?itemId=99',
    );
    expect(ua, contains('Mobile Safari'));
  });

  test('Amazon retry switches to mobile UA', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final uas = <String>[];
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          uas.add(options.headers['User-Agent'] as String);
          if (uas.length == 1) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                statusCode: 202,
                data: _pad('<html>window.gokuProps = {}</html>'),
              ),
            );
            return;
          }
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: _pad('''
<html><head><title>The Alchemist</title></head><body>
<div id="corePriceDisplay_desktop_feature_div">
<span class="a-price reinventPricePriceToPayMargin priceToPay">
<span class="a-price-whole">259</span>
</span>
<div class="twister-plus-buying-options-price-data">{"desktop_buybox_group_1":[{"displayPrice":"₹259.00","priceAmount":259.00}]}</div>
</div>
</body></html>
'''),
            ),
          );
        },
      ),
    );
    await WatchHttpFetcher(dio: dio).scrape(
      'https://www.amazon.in/dp/8172234988',
    );
    expect(uas.length, 2);
    expect(uas[0], contains('Windows NT'));
    expect(uas[1], contains('Mobile Safari'));
  });

  test('parse miss is retried then keeps excerpt for Gemini', () async {
    var calls = 0;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data: _pad(
                '<html><head><title>Widget</title></head><body>hello</body></html>',
              ),
              statusCode: 200,
            ),
          );
        },
      ),
    );
    await expectLater(
      WatchHttpFetcher(dio: dio).scrape('https://www.amazon.in/dp/B0CXXXXXXX'),
      throwsA(
        isA<WatchParseMissException>().having(
          (e) => e.excerpt,
          'excerpt',
          contains('Widget'),
        ),
      ),
    );
    expect(calls, 3);
  });
}
