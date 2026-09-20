import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapeSnapdeal(PageHarvest page) {
  final selling = firstPrice(
    page.html,
    r'"(?:sellingPrice|offerPrice|finalPrice)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: 'snapdeal',
    preferred: selling,
    preferredSource: 'snapdeal.sellingPrice',
  );
}
