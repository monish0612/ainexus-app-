import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/presentation/screens/tutor/coach_diff.dart';

const _text = Color(0xFFF1F5F9);
const _added = Color(0xFF34D399);
const _removed = Color(0xFFF87171);

/// Flatten the rendered words (skipping the whitespace separator spans) into
/// a single string so we can assert exactly what the user sees.
String _rendered(List<InlineSpan> spans) {
  final buf = StringBuffer();
  for (final s in spans) {
    if (s is TextSpan) buf.write(s.text ?? '');
  }
  return buf.toString();
}

bool _anyStrikethrough(List<InlineSpan> spans) {
  for (final s in spans) {
    if (s is TextSpan &&
        s.style?.decoration == TextDecoration.lineThrough) {
      return true;
    }
  }
  return false;
}

List<TextSpan> _wordSpans(List<InlineSpan> spans) => spans
    .whereType<TextSpan>()
    .where((s) => (s.text ?? '').trim().isNotEmpty)
    .toList();

void main() {
  const original = 'i have a doubt i will catch a pain in 10 minutes';
  const corrected = 'I need to step away for about 10 minutes';

  group('coachCleanSpans (default Corrected view)', () {
    test('renders the full corrected sentence, in order', () {
      final spans = coachCleanSpans(
        original: original,
        corrected: corrected,
        textColor: _text,
        addedColor: _added,
      );
      expect(_rendered(spans), corrected);
    });

    test('NEVER renders strikethrough / removed words (the core fix)', () {
      final spans = coachCleanSpans(
        original: original,
        corrected: corrected,
        textColor: _text,
        addedColor: _added,
      );
      expect(_anyStrikethrough(spans), isFalse);
      // No removed-red coloured word should appear either.
      final hasRemovedColour = _wordSpans(spans)
          .any((s) => s.style?.color == _removed);
      expect(hasRemovedColour, isFalse);
    });

    test('highlights changed/added words in the added colour', () {
      final spans = coachCleanSpans(
        original: original,
        corrected: corrected,
        textColor: _text,
        addedColor: _added,
      );
      final added = _wordSpans(spans)
          .where((s) => s.style?.color == _added)
          .map((s) => s.text)
          .toList();
      // "need", "step", "away", "about" are genuine additions.
      expect(added, contains('need'));
      expect(added, contains('about'));
    });

    test('unchanged shared words keep the normal text colour', () {
      final spans = coachCleanSpans(
        original: original,
        corrected: corrected,
        textColor: _text,
        addedColor: _added,
      );
      final normalWords = _wordSpans(spans)
          .where((s) => s.style?.color == _text)
          .map((s) => s.text)
          .toList();
      // "10" and "minutes" are present in both → unchanged.
      expect(normalWords, containsAll(<String>['10', 'minutes']));
    });

    test('identical input and output highlights nothing', () {
      const same = 'this is already correct';
      final spans = coachCleanSpans(
        original: same,
        corrected: same,
        textColor: _text,
        addedColor: _added,
      );
      expect(_rendered(spans), same);
      expect(_anyStrikethrough(spans), isFalse);
      final hasAdded =
          _wordSpans(spans).any((s) => s.style?.color == _added);
      expect(hasAdded, isFalse);
    });

    test('empty original treats everything as an addition', () {
      final spans = coachCleanSpans(
        original: '',
        corrected: 'brand new text',
        textColor: _text,
        addedColor: _added,
      );
      expect(_rendered(spans), 'brand new text');
      expect(
        _wordSpans(spans).every((s) => s.style?.color == _added),
        isTrue,
      );
    });
  });

  group('coachDiffSpans (opt-in Changes view)', () {
    test('retains removed words as strikethrough', () {
      final spans = coachDiffSpans(
        original: original,
        corrected: corrected,
        textColor: _text,
        removedColor: _removed,
        addedColor: _added,
      );
      expect(_anyStrikethrough(spans), isTrue);
      // Removed words like "doubt"/"pain" should appear in the diff view.
      expect(_rendered(spans), contains('doubt'));
      expect(_rendered(spans), contains('pain'));
    });

    test('still contains every corrected word', () {
      final spans = coachDiffSpans(
        original: original,
        corrected: corrected,
        textColor: _text,
        removedColor: _removed,
        addedColor: _added,
      );
      final flat = _rendered(spans);
      for (final w in corrected.split(' ')) {
        expect(flat, contains(w));
      }
    });
  });
}
