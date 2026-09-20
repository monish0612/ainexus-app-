/// Pure routing for notification body/action taps. Kept free of plugin /
/// Flutter UI types so the decision can be unit-tested on a VM.
library;

const kNotifActionAddExpense = 'add_expense';
const kNotifActionDismiss = 'dismiss';
const kNotifActionEnterSalary = 'enter_salary';
const kNotifActionOpenNews = 'open_news';

const kNotifPayloadExpenseTab = 'expense_tab';
const kNotifPayloadExpenseAdd = 'expense_add';
const kNotifPayloadNewsTab = 'news_tab';
const kNotifPayloadTutorTab = 'tutor_tab';

/// Result of mapping a notification [actionId] + [payload] to an in-app route.
class NotificationTap {
  const NotificationTap({
    this.route,
    this.openExpenseAdd = false,
    this.dismissOnly = false,
  });

  /// Payload forwarded onto [notificationPayloadStream], or null when the
  /// tap should not navigate (e.g. Done).
  final String? route;

  /// Open the Add-expense sheet after switching to the Expenses tab.
  final bool openExpenseAdd;

  /// Headless dismiss — native side cancels the notification.
  final bool dismissOnly;
}

/// Maps a notification action (or a body tap) to a route.
///
/// Action ids win over the notification payload so "Add Expense" never
/// collapses into a no-op tab switch when the user is already on Expenses.
NotificationTap resolveNotificationTap({
  String? actionId,
  String? payload,
}) {
  switch (actionId) {
    case kNotifActionDismiss:
      return const NotificationTap(dismissOnly: true);
    case kNotifActionAddExpense:
      return const NotificationTap(
        route: kNotifPayloadExpenseAdd,
        openExpenseAdd: true,
      );
    case kNotifActionEnterSalary:
      return const NotificationTap(route: kNotifPayloadExpenseTab);
    case kNotifActionOpenNews:
      return const NotificationTap(route: kNotifPayloadNewsTab);
  }

  if (payload != null && payload.isNotEmpty) {
    return NotificationTap(route: payload);
  }
  return const NotificationTap();
}

/// Payloads [NotificationService] is allowed to broadcast into the UI.
bool isRoutableNotificationPayload(String payload) {
  return payload == kNotifPayloadExpenseTab ||
      payload == kNotifPayloadExpenseAdd ||
      payload == kNotifPayloadNewsTab ||
      payload == 'news_summary' ||
      payload == kNotifPayloadTutorTab ||
      payload.startsWith('watch:');
}
