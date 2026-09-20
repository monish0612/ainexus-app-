import '../page_harvest.dart';
import '../price_models.dart';
import '../price_parse.dart';

/// JSON-LD / Open Graph product price. Never median-scans the page — a
/// listing or blog with stray rupee amounts must not invent a hit.
ScrapeHit? scrapeStructured(
  PageHarvest page, {
  required String source,
  double? preferred,
  String? preferredSource,
  String? pageProductId,
  int preferredScore = 84,
}) {
  final ld = priceFrom(page.jsonLdPrice);
  final og = priceFrom(page.ogPrice);
  final chosen = preferred ?? ld ?? og;
  if (chosen == null) return null;
  return pickHit(
    preferred: chosen,
    preferredSource: preferred != null
        ? (preferredSource ?? source)
        : ld != null
            ? '$source.jsonld'
            : '$source.og',
    fallbacks: const [],
    name: cleanTitle(page.ogTitle),
    imageUrl: page.ogImage,
    outOfStock: page.outOfStock,
    preferredScore: preferred != null || ld != null ? preferredScore : 72,
    pageProductId: pageProductId ?? page.jsonLdSku,
  );
}

double? firstPrice(String html, String pattern) {
  final m = RegExp(pattern, caseSensitive: false, dotAll: true).firstMatch(html);
  return parsePrice(m?.group(1));
}
