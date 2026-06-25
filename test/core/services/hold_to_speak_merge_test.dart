import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/services/hold_to_speak_service.dart';

/// Regression tests for the hold-to-speak transcript de-duplication. These
/// lock in the fix for the "every word repeated twice" bug that happened when
/// holding the mic: Android's recognizer restarts mid-hold and/or re-emits
/// cumulative finals, and the old naive append doubled the transcript.
void main() {
  group('mergeVoiceTranscript', () {
    test('empty inputs', () {
      expect(mergeVoiceTranscript('', 'hello world'), 'hello world');
      expect(mergeVoiceTranscript('hello world', ''), 'hello world');
      expect(mergeVoiceTranscript('', ''), '');
      expect(mergeVoiceTranscript('  ', 'hi'), 'hi');
    });

    test('appends genuinely new words', () {
      expect(
        mergeVoiceTranscript('hello there', 'how are you'),
        'hello there how are you',
      );
    });

    test('exact re-send of the whole transcript is dropped', () {
      expect(
        mergeVoiceTranscript('pick up my son', 'pick up my son'),
        'pick up my son',
      );
    });

    test('case-insensitive exact re-send is dropped', () {
      expect(
        mergeVoiceTranscript('Pick Up My Son', 'pick up my son'),
        'Pick Up My Son',
      );
    });

    test('cumulative superset replaces (engine re-sent everything + more)', () {
      expect(
        mergeVoiceTranscript('hello', 'hello world'),
        'hello world',
      );
      expect(
        mergeVoiceTranscript(
          'I am going to drop',
          'I am going to drop off this call',
        ),
        'I am going to drop off this call',
      );
    });

    test('boundary overlap is stitched without repeating words', () {
      expect(
        mergeVoiceTranscript(
          'going to pick up my',
          'my son so how should I say',
        ),
        'going to pick up my son so how should I say',
      );
    });

    test('multi-word overlap of several words is collapsed', () {
      expect(
        mergeVoiceTranscript('I have a doubt', 'a doubt about this'),
        'I have a doubt about this',
      );
    });

    test('a new phrase that merely shares a leading word is kept', () {
      // "the" already appears at the tail, but "the store" is genuinely new —
      // the boundary overlap collapses only the repeated "the".
      expect(
        mergeVoiceTranscript('I want to go to the', 'the store'),
        'I want to go to the store',
      );
    });

    test('exact trailing word re-send is treated as an engine echo', () {
      // A lone trailing word that exactly repeats the current tail is almost
      // always a recognizer re-send on restart, so we drop it rather than
      // risk doubling. (Saying a word twice in a row is vanishingly rare.)
      expect(mergeVoiceTranscript('this is my', 'my'), 'this is my');
    });

    test('full-sentence duplicate (the screenshot bug) collapses to one copy',
        () {
      const sentence =
          'I have a doubt I want to drop off this Zoom call I have to '
          'pick up my son I will be back in about 10 minutes';
      // The engine re-sends the entire sentence on restart.
      expect(mergeVoiceTranscript(sentence, sentence), sentence);
    });

    test('repeated incremental finals never accumulate duplicates', () {
      // Simulate the controller folding several engine callbacks in sequence:
      // a mix of cumulative re-sends and one genuinely new tail.
      var committed = '';
      const callbacks = <String>[
        'son so how should I say',
        'son so how should I say', // exact re-send (silence-timeout restart)
        'son so how should I say that', // cumulative superset
        'that can I tell them', // boundary overlap on "that"
      ];
      for (final c in callbacks) {
        committed = mergeVoiceTranscript(committed, c);
      }
      expect(
        committed,
        'son so how should I say that can I tell them',
      );
    });
  });
}
