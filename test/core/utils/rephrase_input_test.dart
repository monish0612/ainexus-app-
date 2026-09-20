import 'package:ai_nexus/core/utils/rephrase_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// These helpers back both the Tutor "Own" field and the floating bubble's tone
/// prompt, so the split between instruction and text must stay exact.
void main() {
  group('parseOwnRephraseInput', () {
    test('splits intent from double-quoted text', () {
      final parsed =
          parseOwnRephraseInput('Rephrase to formal tone "please send the report"');
      expect(parsed.intent, 'formal tone');
      expect(parsed.text, 'please send the report');
    });

    test('handles smart quotes', () {
      final parsed = parseOwnRephraseInput('make it punchy \u201chi there\u201d');
      expect(parsed.intent, 'make it punchy');
      expect(parsed.text, 'hi there');
    });

    test('handles single quotes that are not apostrophes', () {
      final parsed = parseOwnRephraseInput("shorter 'call me back'");
      expect(parsed.intent, 'shorter');
      expect(parsed.text, 'call me back');
    });

    test('treats unquoted input as the text with no intent', () {
      final parsed = parseOwnRephraseInput('hello world');
      expect(parsed.intent, '');
      expect(parsed.text, 'hello world');
    });

    test('strips a leading rephrase prefix when there are no quotes', () {
      final parsed = parseOwnRephraseInput('rephrase this to hello world');
      expect(parsed.intent, '');
      expect(parsed.text, 'hello world');
    });

    test('empty input yields empty parts', () {
      final parsed = parseOwnRephraseInput('   ');
      expect(parsed.intent, '');
      expect(parsed.text, '');
    });
  });

  group('stripRephrasePrefix', () {
    test('drops the rephrase leader the bubble users tend to type', () {
      expect(stripRephrasePrefix('rephrase to professional simple'),
          'professional simple');
      expect(stripRephrasePrefix('Rephrase this as friendly'), 'friendly');
      expect(stripRephrasePrefix('  on my own tone  '), 'on my own tone');
    });

    test('leaves a bare tone untouched', () {
      expect(stripRephrasePrefix('sarcastic but short'), 'sarcastic but short');
    });
  });
}
