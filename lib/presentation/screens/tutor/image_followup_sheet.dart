// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/services/background_task_coordinator.dart';
import '../../../core/services/followup_history.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/reduced_motion.dart';
import '../../../data/services/tutor_ai_service.dart';
import '../../../domain/entities/tutor_entities.dart';
import '../../widgets/block_selectable.dart';
import '../../widgets/nexus_loader.dart';
import '../../widgets/provider_picker.dart';
import '../../widgets/voice_input_button.dart';
import '../settings/settings_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CHAT MESSAGE (private)
// ═══════════════════════════════════════════════════════════════════════════════

class _ChatMessage {
  _ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.isLoading = false,
  });

  final String id;
  final String role;
  String text;
  List<GroundedSource> sources = const <GroundedSource>[];
  String model = '';
  bool isLoading;
  bool isError = false;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RETRY CONTEXT
// ═══════════════════════════════════════════════════════════════════════════════

class _ImageFollowUpRetry {
  _ImageFollowUpRetry({
    required this.query,
    required this.imageBytes,
    required this.imageMediaType,
    required this.aiMsg,
    required this.history,
    required this.question,
    required this.aiService,
    this.mode,
    this.deepModel,
    this.liteModel,
    this.provider,
    this.xgrokLiteModel,
    this.xgrokDeepModel,
    this.xgrokThinkingModel,
  });

  final String query;
  final Uint8List imageBytes;
  final String imageMediaType;
  final _ChatMessage aiMsg;
  final List<Map<String, String>> history;
  final String question;
  final TutorAiService aiService;
  final String? mode;
  final String? deepModel;
  final String? liteModel;
  final String? provider;
  final String? xgrokLiteModel;
  final String? xgrokDeepModel;
  final String? xgrokThinkingModel;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STORE — per-session image chat with retry / FG-service / background notification
// ═══════════════════════════════════════════════════════════════════════════════
//
// Mirrors [SearchFollowUpStore] closely. Differences:
//   • Each session is keyed by [sessionKey] (the active saved-search id
//     on screen), NOT by the user's free-text query — so the SAME query
//     can be asked twice with two different images without collisions.
//   • Each `sendQuestion` call re-attaches the full image bytes from the
//     in-memory session map. The bytes are NEVER pushed to the saved-
//     search server; only the typed text per chat turn syncs cross-device.

class ImageFollowUpStore with WidgetsBindingObserver {
  ImageFollowUpStore._();
  static final instance = ImageFollowUpStore._();

  /// 10-pair Lite → Deep auto-upgrade, same heuristic as the text path.
  static const kAutoDeepThreshold = 10;

  final _cache = <String, List<_ChatMessage>>{};
  final _imageBytes = <String, Uint8List>{};
  final _imageMediaTypes = <String, String>{};
  final _initialAnswers = <String, String>{};
  final _queries = <String, String>{};
  final _listeners = <String, VoidCallback>{};
  final _pendingAiMsgs = <String, _ChatMessage>{};
  final _retryQueue = <String, _ImageFollowUpRetry>{};
  final _cancelTokens = <String, CancelToken>{};
  bool _appInBackground = false;
  bool _observerBound = false;

  static const _kChannelId = 'nexus_ai_processing';
  static const _kChannelName = 'AI Processing';
  static const _kChannelDesc =
      'Shows progress when AI generates answers in the background';
  static const _kProcessingNotifId = 9120;
  static const _kCompletionNotifId = 9121;
  static FlutterLocalNotificationsPlugin? _notifPlugin;

