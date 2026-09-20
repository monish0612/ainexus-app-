import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/services/notification_tap.dart';

void main() {
  group('resolveNotificationTap — expense recap actions', () {
    test('Add Expense opens the add sheet, not a tab-only no-op', () {
      final tap = resolveNotificationTap(
        actionId: kNotifActionAddExpense,
        payload: kNotifPayloadExpenseTab,
      );
      expect(tap.route, kNotifPayloadExpenseAdd);
      expect(tap.openExpenseAdd, isTrue);
      expect(tap.dismissOnly, isFalse);
    });

    test('Add Expense still opens add when payload is missing', () {
      final tap = resolveNotificationTap(actionId: kNotifActionAddExpense);
      expect(tap.route, kNotifPayloadExpenseAdd);
      expect(tap.openExpenseAdd, isTrue);
    });

    test('Done dismisses without navigating', () {
      final tap = resolveNotificationTap(
        actionId: kNotifActionDismiss,
        payload: kNotifPayloadExpenseTab,
      );
      expect(tap.dismissOnly, isTrue);
      expect(tap.route, isNull);
      expect(tap.openExpenseAdd, isFalse);
    });

    test('body tap on the recap opens Expenses, not the add sheet', () {
      final tap = resolveNotificationTap(payload: kNotifPayloadExpenseTab);
      expect(tap.route, kNotifPayloadExpenseTab);
      expect(tap.openExpenseAdd, isFalse);
      expect(tap.dismissOnly, isFalse);
    });

    test('action id wins over a stale payload', () {
      final tap = resolveNotificationTap(
        actionId: kNotifActionAddExpense,
        payload: kNotifPayloadNewsTab,
      );
      expect(tap.route, kNotifPayloadExpenseAdd);
      expect(tap.openExpenseAdd, isTrue);
    });
  });

  group('resolveNotificationTap — other notifications', () {
    test('Read Now opens the news tab', () {
      final tap = resolveNotificationTap(
        actionId: kNotifActionOpenNews,
        payload: kNotifPayloadNewsTab,
      );
      expect(tap.route, kNotifPayloadNewsTab);
    });

    test('Enter salary lands on Expenses', () {
      final tap = resolveNotificationTap(
        actionId: kNotifActionEnterSalary,
        payload: kNotifPayloadExpenseTab,
      );
      expect(tap.route, kNotifPayloadExpenseTab);
      expect(tap.openExpenseAdd, isFalse);
    });

    test('Later / Done on any recap is dismiss-only', () {
      expect(
        resolveNotificationTap(actionId: kNotifActionDismiss).dismissOnly,
        isTrue,
      );
    });

    test('empty action and payload is a no-op', () {
      final tap = resolveNotificationTap();
      expect(tap.route, isNull);
      expect(tap.dismissOnly, isFalse);
    });

    test('unknown payload is forwarded verbatim', () {
      final tap = resolveNotificationTap(payload: 'watch:abc');
      expect(tap.route, 'watch:abc');
    });
  });

  group('isRoutableNotificationPayload', () {
    test('accepts expense add and tab', () {
      expect(isRoutableNotificationPayload(kNotifPayloadExpenseAdd), isTrue);
      expect(isRoutableNotificationPayload(kNotifPayloadExpenseTab), isTrue);
    });

    test('rejects empty and unknown', () {
      expect(isRoutableNotificationPayload(''), isFalse);
      expect(isRoutableNotificationPayload('garbage'), isFalse);
    });

    test('accepts watch deep links', () {
      expect(isRoutableNotificationPayload('watch:sku-1'), isTrue);
    });
  });
}
