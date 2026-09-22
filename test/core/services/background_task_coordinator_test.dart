import 'package:ai_nexus/core/services/background_task_coordinator.dart';
import 'package:ai_nexus/core/services/news_summarize_fg_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final coord = BackgroundTaskCoordinator.instance;

  setUp(coord.debugReset);
  tearDown(coord.debugReset);

  test('AI slots default to dataSync without microphone', () async {
    await coord.acquire('news', label: 'Summarizing');
    expect(coord.activeSlotCount, 1);
    expect(coord.debugServiceTypesIncludeMicrophone, isFalse);
    await coord.release('news');
    expect(coord.activeSlotCount, 0);
  });

  test('needsMicrophone on a slot opts into the microphone FGS type', () async {
    await coord.acquire('voice', label: 'Recording', needsMicrophone: true);
    expect(coord.debugServiceTypesIncludeMicrophone, isTrue);
    await coord.release('voice');
    expect(coord.debugServiceTypesIncludeMicrophone, isFalse);
  });

  test('setMicrophoneInUse does not start a slot of its own', () async {
    await coord.setMicrophoneInUse(true);
    expect(coord.activeSlotCount, 0);
    expect(coord.debugMicrophoneInUse, isTrue);
    expect(coord.debugServiceTypesIncludeMicrophone, isTrue);
    expect(coord.isServiceActive, isFalse);
    await coord.setMicrophoneInUse(false);
    expect(coord.debugServiceTypesIncludeMicrophone, isFalse);
  });

  test('OS timeout drops slots so callers do not think FGS is still up',
      () async {
    await coord.acquire('news', label: 'Summarizing');
    expect(coord.activeSlotCount, 1);
    coord.onTaskIsolateData(kFgsTimeoutEvent);
    expect(coord.activeSlotCount, 0);
    expect(coord.isServiceActive, isFalse);
  });

  test('non-timeout isolate payloads are ignored', () async {
    await coord.acquire('news', label: 'Summarizing');
    coord.onTaskIsolateData('something-else');
    expect(coord.activeSlotCount, 1);
  });

  test('re-acquire of the same slot does not leak a second slot', () async {
    await coord.acquire('news', label: 'Summarizing');
    await coord.acquire('news', label: 'Still summarizing');
    expect(coord.activeSlotCount, 1);
    await coord.release('news');
    expect(coord.activeSlotCount, 0);
  });

  test('release of an unknown slot is a no-op', () async {
    await coord.release('ghost');
    expect(coord.activeSlotCount, 0);
  });

  test('mic flag on a running AI slot adds the microphone FGS type', () async {
    await coord.acquire('news', label: 'Summarizing');
    expect(coord.debugServiceTypesIncludeMicrophone, isFalse);
    await coord.setMicrophoneInUse(true);
    expect(coord.debugServiceTypesIncludeMicrophone, isTrue);
    await coord.setMicrophoneInUse(false);
    expect(coord.debugServiceTypesIncludeMicrophone, isFalse);
    await coord.release('news');
  });

  test('OS timeout drops slots but keeps the live mic flag', () async {
    await coord.acquire('news', label: 'Summarizing');
    await coord.setMicrophoneInUse(true);
    coord.onTaskIsolateData(kFgsTimeoutEvent);
    expect(coord.activeSlotCount, 0);
    expect(coord.isServiceActive, isFalse);
    expect(coord.debugMicrophoneInUse, isTrue);
  });
}
