import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_capabilities.dart';
import 'telegram_logger.dart';

/// Holds the word routed to the Dictionary tab after the user picks from the
/// chooser sheet. Set by AppShell, consumed by TutorScreen.
final pendingDictionaryWordProvider = StateProvider<String?>((ref) => null);

/// Holds the text routed to the Rephrase tab after the user picks from the
/// chooser sheet. Set by AppShell, consumed by TutorScreen.
final pendingRephraseTextProvider = StateProvider<String?>((ref) => null);

/// Holds a URL routed to the Summarizer tab from share intent.
/// Set by AppShell, consumed by TutorScreen.
final pendingSummarizerUrlProvider = StateProvider<String?>((ref) => null);

/// Holds an image path shared via ACTION_SEND for the expense scanner.
/// Set by AppShell, consumed by ExpenseScreen.
final pendingExpenseImageProvider = StateProvider<String?>((ref) => null);

/// Holds freeform text shared via ACTION_SEND (e.g. a bank transaction SMS)
/// that should be parsed into an expense. Set by AppShell, consumed by
/// ExpenseScreen. The text is fed straight into the smart-parse pipeline —
/// the same one the bill/image scanner uses — to auto-fill the add-expense
/// form (amount, merchant, category, bank, card type).
final pendingExpenseTextProvider = StateProvider<String?>((ref) => null);

/// Holds a search query to route to the Summarizer tab's search flow.
/// Set by AppShell, consumed by TutorScreen.
final pendingSearchQueryProvider = StateProvider<String?>((ref) => null);

/// Bridges the Android PROCESS_TEXT intent to Flutter via a MethodChannel.
///
/// Two communication paths:
///  - **Pull** (cold start): Flutter calls [getProcessedText] after launch.
///  - **Push** (warm resume): Native invokes `onProcessedText` via the channel
///    when [onNewIntent] fires on the activity.
class ProcessTextService {
  ProcessTextService._();

  static const _channel = MethodChannel('app.ainexus.ai_nexus/process_text');
  static bool _initialized = false;
  static void Function(String text)? _onTextReceived;
  static void Function(String text)? _onSharedReceived;
  static void Function(String path)? _onSharedImageReceived;

  /// Call once from a high-level widget (e.g. AppShell).
  static void initialize({
    required void Function(String text) onTextReceived,
    required void Function(String text) onSharedReceived,
    required void Function(String path) onSharedImageReceived,
  }) {
    if (!PlatformCapabilities.canUseProcessText) return;
    if (_initialized) return;
    _initialized = true;
    _onTextReceived = onTextReceived;
    _onSharedReceived = onSharedReceived;
    _onSharedImageReceived = onSharedImageReceived;

    _channel.setMethodCallHandler((call) async {
      final arg = call.arguments as String?;
      if (arg == null || arg.isEmpty) return;

      switch (call.method) {
        case 'onProcessedText':
          TLog.d('ProcessText', 'Push: "$arg"');
          _onTextReceived?.call(arg);
        case 'onSharedText':
          TLog.d('ProcessText', 'Share push: "$arg"');
          _onSharedReceived?.call(arg);
        case 'onSharedImage':
          TLog.d('ProcessText', 'Image push: "$arg"');
          _onSharedImageReceived?.call(arg);
      }
    });
  }

  /// Pull the pending text from native (used on cold start).
  /// Returns `null` if no PROCESS_TEXT intent was received.
  static Future<String?> getProcessedText() async {
    if (!PlatformCapabilities.canUseProcessText) return null;
    try {
      final text = await _channel.invokeMethod<String>('getProcessedText');
      if (text != null && text.isNotEmpty) {
        TLog.d('ProcessText', 'Pull: "$text"');
      }
      return text;
    } on PlatformException catch (e) {
      TLog.w('ProcessText', 'Pull failed', error: e);
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Pull the pending shared text from native (used on cold start).
  static Future<String?> getSharedText() async {
    if (!PlatformCapabilities.canUseProcessText) return null;
    try {
      final text = await _channel.invokeMethod<String>('getSharedText');
      if (text != null && text.isNotEmpty) {
        TLog.d('ProcessText', 'Share pull: "$text"');
      }
      return text;
    } on PlatformException catch (e) {
      TLog.w('ProcessText', 'Share pull failed', error: e);
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Pull the pending shared image path from native (used on cold start).
  static Future<String?> getSharedImagePath() async {
    if (!PlatformCapabilities.canUseProcessText) return null;
    try {
      final path = await _channel.invokeMethod<String>('getSharedImagePath');
      if (path != null && path.isNotEmpty) {
        TLog.d('ProcessText', 'Image pull: "$path"');
      }
      return path;
    } on PlatformException catch (e) {
      TLog.w('ProcessText', 'Image pull failed', error: e);
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
