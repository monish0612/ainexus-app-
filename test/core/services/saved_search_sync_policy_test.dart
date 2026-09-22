import 'package:ai_nexus/core/services/saved_search_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stays at 120s until five unchanged syncs', () {
    var current = kSavedSearchForegroundSync;
    for (var streak = 1; streak < kSavedSearchNoChangeBackoffAfter; streak++) {
      current = savedSearchForegroundInterval(
        noChangeStreak: streak,
        current: current,
      );
      expect(current, kSavedSearchForegroundSync);
    }
  });

  test('doubles after five no-change syncs and caps at 600s', () {
    var current = kSavedSearchForegroundSync;
    current = savedSearchForegroundInterval(
      noChangeStreak: 5,
      current: current,
    );
    expect(current, const Duration(seconds: 240));
    current = savedSearchForegroundInterval(
      noChangeStreak: 6,
      current: current,
    );
    expect(current, const Duration(seconds: 480));
    current = savedSearchForegroundInterval(
      noChangeStreak: 7,
      current: current,
    );
    expect(current, kSavedSearchForegroundSyncMax);
    current = savedSearchForegroundInterval(
      noChangeStreak: 20,
      current: current,
    );
    expect(current, kSavedSearchForegroundSyncMax);
  });

  test('a change resets callers to the 120s base', () {
    expect(
      savedSearchForegroundInterval(
        noChangeStreak: 0,
        current: const Duration(seconds: 600),
      ),
      kSavedSearchForegroundSync,
    );
  });
}
