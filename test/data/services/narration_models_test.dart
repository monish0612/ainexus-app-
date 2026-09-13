import 'package:ai_nexus/data/services/narration_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NarrationJob.fromJson maps statuses', () {
    final ready = NarrationJob.fromJson({
      'status': 'ready',
      'cache_key': 'abc',
      'duration_s': 12.5,
      'configured': true,
    });
    expect(ready.isReady, isTrue);
    expect(ready.cacheKey, 'abc');
    expect(ready.durationS, 12.5);

    final queued = NarrationJob.fromJson({'status': 'queued'});
    expect(queued.isPreparing, isTrue);

    final fallback = NarrationJob.fromJson({
      'status': 'fallback',
      'reason': 'breaker_open',
    });
    expect(fallback.useOnDevice, isTrue);

    final down = NarrationJob.fromJson({'status': 'ready', 'configured': false});
    expect(down.configured, isFalse);

    final deleted = NarrationJob.fromJson({'status': 'deleted'});
    expect(deleted.canReplay, isTrue);
    expect(deleted.useOnDevice, isFalse);
    expect(deleted.isReady, isFalse);

    final generating = NarrationJob.fromJson({'status': 'GENERATING'});
    expect(generating.isPreparing, isTrue);
    expect(generating.useOnDevice, isFalse);

    final camel = NarrationJob.fromJson({
      'status': 'ready',
      'cacheKey': 'xyz',
      'duration_s': 8,
    });
    expect(camel.cacheKey, 'xyz');
    expect(camel.durationS, 8.0);

    final empty = NarrationJob.fromJson(<String, dynamic>{});
    expect(empty.status, NarrationJobStatus.unknown);
    expect(empty.useOnDevice, isTrue);
    expect(empty.configured, isTrue);

    final failed = NarrationJob.fromJson({'status': 'failed', 'configured': true});
    expect(failed.useOnDevice, isTrue);

    final hit = NarrationJob.fromJson({'status': 'ready', 'cache_hit': true});
    expect(hit.cacheHit, isTrue);
  });
}
