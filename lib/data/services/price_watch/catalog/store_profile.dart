import '../page_harvest.dart';
import '../price_models.dart';
import '../store_url.dart';

/// Per-shop HTTP identity. New stores register a profile; the fetcher
/// never learns shop-specific ifs besides this table.
enum WatchUserAgent {
  desktop,
  mobile,
  amazon,
}

class StoreProfile {
  const StoreProfile({
    required this.store,
    required this.refererHost,
    required this.ua,
    required this.scrape,
    this.rewriteMobilePdp = false,
  });

  final WatchStore store;
  final String refererHost;
  final WatchUserAgent ua;
  final ScrapeHit? Function(PageHarvest page) scrape;

  /// Amazon last-try `/gp/aw/d/{ASIN}` only.
  final bool rewriteMobilePdp;

  String get label => store.label;
  String get id => store.id;

  bool useMobileUa({required int attempt, required bool onAndroid}) {
    switch (ua) {
      case WatchUserAgent.mobile:
        return true;
      case WatchUserAgent.desktop:
        return false;
      case WatchUserAgent.amazon:
        return onAndroid || attempt > 0;
    }
  }

  String attemptUrl(String url, String? productId, int attempt) {
    if (!rewriteMobilePdp || attempt != 2 || productId == null) return url;
    return 'https://www.amazon.in/gp/aw/d/$productId';
  }
}
