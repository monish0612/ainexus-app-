import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 3a contract: the AI composer surfaces wait with `NexusLoader`, not
/// with bare spinners, and every animation they run is reduced-motion aware.
///
/// These are source-level assertions in the same spirit as
/// `test/android/phase6_ui_a11y_contract_test.dart` — the loading states they
/// cover are driven by live network calls, so pinning them through the widget
/// tree alone would be slow and flaky, while a restyle that quietly puts a
/// spinner back would sail straight through.
void main() {
  late String tutor;
  late String searchFollowUp;
  late String imageFollowUp;
  late String articleFollowUp;
  late String expenseAsk;
  late String voiceButton;

  /// Every composer surface this phase owns.
  late Map<String, String> composers;

  setUpAll(() {
    tutor = File('lib/presentation/screens/tutor/tutor_screen.dart')
        .readAsStringSync();
    searchFollowUp =
        File('lib/presentation/screens/tutor/search_followup_sheet.dart')
            .readAsStringSync();
    imageFollowUp =
        File('lib/presentation/screens/tutor/image_followup_sheet.dart')
            .readAsStringSync();
    articleFollowUp =
        File('lib/presentation/screens/news/article_followup_sheet.dart')
            .readAsStringSync();
    expenseAsk = File(
      'lib/presentation/screens/expense/modals/expense_ai_ask_sheet.dart',
    ).readAsStringSync();
    voiceButton =
        File('lib/presentation/widgets/voice_input_button.dart')
            .readAsStringSync();

    composers = <String, String>{
      'tutor_screen.dart': tutor,
      'search_followup_sheet.dart': searchFollowUp,
      'image_followup_sheet.dart': imageFollowUp,
      'article_followup_sheet.dart': articleFollowUp,
      'expense_ai_ask_sheet.dart': expenseAsk,
    };
  });

  group('loader variants are wired to the right wait', () {
    test('every composer waits with NexusLoader', () {
      composers.forEach((name, src) {
        expect(src.contains('nexus_loader.dart'), isTrue,
            reason: '$name must import the loader primitive');
        expect(src.contains('NexusLoader('), isTrue,
            reason: '$name must render NexusLoader');
      });
    });

    test('InsightAI picks research / think / vision by search kind', () {
      expect(tutor.contains('NexusLoaderVariant.vision'), isTrue,
          reason: 'image search must use the vision variant');
      expect(tutor.contains('NexusLoaderVariant.think'), isTrue,
          reason: 'Deep search must use the think variant');
      expect(tutor.contains('NexusLoaderVariant.research'), isTrue,
          reason: 'Lite search must use the research variant');
    });

    test('the image follow-up sheet waits on the vision variant', () {
      expect(imageFollowUp.contains('NexusLoaderVariant.vision'), isTrue);
    });

    test('the text follow-up sheets swap think for Deep, research for Lite',
        () {
      for (final src in <String>[searchFollowUp, articleFollowUp]) {
        expect(src.contains('NexusLoaderVariant.think'), isTrue);
        expect(src.contains('NexusLoaderVariant.research'), isTrue);
      }
    });

    test('Expense Ask AI waits on the research variant with stage copy', () {
      expect(expenseAsk.contains('NexusLoaderVariant.research'), isTrue);
      expect(expenseAsk.contains('stages:'), isTrue,
          reason: 'the weakest composer had no stage copy at all before');
    });
  });

  group('the bare spinners are gone', () {
    test('no composer renders a CircularProgressIndicator for its main wait',
        () {
      // tutor_screen.dart still hosts the Dictionary / Rephrase / Coach tabs,
      // which are out of this phase's scope, so it is checked by intent
      // below rather than by absence.
      for (final name in const <String>[
        'search_followup_sheet.dart',
        'image_followup_sheet.dart',
        'article_followup_sheet.dart',
        'expense_ai_ask_sheet.dart',
      ]) {
        expect(composers[name]!.contains('CircularProgressIndicator'), isFalse,
            reason: '$name must not fall back to a bare spinner');
      }
    });

    test('the follow-up sheets dropped _TypingDots and the progress bars', () {
      for (final src in <String>[
        searchFollowUp,
        imageFollowUp,
        articleFollowUp,
      ]) {
        expect(src.contains('_TypingDots'), isFalse);
        expect(src.contains('LinearProgressIndicator'), isFalse);
      }
    });

    test('the InsightAI summarizer loader is a NexusLoader', () {
      final loader = tutor.indexOf('Widget _summarizerLoadingWidget');
      expect(loader, greaterThan(-1));
      final body = tutor.substring(loader, loader + 2000);
      expect(body.contains('NexusLoader('), isTrue);
      expect(body.contains('CircularProgressIndicator'), isFalse);
    });
  });

  group('reduced motion', () {
    test('every composer surface consults reducedMotion(context)', () {
      composers.forEach((name, src) {
        expect(src.contains('reducedMotion(context)'), isTrue,
            reason: '$name animates, so it must honour the OS setting');
      });
      expect(voiceButton.contains('reducedMotion(context)'), isTrue);
    });
  });

  group('the phase copy survived the restyle', () {
    test('follow-up phase strings are still the shipped ones', () {
      for (final src in <String>[
        searchFollowUp,
        imageFollowUp,
        articleFollowUp,
      ]) {
        expect(src.contains('Thinking'), isTrue);
      }
    });
  });
}
