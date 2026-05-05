import 'package:flutter/services.dart';

import '../../core/platform/platform_capabilities.dart';
import '../../core/services/telegram_logger.dart';

typedef TtsRangeCallback = void Function(int start, int end);

/// Thin Dart wrapper around the native Android TTS MethodChannel.
/// Bypasses flutter_tts entirely so we can specify the Google engine
/// at construction time (avoids Samsung private-engine bind failures).
class NativeTtsEngine {
  NativeTtsEngine() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const _channel = MethodChannel('app.ainexus.ai_nexus/native_tts');

  VoidCallback? onStart;
  VoidCallback? onDone;
  void Function(String message)? onError;
  TtsRangeCallback? onRange;

  bool _initialized = false;

  Future<bool> init() async {
    if (!PlatformCapabilities.canUseNativeTts) {
      TLog.d('NativeTTS', 'Skipped on non-Android platform');
      return false;
    }
    if (_initialized) return true;
    try {
      final result = await _channel.invokeMethod<int>('init');
      _initialized = result == 1;
      TLog.d('NativeTTS', 'Init result: $result');
      return _initialized;
    } catch (e) {
      TLog.e('NativeTTS', 'init failed', error: e);
      return false;
    }
  }

  Future<void> setLanguage(String language) async {
    try {
      await _channel.invokeMethod('setLanguage', {'language': language});
    } catch (e) {
      TLog.e('NativeTTS', 'setLanguage failed', error: e);
    }
  }

  Future<void> setSpeechRate(double rate) async {
    try {
      await _channel.invokeMethod<int>('setSpeechRate', {'rate': rate});
    } catch (e) {
      TLog.e('NativeTTS', 'setSpeechRate failed', error: e);
    }
  }

  Future<void> setVolume(double volume) async {
    try {
      await _channel.invokeMethod<int>('setVolume', {'volume': volume});
    } catch (e) {
      TLog.e('NativeTTS', 'setVolume failed', error: e);
    }
  }

  Future<void> setPitch(double pitch) async {
    try {
      await _channel.invokeMethod<int>('setPitch', {'pitch': pitch});
    } catch (e) {
      TLog.e('NativeTTS', 'setPitch failed', error: e);
    }
  }

  Future<int> speak(String text) async {
    if (!PlatformCapabilities.canUseNativeTts) return 0;
    try {
      final result = await _channel.invokeMethod<int>('speak', {'text': text});
      return result ?? 0;
    } catch (e) {
      TLog.e('NativeTTS', 'speak failed', error: e);
      return 0;
    }
  }

  Future<void> stop() async {
    if (!PlatformCapabilities.canUseNativeTts) return;
    try {
      await _channel.invokeMethod<int>('stop');
    } catch (e) {
      TLog.e('NativeTTS', 'stop failed', error: e);
    }
  }

  Future<void> shutdown() async {
    if (!PlatformCapabilities.canUseNativeTts) return;
    _initialized = false;
    try {
      await _channel.invokeMethod<int>('shutdown');
    } catch (e) {
      TLog.e('NativeTTS', 'shutdown failed', error: e);
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onStart':
          onStart?.call();
        case 'onDone':
          onDone?.call();
        case 'onError':
          final msg = call.arguments?.toString() ?? 'Unknown error';
          TLog.w('NativeTTS', 'Error: $msg');
          onError?.call(msg);
        case 'onRange':
          final args = call.arguments;
          if (args is Map) {
            final start = args['start'];
            final end = args['end'];
            if (start is int && end is int) {
              onRange?.call(start, end);
            }
          }
      }
    } catch (e) {
      TLog.e('NativeTTS', 'Callback handling failed: ${call.method}', error: e);
    }
  }
}
