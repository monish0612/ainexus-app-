import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

/// Unknown shop: structured Product/Offer only. Never scans ratings or MRP.
ScrapeHit? scrapeGeneric(PageHarvest page) {
  return scrapeStructured(page, source: 'generic', preferredScore: 70);
}
