import '../../../core/utils/tidy_url.dart';

/// Indian storefronts plus a conservative generic product-page fallback.
/// Adding a shop: enum value here, a parser below, an adapter, and one
/// [StoreCatalog] row. Engine / UI never switch on the shop themselves.
enum WatchStore {
  amazon('amazon', 'Amazon'),
  flipkart('flipkart', 'Flipkart'),
  myntra('myntra', 'Myntra'),
  swiggy('swiggy', 'Swiggy'),
  ajio('ajio', 'Ajio'),
  snapdeal('snapdeal', 'Snapdeal'),
  jiomart('jiomart', 'JioMart'),
  tatacliq('tatacliq', 'Tata CLiQ'),
  nykaa('nykaa', 'Nykaa'),
  nykaaFashion('nykaafashion', 'Nykaa Fashion'),
  pepperfry('pepperfry', 'Pepperfry'),
  firstcry('firstcry', 'FirstCry'),
  croma('croma', 'Croma'),
  purplle('purplle', 'Purplle'),
  other('other', 'Other');

  const WatchStore(this.id, this.label);

  final String id;
  final String label;

  static WatchStore? fromId(String? raw) {
    final n = (raw ?? '').toLowerCase().replaceAll(RegExp(r'[_-\s]'), '');
    if (n.isEmpty) return null;
    for (final s in WatchStore.values) {
      if (s.id.replaceAll('_', '') == n) return s;
    }
    switch (n) {
      case 'tata':
      case 'tatacliq':
        return WatchStore.tatacliq;
      case 'jio':
      case 'jiomart':
        return WatchStore.jiomart;
      case 'nykaafashion':
      case 'nykaaf':
        return WatchStore.nykaaFashion;
      case 'generic':
      case 'web':
        return WatchStore.other;
      default:
        return null;
    }
  }

  /// Chips / copy for shops we advertise. [other] is detected, not promoted.
  static List<WatchStore> get advertised =>
      WatchStore.values.where((s) => s != WatchStore.other).toList();
}

class CanonicalWatchUrl {
  const CanonicalWatchUrl({
    required this.store,
    required this.url,
    this.productId,
  });

  final WatchStore store;
  final String url;
  final String? productId;

  /// Stable merge key. Same SKU on two devices (or two share URLs) = same key.
  String get identityKey => watchIdentityKey(store, productId, url);
}

/// `store:sku` when we have a product id, otherwise `store:url:canonical`.
String watchIdentityKey(WatchStore store, String? productId, String canonicalUrl) {
  final id = (productId ?? '').trim();
  if (id.isNotEmpty) return '${store.id}:$id';
  return '${store.id}:url:${canonicalUrl.toLowerCase()}';
}

/// First http(s) URL in freeform share text, or null.
/// Tracking params are left intact — [canonicalizeWatchUrl] is store-specific.
String? extractHttpUrl(String text) {
  final found = TidyUrl.extractUrls(text);
  return found.isNotEmpty ? found.first : null;
}

