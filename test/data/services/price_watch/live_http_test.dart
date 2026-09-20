import 'package:ai_nexus/data/services/price_watch/price_models.dart';
import 'package:ai_nexus/data/services/price_watch/watch_http_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hits the live storefronts. Skips a store if it challenges/blocks us so
/// CI does not flake; a pass here is the real end-to-end proof.
void main() {
  const timeout = Timeout(Duration(seconds: 40));

  Future<ScrapeHit?> tryScrape(String url) async {
    try {
      return await WatchHttpFetcher().scrape(url);
    } on WatchScrapeException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('challenge') ||
          m.contains('checking this phone') ||
          m.contains('blocked') ||
          m.contains('404') ||
          m.contains('empty')) {
        return null;
      }
      rethrow;
    }
  }

  test('Amazon.in product page scrape', () async {
    final hit = await tryScrape('https://www.amazon.in/dp/8172234988');
    if (hit == null) {
      markTestSkipped('Amazon blocked or challenged this HTTP fetch');
      return;
    }
    expect(hit.price, greaterThan(50));
    expect(hit.price, lessThan(5000));
    expect(hit.name.toLowerCase(), contains('alchemist'));
  }, timeout: timeout);

  test('Flipkart product page scrape', () async {
    final hit = await tryScrape(
      'https://www.flipkart.com/apple-iphone-15-blue-128-gb/p/itm6ac6485515ae4?pid=MOBGTAGPAQNVFZZY',
    );
    if (hit == null) {
      markTestSkipped('Flipkart blocked or challenged this HTTP fetch');
      return;
    }
    expect(hit.price, greaterThan(10000));
    expect(hit.pageProductId, 'MOBGTAGPAQNVFZZY');
  }, timeout: timeout);

  test('Flipkart share URL with affid still scrapes the same SKU', () async {
    final hit = await tryScrape(
      'https://www.flipkart.com/apple-iphone-15-blue-128-gb/p/itm6ac6485515ae4?pid=MOBGTAGPAQNVFZZY&affid=partner&utm_source=share',
    );
    if (hit == null) {
      markTestSkipped('Flipkart blocked or challenged this HTTP fetch');
      return;
    }
    expect(hit.price, greaterThan(10000));
    expect(hit.pageProductId, 'MOBGTAGPAQNVFZZY');
  }, timeout: timeout);

  test('Myntra style page scrape', () async {
    final hit = await tryScrape('https://www.myntra.com/18422728');
    if (hit == null) {
      markTestSkipped('Myntra blocked or challenged this HTTP fetch');
      return;
    }
    expect(hit.price, greaterThan(200));
  }, timeout: timeout);

  test('Myntra slug buy URL still scrapes the style id', () async {
    final hit = await tryScrape(
      'https://www.myntra.com/home-furnishing/devansh/foo/18422728/buy?utm_source=share',
    );
    if (hit == null) {
      markTestSkipped('Myntra blocked or challenged this HTTP fetch');
      return;
    }
    expect(hit.price, greaterThan(200));
  }, timeout: timeout);

  test('Swiggy city and restaurant pages are rejected before fetch', () {
    expect(
      () => WatchHttpFetcher().scrape('https://www.swiggy.com/city/chennai'),
      throwsA(
        isA<WatchScrapeException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported'),
        ),
      ),
    );
    expect(
      () => WatchHttpFetcher().scrape(
        'https://www.swiggy.com/restaurants/meghana-foods-residency-road-central-bangalore-3241',
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

  test('Swiggy restaurant HTTP is not treated as an item price', () async {
    expect(
      () => WatchHttpFetcher().scrape(
        'https://www.swiggy.com/instamart/item/abc?itemId=99',
      ),
      throwsA(isA<WatchScrapeException>()),
    );
  }, timeout: timeout);
}
