import '../../domain/entities/tutor_entities.dart';
import 'article_share_text.dart';
import 'followup_history.dart';
import 'saved_search_store.dart';
import 'share_sheet.dart';

/// Header kind in the share payload (`Nexus AI · Search`).
class SearchShareKind {
  SearchShareKind._();
  static const search = 'Search';
  static const urlSummary = 'URL summary';
  static const image = 'Image analysis';
}

/// Fields extracted from a live or saved InsightAI result.
class SearchShareDraft {
  const SearchShareDraft({
    required this.kind,
    required this.query,
    required this.response,
    this.model = '',
  });

  final String kind;
  final String query;
  final String response;
  final String model;
}

/// Chooser payload: header, query, answer, then completed follow-up Q&A.
///
/// Mirrors [formatArticleShareText] so News and Search share the same
/// rhythm. Unlike news, the search *answer* is the body — it is included.
String formatSearchShareText({
  required String query,
  String kind = SearchShareKind.search,
  String? model,
  required String response,
  List<FollowUpMessage> messages = const [],
  List<ArticleShareQa>? qa,
}) {
  final turns = qa ?? articleShareQaFromMessages(messages);
  final buf = StringBuffer();
  final headerKind = _cleanShareChunk(kind).isEmpty
      ? SearchShareKind.search
      : _cleanShareChunk(kind);
  buf.writeln('Nexus AI · $headerKind');
  buf.writeln();

  final q = _cleanShareChunk(query);
  buf.writeln(q.isEmpty ? 'Untitled' : q);
  buf.writeln();

  final m = _cleanShareChunk(model);
  if (m.isNotEmpty) {
    buf.writeln(m);
    buf.writeln();
  }

  final body = _cleanShareChunk(response);
  if (body.isNotEmpty) {
    buf.writeln(body);
    buf.writeln();
  }

  if (turns.isNotEmpty) {
    buf.writeln('────────  Follow-up  ────────');
    buf.writeln();
    for (var i = 0; i < turns.length; i++) {
      final n = i + 1;
      buf.writeln('Question${turns.length == 1 ? '' : ' $n'}');
      buf.writeln(turns[i].question);
      buf.writeln();
      buf.writeln('Answer${turns.length == 1 ? '' : ' $n'}');
      buf.writeln(turns[i].answer);
      if (i < turns.length - 1) {
        buf.writeln();
        buf.writeln('· · ·');
        buf.writeln();
      }
    }
    buf.writeln();
  }

  buf.writeln('— Shared from Nexus AI');
  return '${buf.toString().trimRight()}\n';
}

SearchShareDraft searchShareDraftFromResult(
  Object result, {
  required String fallbackQuery,
}) {
  if (result is GroundedSearchResponse) {
    return SearchShareDraft(
      kind: SearchShareKind.search,
      query: fallbackQuery,
      response: result.answer,
      model: result.model,
    );
  }
  if (result is TavilySearchResponse) {
    return SearchShareDraft(
      kind: SearchShareKind.search,
      query: fallbackQuery,
      response: result.answer,
      model: 'Tavily',
    );
  }
  if (result is ImageGroundedResult) {
    final q = fallbackQuery.trim().isNotEmpty
        ? fallbackQuery
        : (result.question.trim().isNotEmpty
            ? result.question
            : 'Image analysis');
    return SearchShareDraft(
      kind: SearchShareKind.image,
      query: q,
      response: result.answer,
      model: result.model,
    );
  }
  if (result is SummarizerResult) {
    final buf = StringBuffer(result.summary);
    if (result.keyPoints.isNotEmpty) {
      buf.writeln();
      buf.writeln();
      buf.writeln('Key takeaways');
      for (var i = 0; i < result.keyPoints.length; i++) {
        buf.writeln('${i + 1}. ${result.keyPoints[i]}');
      }
    }
    final q = result.title.trim().isNotEmpty
        ? result.title
        : (result.url.trim().isNotEmpty ? result.url : fallbackQuery);
    return SearchShareDraft(
      kind: SearchShareKind.urlSummary,
      query: q,
      response: buf.toString(),
      model: result.model,
    );
  }
  return SearchShareDraft(
    kind: SearchShareKind.search,
    query: fallbackQuery,
    response: '',
  );
}

List<FollowUpMessage> searchShareMessagesFromPersisted(
  List<PersistedChatMessage> rows,
) {
  return [
    for (final m in rows)
      FollowUpMessage(
        role: m.role,
        text: m.text,
        model: m.model,
        sources: [
          for (final s in m.sources)
            FollowUpSourceRef(url: s.url, title: s.title),
        ],
      ),
  ];
}

/// Opens the OS share sheet. Never writes the clipboard.
Future<bool> shareInsightResult({
  required Object result,
  required String query,
  List<FollowUpMessage> messages = const [],
}) {
  final draft = searchShareDraftFromResult(result, fallbackQuery: query);
  return ShareSheet.shareText(
    text: formatSearchShareText(
      query: draft.query,
      kind: draft.kind,
      model: draft.model,
      response: draft.response,
      messages: messages,
    ),
    subject: draft.query.isEmpty ? 'Nexus AI' : draft.query,
  );
}

String _cleanShareChunk(String? raw) {
  if (raw == null) return '';
  return raw
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
