import 'dart:io';

import 'package:ai_nexus/data/services/price_watch/adapters/amazon_in.dart';
import 'package:ai_nexus/data/services/price_watch/adapters/flipkart.dart';
import 'package:ai_nexus/data/services/price_watch/adapters/myntra.dart';
import 'package:ai_nexus/data/services/price_watch/adapters/swiggy.dart';
import 'package:ai_nexus/data/services/price_watch/page_harvest.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs only when `build/watch_probe/*.html` exists from a live fetch.
/// Those files are gitignored and must not be committed.
void main() {
  final dir = Directory('build/watch_probe');
  final amazon = File('${dir.path}/amazon.html');
  final flipkart = File('${dir.path}/flipkart.html');
  final myntra = File('${dir.path}/myntra.html');
  final swiggyOld = File('${dir.path}/swiggy_old.html');

  test(
    'amazon live buybox is 259, not MRP 399',
    () {
      final hit = scrapeAmazon(
        PageHarvest(
          html: amazon.readAsStringSync(),
          finalUrl: 'https://www.amazon.in/dp/8172234988',
        ),
      )!;
      expect(hit.price, 259);
      expect(hit.name.toLowerCase(), contains('alchemist'));
      expect(hit.imageUrl, contains('media-amazon.com'));
    },
    skip: amazon.existsSync() ? false : 'Live amazon.html not present',
  );

  test(
    'flipkart live json-ld is 59900 with sku',
    () {
      final hit = scrapeFlipkart(
        PageHarvest(
          html: flipkart.readAsStringSync(),
          finalUrl:
              'https://www.flipkart.com/apple-iphone-15-blue-128-gb/p/itm6ac6485515ae4?pid=MOBGTAGPAQNVFZZY',
        ),
      )!;
      expect(hit.price, 59900);
      expect(hit.pageProductId, 'MOBGTAGPAQNVFZZY');
      expect(hit.source, 'flipkart.jsonld');
    },
    skip: flipkart.existsSync() ? false : 'Live flipkart.html not present',
  );

  test(
    'myntra live discounted is 3299 not MRP 7999',
    () {
      final hit = scrapeMyntra(
        PageHarvest(
          html: myntra.readAsStringSync(),
          finalUrl: 'https://www.myntra.com/18422728',
        ),
      )!;
      expect(hit.price, 3299);
      expect(hit.pageProductId, '18422728');
    },
    skip: myntra.existsSync() ? false : 'Live myntra.html not present',
  );

  test(
    'swiggy restaurant shell has no item price',
    () {
      expect(
        scrapeSwiggy(
          PageHarvest(
            html: swiggyOld.readAsStringSync(),
            finalUrl:
                'https://www.swiggy.com/restaurants/meghana-foods-residency-road-central-bangalore-3241',
          ),
        ),
        isNull,
      );
    },
    skip: swiggyOld.existsSync() ? false : 'Live swiggy_old.html not present',
  );
}
