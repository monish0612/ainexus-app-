import '../page_harvest.dart';
import '../price_models.dart';
import 'structured.dart';

ScrapeHit? scrapeAjio(PageHarvest page) {
  final offer = firstPrice(
    page.html,
    r'"(?:offerPrice|sellingPrice|discountedPrice)"\s*:\s*"?([\d.]+)"?',
  );
  final nested = firstPrice(
    page.html,
    r'"price"\s*:\s*\{[^}]{0,120}"(?:value|sellingPrice)"\s*:\s*"?([\d.]+)"?',
  );
  return scrapeStructured(
    page,
    source: 'ajio',
    preferred: offer ?? nested,
    preferredSource: offer != null ? 'ajio.offerPrice' : 'ajio.price',
  );
}
