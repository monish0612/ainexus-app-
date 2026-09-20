import '../adapters/ajio.dart';
import '../adapters/amazon_in.dart';
import '../adapters/croma.dart';
import '../adapters/firstcry.dart';
import '../adapters/flipkart.dart';
import '../adapters/generic.dart';
import '../adapters/jiomart.dart';
import '../adapters/myntra.dart';
import '../adapters/nykaa.dart';
import '../adapters/pepperfry.dart';
import '../adapters/purplle.dart';
import '../adapters/snapdeal.dart';
import '../adapters/swiggy.dart';
import '../adapters/tatacliq.dart';
import '../page_harvest.dart';
import '../price_models.dart';
import '../store_url.dart';
import 'store_profile.dart';

/// Single switch for scrape / UA / referer. URL parsing lives in
/// [canonicalizeWatchUrl] so tests can exercise shops without Dio.
class StoreCatalog {
  StoreCatalog._();

  static StoreProfile of(WatchStore store) {
    switch (store) {
      case WatchStore.amazon:
        return amazon;
      case WatchStore.flipkart:
        return flipkart;
      case WatchStore.myntra:
        return myntra;
      case WatchStore.swiggy:
        return swiggy;
      case WatchStore.ajio:
        return ajio;
      case WatchStore.snapdeal:
        return snapdeal;
      case WatchStore.jiomart:
        return jiomart;
      case WatchStore.tatacliq:
        return tatacliq;
      case WatchStore.nykaa:
        return nykaa;
      case WatchStore.nykaaFashion:
        return nykaaFashion;
      case WatchStore.pepperfry:
        return pepperfry;
      case WatchStore.firstcry:
        return firstcry;
      case WatchStore.croma:
        return croma;
      case WatchStore.purplle:
        return purplle;
      case WatchStore.other:
        return other;
    }
  }

  static ScrapeHit? scrape(WatchStore store, PageHarvest page) =>
      of(store).scrape(page);

  /// Cookie jar bucket so Amazon WAF tokens are not sent to Flipkart.
  static String cookieBucket(String host) {
    final h = host.toLowerCase();
    final canon = canonicalizeWatchUrl('https://$h/');
    if (canon != null && canon.store != WatchStore.other) {
      return canon.store.id;
    }
    if (h.contains('amazon') || h.contains('amzn') || h == 'a.co') {
      return WatchStore.amazon.id;
    }
    if (h.contains('flipkart') || h.contains('fkrt')) {
      return WatchStore.flipkart.id;
    }
    if (h.contains('myntra') || h.contains('myntr')) {
      return WatchStore.myntra.id;
    }
    if (h.contains('swiggy')) return WatchStore.swiggy.id;
    return h;
  }

  static const amazon = StoreProfile(
    store: WatchStore.amazon,
    refererHost: 'www.amazon.in',
    ua: WatchUserAgent.amazon,
    scrape: scrapeAmazon,
    rewriteMobilePdp: true,
  );

  static const flipkart = StoreProfile(
    store: WatchStore.flipkart,
    refererHost: 'www.flipkart.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeFlipkart,
  );

  static const myntra = StoreProfile(
    store: WatchStore.myntra,
    refererHost: 'www.myntra.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeMyntra,
  );

  static const swiggy = StoreProfile(
    store: WatchStore.swiggy,
    refererHost: 'www.swiggy.com',
    ua: WatchUserAgent.mobile,
    scrape: scrapeSwiggy,
  );

  static const ajio = StoreProfile(
    store: WatchStore.ajio,
    refererHost: 'www.ajio.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeAjio,
  );

  static const snapdeal = StoreProfile(
    store: WatchStore.snapdeal,
    refererHost: 'www.snapdeal.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeSnapdeal,
  );

  static const jiomart = StoreProfile(
    store: WatchStore.jiomart,
    refererHost: 'www.jiomart.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeJiomart,
  );

  static const tatacliq = StoreProfile(
    store: WatchStore.tatacliq,
    refererHost: 'www.tatacliq.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeTatacliq,
  );

  static const nykaa = StoreProfile(
    store: WatchStore.nykaa,
    refererHost: 'www.nykaa.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeNykaa,
  );

  static const nykaaFashion = StoreProfile(
    store: WatchStore.nykaaFashion,
    refererHost: 'www.nykaafashion.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeNykaaFashion,
  );

  static const pepperfry = StoreProfile(
    store: WatchStore.pepperfry,
    refererHost: 'www.pepperfry.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapePepperfry,
  );

  static const firstcry = StoreProfile(
    store: WatchStore.firstcry,
    refererHost: 'www.firstcry.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeFirstcry,
  );

  static const croma = StoreProfile(
    store: WatchStore.croma,
    refererHost: 'www.croma.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapeCroma,
  );

  static const purplle = StoreProfile(
    store: WatchStore.purplle,
    refererHost: 'www.purplle.com',
    ua: WatchUserAgent.desktop,
    scrape: scrapePurplle,
  );

  static const other = StoreProfile(
    store: WatchStore.other,
    refererHost: '',
    ua: WatchUserAgent.desktop,
    scrape: scrapeGeneric,
  );
}
