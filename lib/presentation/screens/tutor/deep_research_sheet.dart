import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/tutor_ai_service.dart';
import '../../../domain/entities/tutor_entities.dart';
import '../../widgets/voice_input_button.dart';
import '../settings/settings_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CHAT MESSAGE
// ═══════════════════════════════════════════════════════════════════════════════

class _ChatMessage {
  _ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.sources = const [],
    this.model = '',
    this.isLoading = false,
    this.isError = false,
  });

  final String id;
  final String role;
  String text;
  List<GroundedSource> sources;
  String model;
  bool isLoading;
  bool isError;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DEEP RESEARCH STORE — in-memory cache, clears when URL changes
// ═══════════════════════════════════════════════════════════════════════════════

class DeepResearchStore with WidgetsBindingObserver {
  DeepResearchStore._();
  static final instance = DeepResearchStore._();

  String _currentUrl = '';
  final _messages = <_ChatMessage>[];
  final _listeners = <VoidCallback>{};
  _ChatMessage? _pendingAiMsg;
  CancelToken? _cancelToken;
  int _idSeq = 0;
  bool _observerBound = false;

  String? _retryUrl;
  String? _retryQuestion;
  String? _retryDeepModel;
  String? _retryProvider;
  String? _retryXGrokDeepModel;
  String? _retryXGrokThinkingModel;
  _ChatMessage? _retryAiMsg;
  TutorAiService? _retryService;

  String get currentUrl => _currentUrl;
  List<_ChatMessage> get messages => _messages;
  bool get hasPending => _pendingAiMsg != null;

  String _nextId() => 'dr-${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);
  void _notify() {
    for (final cb in List.of(_listeners)) {
      cb();
    }
  }

