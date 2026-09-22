import 'dart:io';

import 'package:ai_nexus/core/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks Phase 2 Android platform contracts against the live files.
void main() {
  late String manifest;
  late String filePaths;
  late String mainNetwork;
  late String debugNetwork;
  late String widgetKt;

  setUpAll(() {
    manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    filePaths =
        File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
    mainNetwork = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();
    debugNetwork = File(
      'android/app/src/debug/res/xml/network_security_config.xml',
    ).readAsStringSync();
    widgetKt = File(
      'android/app/src/main/kotlin/app/ainexus/ai_nexus/ExpenseWidgetProvider.kt',
    ).readAsStringSync();
  });

  group('2.1 microphone FGS', () {
    test('declares microphone FGS permission and type next to dataSync', () {
      expect(
        manifest,
        contains(
          'android.permission.FOREGROUND_SERVICE_MICROPHONE',
        ),
      );
      expect(
        manifest,
        contains('android:foregroundServiceType="dataSync|microphone"'),
      );
      expect(
        File('lib/core/services/background_task_coordinator.dart')
            .readAsStringSync(),
        contains('ForegroundServiceTypes.microphone'),
      );
      expect(
        File('lib/core/services/hold_to_speak_service.dart').readAsStringSync(),
        contains('setMicrophoneInUse'),
      );
    });

    test('plugin 9.2.2 still exposes serviceTypes + microphone', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('flutter_foreground_task:'),
      );
    });
  });

  group('2.2 dataSync timeout', () {
    test('AI and transfer handlers send kFgsTimeoutEvent on isTimeout', () {
      final ai = File('lib/core/services/news_summarize_fg_task.dart')
          .readAsStringSync();
      final transfer = File('lib/core/services/transfer_notification.dart')
          .readAsStringSync();
      expect(ai, contains('kFgsTimeoutEvent'));
      expect(ai, contains('stopWithTask: true'));
      expect(ai, contains('if (isTimeout)'));
      expect(transfer, contains('kFgsTimeoutEvent'));
      expect(transfer, contains('if (isTimeout)'));
    });
  });

  group('2.3 predictive back', () {
    test('application enables OnBackInvokedCallback', () {
      expect(
        manifest,
        contains('android:enableOnBackInvokedCallback="true"'),
      );
    });

    test('existing PopScope interceptors are still present', () {
      for (final path in [
        'lib/presentation/screens/expense/widgets/expense_merge_bar.dart',
        'lib/presentation/widgets/swipe_to_delete.dart',
        'lib/bubble/overlay/panel.dart',
        'lib/presentation/screens/expense/modals/budget_history_modal.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, contains('PopScope'), reason: path);
        expect(src, contains('onPopInvokedWithResult'), reason: path);
      }
      final zoom =
          File('lib/presentation/widgets/image_zoom_viewer.dart').readAsStringSync();
      expect(zoom, contains('maybePop'));
    });
  });

  group('2.4 network security config', () {
    test('release permits cleartext only for the STT host', () {
      expect(manifest, contains('android:networkSecurityConfig'));
      expect(manifest, isNot(contains('android:usesCleartextTraffic="true"')));
      expect(mainNetwork, contains('cleartextTrafficPermitted="false"'));
      expect(mainNetwork, contains(AppConstants.prodSttGatewayHost));
      expect(
        mainNetwork,
        isNot(contains('<domain includeSubdomains="false">localhost')),
      );
    });

    test('debug overlay also allows loopback for local API and STT', () {
      expect(debugNetwork, contains(AppConstants.prodSttGatewayHost));
      expect(debugNetwork, contains('localhost'));
      expect(debugNetwork, contains('10.0.2.2'));
    });
  });

  group('2.5 FileProvider', () {
    test('keeps cache-path and drops shared-storage roots', () {
      expect(filePaths, contains('<cache-path'));
      expect(filePaths, isNot(contains('<external-path')));
      expect(filePaths, isNot(contains('<external-files-path')));
      expect(filePaths, isNot(contains('<files-path')));
    });
  });

  group('2.6 launch theme', () {
    test('LaunchTheme is not fullscreen in any qualifier', () {
      for (final path in [
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, isNot(contains('windowFullscreen')), reason: path);
        expect(src, contains('windowDrawsSystemBarBackgrounds'), reason: path);
        expect(src, contains('windowLayoutInDisplayCutoutMode'), reason: path);
      }
    });
  });

  group('2.7 exact alarm', () {
    test('manifest dropped SCHEDULE_EXACT_ALARM; widget uses inexact', () {
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(widgetKt, contains('setAndAllowWhileIdle'));
      expect(widgetKt, isNot(contains('setExactAndAllowWhileIdle')));
      expect(widgetKt, isNot(contains('canScheduleExactAlarms')));
    });
  });

  group('2.8 firebase meta', () {
    test('dead FCM notification meta-data is gone; app icon meta stays', () {
      expect(
        manifest,
        isNot(contains('com.google.firebase.messaging.default_notification_icon')),
      );
      expect(
        manifest,
        isNot(contains('com.google.firebase.messaging.default_notification_color')),
      );
      expect(manifest, contains('app.ainexus.NOTIFICATION_ICON'));
      final lock = File('pubspec.lock').readAsStringSync();
      expect(lock.toLowerCase(), isNot(contains('firebase_messaging')));
    });
  });

  group('2.9 locales', () {
    test('skips localeConfig because the app is English-only', () {
      expect(manifest, isNot(contains('localeConfig')));
      final arb = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'));
      expect(arb, isEmpty);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('flutter_localizations')),
      );
    });
  });
}
