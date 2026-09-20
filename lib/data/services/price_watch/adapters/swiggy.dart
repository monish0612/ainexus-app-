import '../page_harvest.dart';
import '../price_models.dart';
import '../price_parse.dart';

/// Instamart SKUs leak `offer_price` / `finalPrice`. Food restaurant pages
/// are a client-rendered shell (or a WAF interstitial) over HTTP — never
/// invent a price from ratings or `costForTwo`. Item deep-links need
/// `itemId` / `spinId` in the URL.
ScrapeHit? scrapeSwiggy(PageHarvest page) {
  final ld = priceFrom(page.jsonLdPrice);
  final offer = _firstPrice(page.html, r'"offer_price"\s*:\s*([\d.]+)');
  final finalPrice = _firstPrice(page.html, r'"finalPrice"\s*:\s*([\d.]+)');
  final spin = _firstPrice(page.html, r'"spin_price"\s*:\s*([\d.]+)');
  final named = _firstPrice(
    page.html,
    r'"(?:offerPrice|discountedPrice|itemPrice|defaultPrice)"\s*:\s*([\d.]+)',
  );
  final preferred = ld ?? offer ?? finalPrice ?? spin ?? named;
  if (preferred == null) {
    // No structured item price — restaurant shells must not median-scan.
    return null;
  }
  return pickHit(
    preferred: preferred,
    preferredSource: ld != null
        ? 'swiggy.jsonld'
        : offer != null
            ? 'swiggy.offer_price'
            : finalPrice != null
                ? 'swiggy.finalPrice'
                : spin != null
                    ? 'swiggy.spin_price'
                    : 'swiggy.scan',
    fallbacks: const [],
    name: cleanTitle(page.ogTitle),
    imageUrl: page.ogImage,
    outOfStock: page.outOfStock,
    preferredScore: ld != null || offer != null ? 88 : 70,
    pageProductId: _itemId(page.html) ?? _restId(page.finalUrl),
  );
}

String? _itemId(String html) {
  final m = RegExp(r'"(?:spinId|itemId|item_id)"\s*:\s*"?([^",}]+)"?')
      .firstMatch(html);
  return m?.group(1);
}

String? _restId(String url) {
  return RegExp(r'-rest(\d+)', caseSensitive: false).firstMatch(url)?.group(1);
}

double? _firstPrice(String html, String pattern) {
  final m = RegExp(pattern, caseSensitive: false, dotAll: true).firstMatch(html);
  return parsePrice(m?.group(1));
}
