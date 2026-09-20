import 'price_models.dart';
import 'price_parse.dart';

/// Shared HTML / JSON harvest used by every store adapter.
class PageHarvest {
  const PageHarvest({
    required this.html,
    required this.finalUrl,
  });

  final String html;
  final String finalUrl;

  String get ogTitle =>
      _meta('og:title') ?? _namedMeta('title') ?? _tagTitle ?? '';
  String get ogImage => _meta('og:image') ?? '';
  String? get ogPrice =>
      _meta('product:price:amount') ?? _meta('og:price:amount');
  String? get jsonLdSku {
    for (final block in _jsonLdBlocks()) {
      final m = RegExp(
        r'"(?:sku|productID|gtin13|gtin|mpn)"\s*:\s*"([^"]+)"',
        caseSensitive: false,
      ).firstMatch(block);
      final v = m?.group(1)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  String? get jsonLdPrice {
    final blocks = _jsonLdBlocks().toList();
    for (final block in blocks) {
      if (!_looksLikeOffer(block)) continue;
      final fromOffers = _firstIn(
        block,
        const [
          r'"price"\s*:\s*"?([\d.,]+)"?',
          r'"lowPrice"\s*:\s*"?([\d.,]+)"?',
        ],
      );
      if (fromOffers != null) return fromOffers;
    }
    for (final block in blocks) {
      final fromOffers = _firstIn(
        block,
        const [
          r'"price"\s*:\s*"?([\d.,]+)"?',
          r'"lowPrice"\s*:\s*"?([\d.,]+)"?',
        ],
      );
      if (fromOffers != null) return fromOffers;
    }
    return null;
  }

  bool _looksLikeOffer(String block) {
    final low = block.toLowerCase();
    return low.contains('product') ||
        low.contains('offer') ||
        low.contains('aggregateoffer');
  }

  bool get outOfStock {
    final hay = html.toLowerCase();
    return hay.contains('out of stock') ||
        hay.contains('currently unavailable') ||
        hay.contains('"availability":"https://schema.org/outofstock"') ||
        hay.contains('outofstock');
  }

  String? _meta(String property) {
    final quoted = RegExp(
      'property=["\']$property["\'][^>]*content=["\']([^"\']+)["\']'
      '|content=["\']([^"\']+)["\'][^>]*property=["\']$property["\']',
      caseSensitive: false,
    ).firstMatch(html);
    return quoted?.group(1) ?? quoted?.group(2);
  }

  String? _namedMeta(String name) {
    final m = RegExp(
      'name=["\']$name["\'][^>]*content=["\']([^"\']+)["\']'
      '|content=["\']([^"\']+)["\'][^>]*name=["\']$name["\']',
      caseSensitive: false,
    ).firstMatch(html);
    return m?.group(1) ?? m?.group(2);
  }

  String? get _tagTitle {
    final m = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
        .firstMatch(html);
    return m?.group(1)?.trim();
  }

  Iterable<String> _jsonLdBlocks() {
    return RegExp(
      r'<script[^>]*application/ld\+json[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html).map((m) => m.group(1) ?? '');
  }

  /// Compact page digest for Gemini Flash. Never the raw HTML dump.
  String llmExcerpt({int maxChars = 5500}) {
    final buf = StringBuffer()
      ..writeln('url: $finalUrl')
      ..writeln('title: $ogTitle');
    if (ogImage.isNotEmpty) buf.writeln('og_image: $ogImage');
    if (ogPrice != null) buf.writeln('og_price: $ogPrice');
    if (jsonLdPrice != null) buf.writeln('jsonld_price: $jsonLdPrice');
    if (jsonLdSku != null) buf.writeln('sku: $jsonLdSku');
    final ld = _jsonLdBlocks().take(2).join('\n');
    if (ld.isNotEmpty) {
      buf.writeln('jsonld:');
      buf.writeln(ld.length > 1800 ? ld.substring(0, 1800) : ld);
    }
    buf.writeln('text:');
    buf.writeln(_visibleText());
    final s = buf.toString();
    if (s.length <= maxChars) return s;
    return s.substring(0, maxChars);
  }

  String _visibleText() {
    var t = html
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.length > 2400) t = t.substring(0, 2400);
    return t;
  }
}

String? _firstIn(String hay, List<String> patterns) {
  for (final p in patterns) {
    final m = RegExp(p, caseSensitive: false).firstMatch(hay);
    final raw = m?.group(1);
    if (raw != null && parsePrice(raw) != null) return raw;
  }
  return null;
}

double? priceFrom(String? raw) => parsePrice(raw);

String cleanTitle(String raw) {
  return raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*[|:].*$'), '')
      .replaceAll(
        RegExp(
          r'\s*[-–]\s*(amazon\.in|flipkart|myntra|swiggy|ajio|nykaa|croma|jiomart|tatacliq|snapdeal|pepperfry|firstcry|purplle).*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
}

ScrapeHit? pickHit({
  required double? preferred,
  required String preferredSource,
  required List<double> fallbacks,
  required String name,
  required String imageUrl,
  required bool outOfStock,
  int preferredScore = 88,
  String? pageProductId,
}) {
  final price = preferred ??
      (fallbacks.isEmpty
          ? null
          : (fallbacks.length == 1
              ? fallbacks.first
              : _medianish(fallbacks)));
  if (price == null) return null;
  var score = preferred != null ? preferredScore : 62;
  if (preferred == null && fallbacks.length > 3) score = 48;
  return ScrapeHit(
    price: price,
    source: preferred != null ? preferredSource : 'scan',
    name: name,
    imageUrl: imageUrl,
    availability: outOfStock ? 'OUT_OF_STOCK' : null,
    score: score,
    pageProductId: pageProductId,
  );
}

double _medianish(List<double> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}
