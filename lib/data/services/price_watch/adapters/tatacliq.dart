import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapeTatacliq(PageHarvest page) {
  final selling = firstPrice(
    page.html,
    r'"(?:sellingPrice|offerPrice|discountedPrice)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: 'tatacliq',
    preferred: selling,
    preferredSource: 'tatacliq.sellingPrice',
  );
}
