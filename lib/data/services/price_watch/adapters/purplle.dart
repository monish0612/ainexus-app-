import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapePurplle(PageHarvest page) {
  final offer = firstPrice(
    page.html,
    r'"(?:offer_price|offerPrice|sellingPrice)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: 'purplle',
    preferred: offer,
    preferredSource: 'purplle.offer_price',
  );
}
