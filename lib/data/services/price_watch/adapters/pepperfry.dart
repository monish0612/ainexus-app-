import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapePepperfry(PageHarvest page) {
  final offer = firstPrice(
    page.html,
    r'"(?:offerPrice|sellingPrice|ourPrice)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: 'pepperfry',
    preferred: offer,
    preferredSource: 'pepperfry.offerPrice',
  );
}
