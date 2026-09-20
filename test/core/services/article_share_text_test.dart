import 'dart:io';

import 'package:ai_nexus/core/services/article_share_text.dart';
import 'package:ai_nexus/core/services/followup_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FollowUpMessage user(String text) => FollowUpMessage(role: 'user', text: text);
  FollowUpMessage ai(String text) =>
      FollowUpMessage(role: 'assistant', text: text);

  test('share text is a chooser payload, not the full article body', () {
    const dumpedBody = 'Paragraph one of a very long article that must not leak.';
    final text = formatArticleShareText(
      title: 'Court ruling on housing',
      source: 'The Hindu',
      date: '17 Sep 2026',
      url: 'https://example.com/housing',
      snapshot: 'A short snapshot of the story.',
      messages: const [],
    );
    expect(text, contains('Nexus AI · News'));
    expect(text, contains('Court ruling on housing'));
    expect(text, contains('The Hindu'));
    expect(text, contains('https://example.com/housing'));
    expect(text, contains('A short snapshot of the story.'));
    expect(text, isNot(contains(dumpedBody)));
    expect(text, isNot(contains('Copied to clipboard')));
    expect(text, contains('— Shared from Nexus AI'));
    expect(text.contains('Follow-up'), isFalse);
  });

  test('completed follow-up Q&A is formatted as Question then Answer', () {
    final text = formatArticleShareText(
      title: 'Budget speech',
      source: 'Mint',
      url: 'https://example.com/budget',
      messages: [
        user('What changed for home loans?'),
        ai('The rate cap was lifted from April.'),
        user('Does this apply to existing EMIs?'),
        ai('Only new floating-rate loans from the notified date.'),
      ],
    );
    expect(text, contains('────────  Follow-up  ────────'));
    expect(text, contains('Question 1'));
    expect(text, contains('What changed for home loans?'));
    expect(text, contains('Answer 1'));
    expect(text, contains('The rate cap was lifted from April.'));
    expect(text, contains('Question 2'));
    expect(text, contains('Does this apply to existing EMIs?'));
    expect(text, contains('Answer 2'));
    expect(text, contains('Only new floating-rate loans from the notified date.'));
  });

  test('loading or error assistant turns are omitted', () {
    final qa = articleShareQaFromMessages([
      user('Why?'),
      const FollowUpMessage(
        role: 'assistant',
        text: 'partial',
        isLoading: true,
      ),
      user('Ready now?'),
      ai('Yes — here is the answer.'),
    ]);
    expect(qa, hasLength(1));
    expect(qa.single.question, 'Ready now?');
    expect(qa.single.answer, 'Yes — here is the answer.');
  });

  test('orphan question with no answer is omitted', () {
    final qa = articleShareQaFromMessages([
      user('Still thinking?'),
    ]);
    expect(qa, isEmpty);
  });

  test('article reader share path no longer copies to the clipboard', () {
    final src = File('lib/presentation/screens/news/article_detail_modal.dart')
        .readAsStringSync();
    expect(src, contains('ShareSheet.shareText'));
    expect(src, contains('formatArticleShareText'));
    expect(src, contains('loadShareMessages'));
    expect(src.contains('Clipboard.setData'), isFalse);
    expect(src.contains('Copied to clipboard'), isFalse);
  });
}
