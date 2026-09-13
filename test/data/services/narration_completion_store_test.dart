import 'package:ai_nexus/data/services/narration_completion_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('completion store persists ids and clamps speed', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = NarrationCompletionStore.instance;
    await store.load(prefs);
    expect(store.isCompleted('a1'), isFalse);
    await store.mark('a1');
    expect(store.isCompleted('a1'), isTrue);
    await store.setSpeed(0.2);
    expect(store.speed, 0.5);
    await store.setSpeed(3.0);
    expect(store.speed, 2.0);
    await store.setSpeed(1.25);
    expect(store.speed, 1.25);

    await store.mark('');
    expect(store.isCompleted(''), isFalse);
    await store.mark('a1');
    expect(store.isCompleted('a1'), isTrue);
  });
}
