import 'dart:io';

import 'package:ai_nexus/domain/entities/rephrase_platform.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins catalog + frozen overlay contracts so a new tone cannot silently
/// collide with Casual or break the Kotlin MethodChannel.
void main() {
  test('Tutor dropdown still has exactly the original eleven platforms', () {
    expect(kRephrasePlatforms.map((p) => p.id).toList(), [
      'own',
      'casual',
      'sarcastic',
      'slack',
      'email-short',
      'email-long',
      'whatsapp',
      'zoom',
      'twitter',
      'linkedin',
      'forum',
    ]);
  });

  test('every catalog id is unique across Rewrite / Tone / Chat', () {
    final ids = kAllRephraseActions.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate platform id');
  });

  test('new SwiftSlate-style ids are present and grouped', () {
    expect(kRewritePlatforms.map((p) => p.id).toList(), [
      'fix',
      'improve',
      'shorten',
      'expand',
      'human',
    ]);
    expect(kTonePlatforms.map((p) => p.id).toList(), [
      'own',
      'casual',
      'formal',
      'sarcastic',
      'emoji',
    ]);
    expect(kChatPlatforms.map((p) => p.id), containsAll(['reply', 'define']));
    expect(kChatPlatforms.map((p) => p.id), isNot(contains('own')));
  });

  test('groupForPlatformId defaults to Tone for unknown / empty', () {
    expect(groupForPlatformId(null), RephraseGroup.tone);
    expect(groupForPlatformId(''), RephraseGroup.tone);
    expect(groupForPlatformId('not-a-real-id'), RephraseGroup.tone);
    expect(groupForPlatformId('fix'), RephraseGroup.rewrite);
    expect(groupForPlatformId('whatsapp'), RephraseGroup.chat);
    expect(groupForPlatformId('own'), RephraseGroup.tone);
  });

  test('rephrasePlatformById looks up every catalog action', () {
    for (final platform in kAllRephraseActions) {
      expect(rephrasePlatformById(platform.id)?.id, platform.id);
    }
    expect(rephrasePlatformById('teams'), isNull);
  });

  test('chip labels stay unique so tests and Semantics do not collide', () {
    final labels = kAllRephraseActions.map((p) => p.chipLabel).toList();
    expect(labels.toSet().length, labels.length);
  });

  test('rewrite ids are not in the Tutor dropdown list (prepend is required)', () {
    final dropdownIds = kRephrasePlatforms.map((p) => p.id).toSet();
    for (final platform in kRewritePlatforms) {
      expect(dropdownIds.contains(platform.id), isFalse);
    }
    expect(dropdownIds.contains('reply'), isFalse);
    expect(dropdownIds.contains('define'), isFalse);
  });

  test('busy labels are short header copy, not chip labels', () {
    expect(rephrasePlatformById('fix')?.busyLabel, 'Fixing grammar…');
    expect(rephrasePlatformById('reply')?.busyLabel, 'Writing a reply…');
    expect(rephrasePlatformById('define')?.busyLabel, 'Looking up…');
    expect(rephrasePlatformById('own')?.busyLabel, 'Rephrasing…');
    for (final platform in kAllRephraseActions) {
      expect(platform.busyLabel.length, lessThan(24));
      expect(platform.busyLabel, isNot(equals(platform.chipLabel)));
    }
  });

  test('collapsed bubble icon is still liquid glass + wand, not the panel', () {
    final src = File('lib/bubble/overlay/bubble.dart').readAsStringSync();
    expect(src, contains('class RephraseBubble'));
    expect(src, contains('class _WandGlyph'));
    expect(src, contains('GlassContainer'));
    expect(src, contains('painter: _WandGlyph()'));
    expect(src, isNot(contains('RephrasePanel')));
    expect(src, isNot(contains('Icons.auto_fix')));
  });

  test('overlayMain and the overlay channel names stay frozen', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("vm:entry-point"));
    expect(main, contains('void overlayMain()'));
    expect(main, contains('runBubbleOverlay()'));

    final overlay = File('lib/bubble/overlay/overlay_app.dart').readAsStringSync();
    expect(overlay, contains(': RephraseBubble('));
    expect(overlay, contains('RephrasePanel('));
    expect(overlay, contains('ApiEndpoints.health'));

    final channels = File(
      'android/app/src/main/kotlin/app/ainexus/ai_nexus/bubble/Channels.kt',
    ).readAsStringSync();
    expect(channels, contains('OVERLAY_ENTRYPOINT = "overlayMain"'));
    expect(
      channels,
      contains('OVERLAY_METHOD = "app.ainexus.ai_nexus/bubble_overlay"'),
    );

    final writeBack = File(
      'android/app/src/main/kotlin/app/ainexus/ai_nexus/bubble/NodeTextIO.kt',
    ).readAsStringSync();
    expect(writeBack, contains('ACTION_SET_TEXT'));
    expect(
      writeBack,
      contains('a successful SET_TEXT must never fall through to PASTE'),
    );
  });

  test('bubble rephrase reads lite_model from Settings, not a hardcoded Gemini id',
      () {
    final src =
        File('lib/bubble/rephrase/bubble_rephrase_client.dart').readAsStringSync();
    expect(src, contains("getString('lite_model')"));
    expect(src, contains('prefs.reload()'));
    expect(src, contains('liteModel'));
    expect(src, isNot(contains('gemini-3.1-flash-lite-preview')));
    expect(src, isNot(contains('kDefaultLiteModel')));
  });
}
