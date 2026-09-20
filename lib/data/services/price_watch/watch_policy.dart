import 'price_models.dart';

const kPendingJumpPercent = 35.0;
const kConfirmDelay = Duration(minutes: 10);
const kRetryDelay = Duration(minutes: 5);
const kMaxRetries = 2;
const kMinIntervalMinutes = 15;
const kDefaultIntervalMinutes = 60;
const kMaxIntervalMinutes = 43200;

class CheckDecision {
  const CheckDecision.accept(this.price, {this.notify = true})
      : pending = false,
        failed = false;

  const CheckDecision.pending(this.price)
      : notify = false,
        pending = true,
        failed = false;

  const CheckDecision.fail()
      : price = null,
        notify = false,
        pending = false,
        failed = true;

  final double? price;
  final bool pending;
  final bool failed;
  final bool notify;
}

/// Droplert accept / quarantine / keep-previous.
///
/// A swing larger than [kPendingJumpPercent] vs the last accepted price is
/// treated as a possible scrape miss and parked for a 10-minute confirm.
CheckDecision decideCheck({
  required double? newPrice,
  required double lastPrice,
  required int score,
  required bool confirming,
  double? pendingPrice,
}) {
  if (newPrice == null || newPrice <= 0) return const CheckDecision.fail();
  if (score >= 0 && score < 50 && !confirming) {
    return CheckDecision.pending(newPrice);
  }
  if (!confirming && lastPrice > 0) {
    final jump = ((newPrice - lastPrice).abs() / lastPrice) * 100;
    if (jump >= kPendingJumpPercent) {
      return CheckDecision.pending(newPrice);
    }
  }
  if (confirming) {
    if (pendingPrice != null) {
      final agree =
          ((newPrice - pendingPrice).abs() / (pendingPrice == 0 ? 1 : pendingPrice)) *
              100;
      if (agree > 8) {
        // Confirm pass disagrees — keep previous, do not notify.
        return const CheckDecision.fail();
      }
    }
  }
  return CheckDecision.accept(newPrice);
}

List<AlertReason> decideAlerts({
  required WatchItem product,
  required double oldPrice,
  required double newPrice,
  required bool globalDecrease,
  required bool globalIncrease,
  required bool globalTarget,
}) {
  if (newPrice == oldPrice) return const [];
  final reasons = <AlertReason>[];
  if (product.notifyOnTarget &&
      globalTarget &&
      product.targetPrice != null &&
      newPrice <= product.targetPrice!) {
    reasons.add(AlertReason.target);
  }
  if (product.notifyOnDecrease && globalDecrease && newPrice < oldPrice) {
    reasons.add(AlertReason.decrease);
  }
  if (product.notifyOnIncrease && globalIncrease && newPrice > oldPrice) {
    reasons.add(AlertReason.increase);
  }
  return reasons;
}

bool inQuietHours(DateTime now, {required bool enabled, int start = 22, int end = 8}) {
  if (!enabled) return false;
  final h = now.hour;
  if (start == end) return false;
  if (start > end) {
    return h >= start || h < end;
  }
  return h >= start && h < end;
}
