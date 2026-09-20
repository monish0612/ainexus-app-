import '../page_harvest.dart';
import '../price_models.dart';
import '../price_parse.dart';

/// Live Myntra PDPs: `window.__myx.pdpData.price.discounted`. The old
/// `.pdp-price` class is often absent. Style id is the numeric path segment;
/// the slug can be wrong, so identity is the id.
ScrapeHit? scrapeMyntra(PageHarvest page) {
  final blob = _firstPrice(
    page.html,
    r'"price"\s*:\s*\{[^}]{0,120}"discounted"\s*:\s*([\d.]+)',
  );
  final ld = priceFrom(page.jsonLdPrice);
  final discounted = _firstPrice(page.html, r'"discounted"\s*:\s*([\d.]+)');
  final pdp = _firstPrice(page.html, r'"discountedPrice"\s*:\s*([\d.]+)');
  final dom = _firstPrice(
    page.html,
    r'class="[^"]*pdp-price[^"]*"[^>]*>\s*(?:<[^>]+>)*\s*([^<]{1,24})',
  );
  final preferred = blob ?? ld ?? discounted ?? pdp ?? dom;
  return pickHit(
    preferred: preferred,
    preferredSource: blob != null
        ? 'myntra.pdpData'
        : ld != null
            ? 'myntra.jsonld'
            : discounted != null
                ? 'myntra.discounted'
                : pdp != null
                    ? 'myntra.pdp'
                    : 'myntra.dom',
    fallbacks: const [],
    name: cleanTitle(_pdpName(page.html) ?? page.ogTitle),
    imageUrl: page.ogImage,
    outOfStock: page.outOfStock,
    preferredScore: blob != null || ld != null ? 92 : 68,
    pageProductId: _styleId(page.html),
  );
}

String? _styleId(String html) {
  final m = RegExp(r'"pdpData"\s*:\s*\{[^}]{0,80}"id"\s*:\s*(\d{5,})')
      .firstMatch(html);
  return m?.group(1);
}

String? _pdpName(String html) {
  final m = RegExp(
    r'"pdpData"\s*:\s*\{[^}]{0,200}"name"\s*:\s*"([^"]+)"',
  ).firstMatch(html);
  final name = m?.group(1)?.trim();
  if (name == null || name.isEmpty) return null;
  return name.replaceAll(r'\u002F', '/');
}

double? _firstPrice(String html, String pattern) {
  final m = RegExp(pattern, caseSensitive: false, dotAll: true).firstMatch(html);
  return parsePrice(m?.group(1));
}
