import 'package:ai_nexus/data/services/ai_categorize_service.dart';
import 'package:ai_nexus/data/services/expense_category_memory.dart';
import 'package:ai_nexus/data/services/sms_auto_expense/sms_merchant_category.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('keysFor email / VPA', () {
    test('email@firstcry.com trains firstcry, not email or com', () {
      final keys = ExpenseCategoryMemory.keysFor('email@firstcry.com');
      expect(keys, contains('email@firstcry.com'));
      expect(keys, contains('firstcry.com'));
      expect(keys, contains('firstcry'));
      expect(keys, isNot(contains('email')));
      expect(keys, isNot(contains('com')));
    });

    test('opaque UPI handle does not treat the PSP as a shop', () {
      final keys = ExpenseCategoryMemory.keysFor('Q227400652@ybl');
      expect(keys, contains('q227400652@ybl'));
      expect(keys, isNot(contains('ybl')));
    });

    test('stopwords like from are never keys', () {
      final keys = ExpenseCategoryMemory.keysFor('Tiffin from Mess');
      expect(keys, contains('tiffin'));
      expect(keys, contains('mess'));
      expect(keys, isNot(contains('from')));
    });

    test('Auto Detected stamp is not teachable', () {
      expect(
        ExpenseCategoryMemory.isTeachable(
          'Auto Detected · 11 Sep 2026, 4:22 PM',
        ),
        isFalse,
      );
    });
  });

  group('matchLearned', () {
    test('a taught firstcry brand hits a different firstcry handle', () {
      final hit = ExpenseCategoryMemory.matchLearned(
        'care@firstcry.com',
        {'firstcry': 'Family'},
      );
      expect(hit?.category, 'Family');
      expect(hit?.key, 'firstcry');
    });

    test('exact VPA label wins before the brand', () {
      final hit = ExpenseCategoryMemory.matchLearned(
        'email@firstcry.com',
        {
          'email@firstcry.com': 'Gifts',
          'firstcry': 'Family',
        },
      );
      expect(hit?.category, 'Gifts');
    });
  });

  group('SMS + local categorizer', () {
    test('firstcry.com is Family even before Teach AI', () {
      expect(suggestSmsCategory('email@firstcry.com'), 'Family');
      expect(categorizeLocal('email@firstcry.com', const {}).category, 'Family');
    });

    test('taught brand overrides the built-in Family guess', () {
      expect(
        suggestSmsCategory(
          'email@firstcry.com',
          learnings: {'firstcry': 'Gifts'},
        ),
        'Gifts',
      );
    });

    test('opaque VPA stays Others until labeled', () {
      expect(suggestSmsCategory('Q227400652@ybl'), 'Others');
      expect(
        suggestSmsCategory(
          'Q227400652@ybl',
          labels: {'q227400652@ybl': 'Grocery'},
        ),
        'Grocery',
      );
    });
  });

  test('sms- id is SMS origin', () {
    final e = Expense(
      id: 'sms-abc',
      amount: 1,
      description: 'email@firstcry.com',
      category: 'Others',
      bank: 'HDFC',
      cardType: 'CC',
      date: DateTime(2026, 9, 11).toIso8601String(),
      isManualCategory: false,
      comments: 'Auto Detected · 11 Sep 2026, 5:00 PM',
    );
    expect(ExpenseCategoryMemory.isSmsOrigin(e), isTrue);
  });
}
