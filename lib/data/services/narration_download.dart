import 'dart:math' as math;

/// Pure helpers for offline narration downloads. Kept IO-free so the
/// retry / resume / wipe rules can be tested without plugins.

const int kNarrationDownloadMinBytes = 256;
const int kNarrationDownloadMaxAttempts = 5;
const Duration kNarrationDownloadReceiveTimeout = Duration(minutes: 2);

const List<int> kOggMagic = <int>[0x4F, 0x67, 0x67, 0x53];

enum NarrationDownloadPhase { idle, downloading, ready, error }

class NarrationDownloadProgress {
  const NarrationDownloadProgress({
    required this.phase,
    this.received = 0,
    this.total,
    this.attempt = 0,
    this.error,
  });

  const NarrationDownloadProgress.idle()
      : phase = NarrationDownloadPhase.idle,
        received = 0,
        total = null,
        attempt = 0,
        error = null;

  const NarrationDownloadProgress.ready({this.received = 0, this.total})
      : phase = NarrationDownloadPhase.ready,
        attempt = 0,
        error = null;

  const NarrationDownloadProgress.error(this.error)
      : phase = NarrationDownloadPhase.error,
        received = 0,
        total = null,
        attempt = 0;

  final NarrationDownloadPhase phase;
  final int received;
  final int? total;
  final int attempt;
  final String? error;

  bool get isReady => phase == NarrationDownloadPhase.ready;
  bool get isBusy => phase == NarrationDownloadPhase.downloading;

  double get fraction {
    final cap = total;
    if (cap == null || cap <= 0) return 0;
    return (received / cap).clamp(0.0, 1.0);
  }
}

int narrationDownloadFingerprint(String articleId) {
  var hash = 5381;
  for (final c in articleId.codeUnits) {
    hash = ((hash << 5) + hash + c) & 0x7fffffff;
  }
  return hash;
}

String narrationDownloadBasename(String articleId) {
  final trimmed = articleId.trim();
  if (trimmed.isEmpty) return '';
  var s = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (s == '.' || s == '..') s = 'article';
  if (s.startsWith('.')) s = 'a$s';
  if (s.length > 80) s = s.substring(0, 80);
  final fp = narrationDownloadFingerprint(trimmed).toRadixString(16);
  return '$s-$fp.opus';
}

bool isValidDownloadedOpus({
  required bool exists,
  required int length,
  required List<int> header,
}) {
  if (!exists || length < kNarrationDownloadMinBytes) return false;
  if (header.length < 4) return false;
  return header[0] == kOggMagic[0] &&
      header[1] == kOggMagic[1] &&
      header[2] == kOggMagic[2] &&
      header[3] == kOggMagic[3];
}

Duration narrationDownloadBackoff(int attemptIndex) {
  final exp = math.min(4000, 250 * (1 << attemptIndex.clamp(0, 8)));
  return Duration(milliseconds: exp);
}

bool isRetryableDownloadStatus(int? statusCode) {
  if (statusCode == null) return true;
  if (statusCode == 401 || statusCode == 403) return false;
  if (statusCode == 404 || statusCode == 408 || statusCode == 429) return true;
  return statusCode >= 500;
}

bool shouldPreferLocalAudio({
  required bool fileExists,
  required int bytes,
}) {
  return fileExists && bytes >= kNarrationDownloadMinBytes;
}

bool shouldReloadForLocalFile({
  required bool localReady,
  required bool currentIsLocal,
}) {
  return localReady && !currentIsLocal;
}

bool shouldWipeLocalOnArticleGone(bool articleStillOnDevice) =>
    !articleStillOnDevice;

bool shouldWipeLocalOnMarkRead() => true;

/// Download stays tappable after success so a vanished/corrupt file can
/// be fetched again. Only the in-flight spinner swallows taps.
bool shouldAllowDownloadTap(NarrationDownloadPhase phase) =>
    phase != NarrationDownloadPhase.downloading;

bool shouldSkipNetworkDownload({required bool localPlayable}) =>
    localPlayable;

String narrationDownloadSemantics(NarrationDownloadPhase phase) {
  return switch (phase) {
    NarrationDownloadPhase.ready => 'Audio downloaded',
    NarrationDownloadPhase.downloading => 'Downloading audio',
    NarrationDownloadPhase.error => 'Retry download',
    NarrationDownloadPhase.idle => 'Download audio',
  };
}
