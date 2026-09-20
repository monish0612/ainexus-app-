import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapeFirstcry(PageHarvest page) {
  final offer = firstPrice(
    page.html,
    r'"(?:offer_price|offerPrice|sellingPrice)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: 'firstcry',
    preferred: offer,
    preferredSource: 'firstcry.offer_price',
  );
}
