import 'package:flutter/foundation.dart';

enum NarrationJobStatus {
  unknown,
  queued,
  generating,
  ready,
  fallback,
  failed,
  deleted,
}

@immutable
class NarrationJob {
  const NarrationJob({
    required this.status,
    this.cacheKey,
    this.durationS,
    this.reason,
    this.configured = true,
    this.cacheHit = false,
    this.chunks = const [],
    this.complete = false,
    this.chunkError,
  });

  final NarrationJobStatus status;
  final String? cacheKey;
  final double? durationS;
  final String? reason;
  final bool configured;
  final bool cacheHit;
  final List<int> chunks;
  final bool complete;
  final String? chunkError;

  bool get isReady => status == NarrationJobStatus.ready;
  bool get isPreparing =>
      status == NarrationJobStatus.queued ||
      status == NarrationJobStatus.generating;
  bool get canReplay =>
      isReady || status == NarrationJobStatus.deleted;
  bool get useOnDevice =>
      !configured ||
      status == NarrationJobStatus.fallback ||
      status == NarrationJobStatus.failed ||
      status == NarrationJobStatus.unknown;

  factory NarrationJob.fromJson(Map<String, dynamic> json) {
    final raw = (json['status'] as String? ?? 'unknown').toLowerCase();
    final status = switch (raw) {
      'queued' => NarrationJobStatus.queued,
      'generating' => NarrationJobStatus.generating,
      'ready' => NarrationJobStatus.ready,
      'fallback' => NarrationJobStatus.fallback,
      'failed' => NarrationJobStatus.failed,
      'deleted' => NarrationJobStatus.deleted,
      _ => NarrationJobStatus.unknown,
    };
    return NarrationJob(
      status: status,
      cacheKey: json['cache_key'] as String? ?? json['cacheKey'] as String?,
      durationS: (json['duration_s'] as num?)?.toDouble(),
      reason: json['reason'] as String?,
      configured: json['configured'] != false,
      cacheHit: json['cache_hit'] == true,
      chunks: ((json['chunks'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      complete: json['complete'] == true,
      chunkError: json['chunk_error'] as String?,
    );
  }
}
