import '../page_harvest.dart';
import '../price_models.dart';
import '../price_parse.dart';

/// Live Amazon.in PDPs (2026): buybox JSON + `#corePriceDisplay_*`.
/// Page-wide `a-offscreen` is MRP / related-ASIN junk and must not win.
/// Live pages often have no og:title / JSON-LD; `productTitle` + buybox do.
ScrapeHit? scrapeAmazon(PageHarvest page) {
  final buybox = _buyboxAmount(page.html);
  final core = _corePrice(page.html);
  final ld = priceFrom(page.jsonLdPrice);
  final amount = _firstPrice(
    page.html,
    r'twister-plus-buying-options-price-data[\s\S]{0,400}?"priceAmount"\s*:\s*([\d.]+)',
  );
  final preferred = buybox ?? core ?? ld ?? amount;
  return pickHit(
    preferred: preferred,
    preferredSource: buybox != null
        ? 'amazon.buybox'
        : core != null
            ? 'amazon.corePrice'
            : ld != null
                ? 'amazon.jsonld'
                : 'amazon.priceAmount',
    fallbacks: const [],
    name: cleanTitle(_productTitle(page.html) ?? page.ogTitle),
    imageUrl: page.ogImage.isNotEmpty
        ? page.ogImage
        : (_amazonImage(page.html) ?? ''),
    outOfStock: page.outOfStock,
    preferredScore: (buybox != null || core != null || ld != null) ? 92 : 70,
  );
}

double? _buyboxAmount(String html) {
  final amount = RegExp(
    r'"(?:desktop_buybox_group_1|mobile_buybox_group_1)"\s*:\s*\[\s*\{[^}\]]{0,400}?"priceAmount"\s*:\s*([\d.]+)',
    caseSensitive: false,
  ).firstMatch(html);
  if (amount != null) return parsePrice(amount.group(1));
  final display = RegExp(
    r'"(?:desktop_buybox_group_1|mobile_buybox_group_1)"\s*:\s*\[\s*\{[^}\]]{0,400}?"displayPrice"\s*:\s*"([^"]+)"',
    caseSensitive: false,
  ).firstMatch(html);
  return parsePrice(display?.group(1));
}

double? _corePrice(String html) {
  final window = _buyboxWindow(html);
  if (window == null) return null;
  final offscreen = _liveOffscreen(window);
  if (offscreen != null) return offscreen;
  final whole = _wholeFraction(window) ?? _wholeOnly(window);
  if (whole != null) return whole;
  final access = RegExp(
    r'id="apex-pricetopay-accessibility-label"[^>]*>\s*([^<]{1,80})',
    caseSensitive: false,
  ).firstMatch(window);
  return parsePrice(access?.group(1));
}

String? _buyboxWindow(String html) {
  for (final needle in [
    'id="corePriceDisplay_desktop_feature_div"',
    'id="corePriceDisplay_mobile_feature_div"',
    'id="corePrice_desktop"',
    'id="corePrice_mobile"',
    'class="apex-price-to-pay-value"',
    'reinventPricePriceToPayMargin priceToPay',
  ]) {
    final idx = html.indexOf(needle);
    if (idx < 0) continue;
    final end = (idx + 9000).clamp(0, html.length);
    return html.substring(idx, end);
  }
  return null;
}

double? _liveOffscreen(String html) {
  final rx = RegExp(
    r'<span[^>]*class="([^"]*a-price[^"]*)"[^>]*>[\s\S]{0,360}?class="a-offscreen"[^>]*>\s*([^<]{1,48})',
    caseSensitive: false,
  );
  for (final m in rx.allMatches(html)) {
    final cls = m.group(1)!.toLowerCase();
    if (cls.contains('a-text-price') || cls.contains('a-price-range')) {
      continue;
    }
    final n = parsePrice(m.group(2));
    if (n != null) return n;
  }
  return null;
}

double? _wholeFraction(String html) {
  final m = RegExp(
    r'class="a-price-whole"[^>]*>([\d.,]+).*?class="a-price-fraction"[^>]*>(\d{1,2})',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html);
  if (m == null) return null;
  final whole = m.group(1)!.replaceAll(RegExp(r'[.,]+$'), '');
  return parsePrice('${whole}.${m.group(2)}');
}

double? _wholeOnly(String html) {
  final m = RegExp(
    r'class="a-price-whole"[^>]*>([\d.,]+)',
    caseSensitive: false,
  ).firstMatch(html);
  return parsePrice(m?.group(1));
}

double? _firstPrice(String html, String pattern) {
  final m = RegExp(pattern, caseSensitive: false, dotAll: true).firstMatch(html);
  return parsePrice(m?.group(1));
}

String? _productTitle(String html) {
  final m = RegExp(
    r'id="productTitle"[^>]*>\s*([^<]+)',
    caseSensitive: false,
  ).firstMatch(html);
  final t = m?.group(1)?.trim();
  if (t != null && t.isNotEmpty) return t;
  return null;
}

String? _amazonImage(String html) {
  final hires = RegExp(
    r'data-old-hires="(https://[^"]+)"',
    caseSensitive: false,
  ).firstMatch(html);
  if (hires != null) return hires.group(1);
  final wrap = RegExp(
    r'id="imgTagWrapperId"[\s\S]{0,800}?src="(https://[^"]+)"',
    caseSensitive: false,
  ).firstMatch(html);
  return wrap?.group(1);
}
