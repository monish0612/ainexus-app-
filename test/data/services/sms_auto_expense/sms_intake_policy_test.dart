import 'package:ai_nexus/data/services/sms_auto_expense/sms_intake_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('onArrival', () {
    test('auto + Dart alive never shows queued/ask, even in background', () {
      expect(
        SmsIntakePolicy.onArrival(
          auto: true,
          dartListening: true,
          activityResumed: false,
        ),
        SmsArrivalKind.silentSave,
      );
    });

    test('auto + engine dead queues until open', () {
      expect(
        SmsIntakePolicy.onArrival(
          auto: true,
          dartListening: false,
          activityResumed: false,
        ),
        SmsArrivalKind.queued,
      );
    });

    test('ask + UI visible stays in-app', () {
      expect(
        SmsIntakePolicy.onArrival(
          auto: false,
          dartListening: true,
          activityResumed: true,
        ),
        SmsArrivalKind.inAppReview,
      );
    });

    test('ask + background uses tray Approve', () {
      expect(
        SmsIntakePolicy.onArrival(
          auto: false,
          dartListening: true,
          activityResumed: false,
        ),
        SmsArrivalKind.ask,
      );
    });
  });

  group('notification tap', () {
    test('auto tap saves every queued debit, never asks', () {
      expect(
        SmsIntakePolicy.onNotificationTap(auto: true),
        SmsOpenAction.saveAll,
      );
    });

    test('ask tap focuses that debit', () {
      expect(
        SmsIntakePolicy.onNotificationTap(auto: false),
        SmsOpenAction.reviewThis,
      );
    });
  });

  group('drain auto-save', () {
    test('auto pending and native-approved both save', () {
      expect(
        SmsIntakePolicy.shouldAutoSave(auto: true, status: 'pending'),
        isTrue,
      );
      expect(
        SmsIntakePolicy.shouldAutoSave(auto: true, status: 'approved'),
        isTrue,
      );
      expect(
        SmsIntakePolicy.shouldAutoSave(auto: false, status: 'pending'),
        isFalse,
      );
      expect(
        SmsIntakePolicy.shouldAutoSave(auto: false, status: 'approved'),
        isTrue,
      );
    });

    test('rejected/saved are not saved again', () {
      expect(
        SmsIntakePolicy.shouldAutoSave(auto: true, status: 'rejected'),
        isFalse,
      );
      expect(
        SmsIntakePolicy.shouldAutoSave(auto: true, status: 'saved'),
        isFalse,
      );
    });
  });

  group('review stack', () {
    test('second debit keeps the current card unless that notif was tapped', () {
      expect(
        SmsIntakePolicy.replaceReview(
          currentReviewId: 'one',
          incomingId: 'two',
          notificationTap: false,
        ),
        isFalse,
      );
      expect(
        SmsIntakePolicy.replaceReview(
          currentReviewId: 'one',
          incomingId: 'two',
          notificationTap: true,
        ),
        isTrue,
      );
    });

    test('tapping the first of two notifications still focuses that id', () {
      expect(
        SmsIntakePolicy.replaceReview(
          currentReviewId: 'two',
          incomingId: 'one',
          notificationTap: true,
        ),
        isTrue,
      );
    });
  });

  group('undo after edit', () {
    test('Others → Medical edit blocks SMS undo', () {
      expect(
        SmsIntakePolicy.undoStillValid(
          toastCategory: 'Others',
          toastDescription: 'Q227400652@ybl',
          liveCategory: 'Medical',
          liveDescription: 'Q227400652@ybl',
          liveManualCategory: true,
        ),
        isFalse,
      );
    });

    test('category change blocks delete', () {
      expect(
        SmsIntakePolicy.undoStillValid(
          toastCategory: 'Others',
          toastDescription: 'Swiggy',
          liveCategory: 'Food',
          liveDescription: 'Swiggy',
          liveManualCategory: true,
        ),
        isFalse,
      );
    });

    test('untouched toast may still undo', () {
      expect(
        SmsIntakePolicy.undoStillValid(
          toastCategory: 'Food',
          toastDescription: 'Swiggy',
          liveCategory: 'Food',
          liveDescription: 'Swiggy',
          liveManualCategory: false,
        ),
        isTrue,
      );
    });
  });

  group('expense day', () {
    test('nearby bank date is kept at local noon', () {
      final received = DateTime(2026, 9, 10, 15, 28);
      final day = SmsIntakePolicy.expenseDay(
        DateTime(2026, 9, 10),
        received,
      );
      expect(day, DateTime(2026, 9, 10, 12));
    });

    test('wild dd/mm misread falls back to received day so Today still shows it',
        () {
      final received = DateTime(2026, 9, 10, 15, 28);
      final day = SmsIntakePolicy.expenseDay(
        DateTime(2026, 10, 9),
        received,
      );
      expect(day, DateTime(2026, 9, 10, 12));
    });
  });
}
