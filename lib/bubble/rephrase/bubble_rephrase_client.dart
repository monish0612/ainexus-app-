import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/services/telegram_logger.dart';
import '../../core/utils/rephrase_input.dart';
import '../../data/services/tutor_ai_service.dart';
import 'resilience.dart';

/// Rephrase calls made from the overlay isolate.
///
/// Same endpoint, body and platform ids as the in-app Rephrase tab — this just
/// adds a cache and the guard rails a floating UI needs (bounded time, bounded
/// retries, and a breaker so a dead backend doesn't punish every tap).
class BubbleRephraseClient {
  BubbleRephraseClient({TutorAiService? service})
      : _service = service ?? TutorAiService(ApiClient());

  final TutorAiService _service;
  final _cache = _Lru(32);
  final _breaker = CircuitBreaker();

  /// Rephrase [text] for [platform]. For `own`, [intent] is the tone the user
  /// typed in the panel; it is prefix-stripped so "rephrase to formal tone"
  /// reaches the server as "formal tone", exactly like the in-app parser does.
  ///
  /// [fresh] skips the cache read (the "New version" button) so the model gets
  /// a chance to produce a different take; the new result still replaces the
  /// cached one.
  Future<String> rephrase({
    required String text,
    required String platform,
    String? intent,
    bool fresh = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw BubbleError(BubbleErrorKind.permanent, 'Nothing to rephrase');
    }

    final cleanIntent = intent == null || intent.trim().isEmpty
        ? null
        : stripRephrasePrefix(intent);

    // Lite model is part of the cache key so a Settings change is not served
    // a rewrite produced by the previous Gemini id.
    // Settings live in the main isolate. This overlay must not wait on that
    // plugin channel — a hung read used to leave the panel on "Rephrasing…"
    // forever. A missing model id still rephrases with the server default.
    final liteModel = await _liteModel()
        .timeout(const Duration(milliseconds: 400), onTimeout: () => null);
    final key = '$platform::${cleanIntent ?? ''}::$trimmed::${liteModel ?? ''}';
    if (!fresh) {
      final cached = _cache.get(key);
      if (cached != null) return cached;
    }

    try {
      final result = await _breaker.run(
        () => retryWithBackoff(
          () => withTimeoutOr(
            () async {
              final response = await _service.rephrase(
                text: trimmed,
                platform: platform,
                intent: cleanIntent,
                liteModel: liteModel,
              );
              final text = response.rephrasedText.trim();
              if (isModelRefusal(text)) {
                throw BubbleError(
                  BubbleErrorKind.permanent,
                  'Blocked — try another tone',
                );
              }
              return text;
            },
          ),
        ),
      );
      if (result.isEmpty) {
        throw BubbleError(BubbleErrorKind.permanent, 'Empty rephrase');
      }
      _cache.put(key, result);
      return result;
    } catch (e) {
      final failure = classify(e);
      TLog.e(
        'Bubble',
        'Rephrase failed → platform=$platform kind=${failure.kind.name}',
        error: e,
      );
      throw failure;
    }
  }

  /// Honour the model the user picked in app settings (`lite_model` key written
  /// by SettingsController). Reloads from disk because this client runs in the
  /// overlay isolate, which otherwise keeps a stale copy after Settings saves.
  Future<String?> _liteModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {
        // Still use the in-memory copy if the platform channel is down.
      }
      final model = prefs.getString('lite_model')?.trim();
      return (model == null || model.isEmpty) ? null : model;
    } catch (_) {
      return null;
    }
  }
}

/// Tiny LRU so repeat taps on the same chip are instant.
class _Lru {
  _Lru(this.capacity);

  final int capacity;

  /// A plain map literal is insertion-ordered, so the first key is the LRU.
  final _map = <String, String>{};

  String? get(String key) {
    final value = _map.remove(key);
    if (value != null) _map[key] = value;
    return value;
  }

  void put(String key, String value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > capacity) _map.remove(_map.keys.first);
  }
}
