/// Pure SMS auto-log decisions. Native + Dart both follow this so a
/// notification tap, a second debit 15s later, and an end-of-day category
/// edit cannot disagree.
enum SmsArrivalKind {
  /// Flutter is alive — auto-save now. No tray card.
  silentSave,

  /// Engine was dead. Queue on disk; save the next time Nexus opens.
  queued,

  /// Ask mode, UI not visible. Tray card with Approve / Reject.
  ask,

  /// Ask mode, review sheet already on screen.
  inAppReview,
}

enum SmsOpenAction {
  /// Auto-save this id (and every other pending debit). Never show Approve.
  saveAll,

  /// Show / switch the in-app Approve sheet for this id. Keep the rest queued.
  reviewThis,
}

class SmsIntakePolicy {
  const SmsIntakePolicy._();

  /// What the BroadcastReceiver should do when a bank debit SMS lands.
  static SmsArrivalKind onArrival({
    required bool auto,
    required bool dartListening,
    required bool activityResumed,
  }) {
    if (auto) {
      return dartListening ? SmsArrivalKind.silentSave : SmsArrivalKind.queued;
    }
    if (dartListening && activityResumed) return SmsArrivalKind.inAppReview;
    return SmsArrivalKind.ask;
  }

  /// Notification tap / cold-start extra. Auto never asks.
  static SmsOpenAction onNotificationTap({required bool auto}) {
    return auto ? SmsOpenAction.saveAll : SmsOpenAction.reviewThis;
  }

  /// Drain loop: persist or park for the sheet.
  static bool shouldAutoSave({
    required bool auto,
    required String status,
  }) {
    if (status == 'rejected' || status == 'saved') return false;
    if (status == 'approved') return true;
    return auto && status == 'pending';
  }

  /// A later notification tap may replace the card the user is looking at.
  static bool replaceReview({
    required String? currentReviewId,
    required String incomingId,
    required bool notificationTap,
  }) {
    if (currentReviewId == null || currentReviewId.isEmpty) return true;
    if (currentReviewId == incomingId) return true;
    return notificationTap;
  }

  /// Undo must not delete after the user edited category / description.
  static bool undoStillValid({
    required String toastCategory,
    required String toastDescription,
    required String liveCategory,
    required String liveDescription,
    required bool liveManualCategory,
  }) {
    if (liveManualCategory) return false;
    if (liveCategory != toastCategory) return false;
    if (liveDescription != toastDescription) return false;
    return true;
  }

  /// SMS calendar date for the expense row. Trust the bank day when it is
  /// close to when the SMS arrived; otherwise use the phone's received day so
  /// a dd/mm vs mm/dd misread cannot hide the row from Today.
  static DateTime expenseDay(DateTime txn, DateTime received) {
    final t = DateTime(txn.year, txn.month, txn.day);
    final r = DateTime(received.year, received.month, received.day);
    if ((t.difference(r).inDays).abs() > 1) {
      return DateTime(r.year, r.month, r.day, 12);
    }
    return DateTime(t.year, t.month, t.day, 12);
  }

  static String expenseIdFor(String smsId) =>
      smsId.startsWith('sample-') ? smsId : 'sms-$smsId';
}
