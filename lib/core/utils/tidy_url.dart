/// Port of TidyLink `UrlCanonicalizer`: share-text extraction, tracking-param
/// strip, and de-dupe keys. Used by the URL summarizer and share sheet so the
/// same page (`?si=`, `utm_*`, www/https) hits one job and a clean fetch URL.
///
/// Pure CPU — no timers, sockets, or background schedulers. Duplicate-job collapse is the
/// battery win (one LLM fetch per page, not per share-token).
///
/// Watch SKU canonicalization stays in [store_url.dart] — that path is
/// store-specific (ASIN / pid / style id) and must keep `pid` / item ids.
class TidyUrl {
  TidyUrl._();

  static const _maxExtract = 32;

  static const _tracking = {
    'si',
    'feature',
    'fbclid',
    'gclid',
    'dclid',
    'msclkid',
    'twclid',
    'igsh',
    'igshid',
    'mc_cid',
    'mc_eid',
    'ref_src',
    'ref_url',
    'mibextid',
    'share_id',
    'sfnsn',
    'rdt',
    'sh',
    'context',
    // Click ids TidyLink missed — never content, only duplicate jobs.
    'srsltid',
    'gbraid',
    'wbraid',
    'ttclid',
    'yclid',
    '_ga',
    '_gl',
    'affid',
  };

  static final _urlRx =
      RegExp(r"""https?://[^\s"'<>\])]+""", caseSensitive: false);

  static final _ytId = RegExp(r'^[\w-]{11}$');

  static final _amazonAsin = RegExp(
    r'/(?:dp|gp/product/glance|gp/product|gp/aw/d)/([A-Z0-9]{8,12})(?:/|$)',
    caseSensitive: false,
  );

