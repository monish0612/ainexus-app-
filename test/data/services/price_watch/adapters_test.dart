import 'package:ai_nexus/data/services/price_watch/adapters/ajio.dart';
import 'package:ai_nexus/data/services/price_watch/adapters/amazon_in.dart';
import 'package:ai_nexus/data/services/price_watch/adapters/flipkart.dart';
import 'package:ai_nexus/data/services/price_watch/adapters/generic.dart';
import 'package:ai_nexus/data/services/price_watch/adapters/myntra.dart';
import 'package:ai_nexus/data/services/price_watch/adapters/swiggy.dart';
import 'package:ai_nexus/data/services/price_watch/page_harvest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('amazon', () {
    test('JSON-LD selling price when buybox is absent', () {
      const html = '''
<html><head>
<meta property="og:title" content="Sony WH-1000XM5 | Amazon.in">
<meta property="og:image" content="https://m.media-amazon.com/x.jpg">
<script type="application/ld+json">
{"@type":"Product","offers":{"price":"1299.00","priceCurrency":"INR"}}
</script>
</head><body>
<span class="a-price a-text-price"><span class="a-offscreen">₹1,999.00</span></span>
<span class="a-price"><span class="a-offscreen">₹1,299.00</span></span>
</body></html>
''';
      final hit = scrapeAmazon(
        PageHarvest(html: html, finalUrl: 'https://www.amazon.in/dp/B0CXXXXXXX'),
      )!;
      expect(hit.price, 1299);
      expect(hit.source, 'amazon.jsonld');
      expect(hit.name, contains('Sony'));
    });

    test('buybox JSON wins over carousel and MRP', () {
      const html = '''
<html><head><title>The Alchemist</title>
<meta name="title" content="The Alchemist">
</head><body>
<li class="a-carousel-card"><span class="a-price"><span class="a-offscreen">₹150.00</span>
<span class="a-price-whole">150</span></span></li>
<span class="a-offscreen">₹399.00</span>
<div id="corePriceDisplay_desktop_feature_div">
<span class="a-price reinventPricePriceToPayMargin priceToPay apex-pricetopay-value">
<span class="a-offscreen"> </span>
<span class="a-price-whole">259</span>
</span>
<span class="a-size-small aok-offscreen apex-basisprice-offscreen-label">M.R.P.: ₹399.00</span>
<div class="a-section aok-hidden twister-plus-buying-options-price-data">{"desktop_buybox_group_1":[{"displayPrice":"₹259.00","priceAmount":259.00}]}</div>
</div>
<img id="imgTagWrapperId" src="https://m.media-amazon.com/images/I/tiny.jpg" data-old-hires="https://m.media-amazon.com/images/I/hires.jpg">
<span id="productTitle">        The Alchemist       </span>
</body></html>
''';
      final hit = scrapeAmazon(
        PageHarvest(html: html, finalUrl: 'https://www.amazon.in/dp/8172234988'),
      )!;
      expect(hit.price, 259);
      expect(hit.source, 'amazon.buybox');
      expect(hit.name, 'The Alchemist');
      expect(hit.imageUrl, contains('hires.jpg'));
    });

    test('empty offscreen + whole-only inside corePrice, skips strikethrough', () {
      const html = '''
<html><head><title>Budget earbuds</title></head><body>
<span class="a-price a-text-price" data-a-strike="true"><span class="a-offscreen">₹1,999.00</span></span>
<div id="corePriceDisplay_desktop_feature_div">
<span class="a-price reinventPricePriceToPayMargin priceToPay">
<span class="a-offscreen"> </span>
<span class="a-price-whole">1,299</span>
</span>
</div>
</body></html>
''';
      final hit = scrapeAmazon(
        PageHarvest(html: html, finalUrl: 'https://www.amazon.in/dp/B0CXXXXXXX'),
      )!;
      expect(hit.price, 1299);
      expect(hit.source, 'amazon.corePrice');
    });

    test('page-wide prices without buybox/core do not invent a hit', () {
      const html = '''
<html><body>
<span class="a-price"><span class="a-offscreen">₹150.00</span></span>
<span class="a-price"><span class="a-offscreen">₹482.00</span></span>
</body></html>
''';
      expect(
        scrapeAmazon(
          PageHarvest(html: html, finalUrl: 'https://www.amazon.in/dp/B0CXXXXXXX'),
        ),
        isNull,
      );
    });
  });

  group('flipkart', () {
    test('sellingPrice object still works on older pages', () {
      const html = '''
<html><head>
<meta property="og:title" content="Pixel 8a">
</head><body>
<script>{"sellingPrice":{"value":24999}}</script>
</body></html>
''';
      final hit = scrapeFlipkart(
        PageHarvest(html: html, finalUrl: 'https://www.flipkart.com/x'),
      )!;
      expect(hit.price, 24999);
      expect(hit.source, 'flipkart.sellingPrice');
    });

    test('JSON-LD bare price and sku, ignores higher MRP', () {
      const html = '''
<html><head>
<meta property="og:title" content="Apple iPhone 15 (Blue, 128 GB)">
<script type="application/ld+json">
[{"@type":"Product","sku":"MOBGTAGPAQNVFZZY","offers":{"@type":"Offer","price":59900,"priceCurrency":"INR"}}]
</script>
</head><body>
<script>{"finalPrice":59900,"mrp":69900,"pid":"MOBGTAGPAQNVFZZY"}</script>
</body></html>
''';
      final hit = scrapeFlipkart(
        PageHarvest(
          html: html,
          finalUrl:
              'https://www.flipkart.com/apple-iphone-15-blue-128-gb/p/itm6ac6485515ae4?pid=MOBGTAGPAQNVFZZY',
        ),
      )!;
      expect(hit.price, 59900);
      expect(hit.source, 'flipkart.jsonld');
      expect(hit.pageProductId, 'MOBGTAGPAQNVFZZY');
    });

    test('bare finalPrice number when JSON-LD is missing', () {
      const html = '''
<html><head><meta property="og:title" content="Yamaha guitar"></head>
<body><script>{"finalPrice":7989,"mrp":7990}</script></body></html>
''';
      final hit = scrapeFlipkart(
        PageHarvest(html: html, finalUrl: 'https://www.flipkart.com/x/p/itmabc'),
      )!;
      expect(hit.price, 7989);
      expect(hit.source, 'flipkart.finalPrice');
    });
  });

  group('myntra', () {
    test('discounted key without pdp blob', () {
      const html = '''
<html><head>
<meta property="og:title" content="Nike Pegasus">
</head><body>
<script>{"discounted":7999,"mrp":9999}</script>
<p class="pdp-price">₹7,999</p>
</body></html>
''';
      final hit = scrapeMyntra(
        PageHarvest(html: html, finalUrl: 'https://www.myntra.com/x'),
      )!;
      expect(hit.price, 7999);
      expect(hit.source, 'myntra.discounted');
    });

    test('pdpData price blob uses discounted not MRP', () {
      const html = '''
<html><head>
<meta property="og:title" content="Buy lamp | Myntra">
<script type="application/ld+json">{"offers":{"price" : "3299"}}</script>
</head><body>
<script>window.__myx = {"pdpData":{"id":18422728,"name":"Devansh White Mosaic Glass Spherical Hanging Lamp","price":{"mrp":7999,"discounted":3299}}}</script>
</body></html>
''';
      final hit = scrapeMyntra(
        PageHarvest(html: html, finalUrl: 'https://www.myntra.com/18422728'),
      )!;
      expect(hit.price, 3299);
      expect(hit.source, 'myntra.pdpData');
      expect(hit.pageProductId, '18422728');
      expect(hit.name, contains('Devansh'));
    });
  });

  group('swiggy', () {
    test('offer_price', () {
      const html = '''
<html><head>
<meta property="og:title" content="Amul Milk">
</head><body>
<script>{"offer_price":64,"finalPrice":70}</script>
</body></html>
''';
      final hit = scrapeSwiggy(
        PageHarvest(html: html, finalUrl: 'https://www.swiggy.com/instamart/item/abc'),
      )!;
      expect(hit.price, 64);
      expect(hit.source, 'swiggy.offer_price');
    });

    test('restaurant shell with costForTwo does not invent a price', () {
      const html = '''
<html><head><title>Order Food Online | Swiggy</title></head>
<body>
<script>window.__INITIAL_STATE__ = {"costForTwo":400,"avgRating":4.3,"rupees":"₹199"}</script>
<span>₹199</span><span>₹399</span>
</body></html>
''';
      expect(
        scrapeSwiggy(
          PageHarvest(
            html: html,
            finalUrl:
                'https://www.swiggy.com/city/bangalore/meghana-foods-central-bangalore-rest3241',
          ),
        ),
        isNull,
      );
    });
  });

  group('ajio / generic', () {
    test('Ajio JSON-LD selling price', () {
      const html = '''
<html><head>
<meta property="og:title" content="Navy Slim Fit Shirt | Ajio">
<script type="application/ld+json">
{"@type":"Product","offers":{"price":"599"}}
</script>
</head><body></body></html>
''';
      final hit = scrapeAjio(
        PageHarvest(html: html, finalUrl: 'https://www.ajio.com/p/441137043003'),
      )!;
      expect(hit.price, 599);
      expect(hit.source, 'ajio.jsonld');
    });

    test('generic ignores page-wide rupee scan', () {
      expect(
        scrapeGeneric(
          PageHarvest(
            html: '<html><body>From ₹199 · rating 4.5</body></html>',
            finalUrl: 'https://www.example-boutique.com/product/x',
          ),
        ),
        isNull,
      );
    });

    test('generic JSON-LD product is accepted', () {
      const html = '''
<html><head>
<meta property="og:title" content="Blue Shirt">
<script type="application/ld+json">
{"@type":"Product","sku":"BLU-1","offers":{"price":"1499.00"}}
</script>
</head></html>
''';
      final hit = scrapeGeneric(
        PageHarvest(
          html: html,
          finalUrl: 'https://www.example-boutique.com/product/blue-shirt',
        ),
      )!;
      expect(hit.price, 1499);
      expect(hit.pageProductId, 'BLU-1');
    });
  });
}
