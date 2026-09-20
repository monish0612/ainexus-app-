import 'dart:io';

import 'package:ai_nexus/core/services/article_share_text.dart';
import 'package:ai_nexus/core/services/followup_history.dart';
import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:ai_nexus/core/services/search_share_text.dart';
import 'package:ai_nexus/core/services/share_sheet.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FollowUpMessage user(String text) => FollowUpMessage(role: 'user', text: text);
  FollowUpMessage ai(String text) =>
      FollowUpMessage(role: 'assistant', text: text);

  GroundedSearchResponse grounded({
    String answer = 'Grounded answer body.',
    String model = 'gemini-2.5-flash',
  }) =>
      GroundedSearchResponse(
        answer: answer,
        query: 'ignored-query',
        model: model,
        searchQueries: const ['q'],
        sources: const [],
        citations: const [],
      );

  test('search share includes header, query, answer, not a clipboard dump', () {
    final text = formatSearchShareText(
      query: 'who won the match?',
      kind: SearchShareKind.search,
      model: 'gemini-2.5-flash',
      response: 'India won by 4 wickets.',
      messages: const [],
    );
    expect(text, contains('Nexus AI · Search'));
    expect(text, contains('who won the match?'));
    expect(text, contains('gemini-2.5-flash'));
    expect(text, contains('India won by 4 wickets.'));
    expect(text, contains('— Shared from Nexus AI'));
    expect(text, isNot(contains('Copied to clipboard')));
    expect(text.contains('Follow-up'), isFalse);
    expect(text.endsWith('\n'), isTrue);
  });

  test('completed follow-up Q&A is formatted like news share', () {
    final text = formatSearchShareText(
      query: 'IPL final',
      response: 'The final was in Ahmedabad.',
      messages: [
        user('Who scored the most?'),
        ai('Kohli, with 89 off 61.'),
        user('What was the margin?'),
        ai('Five wickets with four balls left.'),
      ],
    );
    expect(text, contains('────────  Follow-up  ────────'));
    expect(text, contains('Question 1'));
    expect(text, contains('Who scored the most?'));
    expect(text, contains('Answer 1'));
    expect(text, contains('Kohli, with 89 off 61.'));
    expect(text, contains('Question 2'));
    expect(text, contains('What was the margin?'));
    expect(text, contains('Answer 2'));
    expect(text, contains('Five wickets with four balls left.'));
    expect(text, contains('· · ·'));
  });

  test('a single completed pair is labelled Question not Question 1', () {
    final text = formatSearchShareText(
      query: 'one turn',
      response: 'body',
      messages: [user('Only this?'), ai('Yes.')],
    );
    expect(text, contains('Question\nOnly this?'));
    expect(text, contains('Answer\nYes.'));
    expect(text, isNot(contains('Question 1')));
    expect(text, isNot(contains('· · ·')));
  });

  test('loading assistant turns are omitted from search share Q&A', () {
    final qa = articleShareQaFromMessages([
      user('Still going?'),
      const FollowUpMessage(
        role: 'assistant',
        text: 'partial',
        isLoading: true,
      ),
      user('Now?'),
      ai('Done.'),
    ]);
    expect(qa, hasLength(1));
    expect(qa.single.question, 'Now?');
    expect(qa.single.answer, 'Done.');
  });

  test('error assistant turns and orphan questions are omitted', () {
    final qa = articleShareQaFromMessages([
      user('Broken?'),
      const FollowUpMessage(
        role: 'assistant',
        text: 'boom',
        isError: true,
      ),
      user('Hanging with no answer?'),
    ]);
    expect(qa, isEmpty);
  });

  test('blank query, kind, model, and body still produce a chooser payload', () {
    final text = formatSearchShareText(
      query: '   ',
      kind: ' \n ',
      model: '\t',
      response: '\r\n  \r\n',
    );
    expect(text, contains('Nexus AI · Search'));
    expect(text, contains('Untitled'));
    expect(text, isNot(contains('Nexus AI ·  ')));
    expect(text, contains('— Shared from Nexus AI'));
    expect(text.contains('Follow-up'), isFalse);
  });

  test('CRLF and stacked blank lines are collapsed in every chunk', () {
    final text = formatSearchShareText(
      query: 'line one\r\n\r\n\r\nline two',
      response: 'para A\r\n\r\n\r\npara B',
      messages: [
        user('q\r\n\r\n\r\nx'),
        ai('a\r\n\r\n\r\ny'),
      ],
    );
    expect(text, contains('line one\n\nline two'));
    expect(text, contains('para A\n\npara B'));
    expect(text, isNot(contains('\r')));
    expect(text, isNot(contains('\n\n\n')));
  });

  test('grounded result draft uses the live query and answer', () {
    final draft = searchShareDraftFromResult(
      grounded(),
      fallbackQuery: 'chennai rain today',
    );
    expect(draft.kind, SearchShareKind.search);
    expect(draft.query, 'chennai rain today');
    expect(draft.response, 'Grounded answer body.');
    expect(draft.model, 'gemini-2.5-flash');
  });

  test('tavily draft labels the model Tavily and keeps the typed query', () {
    const result = TavilySearchResponse(
      answer: 'Tavily said hello.',
      query: 'ignored',
      results: [],
    );
    final draft = searchShareDraftFromResult(
      result,
      fallbackQuery: 'typed query',
    );
    expect(draft.kind, SearchShareKind.search);
    expect(draft.query, 'typed query');
    expect(draft.response, 'Tavily said hello.');
    expect(draft.model, 'Tavily');
  });

  test('image draft prefers typed query, then the vision question, then a label',
      () {
    final image = ImageGroundedResult(
      response: grounded(answer: 'A red bus.', model: 'gemini-2.5-flash'),
      thumbDataUrl: '',
      originalMediaType: 'image/jpeg',
      question: 'What vehicle is this?',
    );
    expect(
      searchShareDraftFromResult(image, fallbackQuery: 'street photo').query,
      'street photo',
    );
    expect(
      searchShareDraftFromResult(image, fallbackQuery: '  ').query,
      'What vehicle is this?',
    );
    expect(
      searchShareDraftFromResult(
        ImageGroundedResult(
          response: grounded(answer: 'Nothing typed.'),
          thumbDataUrl: '',
          originalMediaType: 'image/png',
          question: '  ',
        ),
        fallbackQuery: '',
      ).query,
      'Image analysis',
    );
    expect(
      searchShareDraftFromResult(image, fallbackQuery: '').kind,
      SearchShareKind.image,
    );
  });

  test('summarizer draft includes key takeaways in the body', () {
    const result = SummarizerResult(
      title: 'Budget night',
      summary: 'Taxes stay flat.',
      keyPoints: ['No surcharge', 'Rebate extended'],
      category: 'Finance',
      readTime: 3,
      source: 'Mint',
      extractionMethod: 'direct-fetch',
      url: 'https://example.com/budget',
      model: 'gemini-2.5-pro',
    );
    final draft = searchShareDraftFromResult(
      result,
      fallbackQuery: 'https://example.com/budget',
    );
    expect(draft.kind, SearchShareKind.urlSummary);
    expect(draft.query, 'Budget night');
    expect(draft.response, contains('Taxes stay flat.'));
    expect(draft.response, contains('Key takeaways'));
    expect(draft.response, contains('1. No surcharge'));
    expect(draft.response, contains('2. Rebate extended'));
  });

  test('summarizer without a title falls back to URL then the typed query', () {
    expect(
      searchShareDraftFromResult(
        const SummarizerResult(
          title: '  ',
          summary: 's',
          keyPoints: [],
          category: '',
          readTime: 1,
          source: '',
          extractionMethod: '',
          url: 'https://example.com/x',
          model: '',
        ),
        fallbackQuery: 'typed',
      ).query,
      'https://example.com/x',
    );
    expect(
      searchShareDraftFromResult(
        const SummarizerResult(
          title: '',
          summary: 's',
          keyPoints: [],
          category: '',
          readTime: 1,
          source: '',
          extractionMethod: '',
          url: '  ',
          model: '',
        ),
        fallbackQuery: 'typed',
      ).query,
      'typed',
    );
  });

  test('unknown result types still share the typed query with an empty body', () {
    final draft = searchShareDraftFromResult(
      'not-a-result',
      fallbackQuery: 'keep me',
    );
    expect(draft.kind, SearchShareKind.search);
    expect(draft.query, 'keep me');
    expect(draft.response, isEmpty);
  });

  test('persisted chat rows map into follow-up share messages with sources', () {
    final messages = searchShareMessagesFromPersisted(const [
      PersistedChatMessage(
        id: 'u1',
        searchId: 's1',
        role: 'user',
        text: 'Why?',
        model: '',
        sources: [],
        createdAt: '2026-09-17T00:00:00Z',
      ),
      PersistedChatMessage(
        id: 'a1',
        searchId: 's1',
        role: 'assistant',
        text: 'Because rates moved.',
        model: 'flash',
        sources: [
          GroundedSource(index: 0, title: 'RBI', url: 'https://rbi.example/x'),
        ],
        createdAt: '2026-09-17T00:00:01Z',
      ),
    ]);
    expect(messages, hasLength(2));
    expect(messages.first.role, 'user');
    expect(messages.last.text, 'Because rates moved.');
    expect(messages.last.sources, hasLength(1));
    expect(messages.last.sources.single.url, 'https://rbi.example/x');
    expect(searchShareMessagesFromPersisted(const []), isEmpty);
  });

  test('formatting a long answer plus many Q&A turns stays under 50ms', () {
    final pairs = <FollowUpMessage>[];
    for (var i = 0; i < 80; i++) {
      pairs.add(user('Question number $i with extra context for length.'));
      pairs.add(ai('Answer number $i with a slightly longer body of text.'));
    }
    final bulky = 'word ' * 4000;
    final sw = Stopwatch()..start();
    final text = formatSearchShareText(
      query: 'bulk share',
      response: bulky,
      messages: pairs,
    );
    sw.stop();
    expect(text, contains('Question 80'));
    expect(text, contains('Answer 80'));
    expect(sw.elapsedMilliseconds, lessThan(50));
  });

  test('empty share sheet text is rejected without throwing', () async {
    expect(await ShareSheet.shareText(text: '   '), isFalse);
  });

  test('wiring: save, follow-up, and copy stay next to the new share path', () {
    final tutor = File('lib/presentation/screens/tutor/tutor_screen.dart')
        .readAsStringSync();
    expect(tutor, contains('shareInsightResult('));
    expect(tutor, contains('_buildShareSaveCluster'));
    expect(tutor, contains('_buildSaveResultButton'));
    expect(tutor, contains('_toggleSaveResult'));
    expect(tutor, contains('_activeSearchIsSaved'));
    expect(tutor, contains('SearchFollowUpFab'));
    expect(tutor, contains('Clipboard.setData'));
    expect(tutor, contains('Future<void> _copy('));
    expect(RegExp(r'(?<!Block)SelectableText').hasMatch(tutor), isFalse);
    expect(RegExp(r'_buildShareSaveCluster\(').allMatches(tutor).length, 5);
    expect(RegExp(r'ownSelectionScope: false').allMatches(tutor).length, 4);

    final lookup =
        File('lib/presentation/screens/tutor/search_lookup_screen.dart')
            .readAsStringSync();
    expect(lookup, contains('shareInsightResult('));
    expect(lookup, contains('SearchFollowUpFab'));
    expect(lookup, contains('_copy('));
    expect(lookup, contains('ownSelectionScope: false'));

    final saved =
        File('lib/presentation/screens/tutor/saved_search_detail_sheet.dart')
            .readAsStringSync();
    expect(saved, contains("tooltip: 'Share'"));
    expect(saved, contains("tooltip: 'Delete'"));
    expect(saved, contains('shareInsightResult('));

    final news =
        File('lib/presentation/screens/news/article_detail_modal.dart')
            .readAsStringSync();
    expect(news, contains('formatArticleShareText'));
    expect(news, contains('ShareSheet.shareText'));
    expect(news.contains('Clipboard.setData'), isFalse);
  });
}
