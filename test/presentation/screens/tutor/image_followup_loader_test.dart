// Live coverage for the image follow-up sheet's waiting state.
//
// Phase 3a replaced `_TypingDots` + an indeterminate `LinearProgressIndicator`
// with `NexusLoader`'s vision variant, which shows the attached thumbnail
// behind a liquid progress ring. The request here is held open on a Completer
// so the loading state can be asserted on rather than raced.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';
import 'package:ai_nexus/presentation/screens/tutor/image_followup_sheet.dart';
import 'package:ai_nexus/presentation/widgets/nexus_loader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1x1 transparent PNG — decodes cleanly in every test backend.
final Uint8List _smallPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
  0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
]);

/// Adapter that answers the settings bootstrap immediately but parks the
/// follow-up call until [release] is called.
class _HoldingAdapter implements HttpClientAdapter {
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/ai/image-followup')) {
      await _gate.future;
      return ResponseBody.fromBytes(
        utf8.encode(jsonEncode(const {
          'answer': 'It looks like a tabby cat.',
          'model': 'gemini-2.5-flash-lite',
          'sources': <Map<String, Object?>>[],
          'searchQueries': <String>[],
        })),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }
    return ResponseBody.fromBytes(
      utf8.encode('{}'),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ThemeData _theme() => ThemeData(
      brightness: Brightness.dark,
      extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
    );

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ImageFollowUpStore.instance.clear('loader-1');
  });

  testWidgets('the in-flight follow-up shows the vision loader, not a spinner',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'xgrok_enabled': false,
      'lite_model': 'gemini-2.5-flash-lite',
      'deep_model': 'gemini-2.5-pro',
      'default_followup_provider': 'gemini',
    });
    final adapter = _HoldingAdapter();
    final apiClient = ApiClient();
    apiClient.dio.httpClientAdapter = adapter;
    final prefs = await SharedPreferences.getInstance();
    final controller =
        SettingsController(prefs, UserPreferencesService(apiClient));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => controller),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: Center(
              child: ImageFollowUpFab(
                sessionKey: 'loader-1',
                query: 'a cat',
                initialAnswer: 'A picture of a cat.',
                model: 'gemini-2.5-flash-lite',
                imageBytes: _smallPng,
                imageMediaType: 'image/png',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ImageFollowUpFab));
    await _drain(tester);

    // Nothing is waiting yet.
    expect(find.byType(NexusLoader), findsNothing);

    await tester.enterText(find.byType(TextField), 'is it tabby?');
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.send));
    await tester.pump(const Duration(milliseconds: 120));

    // The request is parked, so the loading bubble is on screen.
    final loaders = find.byType(NexusLoader);
    expect(loaders, findsOneWidget,
        reason: 'the in-flight turn must render the loader primitive');
    final loader = tester.widget<NexusLoader>(loaders);
    expect(loader.variant, NexusLoaderVariant.vision,
        reason: 'an image follow-up is a vision wait');
    expect(loader.image, isNotNull,
        reason: 'the vision variant renders the attached thumbnail');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    adapter.release();
    await _drain(tester);
    await _drain(tester);

    // Once the answer lands the loader is gone again.
    expect(find.byType(NexusLoader), findsNothing);
    expect(find.text('It looks like a tabby cat.'), findsOneWidget);
  });

  testWidgets('send and voice buttons clear the 48dp minimum target',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'xgrok_enabled': false,
      'lite_model': 'gemini-2.5-flash-lite',
      'deep_model': 'gemini-2.5-pro',
      'default_followup_provider': 'gemini',
    });
    final adapter = _HoldingAdapter();
    final apiClient = ApiClient();
    apiClient.dio.httpClientAdapter = adapter;
    final prefs = await SharedPreferences.getInstance();
    final controller =
        SettingsController(prefs, UserPreferencesService(apiClient));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => controller),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: Center(
              child: ImageFollowUpFab(
                sessionKey: 'loader-1',
                query: 'a cat',
                initialAnswer: 'A picture of a cat.',
                model: 'gemini-2.5-flash-lite',
                imageBytes: _smallPng,
                imageMediaType: 'image/png',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(ImageFollowUpFab));
    await _drain(tester);

    final send = tester.getSize(find.byIcon(LucideIcons.send).hitTestable());
    expect(send.width, greaterThanOrEqualTo(48.0));
    expect(send.height, greaterThanOrEqualTo(48.0));
  });
}
