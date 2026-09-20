import '../page_harvest.dart';
import '../price_models.dart';
import '../price_parse.dart';

/// Live Flipkart PDPs (2026): JSON-LD `offers.price` and a bare
/// `"finalPrice":59900` number. Hashed CSS (`Nx9bqj`) is gone; `sellingPrice`
/// objects are often missing. `pid` / `sku` is the SKU, not the `/p/itm…` slug.
ScrapeHit? scrapeFlipkart(PageHarvest page) {
  final ld = priceFrom(page.jsonLdPrice);
  final finalPlain = _firstPrice(page.html, r'"finalPrice"\s*:\s*([\d.]+)');
  final finalObj = _firstPrice(
    page.html,
    r'"finalPrice"\s*:\s*\{[^}]{0,160}"value"\s*:\s*([\d.]+)',
  );
  final sellingObj = _firstPrice(
    page.html,
    r'"sellingPrice"\s*:\s*\{[^}]{0,160}"value"\s*:\s*([\d.]+)',
  );
  final sellingPlain = _firstPrice(page.html, r'"sellingPrice"\s*:\s*([\d.]+)');
  final hashed = _firstPrice(
    page.html,
    r'class="[^"]*(?:Nx9bqj|hl05eU)[^"]*"[^>]*>([^<]{1,24})',
  );
  final preferred =
      ld ?? finalPlain ?? finalObj ?? sellingObj ?? sellingPlain ?? hashed;
  return pickHit(
    preferred: preferred,
    preferredSource: ld != null
        ? 'flipkart.jsonld'
        : finalPlain != null || finalObj != null
            ? 'flipkart.finalPrice'
            : sellingObj != null || sellingPlain != null
                ? 'flipkart.sellingPrice'
                : 'flipkart.dom',
    fallbacks: const [],
    name: cleanTitle(page.ogTitle),
    imageUrl: page.ogImage,
    outOfStock: page.outOfStock,
    preferredScore: ld != null || finalPlain != null ? 92 : 68,
    pageProductId: _sku(page.html),
  );
}

String? _sku(String html) {
  final m = RegExp(r'"sku"\s*:\s*"([A-Z0-9]{8,})"', caseSensitive: false)
          .firstMatch(html) ??
      RegExp(r'"pid"\s*:\s*"([A-Z0-9]{8,})"', caseSensitive: false)
          .firstMatch(html);
  return m?.group(1);
}

double? _firstPrice(String html, String pattern) {
  final m = RegExp(pattern, caseSensitive: false, dotAll: true).firstMatch(html);
  return parsePrice(m?.group(1));
}