  void init() {
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  // ── Session lifecycle ────────────────────────────────────────────────

  /// Attaches the image bytes for a session. Idempotent — calling
  /// multiple times for the same key replaces the bytes (rare, but
  /// happens if a user "re-attaches" a freshly compressed copy).
  void registerSession({
    required String sessionKey,
    required String query,
    required String initialAnswer,
    required Uint8List imageBytes,
    required String imageMediaType,
  }) {
    _imageBytes[sessionKey] = imageBytes;
    _imageMediaTypes[sessionKey] = imageMediaType;
    _initialAnswers[sessionKey] = initialAnswer;
    _queries[sessionKey] = query;
  }

  bool hasSession(String sessionKey) => _imageBytes.containsKey(sessionKey);
  Uint8List? sessionImageBytes(String sessionKey) => _imageBytes[sessionKey];
  String? sessionImageMediaType(String sessionKey) =>
      _imageMediaTypes[sessionKey];

  void addListener(String key, VoidCallback cb) => _listeners[key] = cb;
  void removeListener(String key, VoidCallback cb) {
    if (_listeners[key] == cb) _listeners.remove(key);
  }

  bool hasPending(String key) => _pendingAiMsgs.containsKey(key);
  List<_ChatMessage> getCached(String key) => _cache[key] ?? const [];

  List<FollowUpMessage> shareMessages(String sessionKey) {
    final list = _cache[sessionKey];
    if (list == null || list.isEmpty) return const [];
    return [
      for (final m in list)
        FollowUpMessage(
          role: m.role,
          text: m.text,
          isLoading: m.isLoading,
          isError: m.isError,
          model: m.model,
          sources: [
            for (final s in m.sources)
              FollowUpSourceRef(url: s.url, title: s.title),
          ],
        ),
    ];
  }

  // ── Background notification helpers ──────────────────────────────────

  static Future<FlutterLocalNotificationsPlugin> _ensureNotifPlugin() async {
    if (_notifPlugin != null) return _notifPlugin!;
    _notifPlugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('ic_notification');
    await _notifPlugin!
        .initialize(const InitializationSettings(android: android));
    return _notifPlugin!;
  }

  Future<void> _showProcessingNotification(String query) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      final q = query.isEmpty
          ? 'your image'
          : (query.length > 50 ? '${query.substring(0, 50)}\u2026' : query);
      const details = AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: _kChannelDesc,
        importance: Importance.low,
        priority: Priority.low,
        icon: 'ic_notification',
        ongoing: true,
        autoCancel: false,
        showProgress: true,
        indeterminate: true,
        category: AndroidNotificationCategory.progress,
        color: ui.Color(0xFF4285F4),
      );
      await fln.show(
        _kProcessingNotifId,
        '\u2728 AI is thinking\u2026',
        'Answering image follow-up for "$q"',
        const NotificationDetails(android: details),
      );
    } catch (e) {
      TLog.w('ImageFollowUp', 'Processing notification failed: $e');
    }
  }

  Future<void> _showCompletionNotification(String query) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      await fln.cancel(_kProcessingNotifId);
      final q = query.isEmpty
          ? 'your image'
          : (query.length > 50 ? '${query.substring(0, 50)}\u2026' : query);
      const details = AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: _kChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
        category: AndroidNotificationCategory.message,
        color: ui.Color(0xFF4285F4),
      );
      await fln.show(
        _kCompletionNotifId,
        '\u2705 Answer ready',
        'Your follow-up about "$q" has been answered',
        const NotificationDetails(android: details),
        payload: 'tutor_tab',
      );
    } catch (e) {
      TLog.w('ImageFollowUp', 'Completion notification failed: $e');
    }
  }

  Future<void> _cancelProcessingNotification() async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      await fln.cancel(_kProcessingNotifId);
    } catch (_) {}
  }

  static String _coordSlotId(String key) =>
      'image_followup:${key.hashCode.toUnsigned(32)}';

  void _acquireCoordSlot(String key, String query) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    final preview =
        query.length > 40 ? '${query.substring(0, 37)}\u2026' : query;
    unawaited(BackgroundTaskCoordinator.instance.acquire(
      _coordSlotId(key),
      label: '\uD83D\uDDBC\uFE0F Image chat: ${preview.isEmpty ? 'follow-up' : preview}',
    ));
  }

  void _releaseCoordSlot(String key) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    unawaited(BackgroundTaskCoordinator.instance.release(_coordSlotId(key)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_appInBackground && _pendingAiMsgs.isNotEmpty) {
        _appInBackground = true;
        final firstKey = _pendingAiMsgs.keys.first;
        unawaited(_showProcessingNotification(_queries[firstKey] ?? ''));
      }
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    final wasInBackground = _appInBackground;
    _appInBackground = false;
    if (wasInBackground) {
      unawaited(_cancelProcessingNotification());
    }

    if (_retryQueue.isEmpty) return;
    final pendingKeys = _retryQueue.keys.toList();

    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      for (final key in pendingKeys) {
        final r = _retryQueue.remove(key);
        if (r == null) continue;
        TLog.d('ImageFollowUp', 'Resumed — retrying for "${r.query}"');
        r.aiMsg
          ..text = ''
          ..isLoading = true
          ..isError = false;
        _pendingAiMsgs[key] = r.aiMsg;
        final token = CancelToken();
        _cancelTokens[key] = token;
        _listeners[key]?.call();
        _acquireCoordSlot(key, r.query);
        unawaited(_executeRequest(
          sessionKey: key,
          query: r.query,
          imageBytes: r.imageBytes,
          imageMediaType: r.imageMediaType,
          aiMsg: r.aiMsg,
          history: r.history,
          question: r.question,
          aiService: r.aiService,
          mode: r.mode,
          deepModel: r.deepModel,
          liteModel: r.liteModel,
          provider: r.provider,
          xgrokLiteModel: r.xgrokLiteModel,
          xgrokDeepModel: r.xgrokDeepModel,
          xgrokThinkingModel: r.xgrokThinkingModel,
          cancelToken: token,
          isRetry: true,
        ));
      }
    });
  }

  static bool _isRetryableNetworkError(Object? e) {
    if (e == null) return false;
    if (e is DioException) {
      if (e.type == DioExceptionType.cancel) return false;
      if (e.type != DioExceptionType.badResponse) return true;
      final s = e.response?.statusCode;
      if (s != null && s >= 500) return true;
      return false;
    }
    final s = e.toString().toLowerCase();
    return s.contains('connection abort') ||
        s.contains('connection reset') ||
        s.contains('broken pipe') ||
        s.contains('network is unreachable') ||
        s.contains('socket') ||
        s.contains('timed out') ||
        s.contains('connection closed');
  }

  // ── Fire-and-forget AI request ───────────────────────────────────────

  void sendQuestion({
    required String sessionKey,
    required String query,
    required _ChatMessage userMsg,
    required _ChatMessage aiMsg,
    required List<Map<String, String>> history,
    required TutorAiService aiService,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? provider,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
  }) {
    final bytes = _imageBytes[sessionKey];
    final media = _imageMediaTypes[sessionKey];
    if (bytes == null || media == null) {
      TLog.w('ImageFollowUp',
          'sendQuestion: no image bytes for session $sessionKey — aborting');
      aiMsg
        ..text = 'Image not available — please re-upload to continue.'
        ..isLoading = false
        ..isError = true;
      _listeners[sessionKey]?.call();
      return;
    }
    TLog.d('ImageFollowUp',
        'sendQuestion mode=${mode ?? 'lite'} provider=${provider ?? 'gemini'} '
        'histLen=${history.length} imageKB=${(bytes.lengthInBytes / 1024).toStringAsFixed(0)}');

    _cache.putIfAbsent(sessionKey, () => []);
    final list = _cache[sessionKey]!;
    if (!list.any((m) => m.id == userMsg.id)) list.add(userMsg);
    if (!list.any((m) => m.id == aiMsg.id)) list.add(aiMsg);

    _pendingAiMsgs[sessionKey] = aiMsg;
    final token = CancelToken();
    _cancelTokens[sessionKey] = token;
    _acquireCoordSlot(sessionKey, query);

    unawaited(_executeRequest(
      sessionKey: sessionKey,
      query: query,
      imageBytes: bytes,
      imageMediaType: media,
      aiMsg: aiMsg,
      history: history,
      question: userMsg.text,
      aiService: aiService,
      mode: mode,
      deepModel: deepModel,
      liteModel: liteModel,
      provider: provider,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
      cancelToken: token,
    ));
  }

  String? cancelPending(String sessionKey) {
    _cancelTokens[sessionKey]?.cancel('User cancelled');
    _cancelTokens.remove(sessionKey);
    _retryQueue.remove(sessionKey);
    _releaseCoordSlot(sessionKey);

    final list = _cache[sessionKey];
    if (list == null || list.isEmpty) {
      _pendingAiMsgs.remove(sessionKey);
      _listeners[sessionKey]?.call();
      return null;
    }
    String? userText;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].isLoading && list[i].role == 'assistant') {
        list.removeAt(i);
        if (i > 0 && list[i - 1].role == 'user') {
          userText = list[i - 1].text;
          list.removeAt(i - 1);
        }
        break;
      }
    }
    _pendingAiMsgs.remove(sessionKey);
    _listeners[sessionKey]?.call();
    return userText;
  }

  Future<void> _executeRequest({
    required String sessionKey,
    required String query,
    required Uint8List imageBytes,
    required String imageMediaType,
    required _ChatMessage aiMsg,
    required List<Map<String, String>> history,
    required String question,
    required TutorAiService aiService,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? provider,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
    bool isRetry = false,
  }) async {
    bool keepPending = false;

    try {
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (cancelToken?.isCancelled ?? false) return;
        try {
          final result = await aiService.imageFollowUp(
            query: query,
            // Pass the original image-search answer so the backend
            // can ground turn #1 even when `history` is empty.
            initialAnswer: _initialAnswers[sessionKey] ?? '',
            question: question,
            imageBytes: imageBytes,
            imageMediaType: imageMediaType,
            history: history,
            mode: mode,
            deepModel: deepModel,
            liteModel: liteModel,
            provider: provider,
            xgrokLiteModel: xgrokLiteModel,
            xgrokDeepModel: xgrokDeepModel,
            xgrokThinkingModel: xgrokThinkingModel,
            cancelToken: cancelToken,
          );
          if (!_cache.containsKey(sessionKey)) return;
          if (cancelToken?.isCancelled ?? false) return;
          aiMsg
            ..text = result.answer
            ..sources = result.sources
            ..model = mode ?? 'lite'
            ..isLoading = false;
          return;
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) return;
          lastError = e;
          if (!_isRetryableNetworkError(e) ||
              !_cache.containsKey(sessionKey)) {
            break;
          }
          if (attempt < 2) {
            TLog.w('ImageFollowUp',
                'Network error — retry ${attempt + 1}/2 (${e.runtimeType})');
            await Future.delayed(Duration(seconds: (attempt + 1) * 5));
            if (cancelToken?.isCancelled ?? false) return;
            if (!_cache.containsKey(sessionKey)) return;
          }
        }
      }

      if (lastError != null &&
          _isRetryableNetworkError(lastError) &&
          _cache.containsKey(sessionKey)) {
        _retryQueue[sessionKey] = _ImageFollowUpRetry(
          query: query,
          imageBytes: imageBytes,
          imageMediaType: imageMediaType,
          aiMsg: aiMsg,
          history: history,
          question: question,
          aiService: aiService,
          mode: mode,
          deepModel: deepModel,
          liteModel: liteModel,
          provider: provider,
          xgrokLiteModel: xgrokLiteModel,
          xgrokDeepModel: xgrokDeepModel,
          xgrokThinkingModel: xgrokThinkingModel,
        );
        keepPending = true;
        TLog.w('ImageFollowUp',
            'Scheduled auto-retry on resume for image follow-up "$query"');
      } else if (_cache.containsKey(sessionKey)) {
        TLog.e('ImageFollowUp', 'Image follow-up failed', error: lastError);
        aiMsg
          ..text = 'Something went wrong. Please try again.'
          ..isLoading = false
          ..isError = true;
      }
    } finally {
      final isStillActive =
          cancelToken != null && identical(_cancelTokens[sessionKey], cancelToken);
      if (isStillActive && !keepPending) {
        _pendingAiMsgs.remove(sessionKey);
        _cancelTokens.remove(sessionKey);
        _releaseCoordSlot(sessionKey);

        if (_appInBackground) {
          unawaited(_cancelProcessingNotification());
          if (!aiMsg.isError && aiMsg.text.isNotEmpty) {
            unawaited(_showCompletionNotification(query));
          }
        }
      }
      if (isStillActive) {
        _listeners[sessionKey]?.call();
      }
    }
  }

  void clear(String sessionKey) {
    _cancelTokens[sessionKey]?.cancel('Cleared');
    _cancelTokens.remove(sessionKey);
    _cache.remove(sessionKey);
    _pendingAiMsgs.remove(sessionKey);
    _retryQueue.remove(sessionKey);
    _imageBytes.remove(sessionKey);
    _imageMediaTypes.remove(sessionKey);
    _initialAnswers.remove(sessionKey);
    _queries.remove(sessionKey);
    _releaseCoordSlot(sessionKey);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  FAB
// ═══════════════════════════════════════════════════════════════════════════════

class ImageFollowUpFab extends StatefulWidget {
  const ImageFollowUpFab({
    super.key,
    required this.sessionKey,
    required this.query,
    required this.initialAnswer,
    required this.model,
    required this.imageBytes,
    required this.imageMediaType,
    this.savedSearchId,
  });

  final String sessionKey;
  final String query;
  final String initialAnswer;
  final String model;
  final Uint8List imageBytes;
  final String imageMediaType;
  final String? savedSearchId;

  @override
  State<ImageFollowUpFab> createState() => _ImageFollowUpFabState();
}

class _ImageFollowUpFabState extends State<ImageFollowUpFab>
    with TickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    final store = ImageFollowUpStore.instance;
    store.init();
    store.registerSession(
      sessionKey: widget.sessionKey,
      query: widget.query,
      initialAnswer: widget.initialAnswer,
      imageBytes: widget.imageBytes,
      imageMediaType: widget.imageMediaType,
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _open() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImageFollowUpChat(
        sessionKey: widget.sessionKey,
        query: widget.query,
        initialAnswer: widget.initialAnswer,
        model: widget.model,
        savedSearchId: widget.savedSearchId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.composerGradientEnd.withValues(alpha: 0.35),
              blurRadius: 16 + _pulseAnim.value,
              spreadRadius: _pulseAnim.value / 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
      child: GestureDetector(
        onTapDown: (_) => _scaleCtrl.forward(),
        onTapUp: (_) {
          _scaleCtrl.reverse();
          _open();
        },
        onTapCancel: () => _scaleCtrl.reverse(),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.composerGradientEnd, AppColors.composerGradientStart],
              ),
            ),
            child: const Icon(LucideIcons.image,
                color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CHAT SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _ImageFollowUpChat extends ConsumerStatefulWidget {
  const _ImageFollowUpChat({
    required this.sessionKey,
    required this.query,
    required this.initialAnswer,
    required this.model,
    this.savedSearchId,
  });

  final String sessionKey;
  final String query;
  final String initialAnswer;
  final String model;
  final String? savedSearchId;

  @override
  ConsumerState<_ImageFollowUpChat> createState() =>
      _ImageFollowUpChatState();
}

class _ImageFollowUpChatState extends ConsumerState<_ImageFollowUpChat>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  var _messages = <_ChatMessage>[];
  bool _sending = false;
  bool _useDeepModel = false;
  late bool _useXGrok;
  bool _maximized = false;
  bool _voiceListening = false;
  String _loadingPhase = '';
  Timer? _phaseTimer;
  int _idSeq = 0;
  bool _autoSwitchedToDeep = false;
  late final AnimationController _entryAnim;

  String _nextId() =>
      'if-${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  @override
  void initState() {
    super.initState();
    _useXGrok = ref.read(settingsProvider).defaultFollowUpIsXGrok;
    final store = ImageFollowUpStore.instance;
    store.init();
    store.addListener(widget.sessionKey, _onStoreUpdate);
    WidgetsBinding.instance.addObserver(this);
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _loadFromStore();
  }

  void _loadFromStore() {
    final store = ImageFollowUpStore.instance;
    final cached = store.getCached(widget.sessionKey);
    final hasPending = store.hasPending(widget.sessionKey);
    setState(() {
      _messages = List<_ChatMessage>.of(cached);
      _sending = hasPending;
    });
    if (hasPending) _startLoadingPhases();
    if (_messages.isNotEmpty) _scrollToBottom();
  }

  void _onStoreUpdate() {
    if (!mounted) return;
    final store = ImageFollowUpStore.instance;
    final cached = store.getCached(widget.sessionKey);
    final stillPending = store.hasPending(widget.sessionKey);
    if (!stillPending) _stopLoadingPhases();
    setState(() {
      _messages = List<_ChatMessage>.of(cached);
      _sending = stillPending;
    });
    _scrollToBottom();
    _maybeMirrorToSavedSearch();
  }

  final Set<String> _mirroredIds = <String>{};

  void _maybeMirrorToSavedSearch() {
    final id = widget.savedSearchId;
    if (id == null) return;
    final store = ref.read(savedSearchStoreProvider);
    for (final m in _messages) {
      if (m.isLoading || m.isError) continue;
      if (m.text.isEmpty) continue;
      if (_mirroredIds.contains(m.id)) continue;
      _mirroredIds.add(m.id);
      unawaited(store.appendMessage(
        searchId: id,
        messageId: m.id,
        role: m.role,
        text: m.text,
        model: m.model,
        sources: m.sources,
      ));
    }
  }

  @override
  void dispose() {
    ImageFollowUpStore.instance
        .removeListener(widget.sessionKey, _onStoreUpdate);
    WidgetsBinding.instance.removeObserver(this);
    _phaseTimer?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _entryAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final store = ImageFollowUpStore.instance;
      final cached = store.getCached(widget.sessionKey);
      final stillPending = store.hasPending(widget.sessionKey);
      setState(() {
        _messages = List<_ChatMessage>.of(cached);
        _sending = stillPending;
      });
      if (!stillPending) _stopLoadingPhases();
      _scrollToBottom();
    }
  }

  static const _litePhases = [
    'Examining image\u2026',
    'Analyzing details\u2026',
    'Composing answer\u2026',
  ];

  static const _deepPhases = [
    'Examining image\u2026',
    'Cross-referencing context\u2026',
    'Finding relevant details\u2026',
    'Synthesizing insights\u2026',
    'Composing detailed answer\u2026',
  ];

  static const _extendedPhases = [
    'Still analyzing\u2026',
    'Refining the response\u2026',
    'Almost there\u2026',
  ];

  void _startLoadingPhases() {
    if (_phaseTimer != null) return;
    final phases = _useDeepModel ? _deepPhases : _litePhases;
    int idx = 0;
    setState(() => _loadingPhase = phases[0]);

    _phaseTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      idx++;
      if (!mounted) return;
      String phase;
      if (idx < phases.length) {
        phase = phases[idx];
      } else {
        final extIdx = (idx - phases.length) % _extendedPhases.length;
        phase = _extendedPhases[extIdx];
      }
      setState(() => _loadingPhase = phase);
    });
  }

  void _stopLoadingPhases() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
  }

  void _cancel() {
    TLog.i('ImageChat', 'User cancelled image follow-up');
    final store = ImageFollowUpStore.instance;
    final restoredText = store.cancelPending(widget.sessionKey);
    _stopLoadingPhases();
    if (restoredText != null && restoredText.isNotEmpty) {
      _ctrl.text = restoredText;
      _ctrl.selection =
          TextSelection.collapsed(offset: restoredText.length);
    }
    _focusNode.requestFocus();
  }

  /// Re-shapes the in-memory chat into the `[{role, text}]` history
  /// the backend expects. Pairs are: (user, assistant) — we collect
  /// every completed pair before the in-flight user message.
  List<Map<String, String>> _collectPairs() {
    final out = <Map<String, String>>[];
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.isLoading || m.isError) continue;
      if (m.text.isEmpty) continue;
      out.add({'role': m.role, 'text': m.text});
    }
    return out;
  }

  void _maybeAutoSwitchToDeep(int pairCount) {
    if (_autoSwitchedToDeep || _useDeepModel) return;
    if (pairCount < ImageFollowUpStore.kAutoDeepThreshold) return;
    setState(() {
      _useDeepModel = true;
      _autoSwitchedToDeep = true;
    });
    TLog.i('ImageChat',
        'Auto-switched Lite \u2192 Deep at $pairCount pairs (image session)');
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1E1B4B),
      content: Row(
        children: [
          const Icon(LucideIcons.brain, size: 16, color: AppColors.deepViolet),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Switched to Deep — richer recall after 10+ messages',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ));
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    final store = ImageFollowUpStore.instance;
    final history = _collectPairs();
    _maybeAutoSwitchToDeep(history.length ~/ 2);

    final providerTag = _useXGrok ? 'xGrok' : 'Gemini';
    final modeTag = _useDeepModel ? 'Deep' : 'Lite';
    TLog.i('ImageChat',
        'Sending [$providerTag/$modeTag]: "${text.length > 60 ? '${text.substring(0, 60)}\u2026' : text}" '
        '(pairs=${history.length ~/ 2})');

    _ctrl.clear();
    _focusNode.requestFocus();

    final userMsg = _ChatMessage(id: _nextId(), role: 'user', text: text);
    final aiMsg = _ChatMessage(
        id: _nextId(), role: 'assistant', text: '', isLoading: true);

    setState(() {
      _messages.add(userMsg);
      _messages.add(aiMsg);
      _sending = true;
    });
    _startLoadingPhases();
    _scrollToBottom();

    final settings = ref.read(settingsProvider);
    final xgrokOn = settings.xgrokEnabled && _useXGrok;

    store.sendQuestion(
      sessionKey: widget.sessionKey,
      query: widget.query,
      userMsg: userMsg,
      aiMsg: aiMsg,
      history: history,
      aiService: ref.read(tutorAiServiceProvider),
      mode: _useDeepModel ? 'deep' : 'lite',
      deepModel: _useDeepModel ? settings.deepModel : null,
      liteModel: (_useDeepModel || xgrokOn) ? null : settings.liteModel,
      provider: xgrokOn ? 'xgrok' : null,
      xgrokLiteModel: xgrokOn ? settings.xgrokLiteModel : null,
      xgrokDeepModel: xgrokOn ? settings.xgrokDeepModel : null,
      xgrokThinkingModel: xgrokOn ? settings.xgrokThinkingModel : null,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;
    final safePad = MediaQuery.viewPaddingOf(context).bottom;

    final still = reducedMotion(context);

    return AnimatedBuilder(
      animation: _entryAnim,
      builder: (context, child) {
        // Reduced motion: no rise, no fade — the sheet is simply there.
        if (still) return child!;
        final slide = Tween<double>(begin: 40, end: 0)
            .animate(CurvedAnimation(
                parent: _entryAnim, curve: Curves.easeOutCubic))
            .value;
        return Transform.translate(
          offset: Offset(0, slide),
          child: Opacity(opacity: _entryAnim.value, child: child),
        );
      },
      child: AnimatedContainer(
        duration: still ? Duration.zero : const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        height: _maximized
            ? MediaQuery.sizeOf(context).height
            : MediaQuery.sizeOf(context).height * 0.78,
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_maximized ? 0 : AppRadii.sheet),
          ),
          border: _maximized
              ? null
              : Border(top: BorderSide(color: colors.border)),
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: still ? Duration.zero : const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              height: _maximized
                  ? MediaQuery.viewPaddingOf(context).top + 4
                  : 0,
              color: _maximized ? colors.bg : null,
            ),
            _buildHeader(colors),
            Expanded(
              child:
                  _messages.isEmpty ? _buildEmpty(colors) : _buildChat(colors),
            ),
            _buildInput(colors, bottomPad > 0 ? bottomPad : safePad),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors) {
    final subtitle = widget.query.isEmpty
        ? 'Image upload'
        : (widget.query.length > 50
            ? '${widget.query.substring(0, 50)}\u2026'
            : widget.query);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.composerGradientEnd, AppColors.composerGradientStart],
              ),
            ),
            child: const Icon(LucideIcons.image,
                size: 14, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Image follow-up',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
          ),
          // In-flight state lives on the pending bubble's NexusLoader and the
          // red stop button — no third bare spinner up here.
          IconButton(
            icon: Icon(
              _maximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
              size: 18,
              color: colors.text3,
            ),
            onPressed: () => setState(() => _maximized = !_maximized),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 18, color: colors.text3),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppColors colors) {
    final imgBytes = ImageFollowUpStore.instance
        .sessionImageBytes(widget.sessionKey);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imgBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                imgBytes,
                width: 160,
                height: 160,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            'Continue the conversation',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _useXGrok && ref.watch(settingsProvider).xgrokEnabled
                ? 'Powered by xGrok Vision. Each turn re-attaches the image,\n'
                    'so switching Lite/Deep mid-chat stays accurate.'
                : 'Powered by Gemini Vision. Each turn re-attaches the image,\n'
                    'so switching Lite/Deep mid-chat stays accurate.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              height: 1.5,
              color: colors.text3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChat(AppColors colors) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _buildMessage(colors, _messages[i]),
    );
  }

  Widget _buildLoadingBubble(AppColors colors) {
    // The wait shows the picture the model is actually looking at, behind a
    // liquid progress ring, rather than three dots that could mean anything.
    final imgBytes =
        ImageFollowUpStore.instance.sessionImageBytes(widget.sessionKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiBadge(),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.bg2,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: colors.border2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `_loadingPhase` is still this sheet's own
                  // `_litePhases` / `_deepPhases` / `_extendedPhases` copy on
                  // its own 5-second timer.
                  NexusLoader(
                    variant: NexusLoaderVariant.vision,
                    tone: _useDeepModel
                        ? NexusLoaderTone.deep
                        : NexusLoaderTone.lite,
                    label: _loadingPhase.isEmpty ? null : _loadingPhase,
                    image: imgBytes == null ? null : MemoryImage(imgBytes),
                    size: 96,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildMessage(AppColors colors, _ChatMessage msg) {
    if (msg.isLoading) return _buildLoadingBubble(colors);

    final isUser = msg.role == 'user';
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 40),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.composerGradientEnd.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border.all(
                    color: AppColors.composerGradientEnd.withValues(alpha: 0.2),
                  ),
                ),
                child: ArticleSelectionScope(
                  child: BlockSelectableText(
                  msg.text,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.6,
                    color: colors.text,
                  ),
                ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isError = msg.isError;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiBadge(),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isError
                    ? colors.danger.withValues(alpha: 0.08)
                    : colors.bg2,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(
                  color: isError
                      ? colors.danger.withValues(alpha: 0.2)
                      : colors.border2,
                ),
              ),
              child: isError
                  ? ArticleSelectionScope(
                      child: BlockSelectableText(
                      msg.text,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        height: 1.7,
                        color: colors.danger,
                      ),
                    ),
                    )
                  : BlockSelectableMarkdown(
                      data: msg.text,
                      onTapLink: (_, href, __) async {
                        if (href == null || href.isEmpty) return;
                        final uri = Uri.tryParse(href);
                        if (uri == null) return;
                        try {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        } catch (e) {
                          TLog.w('ImageChat',
                              'Failed to launch URL: $href',
                              error: e);
                        }
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          height: 1.7,
                          color: colors.text,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _aiBadge() => Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.composerGradientEnd, AppColors.composerGradientStart],
          ),
        ),
        child: const Icon(LucideIcons.image, size: 12, color: Colors.white),
      );

  Widget _buildInput(AppColors colors, double bottomPad) {
    final still = reducedMotion(context);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 12, bottomPad + 10),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModelToggle(colors),
              if (ref.watch(settingsProvider).xgrokEnabled) ...[
                const SizedBox(width: 8),
                ProviderPicker(
                  options: const <ProviderOption>[
                    ProviderOption(
                      id: 'gemini',
                      label: 'Gemini',
                      icon: LucideIcons.sparkles,
                      color: AppColors.geminiBlue,
                    ),
                    ProviderOption(
                      id: 'xgrok',
                      label: 'xGrok',
                      icon: LucideIcons.bot,
                      color: AppColors.xgrokRed,
                    ),
                  ],
                  selectedId: _useXGrok ? 'xgrok' : 'gemini',
                  onChanged: _sending
                      ? (_) {}
                      : (id) {
                          HapticFeedback.selectionClick();
                          setState(() => _useXGrok = id == 'xgrok');
                        },
                  colors: colors,
                  heroTag: 'image-followup-provider',
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Blur bounded to the field's own rounded rect instead of the whole
          // row — same glass, one small saveLayer instead of a full-width one
          // on every keystroke frame.
          RepaintBoundary(
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: AppRadii.brSheet,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.bg2,
                          borderRadius: AppRadii.brSheet,
                          border: Border.all(color: colors.border),
                        ),
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focusNode,
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: colors.text,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ask about the image\u2026',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: colors.text4,
                            ),
                            hintMaxLines: 2,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                VoiceInputButton(
                  controller: _ctrl,
                  colors: colors,
                  disabled: _sending,
                  tag: 'ImageVoice',
                  onListeningChanged: (v) {
                    if (mounted) setState(() => _voiceListening = v);
                  },
                ),
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  enabled: !_voiceListening,
                  label: _sending
                      ? 'Stop the answer in progress'
                      : 'Send follow-up question',
                  onTap: _voiceListening ? null : (_sending ? _cancel : _send),
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      onTap: _voiceListening
                          ? null
                          : (_sending ? _cancel : _send),
                      child: AnimatedContainer(
                        duration: still
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        width: AppSpacing.tapTarget,
                        height: AppSpacing.tapTarget,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _voiceListening
                              ? colors.bg3
                              : (_sending
                                  ? colors.danger
                                  : AppColors.composerGradientEnd),
                        ),
                        child: _sending
                            ? Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              )
                            : Icon(
                                LucideIcons.send,
                                size: 18,
                                color: _voiceListening
                                    ? colors.text5
                                    : Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelToggle(AppColors colors) {
    final liteColor = colors.modeLite;
    final deepColor = colors.modeDeep;
    final still = reducedMotion(context);

    return Semantics(
      button: true,
      enabled: !_sending,
      toggled: _useDeepModel,
      label: _useDeepModel
          ? 'Answer depth: Deep (slower, thorough)'
          : 'Answer depth: Lite (faster)',
      child: GestureDetector(
        onTap: _sending
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(() => _useDeepModel = !_useDeepModel);
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.tapTarget),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedContainer(
              duration:
                  still ? Duration.zero : const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              decoration: BoxDecoration(
                color: colors.bg2,
                borderRadius: AppRadii.brLg,
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toggleChip(
                    label: 'Lite',
                    icon: LucideIcons.zap,
                    active: !_useDeepModel,
                    color: liteColor,
                    colors: colors,
                    still: still,
                  ),
                  const SizedBox(width: 2),
                  _toggleChip(
                    label: 'Deep',
                    icon: LucideIcons.brain,
                    active: _useDeepModel,
                    color: deepColor,
                    colors: colors,
                    still: still,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color color,
    required AppColors colors,
    required bool still,
  }) {
    return AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: AppRadii.brCard,
        border: Border.all(
          color: active ? color.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: active ? color : colors.text5),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? color : colors.text4,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════════
//  Public helper: decode a "data:image/jpeg;base64,..." URL to raw bytes.
//  Used by saved_search_detail_sheet.dart when rendering the thumbnail
//  for image-grounded entries fetched from another device.
// ═══════════════════════════════════════════════════════════════════════════════

Uint8List? tryDecodeImageDataUrl(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) return null;
  final commaIdx = dataUrl.indexOf(',');
  if (commaIdx <= 0) return null;
  try {
    final b64 = dataUrl.substring(commaIdx + 1);
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}
