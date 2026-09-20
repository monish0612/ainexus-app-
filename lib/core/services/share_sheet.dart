import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';
import 'telegram_logger.dart';

/// Opens the OS share sheet (Android app chooser). Never writes the
/// clipboard — copy-as-share was the news-article bug.
class ShareSheet {
  ShareSheet._();

  static const _channel = MethodChannel('app.ainexus.ai_nexus/share');

  /// Returns `true` when the system chooser was shown.
  static Future<bool> shareText({
    required String text,
    String subject = 'Nexus AI',
  }) async {
    final body = text.trim();
    if (body.isEmpty) return false;
    if (!PlatformCapabilities.canUseProcessText) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('shareText', {
        'text': body,
        'subject': subject,
      });
      return ok == true;
    } on MissingPluginException catch (e) {
      TLog.w('Share', 'Share channel missing', error: e);
      return false;
    } catch (e) {
      TLog.w('Share', 'Share sheet failed', error: e);
      return false;
    }
  }
}
