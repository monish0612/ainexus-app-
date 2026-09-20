import 'package:ai_nexus/bubble/overlay/overlay_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract test for the Dart↔Kotlin overlay channel.
///
/// The method names and argument keys here must match `OverlayBridgeHost.kt`
/// exactly — a typo on either side fails silently at runtime, so it is pinned
/// down in a test instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.ainexus.ai_nexus/bubble_overlay');
  final calls = <MethodCall>[];
  late OverlayBridge bridge;

  setUp(() {
    calls.clear();
    bridge = OverlayBridge();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'target':
        case 'expand':
          return <String, dynamic>{
            'text': 'captured text',
            'package': 'com.whatsapp',
            'maxWidth': 324.0,
            'maxHeight': 288.0,
            'lastPlatformId': 'whatsapp',
            'bubbleX': 280.0,
            'bubbleY': 520.0,
            'bubbleSize': 76.0,
          };
        case 'replace':
          return 'REPLACED_SET_TEXT';
        default:
          return true;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('outgoing calls', () {
    test('target returns the snapshot and the panel size budget', () async {
      final target = await bridge.target();
      expect(calls.single.method, 'target');
      expect(target.text, 'captured text');
      expect(target.package, 'com.whatsapp');
      expect(target.maxWidth, 324.0);
      expect(target.maxHeight, 288.0);
      expect(target.lastPlatformId, 'whatsapp');
      expect(target.bubbleX, 280.0);
      expect(target.bubbleY, 520.0);
      expect(target.bubbleSize, 76.0);
    });

    test('saveLastPlatform sends the platform id', () async {
      await bridge.saveLastPlatform('casual');
      expect(calls.single.method, 'saveLastPlatform');
      expect(calls.single.arguments, {'platform': 'casual'});
    });

    test('expand asks native for a fresh read', () async {
      final target = await bridge.expand();
      expect(calls.single.method, 'expand');
      expect(target.text, 'captured text');
    });

    test('replace passes the text and maps the outcome', () async {
      final outcome = await bridge.replace('new text');
      expect(calls.single.method, 'replace');
      expect(calls.single.arguments, {'text': 'new text'});
      expect(outcome, ReplaceOutcome.setText);
      expect(outcome.replaced, isTrue);
    });

    test('resize reports logical pixels as width and height', () async {
      await bridge.resize(const Size(308, 214));
      expect(calls.single.method, 'resize');
      expect(calls.single.arguments, {'width': 308.0, 'height': 214.0});
    });

    test('setFocusable carries the boolean', () async {
      await bridge.setFocusable(true);
      expect(calls.single.method, 'setFocusable');
      expect(calls.single.arguments, {'value': true});
    });

    test('simple commands take no arguments', () async {
      await bridge.collapse();
      await bridge.hideKeyboard();
      expect(
        calls.map((c) => c.method),
        ['collapse', 'hideKeyboard'],
      );
      expect(calls.every((c) => c.arguments == null), isTrue);
    });

    test('copy sends the text', () async {
      await bridge.copy('to clipboard');
      expect(calls.single.method, 'copy');
      expect(calls.single.arguments, {'text': 'to clipboard'});
    });
  });

  group('outcome mapping', () {
    test('maps every native outcome name', () {
      expect(ReplaceOutcome.fromName('REPLACED_SET_TEXT'), ReplaceOutcome.setText);
      expect(ReplaceOutcome.fromName('REPLACED_PASTE'), ReplaceOutcome.paste);
      expect(ReplaceOutcome.fromName('BLOCKED'), ReplaceOutcome.blocked);
      // Anything unexpected is treated as blocked, never as success.
      expect(ReplaceOutcome.fromName(null), ReplaceOutcome.blocked);
      expect(ReplaceOutcome.fromName('SOMETHING_NEW'), ReplaceOutcome.blocked);
      expect(ReplaceOutcome.paste.replaced, isTrue);
      expect(ReplaceOutcome.blocked.replaced, isFalse);
    });
  });

  group('resilience to a dead service', () {
    test('a platform failure degrades to blocked rather than throwing',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'BUBBLE_BRIDGE');
      });

      expect(await bridge.replace('text'), ReplaceOutcome.blocked);
      expect((await bridge.target()).text, isEmpty);
      // Fire-and-forget commands must swallow the failure.
      await bridge.collapse();
      await bridge.resize(const Size(10, 10));
    });
  });

  group('incoming calls', () {
    Future<void> send(String method, [Object? args]) {
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
    }

    test('onTarget delivers the payload, including the size budget', () async {
      BubbleTarget? received;
      bridge.onTarget = (target) => received = target;

      await send('onTarget', {
        'text': 'typed in gmail',
        'package': 'com.google.android.gm',
        'maxWidth': 300.0,
        'maxHeight': 250.0,
      });

      expect(received?.text, 'typed in gmail');
      expect(received?.package, 'com.google.android.gm');
      expect(received?.maxHeight, 250.0);
    });

    test('a payload without a budget falls back to sane defaults', () async {
      BubbleTarget? received;
      bridge.onTarget = (target) => received = target;

      await send('onTarget', {'text': 'x', 'package': 'y'});
      expect(received?.maxWidth, greaterThan(0));
      expect(received?.maxHeight, greaterThan(0));
    });

    test('a zero budget is replaced by the default', () async {
      BubbleTarget? received;
      bridge.onTarget = (target) => received = target;

      await send('onTarget', {
        'text': 'x',
        'package': 'y',
        'maxWidth': 0,
        'maxHeight': 0,
      });
      expect(received?.maxWidth, greaterThan(0));
      expect(received?.maxHeight, greaterThan(0));
    });

    test('onCollapse fires', () async {
      var collapsed = 0;
      bridge.onCollapse = () => collapsed++;
      await send('onCollapse');
      expect(collapsed, 1);
    });

    test('onTap fires when native detects a bubble tap', () async {
      var taps = 0;
      bridge.onTap = () => taps++;
      await send('onTap');
      expect(taps, 1);
    });

    test('an unknown incoming method is ignored', () async {
      await send('somethingElse');
    });
  });
}
