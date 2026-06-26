// Hermetic tests for the OFFLINE categorization logic — the keyword rules,
// learnings votes, tokenizer, and the learn-from-correction memory. These run
// with zero network (the LLM fallback path is only reached when online and is
// not exercised here).

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/ai_categorize_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tokenize', () {
    test('lowercases, splits on punctuation/space, drops <=2 char tokens', () {
      expect(tokenize('Swiggy Order #42 - Lunch'),
          containsAll(<String>['swiggy', 'order', 'lunch']));
      // 2-char and shorter tokens are dropped ('a', 'to', 'go' all <= 2).
      expect(tokenize('a to go'), isEmpty);
    });

    test('splits on slashes, dashes, dots, parens', () {
      expect(tokenize('uber/ola (cab).ride'),
          containsAll(<String>['uber', 'ola', 'cab', 'ride']));
    });
  });

  group('categorizeLocal', () {
    test('too-short description → Others/default', () {
      final r = categorizeLocal('a', const {});
      expect(r.category, 'Others');
      expect(r.confidence, 'default');
      expect(r.score, 0);
    });

    test('keyword match classifies (Food)', () {
      final r = categorizeLocal('Dinner at Swiggy', const {});
      expect(r.category, 'Food');
      expect(r.confidence, 'matched');
    });

    test('keyword match classifies (Transport)', () {
      final r = categorizeLocal('Ola cab ride home', const {});
      expect(r.category, 'Transport');
    });

    test('no signal → Others/default with low score', () {
      final r = categorizeLocal('qwerty zxcvb', const {});
      expect(r.category, 'Others');
      expect(r.confidence, 'default');
      expect(r.score, 0.3);
    });

    test('learnings override keyword rules and win', () {
      // "swiggy" would normally be Food, but a learned correction maps the
      // token to "Snacks" — learnings take priority.
      final r = categorizeLocal('swiggy', const {'swiggy': 'Snacks'});
      expect(r.category, 'Snacks');
      expect(r.confidence, 'learned');
      expect(r.score, 0.97);
    });

    test('learnings vote — most frequent learned category wins', () {
      final r = categorizeLocal(
        'alpha beta alpha',
        const {'alpha': 'CatA', 'beta': 'CatB'},
      );
      expect(r.category, 'CatA');
    });

    test('"grooming" ambiguity resolves deterministically to Personal', () {
      // "grooming" appears in BOTH Personal and Pets keyword lists. Map
      // iteration is insertion order, and Personal is declared before Pets,
      // so it must deterministically classify as Personal. This locks the
      // documented behaviour so a future map reorder is caught.
      final r = categorizeLocal('grooming session', const {});
      expect(r.category, 'Personal');
    });
  });

  group('learnFromCorrection', () {
    final svc = AICategorizeService(ApiClient());

    test('stores words longer than 3 chars mapped to the chosen category', () {
      final updated =
          svc.learnFromCorrection('Tiffin from Mess', 'Food', const {});
      expect(updated['tiffin'], 'Food');
      expect(updated['from'], 'Food');
      expect(updated['mess'], 'Food');
    });

    test('does not mutate the original map', () {
      final original = <String, String>{};
      final updated = svc.learnFromCorrection('Zomato', 'Food', original);
      expect(original, isEmpty);
      expect(updated['zomato'], 'Food');
    });

    test('a learned correction then feeds categorizeLocal', () {
      final learnings = svc.learnFromCorrection('NeoBank xfer', 'Banking', const {});
      final r = categorizeLocal('NeoBank xfer', learnings);
      expect(r.category, 'Banking');
      expect(r.confidence, 'learned');
    });
  });
}
