import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String gradle;
  late String props;

  setUpAll(() {
    gradle = File('android/app/build.gradle.kts').readAsStringSync();
    props = File('android/gradle.properties').readAsStringSync();
  });

  test('release still minifies and shrinks resources', () {
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(gradle, contains('proguard-android-optimize.txt'));
  });

  test('release APK keeps only arm64 native libs', () {
    expect(gradle, contains('abiFilters.add("arm64-v8a")'));
    expect(gradle, contains('abiFilters.clear()'));
  });

  test('nonTransitive R class is on; incremental Kotlin stays off', () {
    expect(props, contains('android.nonTransitiveRClass=true'));
    expect(props, contains('kotlin.incremental=false'));
  });
}
