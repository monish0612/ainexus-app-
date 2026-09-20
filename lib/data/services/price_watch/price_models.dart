import 'store_url.dart';

/// In-memory product the UI and engine share. Drift maps to this.
class WatchItem {
  const WatchItem({
    required this.id,
    required this.name,
    required this.url,
    required this.canonicalUrl,
    required this.store,
    required this.currentPrice,
    required this.basePrice,
    required this.lastChecked,
    required this.createdAt,
    required this.checkIntervalMinutes,
    this.imageUrl = '',
    this.productId,
    this.identityKey = '',
    this.updatedAt,
    this.rev = 0,
    this.targetPrice,
    this.notifyOnDecrease = true,
    this.notifyOnIncrease = false,
    this.notifyOnTarget = true,
    this.isPaused = false,
    this.isPinned = false,
    this.manuallyPaused = false,
    this.pausedAt,
    this.pinnedAt,
    this.pendingPrice,
    this.pendingPriceAt,
    this.consecutiveFailures = 0,
    this.lastCheckError,
    this.availability,
    this.currencyCode = 'INR',
    this.lastSource = '',
    this.lastScore = 0,
  });

  final String id;
  final String name;
  final String url;
  final String canonicalUrl;
  final WatchStore store;
  final String? productId;
  final String identityKey;
  final DateTime? updatedAt;
  final int rev;
  final String imageUrl;
  final double currentPrice;
  final double basePrice;
  final DateTime lastChecked;
  final DateTime createdAt;
  final double? targetPrice;
  final bool notifyOnDecrease;
  final bool notifyOnIncrease;
  final bool notifyOnTarget;
  final int checkIntervalMinutes;
  final bool isPaused;
  final bool isPinned;
  final bool manuallyPaused;
  final DateTime? pausedAt;
  final DateTime? pinnedAt;
  final double? pendingPrice;
  final DateTime? pendingPriceAt;
  final int consecutiveFailures;
  final String? lastCheckError;
  final String? availability;
  final String currencyCode;
  final String lastSource;
  final int lastScore;

  bool get outOfStock =>
      (availability ?? '').toUpperCase().contains('OUT_OF_STOCK');

  String get resolvedIdentity => identityKey.isNotEmpty
      ? identityKey
      : watchIdentityKey(store, productId, canonicalUrl);

  bool get isDue {
    if (isPaused || checkIntervalMinutes <= 0) return false;
    return DateTime.now().difference(lastChecked) >=
        Duration(minutes: checkIntervalMinutes);
  }

  double get dropVsBase {
    if (basePrice <= 0) return 0;
    return ((basePrice - currentPrice) / basePrice) * 100;
  }

  WatchItem copyWith({
    String? name,
    String? url,
    String? canonicalUrl,
    WatchStore? store,
    String? productId,
    String? identityKey,
    DateTime? updatedAt,
    int? rev,
    String? imageUrl,
    double? currentPrice,
    double? basePrice,
    DateTime? lastChecked,
    double? targetPrice,
    bool? notifyOnDecrease,
    bool? notifyOnIncrease,
    bool? notifyOnTarget,
    int? checkIntervalMinutes,
    bool? isPaused,
    bool? isPinned,
    bool? manuallyPaused,
    DateTime? pausedAt,
    DateTime? pinnedAt,
    double? pendingPrice,
    DateTime? pendingPriceAt,
    int? consecutiveFailures,
    String? lastCheckError,
    String? availability,
    String? lastSource,
    int? lastScore,
    bool clearTarget = false,
    bool clearPending = false,
    bool clearError = false,
    bool clearPausedAt = false,
  }) {
    return WatchItem(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      store: store ?? this.store,
      productId: productId ?? this.productId,
      identityKey: identityKey ?? this.identityKey,
      updatedAt: updatedAt ?? this.updatedAt,
      rev: rev ?? this.rev,
      imageUrl: imageUrl ?? this.imageUrl,
      currentPrice: currentPrice ?? this.currentPrice,
      basePrice: basePrice ?? this.basePrice,
      lastChecked: lastChecked ?? this.lastChecked,
      createdAt: createdAt,
      targetPrice: clearTarget ? null : (targetPrice ?? this.targetPrice),
      notifyOnDecrease: notifyOnDecrease ?? this.notifyOnDecrease,
      notifyOnIncrease: notifyOnIncrease ?? this.notifyOnIncrease,
      notifyOnTarget: notifyOnTarget ?? this.notifyOnTarget,
      checkIntervalMinutes: checkIntervalMinutes ?? this.checkIntervalMinutes,
      isPaused: isPaused ?? this.isPaused,
      isPinned: isPinned ?? this.isPinned,
      manuallyPaused: manuallyPaused ?? this.manuallyPaused,
      pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
      pinnedAt: pinnedAt ?? this.pinnedAt,
      pendingPrice: clearPending ? null : (pendingPrice ?? this.pendingPrice),
      pendingPriceAt:
          clearPending ? null : (pendingPriceAt ?? this.pendingPriceAt),
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastCheckError: clearError ? null : (lastCheckError ?? this.lastCheckError),
      availability: availability ?? this.availability,
      currencyCode: currencyCode,
      lastSource: lastSource ?? this.lastSource,
      lastScore: lastScore ?? this.lastScore,
    );
  }
}

class WatchPricePoint {
  const WatchPricePoint({
    required this.id,
    required this.productId,
    required this.price,
    required this.checkedAt,
    this.source = '',
  });

  final String id;
  final String productId;
  final double price;
  final DateTime checkedAt;
  final String source;
}

class WatchAlert {
  const WatchAlert({
    required this.id,
    required this.productId,
    required this.productName,
    required this.oldPrice,
    required this.newPrice,
    required this.reason,
    required this.createdAt,
    this.imageUrl = '',
    this.isRead = false,
  });

  final String id;
  final String productId;
  final String productName;
  final String imageUrl;
  final double oldPrice;
  final double newPrice;
  final String reason;
  final DateTime createdAt;
  final bool isRead;
}

class ScrapeHit {
  const ScrapeHit({
    required this.price,
    required this.source,
    this.name = '',
    this.imageUrl = '',
    this.availability,
    this.score = 70,
    this.currency = 'INR',
    this.resolvedUrl,
    this.pageProductId,
  });

  final double price;
  final String source;
  final String name;
  final String imageUrl;
  final String? availability;
  final int score;
  final String currency;
  final String? resolvedUrl;
  final String? pageProductId;

  bool get lowConfidence => score >= 0 && score < 50;

  ScrapeHit withResolvedUrl(String url) {
    return ScrapeHit(
      price: price,
      source: source,
      name: name,
      imageUrl: imageUrl,
      availability: availability,
      score: score,
      currency: currency,
      resolvedUrl: url,
      pageProductId: pageProductId,
    );
  }
}

enum WatchCheckKind { periodic, confirm, retry, immediate, manual }

enum AlertReason { decrease, increase, target, significant }

String alertReasonLabel(AlertReason r) {
  switch (r) {
    case AlertReason.decrease:
      return 'dropped';
    case AlertReason.increase:
      return 'rose';
    case AlertReason.target:
      return 'hit target';
    case AlertReason.significant:
      return 'moved';
  }
}
