import 'dart:io';

import 'package:ai_nexus/data/services/narration_models.dart';
import 'package:ai_nexus/data/services/narration_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a leftover completed event cannot skip the next track', () {
    final gate = NarrationAdvanceGate();
    expect(gate.onState('completed'), isFalse);
    expect(gate.onState('loading'), isFalse);
    expect(gate.onState('ready'), isFalse);
    expect(gate.onState('completed'), isTrue);
    expect(gate.onState('completed'), isFalse);
    expect(gate.onState('buffering'), isFalse);
    expect(gate.onState('completed'), isTrue);
  });

  test('play tap after completed restarts instead of no-op play()', () {
    expect(
      narrationPlayTap(isThisArticle: false, completed: false),
      NarrationPlayTap.start,
    );
    expect(
      narrationPlayTap(isThisArticle: true, completed: false),
      NarrationPlayTap.toggle,
    );
    expect(
      narrationPlayTap(isThisArticle: true, completed: true),
      NarrationPlayTap.restart,
    );
    expect(
      narrationPlayTap(isThisArticle: false, completed: true),
      NarrationPlayTap.start,
    );
  });

  test('ready audio plays without ensure; local file also skips ensure', () {
    for (final status in NarrationJobStatus.values) {
      expect(
        shouldEnsureBeforePlay(
          NarrationJob(status: status),
          localReady: true,
        ),
        isFalse,
        reason: 'local file must skip /ensure for $status',
      );
    }
    expect(
      shouldEnsureBeforePlay(
        const NarrationJob(status: NarrationJobStatus.ready),
      ),
      isFalse,
    );
    expect(
      shouldEnsureBeforePlay(
        const NarrationJob(status: NarrationJobStatus.unknown),
        localReady: true,
      ),
      isFalse,
    );
    expect(
      shouldEnsureBeforePlay(
        const NarrationJob(status: NarrationJobStatus.queued),
      ),
      isFalse,
    );
    expect(
      shouldEnsureBeforePlay(
        const NarrationJob(status: NarrationJobStatus.generating),
      ),
      isFalse,
    );
    expect(
      shouldEnsureBeforePlay(
        const NarrationJob(status: NarrationJobStatus.deleted),
      ),
      isTrue,
    );
    expect(
      shouldEnsureBeforePlay(
        const NarrationJob(status: NarrationJobStatus.unknown),
      ),
      isTrue,
    );
    expect(
      shouldEnsureBeforePlay(
        const NarrationJob(status: NarrationJobStatus.fallback),
      ),
      isTrue,
    );
    expect(
      shouldEnsureBeforePlay(
        const NarrationJob(status: NarrationJobStatus.failed),
      ),
      isTrue,
    );
  });

  test('same article with a loaded source is reused for instant replay', () {
    expect(
      shouldReuseLoadedSource(
        currentId: 'a1',
        articleId: 'a1',
        idle: false,
      ),
      isTrue,
    );
    expect(
      shouldReuseLoadedSource(
        currentId: 'a1',
        articleId: 'a1',
        idle: true,
      ),
      isFalse,
    );
    expect(
      shouldReuseLoadedSource(
        currentId: 'a2',
        articleId: 'a1',
        idle: false,
      ),
      isFalse,
    );
  });

  test('last queue item keeps the loaded source instead of stopping', () {
    expect(shouldKeepSourceAtQueueEnd(index: 0, length: 1), isTrue);
    expect(shouldKeepSourceAtQueueEnd(index: 1, length: 2), isTrue);
    expect(shouldKeepSourceAtQueueEnd(index: 0, length: 2), isFalse);
    expect(shouldKeepSourceAtQueueEnd(index: 0, length: 0), isTrue);
  });

  test('completed playback always seeks to start before play', () {
    expect(shouldSeekToStartBeforePlay(completed: true), isTrue);
    expect(shouldSeekToStartBeforePlay(completed: false), isFalse);
  });

  test('status label does not say Paused after the track ended', () {
    expect(
      narrationStatusLabel(
        isThisArticle: true,
        playing: false,
        completed: true,
        listened: true,
      ),
      'Played · tap to hear again',
    );
    expect(
      narrationStatusLabel(
        isThisArticle: true,
        playing: true,
        completed: false,
        listened: false,
      ),
      'Playing',
    );
    expect(
      narrationStatusLabel(
        isThisArticle: true,
        playing: false,
        completed: false,
        listened: false,
      ),
      'Paused',
    );
    expect(
      narrationStatusLabel(
        isThisArticle: false,
        playing: false,
        completed: false,
        listened: false,
      ),
      'Narrated voice',
    );
  });

  test('clear/delete of the playing article stops playback', () {
    expect(
      shouldStopNarrationPlayback(currentId: 'a1', droppedIds: ['a1', 'a2']),
      isTrue,
    );
    expect(
      shouldStopNarrationPlayback(currentId: 'a1', droppedIds: ['a2']),
      isFalse,
    );
    expect(
      shouldStopNarrationPlayback(currentId: null, droppedIds: ['a1']),
      isFalse,
    );
  });

  test('listen complete never wipes the local or server opus', () {
    final completion =
        File('lib/data/services/narration_completion_store.dart').readAsStringSync();
    expect(completion.contains('NarrationDownloadStore'), isFalse);
    expect(completion.contains('wipe('), isFalse);
    final src =
        File('lib/data/services/narration_audio_handler.dart').readAsStringSync();
    expect(src.contains('_markComplete'), isTrue);
    expect(src.contains('_api.complete'), isFalse);
    expect(src.contains('shouldSeekToStartBeforePlay'), isTrue);
    expect(src.contains('shouldKeepSourceAtQueueEnd'), isTrue);
    expect(src.contains('NarrationCompletionStore.instance.mark'), isTrue);
    expect(src.contains('isNarrationIdDropped'), isTrue);
    expect(src.contains('timeout = const Duration(seconds: 8)'), isTrue);
  });

  test('clear/delete stops in-progress narration and drops server audio', () {
    final handler =
        File('lib/data/services/narration_audio_handler.dart').readAsStringSync();
    expect(handler.contains('dropArticles'), isTrue);
    expect(handler.contains('dropNarrationFor'), isTrue);
    expect(handler.contains('NarrationDownloadStore.instance.wipe'), isTrue);
    expect(handler.contains('shouldReloadForLocalFile'), isTrue);
    expect(handler.contains('setFilePath'), isTrue);
    expect(handler.contains('hasPlayableFile'), isTrue);
    expect(handler.contains('rememberDroppedNarrationIds'), isTrue);
    final ctrl =
        File('lib/presentation/screens/news/news_controller.dart').readAsStringSync();
    expect(ctrl.contains('dropNarrationFor'), isTrue);
    expect(ctrl.contains('unawaited(dropNarrationFor([id]))'), isTrue);
    expect(ctrl.contains('markManyRead'), isTrue);
    final markAt = ctrl.indexOf('Future<int> markManyRead');
    final loadAt = ctrl.indexOf('Future<Article?> loadArticle');
    expect(markAt, greaterThan(0));
    expect(loadAt, greaterThan(markAt));
    expect(
      ctrl.substring(markAt, loadAt).contains('dropNarrationFor'),
      isFalse,
      reason: 'Clear All must not tombstone Saved-tab audio',
    );
    final repo =
        File('lib/data/repositories/news_repository.dart').readAsStringSync();
    expect(repo.contains('dropNarrationFor(unsavedIds)'), isTrue);
    expect(repo.contains('dropNarrationFor([id])'), isTrue);
    expect(repo.contains('dropNarrationFor(ids)'), isTrue);
    expect(repo.contains('NarrationDownloadStore.instance.wipe([id])'), isTrue);
    expect(repo.contains('dropNarrationFor(staleIds)'), isTrue);
  });

  test('listen bar restarts from completed and does not ensure when ready', () {
    final src = File(
      'lib/presentation/screens/news/widgets/narration_listen_bar.dart',
    ).readAsStringSync();
    expect(src.contains('narrationPlayTap'), isTrue);
    expect(src.contains('NarrationPlayTap.restart'), isTrue);
    expect(src.contains('shouldEnsureBeforePlay'), isTrue);
    expect(src.contains('initNarrationAudio'), isTrue);
    expect(src.contains('timeout: const Duration(seconds: 20)'), isTrue);
    expect(src.contains('isNarrationIdDropped'), isTrue);
    expect(src.contains('NewsListenDownloadDisc'), isTrue);
    expect(src.contains('_downloadAudio'), isTrue);
    expect(src.contains('hasPlayableFile'), isTrue);
    expect(src.contains('localReady: localReady'), isTrue);
    expect(src.contains('waitUntilReady'), isTrue);
    expect(src.contains('whichListenSurface'), isTrue);
    expect(src.contains('isTransientNarrationFailure'), isTrue);
    expect(src.contains('shouldEnsureOnBoot'), isTrue);
    expect(src.contains('shouldShowOnDeviceAfterPlayError'), isTrue);
    expect(src.contains('shouldAcceptNarrationJob'), isTrue);
    expect(src.contains('_waitForAuthToken'), isTrue);
    expect(src.contains('_applyJob'), isTrue);
    expect(src.contains('shouldAllowDownloadTap'), isTrue);
    expect(
      src.contains(
        'if (NarrationDownloadStore.instance.isReady(widget.article.id)) return;',
      ),
      isFalse,
      reason: 'a vanished file must be allowed to re-download',
    );
  });

  test('dropped ids stay blocked even before AudioService is bound', () {
    resetDroppedNarrationIdsForTest();
    addTearDown(resetDroppedNarrationIdsForTest);
    expect(isNarrationIdDropped('a1'), isFalse);
    rememberDroppedNarrationIds(['a1', '', 'a2']);
    expect(isNarrationIdDropped('a1'), isTrue);
    expect(isNarrationIdDropped('a2'), isTrue);
    expect(isNarrationIdDropped(''), isFalse);
    expect(isNarrationIdDropped('saved-keep'), isFalse);
    expect(snapshotDroppedNarrationIds(), {'a1', 'a2'});
    rememberDroppedNarrationIds(['a1']);
    expect(snapshotDroppedNarrationIds(), {'a1', 'a2'});
    expect(
      shouldStopNarrationPlayback(currentId: 'a1', droppedIds: const <String>[]),
      isFalse,
    );
    expect(
      shouldReuseLoadedSource(currentId: null, articleId: 'a1', idle: false),
      isFalse,
    );
  });

  test('listen surface prefers server audio over on-device TTS', () {
    const unknown = NarrationJob(status: NarrationJobStatus.unknown);
    const timeout = NarrationJob(
      status: NarrationJobStatus.unknown,
      reason: 'timeout',
    );
    const stickyTimeout = NarrationJob(
      status: NarrationJobStatus.fallback,
      configured: false,
      reason: 'timeout',
    );
    const ready = NarrationJob(status: NarrationJobStatus.ready);
    const queued = NarrationJob(status: NarrationJobStatus.queued);
    const failed = NarrationJob(status: NarrationJobStatus.failed);
    const widgetTest = NarrationJob(
      status: NarrationJobStatus.fallback,
      configured: false,
      reason: 'widget_test',
    );
    const breaker = NarrationJob(
      status: NarrationJobStatus.fallback,
      configured: false,
      reason: 'breaker_open',
    );
    const exhausted = NarrationJob(
      status: NarrationJobStatus.fallback,
      configured: false,
      reason: 'unreachable_exhausted',
    );

    expect(isTransientNarrationFailure(unknown), isTrue);
    expect(isTransientNarrationFailure(timeout), isTrue);
    expect(isTransientNarrationFailure(stickyTimeout), isTrue);
    expect(isTransientNarrationFailure(failed), isFalse);
    expect(isTerminalNarrationFailure(widgetTest), isTrue);
    expect(isTerminalNarrationFailure(breaker), isTrue);
    expect(isTerminalNarrationFailure(exhausted), isTrue);
    expect(isTerminalNarrationFailure(stickyTimeout), isFalse);

    expect(shouldEnsureOnBoot(timeout), isFalse);
    expect(shouldEnsureOnBoot(unknown), isTrue);
    expect(shouldEnsureOnBoot(ready), isFalse);
    expect(shouldEnsureOnBoot(queued), isFalse);
    expect(shouldEnsureOnBoot(breaker), isFalse);
    expect(
      shouldEnsureOnBoot(
        const NarrationJob(status: NarrationJobStatus.deleted),
      ),
      isTrue,
    );

    expect(shouldKeepPollingNarration(timeout), isTrue);
    expect(shouldKeepPollingNarration(queued), isTrue);
    expect(shouldKeepPollingNarration(ready), isFalse);
    expect(shouldKeepPollingNarration(breaker), isFalse);

    expect(narrationPollInterval(0), const Duration(seconds: 2));
    expect(narrationPollInterval(1), const Duration(seconds: 2));
    expect(narrationPollInterval(2), const Duration(seconds: 5));
    expect(narrationPollInterval(3), const Duration(seconds: 5));
    expect(narrationPollInterval(4), const Duration(seconds: 10));
    expect(
      narrationShouldOfferUnreachableFallback(const Duration(seconds: 44)),
      isFalse,
    );
    expect(
      narrationShouldOfferUnreachableFallback(const Duration(seconds: 45)),
      isTrue,
    );

    expect(
      whichListenSurface(job: unknown, localReady: true, booted: false),
      ListenSurface.server,
    );
    expect(
      whichListenSurface(job: stickyTimeout, localReady: false, booted: true),
      ListenSurface.checking,
    );
    expect(
      whichListenSurface(job: ready, localReady: false, booted: true),
      ListenSurface.server,
    );
    expect(
      whichListenSurface(job: queued, localReady: false, booted: true),
      ListenSurface.preparing,
    );
    expect(
      whichListenSurface(job: widgetTest, localReady: false, booted: true),
      ListenSurface.onDevice,
    );
    expect(
      whichListenSurface(job: unknown, localReady: false, booted: false),
      ListenSurface.checking,
    );
    expect(
      whichListenSurface(job: failed, localReady: false, booted: true),
      ListenSurface.onDevice,
    );

    expect(
      shouldShowOnDeviceAfterPlayError(localReady: true, job: unknown),
      isFalse,
    );
    expect(
      shouldShowOnDeviceAfterPlayError(localReady: false, job: ready),
      isFalse,
    );
    expect(
      shouldShowOnDeviceAfterPlayError(localReady: false, job: failed),
      isTrue,
    );

    expect(
      shouldAcceptNarrationJob(
        current: unknown,
        next: ready,
        localReady: false,
        booted: true,
      ),
      isTrue,
      reason: 'late ready must replace a timeout/unknown check',
    );
    expect(
      shouldAcceptNarrationJob(
        current: ready,
        next: unknown,
        localReady: false,
        booted: true,
      ),
      isFalse,
      reason: 'racing ensure/status must not downgrade ready to checking',
    );
    expect(
      shouldAcceptNarrationJob(
        current: ready,
        next: queued,
        localReady: false,
        booted: true,
      ),
      isFalse,
      reason: 'ensure must not re-queue over an already-ready job',
    );
    expect(
      shouldAcceptNarrationJob(
        current: exhausted,
        next: ready,
        localReady: false,
        booted: true,
      ),
      isTrue,
      reason: 'Local LLM ready must upgrade away from on-device TTS',
    );
    expect(
      shouldAcceptNarrationJob(
        current: exhausted,
        next: unknown,
        localReady: false,
        booted: true,
      ),
      isFalse,
      reason: 'do not flap TTS back to Checking on a blip',
    );
    expect(
      shouldAcceptNarrationJob(
        current: unknown,
        next: exhausted,
        localReady: false,
        booted: true,
        allowTerminalFallback: true,
      ),
      isTrue,
    );
    expect(
      shouldAcceptNarrationJob(
        current: unknown,
        next: exhausted,
        localReady: false,
        booted: true,
      ),
      isFalse,
    );
  });
}