  static const _youtubeHosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtu.be',
    'www.youtu.be',
    'm.youtu.be',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
  };

  static const _youtubePathKinds = {'shorts', 'embed', 'live', 'v'};

  /// Every distinct http(s) URL in freeform text.
  static List<String> extractUrls(String text) {
    final out = <String>[];
    final seen = <String>{};
    for (final m in _urlRx.allMatches(text)) {
      final url = _trimExtracted(m.group(0)!);
      if (!isValidHttpUrl(url)) continue;
      if (seen.add(url)) out.add(url);
      if (out.length >= _maxExtract) break;
    }
    return out;
  }

  /// First URL in share text, or a valid bare domain, else null.
  static String? extractSharedUrl(String text) {
    final found = extractUrls(text);
    if (found.isNotEmpty) return found.first;
    final t = text.trim();
    return isValidHttpUrl(t) ? t : null;
  }

  static String _trimExtracted(String raw) {
    var url = _trimEndChars(raw, '.,;)]>"\'');
    if (isValidHttpUrl(url)) return url;
    return _trimEndChars(url, '!');
  }

  static String _trimEndChars(String raw, String chars) {
    var url = raw;
    while (url.isNotEmpty && chars.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static String _trimPath(String path) {
    var p = path;
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    if (p == '/') return '';
    return p;
  }

  /// Dart's [Uri.parse] is more lenient than Java's URI (spaces become
  /// `%20`, `example.com!` is a host). Reject those so we match TidyLink.
  static bool _looksLikeHost(String host) {
    if (host.isEmpty) return false;
    String decoded;
    try {
      decoded = Uri.decodeComponent(host).toLowerCase();
    } catch (_) {
      return false;
    }
    if (decoded.contains(' ') || decoded.contains('%')) return false;
    return RegExp(
      r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
    ).hasMatch(decoded);
  }

  static String hostOf(String url) {
    try {
      final host = Uri.parse(cleanUrl(url)).host.toLowerCase();
      if (!_looksLikeHost(host)) return '';
      return host;
    } catch (_) {
      return '';
    }
  }

  static bool hostMatches(String url, List<String> domains) {
    final host = hostOf(url);
    if (host.isEmpty) return false;
    return domains.any((d) => host == d || host.endsWith('.$d'));
  }

  /// Scheme + lowercase host, tracking query gone, plain `#anchors` dropped,
  /// SPA hash-routes (`#/` / `#!/`) kept.
  static String cleanUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    final lower = trimmed.toLowerCase();
    final hasScheme =
        lower.startsWith('http://') || lower.startsWith('https://');
    final withScheme = hasScheme ? trimmed : 'https://$trimmed';
    try {
      final uri = Uri.parse(withScheme);
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return withScheme;
      var host = uri.host;
      if (!_looksLikeHost(host)) return withScheme;
      host = host.toLowerCase();
      final path = _trimPath(uri.path);

      final kept = <String>[];
      if (uri.query.isNotEmpty) {
        for (final param in uri.query.split('&')) {
          final key = param.split('=').first.toLowerCase();
          if (key.isEmpty) continue;
          if (key.startsWith('utm_')) continue;
          if (_tracking.contains(key)) continue;
          kept.add(param);
        }
      }

      return _build(
        scheme: scheme,
        host: host,
        port: uri.hasPort ? uri.port : null,
        path: path,
        query: kept,
        fragment: uri.fragment,
      );
    } catch (_) {
      return withScheme;
    }
  }

  /// Same page under http/https, www, and tracking variants.
  static String dedupeKey(String url) {
    var s = cleanUrl(url);
    s = s.replaceFirst(RegExp(r'^https://'), '');
    s = s.replaceFirst(RegExp(r'^http://'), '');
    s = s.replaceFirst(RegExp(r'^www\.'), '');
    return s;
  }

  /// Job key used by [SummarizeStore] — normalize first so youtu.be / m. /
  /// tracking variants collide on one in-flight request.
  static String summarizeJobKey(String url) {
    final cleaned = normalizeForSummarize(url);
    final fetchUrl = cleaned.isEmpty ? url.trim() : cleaned;
    return dedupeKey(fetchUrl);
  }

  static String placeholderTitle(String url) {
    var s = url
        .replaceFirst(RegExp(r'^https://'), '')
        .replaceFirst(RegExp(r'^http://'), '')
        .replaceFirst(RegExp(r'^www\.'), '');
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static bool isValidHttpUrl(String raw) {
    if (raw.trim().isEmpty) return false;
    try {
      final uri = Uri.parse(cleanUrl(raw));
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return false;
      return _looksLikeHost(uri.host);
    } catch (_) {
      return false;
    }
  }

  /// True when the whole field is a URL (optional wrapping punctuation).
  static bool isUrlField(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    if (isValidHttpUrl(t)) return true;
    final urls = extractUrls(t);
    if (urls.length != 1) return false;
    final rest = t.replaceFirst(urls.first, '');
    return rest.replaceAll(RegExp(r'''[\s.,;:!?()\[\]<>\"']+'''), '').isEmpty;
  }

  /// Extract + clean for the summarizer / backend fetch.
  static String normalizeForSummarize(String raw) {
    final extracted = extractSharedUrl(raw) ?? raw.trim();
    if (extracted.isEmpty || !isValidHttpUrl(extracted)) return '';
    return _summarizeCanonical(cleanUrl(extracted));
  }

  /// Collapse YouTube aliases and Amazon `/dp/ASIN` so share variants
  /// hit the same summarize job. Does **not** rewrite Flipkart `pid`.
  static String _summarizeCanonical(String cleaned) {
    try {
      final uri = Uri.parse(cleaned);
      var host = uri.host.toLowerCase();
      var path = _trimPath(uri.path);
      var kept = uri.query.isEmpty
          ? <String>[]
          : uri.query.split('&').where((p) => p.isNotEmpty).toList();

      final videoId = _youtubeVideoId(host, path, kept);
      if (videoId != null) {
        host = 'www.youtube.com';
        path = '/watch';
        kept = ['v=$videoId'];
      } else if (host == 'm.youtube.com' || host == 'music.youtube.com') {
        host = 'www.youtube.com';
      } else {
        final asin = _amazonAsin.firstMatch(path)?.group(1);
        if (asin != null && _isAmazonProductHost(host)) {
          path = '/dp/${asin.toUpperCase()}';
          kept = <String>[];
        }
      }

      return _build(
        scheme: uri.scheme.toLowerCase(),
        host: host,
        port: uri.hasPort ? uri.port : null,
        path: path,
        query: kept,
        fragment: uri.fragment,
      );
    } catch (_) {
      return cleaned;
    }
  }

  static String? _youtubeVideoId(
    String host,
    String path,
    List<String> kept,
  ) {
    if (!_youtubeHosts.contains(host)) return null;
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (host == 'youtu.be' || host == 'www.youtu.be' || host == 'm.youtu.be') {
      if (segs.isEmpty) return null;
      return _ytId.hasMatch(segs.first) ? segs.first : null;
    }
    if (path == '/watch') {
      final v = _queryValue(kept, 'v');
      return (v != null && _ytId.hasMatch(v)) ? v : null;
    }
    if (segs.length >= 2 &&
        _youtubePathKinds.contains(segs.first.toLowerCase()) &&
        _ytId.hasMatch(segs[1])) {
      return segs[1];
    }
    return null;
  }

  static bool _isAmazonProductHost(String host) {
    final h = host.replaceFirst(RegExp(r'^www\.'), '');
    return h == 'amazon.in' ||
        h == 'amazon.com' ||
        h.endsWith('.amazon.in') ||
        h.endsWith('.amazon.com');
  }

  static bool _isDefaultPort(String scheme, int port) =>
      (scheme == 'https' && port == 443) || (scheme == 'http' && port == 80);

  static String _build({
    required String scheme,
    required String host,
    required int? port,
    required String path,
    required List<String> query,
    required String fragment,
  }) {
    final buf = StringBuffer()
      ..write(scheme)
      ..write('://')
      ..write(host);
    if (port != null && !_isDefaultPort(scheme, port)) {
      buf.write(':');
      buf.write(port);
    }
    buf.write(path);
    if (query.isNotEmpty) {
      buf.write('?');
      buf.write(query.join('&'));
    }
    if (fragment.startsWith('/') || fragment.startsWith('!/')) {
      buf.write('#');
      buf.write(fragment);
    }
    return buf.toString();
  }

  static String? _queryValue(List<String> params, String key) {
    for (final p in params) {
      final i = p.indexOf('=');
      final k = (i < 0 ? p : p.substring(0, i)).toLowerCase();
      if (k == key) return i < 0 ? '' : p.substring(i + 1);
    }
    return null;
  }
}