/// Detect store + collapse affiliate / tracking query junk so the unique
/// index on `canonicalUrl` actually de-dupes **the same SKU**.
CanonicalWatchUrl? canonicalizeWatchUrl(String raw) {
  final extracted = extractHttpUrl(raw) ?? raw.trim();
  Uri uri;
  try {
    uri = Uri.parse(extracted);
  } catch (_) {
    return null;
  }
  if (uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

  for (final parse in _parsers) {
    final hit = parse(uri, host);
    if (hit != null) return hit;
  }
  return _generic(uri, host);
}

bool isWatchStoreUrl(String text) => canonicalizeWatchUrl(text) != null;

/// Share-sheet candidate: known shop **or** a deep link on an unknown host
/// (boutique PDP). Homepages and social/search hosts stay out.
bool isWatchShareCandidate(String text) {
  if (canonicalizeWatchUrl(text) != null) return true;
  final url = extractHttpUrl(text);
  if (url == null) return false;
  Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return false;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (host.isEmpty || _deniedHost.hasMatch(host)) return false;
  final segs = uri.path.split('/').where((s) => s.isNotEmpty).toList();
  return segs.length >= 2;
}

/// After HTTP redirects (amzn.to / fkrt.it / bit.ly), prefer the final
/// product URL. [WatchStore.other] may upgrade to a named shop.
CanonicalWatchUrl preferResolvedCanonical(
  CanonicalWatchUrl canon,
  String? resolved,
) {
  if (resolved == null || resolved.isEmpty) return canon;
  final better = canonicalizeWatchUrl(resolved);
  if (better == null) return canon;
  if (better.store != canon.store && canon.store != WatchStore.other) {
    return canon;
  }
  return better;
}

typedef _Parser = CanonicalWatchUrl? Function(Uri uri, String host);

final List<_Parser> _parsers = [
  _amazon,
  _flipkart,
  _myntra,
  _swiggy,
  _ajio,
  _snapdeal,
  _jiomart,
  _tatacliq,
  _nykaaFashion,
  _nykaa,
  _pepperfry,
  _firstcry,
  _croma,
  _purplle,
];

CanonicalWatchUrl? _amazon(Uri uri, String host) {
  if (!_amazonHost.hasMatch(host)) return null;
  final asin =
      _amazonAsin.firstMatch(uri.path)?.group(1) ?? uri.queryParameters['asin'];
  if (asin != null && asin.length >= 8) {
    return CanonicalWatchUrl(
      store: WatchStore.amazon,
      url: 'https://www.amazon.in/dp/${asin.toUpperCase()}',
      productId: asin.toUpperCase(),
    );
  }
  if (host == 'amzn.to' ||
      host == 'amzn.in' ||
      host == 'a.co' ||
      host.endsWith('.amzn.to')) {
    return CanonicalWatchUrl(
      store: WatchStore.amazon,
      url: _originPath(uri),
    );
  }
  return null;
}

CanonicalWatchUrl? _flipkart(Uri uri, String host) {
  if (!_flipkartHost.hasMatch(host)) return null;
  final pid = uri.queryParameters['pid'] ?? uri.queryParameters['PID'];
  final itm = _flipkartItm.firstMatch(uri.path)?.group(1);
  final isShort = host == 'fkrt.it' || host.startsWith('dl.flipkart.');
  if (pid == null && itm == null && !isShort) return null;
  if (_flipkartReject.hasMatch(uri.path)) return null;
  final path = _absPath(uri.path);
  final clean = Uri(
    scheme: 'https',
    host: isShort ? uri.host : 'www.flipkart.com',
    path: isShort ? uri.path : path,
    queryParameters: pid == null ? null : {'pid': pid},
  );
  return CanonicalWatchUrl(
    store: WatchStore.flipkart,
    url: clean.toString(),
    productId: pid ?? itm,
  );
}

CanonicalWatchUrl? _myntra(Uri uri, String host) {
  if (!_myntraHost.hasMatch(host)) return null;
  final id = _myntraStyleId(uri.path);
  if (id != null) {
    return CanonicalWatchUrl(
      store: WatchStore.myntra,
      url: 'https://www.myntra.com/$id',
      productId: id,
    );
  }
  if (host == 'myntr.it' || host.endsWith('.myntr.it')) {
    return CanonicalWatchUrl(
      store: WatchStore.myntra,
      url: _originPath(uri),
    );
  }
  return null;
}

CanonicalWatchUrl? _swiggy(Uri uri, String host) {
  if (!_swiggyHost.hasMatch(host)) return null;
  final restId = _swiggyRest.firstMatch(uri.path)?.group(1);
  final itemPath = _swiggyItemPath.hasMatch(uri.path);
  final q = _keepQuery(uri, const [
    'storeId',
    'store_id',
    'itemId',
    'item_id',
    'spinId',
    'skuId',
    'sld',
  ]);
  final hasItemQuery = q != null &&
      (q.containsKey('itemId') ||
          q.containsKey('item_id') ||
          q.containsKey('spinId') ||
          q.containsKey('skuId'));
  final isShort = host == 'link.swiggy.com' || host.endsWith('.link.swiggy.com');
  if (!itemPath && !hasItemQuery && !isShort) return null;
  return CanonicalWatchUrl(
    store: WatchStore.swiggy,
    url: Uri(
      scheme: 'https',
      host: uri.host,
      path: _absPath(uri.path),
      queryParameters: q,
    ).toString(),
    productId: q?['itemId'] ??
        q?['item_id'] ??
        q?['spinId'] ??
        q?['skuId'] ??
        (restId == null ? null : 'rest$restId'),
  );
}

CanonicalWatchUrl? _ajio(Uri uri, String host) {
  if (!_ajioHost.hasMatch(host)) return null;
  if (_listingReject.hasMatch(uri.path)) return null;
  final code = _ajioCode.firstMatch(uri.path)?.group(1);
  if (code == null) {
    if (host.contains('ajio') && _isShortPath(uri.path)) {
      return CanonicalWatchUrl(store: WatchStore.ajio, url: _originPath(uri));
    }
    return null;
  }
  return CanonicalWatchUrl(
    store: WatchStore.ajio,
    url: Uri(
      scheme: 'https',
      host: 'www.ajio.com',
      path: _absPath(uri.path),
    ).toString(),
    productId: code,
  );
}

CanonicalWatchUrl? _snapdeal(Uri uri, String host) {
  if (!_hostIs(host, const ['snapdeal.com'])) return null;
  if (_listingReject.hasMatch(uri.path)) return null;
  final pog = _snapdealPog.firstMatch(uri.path)?.group(1);
  if (pog == null) return null;
  return CanonicalWatchUrl(
    store: WatchStore.snapdeal,
    url: Uri(
      scheme: 'https',
      host: 'www.snapdeal.com',
      path: _absPath(uri.path),
    ).toString(),
    productId: pog,
  );
}

CanonicalWatchUrl? _jiomart(Uri uri, String host) {
  if (!_hostIs(host, const ['jiomart.com'])) return null;
  if (_listingReject.hasMatch(uri.path)) return null;
  if (!_jiomartPath.hasMatch(uri.path)) return null;
  final sku = uri.queryParameters['sku'] ??
      uri.queryParameters['skuId'] ??
      _trailingId(uri.path);
  return CanonicalWatchUrl(
    store: WatchStore.jiomart,
    url: Uri(
      scheme: 'https',
      host: 'www.jiomart.com',
      path: _absPath(uri.path),
    ).toString(),
    productId: sku,
  );
}

CanonicalWatchUrl? _tatacliq(Uri uri, String host) {
  if (!_hostIs(host, const ['tatacliq.com'])) return null;
  if (_listingReject.hasMatch(uri.path)) return null;
  final id = _tataId.firstMatch(uri.path)?.group(1);
  if (id == null) return null;
  return CanonicalWatchUrl(
    store: WatchStore.tatacliq,
    url: Uri(
      scheme: 'https',
      host: 'www.tatacliq.com',
      path: _absPath(uri.path),
    ).toString(),
    productId: id,
  );
}

CanonicalWatchUrl? _nykaaFashion(Uri uri, String host) {
  if (!_hostIs(host, const ['nykaafashion.com'])) return null;
  return _nykaaLike(uri, host, WatchStore.nykaaFashion, 'www.nykaafashion.com');
}

CanonicalWatchUrl? _nykaa(Uri uri, String host) {
  if (!_hostIs(host, const ['nykaa.com', 'nykaaman.com'])) return null;
  return _nykaaLike(uri, host, WatchStore.nykaa, 'www.nykaa.com');
}

CanonicalWatchUrl? _nykaaLike(
  Uri uri,
  String host,
  WatchStore store,
  String canonHost,
) {
  if (_listingReject.hasMatch(uri.path)) return null;
  final id = _nykaaId.firstMatch(uri.path)?.group(1) ??
      uri.queryParameters['productId'] ??
      uri.queryParameters['sku'];
  if (id == null) return null;
  return CanonicalWatchUrl(
    store: store,
    url: Uri(
      scheme: 'https',
      host: canonHost,
      path: _absPath(uri.path),
    ).toString(),
    productId: id,
  );
}

CanonicalWatchUrl? _pepperfry(Uri uri, String host) {
  if (!_hostIs(host, const ['pepperfry.com'])) return null;
  if (_listingReject.hasMatch(uri.path)) return null;
  final qid = uri.queryParameters['item_id'] ??
      uri.queryParameters['id'] ??
      uri.queryParameters['productId'];
  final pathId = _pepperId.firstMatch(uri.path)?.group(1);
  final id = qid ?? pathId;
  final productPath = uri.path.toLowerCase().contains('/product') ||
      uri.path.toLowerCase().contains('/site_product') ||
      uri.path.toLowerCase().endsWith('.html');
  if (id == null && !productPath) return null;
  return CanonicalWatchUrl(
    store: WatchStore.pepperfry,
    url: Uri(
      scheme: 'https',
      host: 'www.pepperfry.com',
      path: _absPath(uri.path),
      queryParameters: id == null ? null : {'item_id': id},
    ).toString(),
    productId: id,
  );
}

CanonicalWatchUrl? _firstcry(Uri uri, String host) {
  if (!_hostIs(host, const ['firstcry.com'])) return null;
  if (_listingReject.hasMatch(uri.path)) return null;
  final pid = uri.queryParameters['pid'] ?? uri.queryParameters['PID'];
  final pathId = _firstcryId.firstMatch(uri.path)?.group(1);
  if (pid == null && pathId == null) return null;
  return CanonicalWatchUrl(
    store: WatchStore.firstcry,
    url: Uri(
      scheme: 'https',
      host: 'www.firstcry.com',
      path: _absPath(uri.path),
      queryParameters: pid == null ? null : {'pid': pid},
    ).toString(),
    productId: pid ?? pathId,
  );
}

CanonicalWatchUrl? _croma(Uri uri, String host) {
  if (!_hostIs(host, const ['croma.com'])) return null;
  if (_listingReject.hasMatch(uri.path)) return null;
  final id = _cromaId.firstMatch(uri.path)?.group(1) ??
      uri.queryParameters['sku'] ??
      uri.queryParameters['id'];
  if (id == null) return null;
  return CanonicalWatchUrl(
    store: WatchStore.croma,
    url: Uri(
      scheme: 'https',
      host: 'www.croma.com',
      path: _absPath(uri.path),
    ).toString(),
    productId: id,
  );
}

CanonicalWatchUrl? _purplle(Uri uri, String host) {
  if (!_hostIs(host, const ['purplle.com'])) return null;
  if (_listingReject.hasMatch(uri.path)) return null;
  if (!_purpllePath.hasMatch(uri.path)) return null;
  final slug = _purplleSlug.firstMatch(uri.path)?.group(1);
  return CanonicalWatchUrl(
    store: WatchStore.purplle,
    url: Uri(
      scheme: 'https',
      host: 'www.purplle.com',
      path: _absPath(uri.path),
    ).toString(),
    productId: slug,
  );
}

/// Unknown shop: product-like path, or a known shortener we resolve after GET.
CanonicalWatchUrl? _generic(Uri uri, String host) {
  if (_deniedHost.hasMatch(host)) return null;
  if (_namedShopHost.hasMatch(host)) return null;
  if (_shortener.hasMatch(host)) {
    return CanonicalWatchUrl(
      store: WatchStore.other,
      url: _originPath(uri),
    );
  }
  if (_listingReject.hasMatch(uri.path)) return null;
  final q = _keepQuery(uri, const [
    'pid',
    'sku',
    'skuId',
    'product_id',
    'productId',
    'item_id',
    'itemId',
  ]);
  final looks = _genericProduct.hasMatch(uri.path) ||
      (q != null && q.isNotEmpty) ||
      uri.path.split('/').where((s) => s.isNotEmpty).length >= 2;
  if (!looks) return null;
  return CanonicalWatchUrl(
    store: WatchStore.other,
    url: Uri(
      scheme: 'https',
      host: uri.host,
      path: _absPath(uri.path),
      queryParameters: q,
    ).toString(),
    productId: q?['pid'] ??
        q?['sku'] ??
        q?['skuId'] ??
        q?['productId'] ??
        q?['product_id'] ??
        q?['itemId'] ??
        q?['item_id'] ??
        _trailingId(uri.path),
  );
}

String _absPath(String path) => path.startsWith('/') ? path : '/$path';

String _originPath(Uri uri) {
  return Uri(
    scheme: 'https',
    host: uri.host,
    path: _absPath(uri.path),
  ).toString();
}

bool _isShortPath(String path) {
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  return segs.length <= 2 && segs.every((s) => s.length <= 24);
}

bool _hostIs(String host, List<String> suffixes) {
  for (final s in suffixes) {
    if (host == s || host.endsWith('.$s')) return true;
  }
  return false;
}

String? _myntraStyleId(String path) {
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  if (segs.last.toLowerCase() == 'buy' &&
      segs.length >= 2 &&
      _myntraDigits.hasMatch(segs[segs.length - 2])) {
    return segs[segs.length - 2];
  }
  if (_myntraDigits.hasMatch(segs.last)) return segs.last;
  return null;
}

String? _trailingId(String path) {
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  var last = segs.last;
  if (last.toLowerCase() == 'product-detail' && segs.length >= 2) {
    last = segs[segs.length - 2];
  }
  last = last.replaceAll(RegExp(r'\.html?$', caseSensitive: false), '');
  if (_myntraDigits.hasMatch(last) || _skuToken.hasMatch(last)) return last;
  return null;
}

Map<String, String>? _keepQuery(Uri uri, List<String> keys) {
  final keep = <String, String>{};
  for (final key in keys) {
    final v = uri.queryParameters[key];
    if (v != null && v.isNotEmpty) keep[key] = v;
  }
  return keep.isEmpty ? null : keep;
}

final _amazonHost = RegExp(
  r'(^|\.)amazon\.in$|(^|\.)amazon\.com$|(^|\.)amzn\.in$|(^|\.)amzn\.to$|(^|\.)a\.co$',
);
final _flipkartHost = RegExp(
  r'(^|\.)flipkart\.com$|(^|\.)fkrt\.it$|(^|\.)dl\.flipkart\.com$',
);
final _myntraHost = RegExp(r'(^|\.)myntra\.com$|(^|\.)myntr\.it$');
final _swiggyHost = RegExp(
  r'(^|\.)swiggy\.com$|(^|\.)instamart\.swiggy\.com$|(^|\.)link\.swiggy\.com$',
);
final _ajioHost = RegExp(r'(^|\.)ajio\.com$|(^|\.)ajiio\.in$');

final _amazonAsin = RegExp(
  r'/(?:dp|gp/product/glance|gp/product|gp/aw/d)/([A-Z0-9]{8,12})(?:/|$)',
  caseSensitive: false,
);
final _flipkartItm = RegExp(r'/p/(itm[a-z0-9]+)', caseSensitive: false);
final _flipkartReject = RegExp(
  r'/(search|travel|flights|offer-store|plus)(/|$)|/pr$',
  caseSensitive: false,
);
final _myntraDigits = RegExp(r'^\d{5,}$');
final _skuToken = RegExp(r'^[A-Z0-9_-]{6,}$', caseSensitive: false);
final _swiggyRest = RegExp(r'-rest(\d+)(?:/|$)', caseSensitive: false);
final _swiggyItemPath = RegExp(
  r'/instamart/(?:item|products)/',
  caseSensitive: false,
);
final _ajioCode = RegExp(r'/p/(\d{6,})(?:/|$)', caseSensitive: false);
final _snapdealPog = RegExp(r'/product/[^/]+/(\d{6,})(?:/|$)', caseSensitive: false);
final _jiomartPath = RegExp(r'/(p|products)/', caseSensitive: false);
final _tataId = RegExp(r'(p-mp\d+)', caseSensitive: false);
final _nykaaId = RegExp(r'/p/(\d{5,})(?:/|$)', caseSensitive: false);
final _pepperId = RegExp(
  r'(?:/site_product/|/product/.*?[-_])(\d{5,})',
  caseSensitive: false,
);
final _firstcryId = RegExp(
  r'/(\d{5,})(?:/product-detail|/$)',
  caseSensitive: false,
);
final _cromaId = RegExp(r'/p/(\d{4,})(?:/|$)', caseSensitive: false);
final _purpllePath = RegExp(r'/product/', caseSensitive: false);
final _purplleSlug = RegExp(r'/product/([^/?#]+)', caseSensitive: false);
final _genericProduct = RegExp(
  r'/(?:p|dp|gp/product|product|products|item|items)/',
  caseSensitive: false,
);
final _listingReject = RegExp(
  r'/(search|s|cart|login|account|category|categories|collection|collections|blog|tag|offers?|store)(/|$)',
  caseSensitive: false,
);
final _shortener = RegExp(
  r'^(bit\.ly|bitly\.com|j\.mp|tinyurl\.com|tiny\.cc|is\.gd|cutt\.ly)$',
);
/// Dedicated parsers already ran. A miss on these hosts is a listing, not
/// a boutique "other" PDP.
final _namedShopHost = RegExp(
  r'(^|\.)(amazon|amzn|flipkart|fkrt|myntra|myntr|swiggy|ajio|ajiio|'
  r'snapdeal|jiomart|tatacliq|nykaa|pepperfry|firstcry|croma|purplle)\.',
);
final _deniedHost = RegExp(
  r'(^|\.)google\.(com|co\.in)$|(^|\.)youtube\.|(^|\.)facebook\.|(^|\.)instagram\.|(^|\.)twitter\.|(^|\.)x\.com$|(^|\.)wikipedia\.|(^|\.)reddit\.|(^|\.)github\.|(^|\.)linkedin\.|(^|\.)whatsapp\.|(^|\.)telegram\.|(^|\.)t\.me$',
);
