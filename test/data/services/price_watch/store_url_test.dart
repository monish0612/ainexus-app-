import 'package:ai_nexus/core/utils/tidy_url.dart';
import 'package:ai_nexus/data/services/price_watch/store_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonicalizeWatchUrl', () {
    test('Amazon share ref=cm_sw_r_apan_dp keeps ASIN', () {
      final c = canonicalizeWatchUrl(
        'https://www.amazon.in/dp/B0CXXXXXXX/ref=cm_sw_r_apan_dp_YOAZEN2KKJMWNMK3HT5R',
      )!;
      expect(c.store, WatchStore.amazon);
      expect(c.productId, 'B0CXXXXXXX');
      expect(c.url, 'https://www.amazon.in/dp/B0CXXXXXXX');
    });

    test('Amazon slug /Name/dp/ASIN', () {
      final c = canonicalizeWatchUrl(
        'https://www.amazon.in/Alchemist-Paulo-Coelho/dp/8172234988/ref=sr_1_1',
      )!;
      expect(c.productId, '8172234988');
      expect(c.url, 'https://www.amazon.in/dp/8172234988');
    });

    test('Amazon gp/product path', () {
      final c = canonicalizeWatchUrl(
        'https://www.amazon.in/gp/product/B09ABCDEFG/ref=xx',
      )!;
      expect(c.productId, 'B09ABCDEFG');
      expect(c.url, 'https://www.amazon.in/dp/B09ABCDEFG');
    });

    test('Amazon.com ASIN still lands on amazon.in', () {
      final c = canonicalizeWatchUrl('https://www.amazon.com/dp/B0CXXXXXXX')!;
      expect(c.url, 'https://www.amazon.in/dp/B0CXXXXXXX');
    });

    test('Amazon search and home are rejected', () {
      expect(canonicalizeWatchUrl('https://www.amazon.in/s?k=iphone'), isNull);
      expect(canonicalizeWatchUrl('https://www.amazon.in/'), isNull);
    });

    test('Flipkart keeps pid', () {
      final c = canonicalizeWatchUrl(
        'https://www.flipkart.com/foo/p/itmabc123?pid=MOBXYZ&affid=x',
      )!;
      expect(c.store, WatchStore.flipkart);
      expect(c.productId, 'MOBXYZ');
      expect(c.url, contains('pid=MOBXYZ'));
      expect(c.url, isNot(contains('affid')));
    });

    test('Flipkart search and listing are rejected', () {
      expect(
        canonicalizeWatchUrl('https://www.flipkart.com/search?q=iphone'),
        isNull,
      );
      expect(
        canonicalizeWatchUrl('https://www.flipkart.com/laptops/pr?sid=6bo'),
        isNull,
      );
    });

    test('Myntra buy path collapses to style id', () {
      final c = canonicalizeWatchUrl(
        'https://www.myntra.com/shoes/nike/foo/12345678/buy?utm=1',
      )!;
      expect(c.store, WatchStore.myntra);
      expect(c.productId, '12345678');
      expect(c.url, 'https://www.myntra.com/12345678');
    });

    test('Myntra without /buy still uses the numeric id', () {
      final c = canonicalizeWatchUrl(
        'https://www.myntra.com/tshirts/roadster/foo/18422728',
      )!;
      expect(c.productId, '18422728');
      expect(c.url, 'https://www.myntra.com/18422728');
    });

    test('Myntra listing without style id is rejected', () {
      expect(canonicalizeWatchUrl('https://www.myntra.com/men-tshirts'), isNull);
    });

    test('Flipkart and Myntra share junk still canonicalize', () {
      final fk = canonicalizeWatchUrl(
        'https://www.flipkart.com/apple-iphone-15-blue-128-gb/p/itm6ac6485515ae4?pid=MOBGTAGPAQNVFZZY&affid=x&utm_source=share',
      )!;
      expect(fk.productId, 'MOBGTAGPAQNVFZZY');
      expect(fk.url, contains('pid=MOBGTAGPAQNVFZZY'));
      expect(fk.url, isNot(contains('utm_')));
      expect(fk.url, isNot(contains('affid')));

      final my = canonicalizeWatchUrl(
        'https://www.myntra.com/home-furnishing/devansh/foo/18422728/buy?utm_source=share&utm_medium=app',
      )!;
      expect(my.productId, '18422728');
      expect(my.url, 'https://www.myntra.com/18422728');
    });

    test('Swiggy keeps store/item query', () {
      final c = canonicalizeWatchUrl(
        'https://www.swiggy.com/instamart/item/abc?storeId=12&itemId=99&foo=1',
      )!;
      expect(c.store, WatchStore.swiggy);
      expect(c.url, contains('storeId=12'));
      expect(c.url, contains('itemId=99'));
      expect(c.url, isNot(contains('foo=')));
    });

    test('Swiggy city and restaurant-only pages are rejected', () {
      expect(canonicalizeWatchUrl('https://www.swiggy.com/city/chennai'), isNull);
      expect(
        canonicalizeWatchUrl(
          'https://www.swiggy.com/city/bangalore/meghana-foods-central-bangalore-rest3241',
        ),
        isNull,
      );
      expect(
        canonicalizeWatchUrl(
          'https://www.swiggy.com/restaurants/meghana-foods-residency-road-central-bangalore-3241',
        ),
        isNull,
      );
    });

    test('Swiggy restaurant plus itemId is accepted', () {
      final c = canonicalizeWatchUrl(
        'https://www.swiggy.com/city/bangalore/foo-rest3241?itemId=99',
      )!;
      expect(c.productId, '99');
    });

    test('share text extracts first http URL', () {
      final c = canonicalizeWatchUrl(
        'Check this https://www.amazon.in/dp/B0CXXXXXXX wow',
      );
      expect(c?.productId, 'B0CXXXXXXX');
    });

    test('unknown host is rejected', () {
      expect(canonicalizeWatchUrl('https://www.google.com/search?q=x'), isNull);
    });

    test('Ajio /p/code is identity', () {
      final c = canonicalizeWatchUrl(
        'https://www.ajio.com/s.oliver-navy-shirt/p/441137043003?utm_source=share',
      )!;
      expect(c.store, WatchStore.ajio);
      expect(c.productId, '441137043003');
      expect(c.identityKey, 'ajio:441137043003');
    });

    test('Nykaa and Nykaa Fashion keep numeric id', () {
      final n = canonicalizeWatchUrl(
        'https://www.nykaa.com/mcaffeine-coffee/p/1234567?utm=1',
      )!;
      expect(n.store, WatchStore.nykaa);
      expect(n.productId, '1234567');

      final f = canonicalizeWatchUrl(
        'https://www.nykaafashion.com/levi-s-tee/p/7654321',
      )!;
      expect(f.store, WatchStore.nykaaFashion);
      expect(f.productId, '7654321');
    });

    test('Croma /p/id and Tata CLiQ p-mp id', () {
      final c = canonicalizeWatchUrl(
        'https://www.croma.com/apple-iphone-15/p/271717',
      )!;
      expect(c.store, WatchStore.croma);
      expect(c.productId, '271717');

      final t = canonicalizeWatchUrl(
        'https://www.tatacliq.com/apple-iphone-15/p-mp000000012345678',
      )!;
      expect(t.store, WatchStore.tatacliq);
      expect(t.productId, 'p-mp000000012345678');
    });

    test('JioMart, Snapdeal, Purplle, FirstCry, Pepperfry', () {
      expect(
        canonicalizeWatchUrl(
          'https://www.jiomart.com/p/groceries/fortune-sunflower/590004047',
        )?.productId,
        '590004047',
      );
      expect(
        canonicalizeWatchUrl(
          'https://www.snapdeal.com/product/asian-running-shoes/123456789',
        )?.productId,
        '123456789',
      );
      expect(
        canonicalizeWatchUrl(
          'https://www.purplle.com/product/maybelline-fit-me',
        )?.productId,
        'maybelline-fit-me',
      );
      expect(
        canonicalizeWatchUrl(
          'https://www.firstcry.com/huggies/4455667/product-detail',
        )?.productId,
        '4455667',
      );
      expect(
        canonicalizeWatchUrl(
          'https://www.pepperfry.com/casacraft-sofa.html?item_id=998877',
        )?.productId,
        '998877',
      );
    });

    test('generic product path is other; google still rejected', () {
      final g = canonicalizeWatchUrl(
        'https://www.example-boutique.com/product/blue-shirt?utm_source=x',
      )!;
      expect(g.store, WatchStore.other);
      expect(g.url, isNot(contains('utm_')));
      expect(canonicalizeWatchUrl('https://www.google.com/product/x'), isNull);
      final deep = canonicalizeWatchUrl(
        'https://www.example-boutique.com/shop/blue-linen-shirt',
      );
      expect(deep?.store, WatchStore.other);
    });

    test('bit.ly shortener is accepted as other until redirect', () {
      final c = canonicalizeWatchUrl('https://bit.ly/abc123');
      expect(c?.store, WatchStore.other);
    });

    test('preferResolvedCanonical upgrades other to Amazon', () {
      final short = canonicalizeWatchUrl('https://bit.ly/abc123')!;
      final better = preferResolvedCanonical(
        short,
        'https://www.amazon.in/dp/B0CXXXXXXX?th=1',
      );
      expect(better.store, WatchStore.amazon);
      expect(better.productId, 'B0CXXXXXXX');
    });
  });

  test('isWatchStoreUrl', () {
    expect(isWatchStoreUrl('https://www.flipkart.com/x/p/itm1?pid=A'), isTrue);
    expect(isWatchStoreUrl('hello world'), isFalse);
    expect(
      isWatchShareCandidate(
        'https://www.example-boutique.com/shop/blue-linen-shirt',
      ),
      isTrue,
    );
    expect(isWatchShareCandidate('https://www.google.com/maps/place/x'), isFalse);
    expect(isWatchShareCandidate('https://www.ndtv.com/'), isFalse);
  });

  test('preferResolvedCanonical follows same-store redirect', () {
    final short = canonicalizeWatchUrl('https://amzn.in/d/abcde12')!;
    final better = preferResolvedCanonical(
      short,
      'https://www.amazon.in/dp/B0CXXXXXXX?th=1',
    );
    expect(better.url, 'https://www.amazon.in/dp/B0CXXXXXXX');
    expect(better.productId, 'B0CXXXXXXX');
  });

  test('extracts store URL wrapped in punctuation / WhatsApp noise', () {
    final amazon = canonicalizeWatchUrl(
      'Buy now (https://www.amazon.in/dp/B0CXXXXXXX).',
    );
    expect(amazon?.productId, 'B0CXXXXXXX');

    final flipkart = canonicalizeWatchUrl(
      'https://www.flipkart.com/foo/p/itmabc123?pid=MOBXYZ&utm_source=share\n\nSent from my phone',
    );
    expect(flipkart?.productId, 'MOBXYZ');
    expect(flipkart?.url, contains('pid=MOBXYZ'));
  });

  test('TidyUrl must not steal Flipkart pid before Watch canonicalize', () {
    const raw =
        'https://www.flipkart.com/foo/p/itmabc123?pid=MOBXYZ&affid=x&utm_source=share';
    expect(TidyUrl.cleanUrl(raw), contains('pid=MOBXYZ'));
    expect(TidyUrl.cleanUrl(raw), isNot(contains('affid')));
    expect(canonicalizeWatchUrl(raw)?.productId, 'MOBXYZ');
  });
}
