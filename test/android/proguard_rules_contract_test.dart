import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks the Phase 1 R8 / Gradle contracts. These are not runtime gates —
/// they are the keep lines and property flags that stop minify from
/// silently breaking notifications on a release APK.
void main() {
  late String proguard;
  late String gradleProperties;

  setUpAll(() {
    proguard = File('android/app/proguard-rules.pro').readAsStringSync();
    gradleProperties = File('android/gradle.properties').readAsStringSync();
  });

  group('proguard-rules.pro', () {
    test('keeps existing sms / widget / audio / mlkit surfaces', () {
      expect(proguard, contains('-keep class app.ainexus.ai_nexus.sms.** { *; }'));
      expect(proguard, contains('-keep class app.ainexus.ai_nexus.ExpenseWidget** { *; }'));
      expect(proguard, contains('-keep class app.ainexus.ai_nexus.SearchWidget** { *; }'));
      expect(proguard, contains('-keep class app.ainexus.ai_nexus.WidgetBootReceiver { *; }'));
      expect(proguard, contains('-keep class com.ryanheise.** { *; }'));
      expect(proguard, contains('-keep class com.google.mlkit.vision.text.** { *; }'));
    });

    test('keeps flutter_local_notifications for Gson scheduled payloads', () {
      expect(
        proguard,
        contains('-keep class com.dexterous.flutterlocalnotifications.** { *; }'),
      );
      expect(
        proguard,
        contains(
          '-keepclassmembers class com.dexterous.flutterlocalnotifications.** { *; }',
        ),
      );
      expect(proguard, contains('-keepattributes Signature'));
      expect(
        proguard,
        contains(
          '-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken',
        ),
      );
    });

    test('keeps WorkManager BackgroundWorker by class name', () {
      expect(
        proguard,
        contains(
          '-keep class dev.fluttercommunity.workmanager.BackgroundWorker { *; }',
        ),
      );
    });
  });

  group('gradle.properties', () {
    test('does not enable R8 fullMode', () {
      expect(gradleProperties, isNot(contains('android.enableR8.fullMode=true')));
    });

    test('uses non-transitive R class and keeps Kotlin incremental off', () {
      expect(gradleProperties, contains('android.nonTransitiveRClass=true'));
      expect(gradleProperties, contains('kotlin.incremental=false'));
      expect(gradleProperties, isNot(contains('kotlin.incremental=true')));
    });

    test('leaves the existing Gradle JVM args line intact', () {
      expect(
        gradleProperties,
        contains(
          'org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError',
        ),
      );
    });
  });
}
