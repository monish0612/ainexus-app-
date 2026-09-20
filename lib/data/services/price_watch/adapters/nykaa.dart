import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapeNykaa(PageHarvest page) {
  return _nykaaFamily(page, 'nykaa');
}

ScrapeHit? scrapeNykaaFashion(PageHarvest page) {
  return _nykaaFamily(page, 'nykaafashion');
}

ScrapeHit? _nykaaFamily(PageHarvest page, String source) {
  final finalP = firstPrice(
    page.html,
    r'"(?:finalPrice|discountedPrice|offerPrice)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: source,
    preferred: finalP,
    preferredSource: '$source.finalPrice',
  );
}
