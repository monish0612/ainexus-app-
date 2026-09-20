import 'followup_history.dart';

/// One completed follow-up exchange for the article share payload.
class ArticleShareQa {
  const ArticleShareQa({required this.question, required this.answer});

  final String question;
  final String answer;
}

/// Pairs finalized user/assistant turns. Loading, error, and orphan
/// questions (no answer yet) are omitted.
List<ArticleShareQa> articleShareQaFromMessages(List<FollowUpMessage> messages) {
  const builder = FollowUpHistoryBuilder(config: FollowUpHistoryConfig());
  final pairs = builder.collectCompletedPairs(messages);
  final out = <ArticleShareQa>[];
  for (var i = 0; i + 1 < pairs.length; i += 2) {
    final q = _cleanShareChunk(pairs[i]['text']);
    final a = _cleanShareChunk(pairs[i + 1]['text']);
    if (q.isEmpty && a.isEmpty) continue;
    out.add(ArticleShareQa(
      question: q.isEmpty ? '(No question text)' : q,
      answer: a.isEmpty ? '(No answer yet)' : a,
    ));
  }
  return out;
}

/// Human-readable share body for the system chooser.
///
/// Never includes the full article body. Title, source, optional short
/// snapshot, link, then every completed follow-up Q&A.
String formatArticleShareText({
  required String title,
  required String source,
  String? date,
  String? url,
  String? snapshot,
  List<FollowUpMessage> messages = const [],
  List<ArticleShareQa>? qa,
}) {
  final turns = qa ?? articleShareQaFromMessages(messages);
  final buf = StringBuffer();
  buf.writeln('Nexus AI · News');
  buf.writeln();
  buf.writeln(_cleanShareChunk(title).isEmpty ? 'Untitled article' : _cleanShareChunk(title));
  buf.writeln();

  final meta = <String>[];
  final src = _cleanShareChunk(source);
  if (src.isNotEmpty) meta.add(src);
  final when = _cleanShareChunk(date);
  if (when.isNotEmpty) meta.add(when);
  if (meta.isNotEmpty) {
    buf.writeln(meta.join('  ·  '));
    buf.writeln();
  }

  final snap = _cleanShareChunk(snapshot);
  if (snap.isNotEmpty && snap != _cleanShareChunk(title)) {
    buf.writeln(snap);
    buf.writeln();
  }

  final link = (url ?? '').trim();
  if (link.isNotEmpty) {
    buf.writeln(link);
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
  return buf.toString().trimRight() + '\n';
}

String _cleanShareChunk(String? raw) {
  if (raw == null) return '';
  return raw.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
