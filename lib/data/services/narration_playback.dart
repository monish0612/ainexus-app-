import 'narration_models.dart';

/// What the listen-bar play button should do for this tap.
enum NarrationPlayTap { start, toggle, restart }

/// After a track ends, just_audio stays in `completed`. Calling `play()`
/// without `seek(0)` is a no-op — that is the "tap Play and nothing happens"
/// bug. Restart from the start instead.
NarrationPlayTap narrationPlayTap({
  required bool isThisArticle,
  required bool completed,
}) {
  if (!isThisArticle) return NarrationPlayTap.start;
  if (completed) return NarrationPlayTap.restart;
  return NarrationPlayTap.toggle;
}

/// Ready audio is already on disk — do not hit `/ensure` (that re-queues and
/// shows "Preparing your audio…"). Deleted is a leftover listen-complete
/// tombstone; the article is still in the feed, so recover once.
bool shouldEnsureBeforePlay(NarrationJob job, {bool localReady = false}) {
  if (localReady) return false;
  if (job.isReady) return false;
  if (job.isPreparing) return false;
  return true;
}

/// Which listen-bar chrome to show. Local opus and a ready server job always
/// win. Slow / unknown / timed-out status stays on "Checking" and keeps
/// polling — never the on-device female TTS fallback.
enum ListenSurface { checking, preparing, server, onDevice }

bool isTransientNarrationFailure(NarrationJob job) {
  if (job.status == NarrationJobStatus.unknown) return true;
  if (job.status == NarrationJobStatus.fallback &&
      (job.reason == 'timeout' ||
          job.reason == 'unreachable' ||
          job.reason == 'ensure_timeout')) {
    return true;
  }
  return false;
}

bool isTerminalNarrationFailure(NarrationJob job) {
  if (job.status == NarrationJobStatus.failed) return true;
  if (job.status == NarrationJobStatus.fallback &&
      !isTransientNarrationFailure(job)) {
    return true;
  }
  return false;
}

bool shouldEnsureOnBoot(NarrationJob job) {
  if (job.isReady || job.isPreparing) return false;
  // A slow /status must not start a second synthesis. The phone's ensure
  // body is the summary; ingest already hashed the full article. Timing out
  // and then ensuring used to overwrite a finished track with "Preparing…".
  if (job.reason == 'timeout' ||
      job.reason == 'unreachable' ||
      job.reason == 'ensure_timeout') {
    return false;
  }
  if (job.status == NarrationJobStatus.deleted) return true;
  if (isTerminalNarrationFailure(job) && !job.configured) return false;
  return true;
}

/// Completed is sticky in just_audio. Arm only after the new source has
/// actually become ready, so a leftover completed event cannot skip a track.
class NarrationAdvanceGate {
  bool armed = false;

  bool onState(String state) {
    if (state == 'ready' || state == 'buffering') {
      armed = true;
      return false;
    }
    if (state == 'completed' && armed) {
      armed = false;
      return true;
    }
    return false;
  }
}

bool shouldKeepPollingNarration(NarrationJob job) {
  if (job.isReady) return false;
  if (isTerminalNarrationFailure(job)) return false;
  return job.isPreparing || isTransientNarrationFailure(job);
}

/// Status-poll spacing while a job is still preparing / unreachable.
Duration narrationPollInterval(int transientTries) {
  if (transientTries >= 4) return const Duration(seconds: 10);
  if (transientTries >= 2) return const Duration(seconds: 5);
  return const Duration(milliseconds: 175);
}

/// Same ~45s unreachable window as the old 22 × 2s poll, independent of backoff.
bool narrationShouldOfferUnreachableFallback(Duration elapsed) =>
    elapsed >= const Duration(seconds: 45);

/// Play errors must not hide an already-ready Local LLM / opus track.
bool shouldShowOnDeviceAfterPlayError({
  required bool localReady,
  required NarrationJob job,
}) {
  if (localReady || job.isReady || job.isPreparing) return false;
  return true;
}

ListenSurface whichListenSurface({
  required NarrationJob job,
  required bool localReady,
  required bool booted,
}) {
  if (localReady || job.canReplay) return ListenSurface.server;
  if (job.isPreparing) return ListenSurface.preparing;
  if (!booted || isTransientNarrationFailure(job)) {
    return ListenSurface.checking;
  }
  if (isTerminalNarrationFailure(job)) return ListenSurface.onDevice;
  return ListenSurface.checking;
}

int listenSurfaceRank(ListenSurface surface) => switch (surface) {
      ListenSurface.server => 3,
      ListenSurface.preparing => 2,
      ListenSurface.checking => 1,
      ListenSurface.onDevice => 0,
    };

/// Monotonic job updates so a late `/status` ready cannot be overwritten by
/// a racing `/ensure`, and so on-device TTS can still upgrade to narrated
/// audio without flapping back to "Checking".
bool shouldAcceptNarrationJob({
  required NarrationJob current,
  required NarrationJob next,
  required bool localReady,
  required bool booted,
  bool allowTerminalFallback = false,
}) {
  final cur = whichListenSurface(
    job: current,
    localReady: localReady,
    booted: booted,
  );
  final nxt = whichListenSurface(
    job: next,
    localReady: localReady,
    booted: true,
  );
  if (listenSurfaceRank(nxt) > listenSurfaceRank(cur)) {
    if (cur == ListenSurface.onDevice && nxt == ListenSurface.checking) {
      return false;
    }
    return true;
  }
  if (listenSurfaceRank(nxt) == listenSurfaceRank(cur)) return true;
  return allowTerminalFallback && nxt == ListenSurface.onDevice;
}

bool shouldReuseLoadedSource({
  required String? currentId,
  required String articleId,
  required bool idle,
}) {
  return currentId == articleId && !idle;
}

/// Last item in the queue: keep the AudioSource loaded so Play is seek(0),
/// not a network reload.
bool shouldKeepSourceAtQueueEnd({required int index, required int length}) {
  return length <= 0 || index + 1 >= length;
}

bool shouldSeekToStartBeforePlay({required bool completed}) => completed;

bool shouldStopNarrationPlayback({
  required String? currentId,
  required Iterable<String> droppedIds,
}) {
  return currentId != null && droppedIds.contains(currentId);
}

/// Session tombstone for articles whose audio was cleared/deleted.
/// Survives AudioService still being in-flight so Listen cannot restart
/// a track after Clear All / swipe-delete / nuke.
final Set<String> _droppedNarrationIds = <String>{};

void rememberDroppedNarrationIds(Iterable<String> ids) {
  for (final id in ids) {
    if (id.isNotEmpty) _droppedNarrationIds.add(id);
  }
}

bool isNarrationIdDropped(String id) => _droppedNarrationIds.contains(id);

Set<String> snapshotDroppedNarrationIds() =>
    Set<String>.from(_droppedNarrationIds);

/// Isolates drop-gate state between tests.
void resetDroppedNarrationIdsForTest() => _droppedNarrationIds.clear();

String narrationStatusLabel({
  required bool isThisArticle,
  required bool playing,
  required bool completed,
  required bool listened,
}) {
  if (isThisArticle && !completed) {
    return playing ? 'Playing' : 'Paused';
  }
  if (listened || completed) return 'Played · tap to hear again';
  return 'Narrated voice';
}