  void _ensureObserver() {
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final aiMsg = _retryAiMsg;
    final url = _retryUrl;
    final svc = _retryService;
    if (aiMsg == null || url == null || svc == null) return;
    final question = _retryQuestion ?? '';
    final dm = _retryDeepModel;
    final prov = _retryProvider;
    final xgrokDm = _retryXGrokDeepModel;
    final xgrokTm = _retryXGrokThinkingModel;
    _clearRetry();

    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      TLog.d('DeepResearch', 'App resumed — auto-retrying request');
      aiMsg
        ..text = ''
        ..isLoading = true
        ..isError = false;
      _pendingAiMsg = aiMsg;
      _notify();

      unawaited(_executeRequest(
        url: url,
        question: question,
        aiMsg: aiMsg,
        aiService: svc,
        deepModel: dm,
        provider: prov,
        xgrokDeepModel: xgrokDm,
        xgrokThinkingModel: xgrokTm,
      ));
    });
  }

  void _clearRetry() {
    _retryUrl = null;
    _retryQuestion = null;
    _retryDeepModel = null;
    _retryProvider = null;
    _retryXGrokDeepModel = null;
    _retryXGrokThinkingModel = null;
    _retryAiMsg = null;
    _retryService = null;
  }

  /// Returns true for ANY Dio transport-level error (timeout, socket kill,
  /// connection reset, etc.) — all of which are retryable after resume.
  /// Only HTTP response errors (4xx/5xx) are considered non-retryable.
  static bool _isRetryableNetworkError(Object? e) {
    if (e == null) return false;
    if (e is DioException) {
      if (e.type == DioExceptionType.cancel) return false;
      if (e.type != DioExceptionType.badResponse) return true;
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

  /// Prepare store for a URL. If the URL changes, all history is cleared.
  void prepareForUrl(String url) {
    if (url == _currentUrl && _messages.isNotEmpty) return;
    _currentUrl = url;
    _messages.clear();
    _pendingAiMsg = null;
    _clearRetry();
  }

  void sendQuestion({
    required String url,
    required String question,
    required TutorAiService aiService,
    String? deepModel,
    String? provider,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
  }) {
    _ensureObserver();
    prepareForUrl(url);

    final userMsg = _ChatMessage(
      id: _nextId(),
      role: 'user',
      text: question.isEmpty ? 'Deep research: $url' : question,
    );
    final aiMsg = _ChatMessage(
      id: _nextId(),
      role: 'assistant',
      text: '',
      isLoading: true,
    );

    _messages.add(userMsg);
    _messages.add(aiMsg);
    _pendingAiMsg = aiMsg;
    final token = CancelToken();
    _cancelToken = token;
    _notify();

    unawaited(_executeRequest(
      url: url,
      question: question,
      aiMsg: aiMsg,
      aiService: aiService,
      deepModel: deepModel,
      provider: provider,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
      cancelToken: token,
    ));
  }

  void startResearch({
    required String url,
    required TutorAiService aiService,
    String? deepModel,
    String? provider,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
  }) {
    _ensureObserver();
    prepareForUrl(url);

    final systemMsg = _ChatMessage(
      id: _nextId(),
      role: 'user',
      text: 'Perform a deep research analysis of this URL.',
    );
    final aiMsg = _ChatMessage(
      id: _nextId(),
      role: 'assistant',
      text: '',
      isLoading: true,
    );

    _messages.add(systemMsg);
    _messages.add(aiMsg);
    _pendingAiMsg = aiMsg;
    final token = CancelToken();
    _cancelToken = token;
    _notify();

    unawaited(_executeRequest(
      url: url,
      question: '',
      aiMsg: aiMsg,
      aiService: aiService,
      deepModel: deepModel,
      provider: provider,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
      cancelToken: token,
    ));
  }

  /// Cancel in-flight request. Returns the user's question text so the UI
  /// can restore it to the input field.
  String? cancelPending() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
    _clearRetry();

    String? userText;
    if (_pendingAiMsg != null) {
      final aiIdx = _messages.indexOf(_pendingAiMsg!);
      if (aiIdx >= 0) {
        _messages.removeAt(aiIdx);
        if (aiIdx > 0 && _messages[aiIdx - 1].role == 'user') {
          userText = _messages[aiIdx - 1].text;
          _messages.removeAt(aiIdx - 1);
        }
      }
      _pendingAiMsg = null;
    }
    _notify();
    return userText;
  }

  Future<void> _executeRequest({
    required String url,
    required String question,
    required _ChatMessage aiMsg,
    required TutorAiService aiService,
    String? deepModel,
    String? provider,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
    CancelToken? cancelToken,
  }) async {
    bool keepPending = false;

    try {
      final history = <Map<String, String>>[];
      final settled = _messages.where((m) => !m.isLoading).toList();
      for (var i = 0; i < settled.length - 1; i++) {
        final m = settled[i];
        if (m.isError) continue;
        if (m.role == 'user' && i + 1 < settled.length) {
          final next = settled[i + 1];
          if (next.role == 'assistant' && !next.isError) {
            history.add({'role': 'user', 'text': m.text});
            history.add({'role': 'assistant', 'text': next.text});
            i++;
          }
        }
      }

      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (cancelToken?.isCancelled ?? false) return;
        try {
          final result = await aiService.deepResearch(
            url: url,
            question: question,
            history: history,
            deepModel: deepModel,
            provider: provider,
            xgrokDeepModel: xgrokDeepModel,
            xgrokThinkingModel: xgrokThinkingModel,
            cancelToken: cancelToken,
          );
          if (_pendingAiMsg != aiMsg) return;
          aiMsg
            ..text = result.answer
            ..sources = result.sources
            ..model = result.model
            ..isLoading = false;
          return;
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) return;
          lastError = e;
          if (!_isRetryableNetworkError(e) || _pendingAiMsg != aiMsg) break;
          if (attempt < 2) {
            TLog.w('DeepResearch',
                'Network error — retry ${attempt + 1}/2 (${e.runtimeType})');
            await Future.delayed(Duration(seconds: (attempt + 1) * 5));
            if (cancelToken?.isCancelled ?? false) return;
            if (_pendingAiMsg != aiMsg) return;
          }
        }
      }

      // All inline retries exhausted
      if (lastError != null &&
          _isRetryableNetworkError(lastError) &&
          _pendingAiMsg == aiMsg) {
        // Schedule auto-retry when the app resumes from background
        _retryUrl = url;
        _retryQuestion = question;
        _retryDeepModel = deepModel;
        _retryProvider = provider;
        _retryXGrokDeepModel = xgrokDeepModel;
        _retryXGrokThinkingModel = xgrokThinkingModel;
        _retryAiMsg = aiMsg;
        _retryService = aiService;
        keepPending = true;
        TLog.w('DeepResearch', 'Scheduled auto-retry on app resume');
      } else if (_pendingAiMsg == aiMsg) {
        TLog.e('DeepResearch', 'Request failed', error: lastError);
        aiMsg
          ..text =
              'Deep research failed. Please check your connection and try again.'
          ..isLoading = false
          ..isError = true;
      }
    } finally {
      if (!keepPending && _pendingAiMsg == aiMsg) _pendingAiMsg = null;
      _notify();
    }
  }

  void clear() {
    _cancelToken?.cancel('Cleared');
    _cancelToken = null;
    _messages.clear();
    _pendingAiMsg = null;
    _currentUrl = '';
    _clearRetry();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DEEP RESEARCH BUTTON — gradient pill button for the summarizer tab
// ═══════════════════════════════════════════════════════════════════════════════

class DeepResearchButton extends ConsumerWidget {
  const DeepResearchButton({
    super.key,
    required this.url,
    required this.enabled,
  });

  final String url;
  final bool enabled;

  static const _gradientStart = Color(0xFF0EA5E9);
  static const _gradientEnd = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: enabled
          ? () => _openDeepResearch(context, ref)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: [_gradientStart, _gradientEnd])
              : null,
          color: enabled ? null : _gradientStart.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? _gradientStart.withValues(alpha: 0.4)
                : _gradientStart.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.microscope,
              size: 17,
              color: enabled ? Colors.white : _gradientStart.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Text(
              'Deep Research',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: enabled ? Colors.white : _gradientStart.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDeepResearch(BuildContext context, WidgetRef ref) {
    final store = DeepResearchStore.instance;
    final aiService = ref.read(tutorAiServiceProvider);
    final settings = ref.read(settingsProvider);
    final xgrokOn = settings.xgrokEnabled;
    final modelName = xgrokOn ? settings.xgrokDeepModel : settings.deepModel;
    TLog.i('DeepResearch', 'Opening [${xgrokOn ? "xGrok" : "Gemini"}/$modelName] url=${url.length > 60 ? '${url.substring(0, 60)}…' : url}');

    if (store.currentUrl != url || store.messages.isEmpty) {
      store.startResearch(
        url: url,
        aiService: aiService,
        deepModel: xgrokOn ? null : settings.deepModel,
        provider: xgrokOn ? 'xgrok' : null,
        xgrokDeepModel: xgrokOn ? settings.xgrokDeepModel : null,
        xgrokThinkingModel: xgrokOn ? settings.xgrokThinkingModel : null,
      );
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeepResearchChat(url: url),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DEEP RESEARCH CHAT SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _DeepResearchChat extends ConsumerStatefulWidget {
  const _DeepResearchChat({required this.url});
  final String url;

  @override
  ConsumerState<_DeepResearchChat> createState() => _DeepResearchChatState();
}

class _DeepResearchChatState extends ConsumerState<_DeepResearchChat>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  bool _voiceListening = false;
  bool _maximized = false;
  String _loadingPhase = '';
  Timer? _phaseTimer;

  late final AnimationController _entryAnim;

  DeepResearchStore get _store => DeepResearchStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreUpdate);
    WidgetsBinding.instance.addObserver(this);
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    if (_store.hasPending) _startLoadingPhases();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreUpdate);
    WidgetsBinding.instance.removeObserver(this);
    _phaseTimer?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _entryAnim.dispose();
    super.dispose();
  }

  void _onStoreUpdate() {
    if (!mounted) return;
    if (!_store.hasPending) _stopLoadingPhases();
    setState(() {});
    _scrollToBottom();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      if (!_store.hasPending) _stopLoadingPhases();
      _scrollToBottom();
    }
  }

  static const _phases = [
    'Searching the web…',
    'Reading the source page…',
    'Analyzing related sources…',
    'Cross-referencing data…',
    'Building deep analysis…',
    'Compiling research report…',
  ];

  void _startLoadingPhases() {
    if (_phaseTimer != null) return;
    int idx = 0;
    setState(() => _loadingPhase = _phases[0]);
    _phaseTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      idx++;
      if (idx < _phases.length && mounted) {
        setState(() => _loadingPhase = _phases[idx]);
      }
    });
  }

  void _stopLoadingPhases() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
  }

  void _cancel() {
    final restoredText = _store.cancelPending();
    _stopLoadingPhases();
    if (restoredText != null && restoredText.isNotEmpty) {
      _ctrl.text = restoredText;
      _ctrl.selection =
          TextSelection.collapsed(offset: restoredText.length);
    }
    _focusNode.requestFocus();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _store.hasPending) return;
    _ctrl.clear();
    _focusNode.requestFocus();

    final settings = ref.read(settingsProvider);
    final xgrokOn = settings.xgrokEnabled;
    final providerTag = xgrokOn ? 'xGrok' : 'Gemini';
    final modelName = xgrokOn ? settings.xgrokDeepModel : settings.deepModel;
    TLog.i('DeepResearch', 'Follow-up [$providerTag/$modelName]: "${text.length > 60 ? '${text.substring(0, 60)}…' : text}"');

    _store.sendQuestion(
      url: widget.url,
      question: text,
      aiService: ref.read(tutorAiServiceProvider),
      deepModel: xgrokOn ? null : settings.deepModel,
      provider: xgrokOn ? 'xgrok' : null,
      xgrokDeepModel: xgrokOn ? settings.xgrokDeepModel : null,
      xgrokThinkingModel: xgrokOn ? settings.xgrokThinkingModel : null,
    );
    _startLoadingPhases();
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;
    final safePad = MediaQuery.paddingOf(context).bottom;

    return AnimatedBuilder(
      animation: _entryAnim,
      builder: (context, child) {
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
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        height: _maximized
            ? MediaQuery.sizeOf(context).height
            : MediaQuery.sizeOf(context).height * 0.85,
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_maximized ? 0 : 24),
          ),
          border: _maximized
              ? null
              : Border(top: BorderSide(color: colors.border)),
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              height: _maximized
                  ? MediaQuery.paddingOf(context).top
                  : 0,
            ),
            _buildHeader(colors),
            Expanded(
              child: _store.messages.isEmpty
                  ? _buildEmpty(colors)
                  : _buildChat(colors),
            ),
            _buildInput(colors, bottomPad > 0 ? bottomPad : safePad),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors) {
    final urlDisplay = widget.url.length > 45
        ? '${widget.url.substring(0, 45)}…'
        : widget.url;

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
                colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
              ),
            ),
            child: const Icon(LucideIcons.microscope, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deep Research',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
                Text(
                  urlDisplay,
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
          if (_store.hasPending)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: const Color(0xFF0EA5E9),
                ),
              ),
            ),
          _MaximizeButton(
            maximized: _maximized,
            accentColor: const Color(0xFF0EA5E9),
            colors: colors,
            onTap: () => setState(() => _maximized = !_maximized),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0EA5E9).withValues(alpha: 0.08),
              border: Border.all(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
              ),
            ),
            child: const Icon(LucideIcons.microscope,
                size: 20, color: Color(0xFF0EA5E9)),
          ),
          const SizedBox(height: 12),
          Text(
            'Deep research starting…',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.text,
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
      itemCount: _store.messages.length,
      itemBuilder: (_, i) => _buildMessage(colors, _store.messages[i]),
    );
  }

  // ── Message rendering ─────────────────────────────────────────────────────

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
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border.all(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                  ),
                ),
                child: SelectableText(
                  msg.text,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    height: 1.6,
                    color: colors.text,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isError
                        ? const Color(0xFFFF6B6B).withValues(alpha: 0.08)
                        : colors.bg2,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: isError
                          ? const Color(0xFFFF6B6B).withValues(alpha: 0.2)
                          : colors.border2,
                    ),
                  ),
                  child: isError
                      ? SelectableText(
                          msg.text,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            height: 1.7,
                            color: const Color(0xFFFF6B6B),
                          ),
                        )
                      : SelectionArea(
                          child: MarkdownBody(
                            data: msg.text,
                            selectable: false,
                            onTapLink: (_, href, __) async {
                              if (href == null || href.isEmpty) return;
                              final uri = Uri.tryParse(href);
                              if (uri == null) return;
                              try {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              } catch (e) {
                                TLog.w('DeepResearch', 'Failed to launch URL: $href', error: e);
                              }
                            },
                            styleSheet: _markdownStyle(colors),
                          ),
                        ),
                ),
                if (msg.model.isNotEmpty || msg.sources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (msg.model.isNotEmpty)
                          _metaChip(colors, msg.model, LucideIcons.brain,
                              const Color(0xFFC084FC)),
                        if (msg.sources.isNotEmpty)
                          _metaChip(
                              colors,
                              '${msg.sources.length} sources',
                              LucideIcons.link,
                              const Color(0xFF34D399)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble(AppColors colors) {
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _TypingDots(),
                      const SizedBox(width: 10),
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _loadingPhase,
                            key: ValueKey(_loadingPhase),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0EA5E9),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor:
                          const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF0EA5E9)),
                    ),
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _aiBadge() {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
        ),
      ),
      child: const Icon(LucideIcons.microscope, size: 12, color: Colors.white),
    );
  }

  Widget _metaChip(AppColors colors, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(AppColors colors) {
    const accent = Color(0xFF0EA5E9);
    return MarkdownStyleSheet(
      p: GoogleFonts.plusJakartaSans(
          fontSize: 14, height: 1.7, color: colors.text),
      pPadding: const EdgeInsets.only(bottom: 6),
      h1: GoogleFonts.plusJakartaSans(
          fontSize: 18, fontWeight: FontWeight.w800, height: 1.3, color: colors.text),
      h1Padding: const EdgeInsets.only(top: 6, bottom: 4),
      h2: GoogleFonts.plusJakartaSans(
          fontSize: 16, fontWeight: FontWeight.w800, height: 1.35, color: colors.text),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h3: GoogleFonts.plusJakartaSans(
          fontSize: 15, fontWeight: FontWeight.w700, height: 1.4, color: colors.text),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 2),
      strong: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: colors.text),
      em: GoogleFonts.plusJakartaSans(fontStyle: FontStyle.italic, color: colors.text3),
      blockquote: GoogleFonts.plusJakartaSans(
          fontSize: 13, fontStyle: FontStyle.italic, height: 1.6, color: colors.text2),
      blockquoteDecoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: accent, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      listBullet: GoogleFonts.plusJakartaSans(
          fontSize: 13, fontWeight: FontWeight.w700, color: accent),
      listBulletPadding: const EdgeInsets.only(right: 6),
      listIndent: 18,
      tableHead: GoogleFonts.plusJakartaSans(
          fontSize: 11, fontWeight: FontWeight.w700, color: colors.text),
      tableBody: GoogleFonts.plusJakartaSans(
          fontSize: 11, height: 1.5, color: colors.text2),
      tableBorder: TableBorder.all(
          color: colors.border, borderRadius: BorderRadius.circular(8)),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tableColumnWidth: const FlexColumnWidth(),
      code: GoogleFonts.jetBrainsMono(
          fontSize: 12, color: accent, backgroundColor: colors.bg3),
      codeblockDecoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      a: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: accent,
        decoration: TextDecoration.underline,
        decorationColor: accent.withValues(alpha: 0.4),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border, width: 0.5)),
      ),
    );
  }

  Widget _buildInput(AppColors colors, double bottomPad) {
    final sending = _store.hasPending;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 12, bottomPad + 12),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.bg2,
                    borderRadius: BorderRadius.circular(24),
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
                        fontSize: 14, color: colors.text),
                    decoration: InputDecoration(
                      hintText: 'Ask a follow-up question…',
                      hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 14, color: colors.text4),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              VoiceInputButton(
                controller: _ctrl,
                colors: colors,
                disabled: sending,
                tag: 'DeepVoice',
                onListeningChanged: (v) {
                  if (mounted) setState(() => _voiceListening = v);
                },
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _voiceListening
                    ? null
                    : (sending ? _cancel : _send),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _voiceListening
                        ? colors.bg3
                        : (sending
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF0EA5E9)),
                  ),
                  child: sending
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
                          size: 16,
                          color: _voiceListening
                              ? colors.text5
                              : Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TYPING DOTS ANIMATION
// ═══════════════════════════════════════════════════════════════════════════════

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
            final y = -3.0 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Transform.translate(
              offset: Offset(0, y),
              child: Container(
                width: 6,
                height: 6,
                margin: EdgeInsets.only(right: i < 2 ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0EA5E9)
                      .withValues(alpha: 0.4 + 0.6 * (1 - (y.abs() / 3))),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  const _MaximizeButton({
    required this.maximized,
    required this.colors,
    required this.onTap,
    this.accentColor = const Color(0xFF4285F4),
  });

  final bool maximized;
  final AppColors colors;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.85,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    return GestureDetector(
      onTapDown: (_) => _press.reverse(),
      onTapUp: (_) {
        _press.forward();
        widget.onTap();
      },
      onTapCancel: () => _press.forward(),
      child: ScaleTransition(
        scale: _press,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: widget.maximized
                ? accent.withValues(alpha: 0.14)
                : widget.colors.bg3,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.maximized
                  ? accent.withValues(alpha: 0.3)
                  : widget.colors.border,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            child: Icon(
              widget.maximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
              key: ValueKey(widget.maximized),
              size: 14,
              color: widget.maximized ? accent : widget.colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}
