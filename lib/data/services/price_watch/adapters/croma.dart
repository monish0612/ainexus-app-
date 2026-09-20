import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapeCroma(PageHarvest page) {
  final selling = firstPrice(
    page.html,
    r'"(?:sellingPrice|offerPrice|finalPrice)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: 'croma',
    preferred: selling,
    preferredSource: 'croma.sellingPrice',
  );
}
