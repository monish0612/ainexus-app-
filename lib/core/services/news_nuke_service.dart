import '../../data/repositories/news_repository.dart';
import 'nuke_report.dart';
import 'telegram_logger.dart';

/// The news-scope "nuke" engine — triggered by typing `nuke` into the News
/// tab's saved-articles search box. It permanently deletes EVERY article,
/// **including saved ones**, both locally and on the server (where each guid
/// is tombstoned so the RSS/X schedulers can't immediately re-import them).
///
/// Emits the same [NukeReport] shape as [AppNukeService] / [ExpenseNukeService]
/// so the shared cinematic result window renders it unchanged.
class NewsNukeService {
  NewsNukeService(this._repo);

  final NewsRepository _repo;

  static const _tag = 'Nuke';

  Future<NukeReport> nuke() async {
    final sw = Stopwatch()..start();

    var removed = 0;
    var serverOk = false;
    try {
      final result = await _repo.clearAllNews();
      removed = result.removed;
      serverOk = result.serverOk;
    } catch (e, st) {
      // clearAllNews swallows its own server errors, so reaching here means the
      // local wipe itself failed — surface it but still emit a (zeroed) report.
      TLog.e(_tag, 'News nuke failed', error: e, st: st);
    }

    sw.stop();

    final summary = serverOk
        ? '✅ local wiped + server cleared'
        : '⏳ local wiped — server clear pending/failed';
    TLog.w(
      _tag,
      '☢️ NEWS NUKE complete in ${sw.elapsedMilliseconds}ms — removed $removed '
      'article(s) incl. saved — $summary',
    );

    return NukeReport(
      scope: NukeScope.news,
      elapsedMs: sw.elapsedMilliseconds,
      fullySynced: serverOk,
      lines: [
        NukeLine(label: 'News', emoji: '📰', count: removed, cloudSynced: serverOk),
      ],
    );
  }
}
