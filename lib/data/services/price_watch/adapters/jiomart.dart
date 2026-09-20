import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapeJiomart(PageHarvest page) {
  final selling = firstPrice(
    page.html,
    r'"(?:selling_price|sellingPrice|offer_price)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: 'jiomart',
    preferred: selling,
    preferredSource: 'jiomart.selling_price',
  );
}
