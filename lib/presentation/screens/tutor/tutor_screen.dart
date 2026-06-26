import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/llm/model_name_format.dart';
import '../../../core/network/ai_error.dart';
import '../../../core/services/hold_to_speak_service.dart';
import '../../../core/services/image_pipeline.dart';
import '../../../core/services/image_search_store.dart';
import '../../../core/services/nuke_report.dart';
import '../../../core/services/online_search_store.dart';
import '../../../core/services/process_text_service.dart';
import '../../../core/services/summarize_store.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/saved_search.dart';
import '../../../domain/entities/tutor_entities.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/compact_header.dart';
import '../../widgets/provider_picker.dart';
import '../../widgets/sources_disclosure.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_modal.dart';
import '../expense/widgets/nuke_easter_egg.dart';
import 'coach_diff.dart';
import 'deep_research_sheet.dart';
import 'image_followup_sheet.dart';
import 'saved_search_detail_sheet.dart';
import 'saved_searches_sheet.dart';
import 'search_followup_sheet.dart';

const int _kMaxRephrase = 5000;
const int _kMaxCoach = 5000;

// ── Rephrase platform config ─────────────────────────────────────────────────

class _RephrasePlatform {
  const _RephrasePlatform({
    required this.id,
    required this.label,
    required this.emoji,
    required this.color,
    required this.icon,
  });

  final String id;
  final String label;
  final String emoji;
  final Color color;
  final IconData icon;
}

const List<_RephrasePlatform> _rephrasePlatforms = [
  _RephrasePlatform(
    id: 'own',
    label: 'Own',
    emoji: '✨',
    color: Color(0xFF0D59F2),
    icon: LucideIcons.wand2,
  ),
  _RephrasePlatform(
    id: 'casual',
    label: 'Casual',
    emoji: '😊',
    color: Color(0xFF60A5FA),
    icon: LucideIcons.smile,
  ),
  _RephrasePlatform(
    id: 'sarcastic',
    label: 'Sarcastic',
    emoji: '😏',
    color: Color(0xFFF87171),
    icon: LucideIcons.flame,
  ),
  _RephrasePlatform(
    id: 'slack',
    label: 'Slack',
    emoji: '💬',
    color: Color(0xFFC084FC),
    icon: LucideIcons.messageSquare,
  ),
  _RephrasePlatform(
    id: 'email-short',
    label: 'Email Short',
    emoji: '✉️',
    color: Color(0xFFFCD34D),
    icon: LucideIcons.inbox,
  ),
  _RephrasePlatform(
    id: 'email-long',
    label: 'Email Long',
    emoji: '📧',
    color: Color(0xFFF59E0B),
    icon: LucideIcons.mail,
  ),
  _RephrasePlatform(
    id: 'whatsapp',
    label: 'WhatsApp',
    emoji: '📱',
    color: Color(0xFF4ADE80),
    icon: LucideIcons.smartphone,
  ),
  _RephrasePlatform(
    id: 'zoom',
    label: 'Zoom',
    emoji: '🎥',
    color: Color(0xFF60A5FA),
    icon: LucideIcons.video,
  ),
  _RephrasePlatform(
    id: 'twitter',
    label: 'Twitter / X',
    emoji: '𝕏',
    color: Color(0xFFE7E9EA),
    icon: LucideIcons.hash,
  ),
  _RephrasePlatform(
    id: 'linkedin',
    label: 'LinkedIn',
    emoji: '💼',
    color: Color(0xFF60A5FA),
    icon: LucideIcons.briefcase,
  ),
  _RephrasePlatform(
    id: 'forum',
    label: 'Forum',
    emoji: '🌐',
    color: Color(0xFF818CF8),
    icon: LucideIcons.globe,
  ),
];

// ── Own-mode intent parser ──────────────────────────────────────────────────

final _ownDoubleQuote = RegExp(r'"([^"]+)"');
final _ownSingleQuote = RegExp(r"(?<![a-zA-Z])'([^']+)'");
final _ownSmartQuote = RegExp(r'\u201c([^\u201d]+)\u201d');
final _ownPrefixStrip =
    RegExp(r'^rephrase\b\s*(this\s+)?(it\s+)?(to\s+|as\s+)?', caseSensitive: false);

({String intent, String text}) parseOwnRephraseInput(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return (intent: '', text: '');

  for (final pattern in [_ownDoubleQuote, _ownSingleQuote, _ownSmartQuote]) {
    final match = pattern.firstMatch(input);
    if (match != null) {
      final quoted = match.group(1)!.trim();
      if (quoted.isEmpty) continue;

      final before = input.substring(0, match.start).trim();
      final intent = before.replaceFirst(_ownPrefixStrip, '').trim();
      return (intent: intent, text: quoted);
    }
  }

  // No quotes found — treat as plain text with no explicit intent
  final stripped = input.replaceFirst(_ownPrefixStrip, '').trim();
  if (stripped.length < input.length) {
    return (intent: '', text: stripped);
  }
  return (intent: '', text: input);
}

// ── Coach variation tone colours ─────────────────────────────────────────────

Color _coachLabelColor(String label) {
  switch (label.toLowerCase()) {
    case 'casual':
      return const Color(0xFF60A5FA);
    case 'professional':
      return const Color(0xFFA78BFA);
    case 'formal email':
      return const Color(0xFFF59E0B);
    case 'friendly':
      return const Color(0xFF4ADE80);
    case 'direct':
      return const Color(0xFFFBBF24);
    case 'diplomatic':
      return const Color(0xFF818CF8);
    default:
      return const Color(0xFF94A3B8);
  }
}

String _coachLabelEmoji(String label) {
  switch (label.toLowerCase()) {
    case 'casual':
      return '😊';
    case 'professional':
      return '💼';
    case 'formal email':
      return '✉️';
    case 'friendly':
      return '🤝';
    case 'direct':
      return '⚡';
    case 'diplomatic':
      return '🕊️';
    default:
      return '💬';
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

/// Callback to switch the Tutor tab controller from outside.
typedef TutorSubtabSwitcher = void Function(int index);

/// Registered by _TutorScreenState so AppShell can drive subtab switches.
TutorSubtabSwitcher? activeTutorSubtabSwitcher;

class TutorScreen extends ConsumerStatefulWidget {
  const TutorScreen({super.key});

  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;

  final TextEditingController _rephraseCtrl = TextEditingController();
  final TextEditingController _coachCtrl = TextEditingController();
  final TextEditingController _dictCtrl = TextEditingController();

  String? _onlineSearchKey;
  String? _summarizeKey;

  // Rephrase
  _RephrasePlatform _selectedPlatform = _rephrasePlatforms[0];
  bool _rephraseLoading = false;
  RephraseResult? _rephraseResult;

  // Coach
  bool _coachLoading = false;
  CoachResult? _coachResult;

  /// Corrected-view mode. `false` (default) shows the clean, ready-to-use
  /// corrected sentence with only the improvements highlighted; `true` reveals
  /// the full word-level diff (struck-out removals) for users who want to see
  /// exactly what changed.
  bool _coachShowDiff = false;

  // ── Voice (hold-to-speak) ───────────────────────────────────────────────
  // All robustness (auto-restart on Android silence-timeout, final-result
  // tracking, error backoff, single-engine coordination, sound-level
  // monitoring) lives in [HoldToSpeakController]. We just bind it to the
  // currently selected target controller (Coach / Search / etc.).
  late final HoldToSpeakController _voice;
  TextEditingController? _voiceTarget;
  String _voiceLastShown = '';
  bool _isListening = false;

  // Summarizer & Search
  final TextEditingController _summaryUrlCtrl = TextEditingController();
  final FocusNode _summaryFocusNode = FocusNode();
  bool _summaryLoading = false;
  SummarizerResult? _summaryResult;
  String _summaryStage = '';
  TavilySearchResponse? _tavilyResult;
  GroundedSearchResponse? _groundedResult;

  /// Search depth toggle for the InsightAI tab. Defaults to Lite (fast). Mirrors
  /// the Lite/Deep toggle in the search follow-up sheet so users get a
  /// consistent experience across the search → follow-up flow.
  bool _searchUseDeepModel = false;

  /// Stable session id for the currently displayed result. Set the moment
  /// a result lands (as a hidden DRAFT in [SavedSearchStore]) and reused
  /// for the lifetime of the result so every follow-up chat turn is keyed
  /// to the same id from message #1.
  ///
  /// State machine:
  ///   • null                    → no result on screen
  ///   • non-null, !isSaved      → draft (bookmark outline; row hidden
  ///                                from History sheet)
  ///   • non-null, isSaved=true  → user-saved (bookmark filled; row
  ///                                visible in History sheet)
  ///
  /// Reset to null by [_resetSearchSession] (Clear / Search Again) or by
  /// [_runTavilySearch] / [_runSummarize] when the user kicks off a new
  /// search without first clearing.
  String? _activeSearchId;

  /// Mirror of `store.isSaved(_activeSearchId)`, refreshed whenever the
  /// active id changes or the user toggles the bookmark. Drives the
  /// outlined-vs-filled icon state — relying on `_activeSearchId != null`
  /// alone would render every draft as "already saved", which is exactly
  /// the bug we're fixing.
  bool _activeSearchIsSaved = false;

  /// Re-entrancy guard for the bookmark toggle. Prevents a rapid double-tap
  /// from creating two saved-search rows (the first save would still be
  /// in-flight when the second tap fires, so `_activeSearchId` is still
  /// null and the second tap reads the stale state). Stays `true` for the
  /// duration of the snackbar to also serialise the optional Undo path.
  bool _saveToggleInFlight = false;

  // ── InsightAI Image (vision) state ───────────────────────────────────
  //
  // Holds the user's pending image attachment (after pick + compress)
  // plus the active vision-search session. The session key is the
  // `_activeSearchId` once a draft is started, otherwise a transient
  // uuid generated when the search kicks off. The image bytes live
  // ONLY in memory + in the ImageSearchStore — no thumbnail is shown
  // on this device until the result lands.
  PickedImage? _pendingImage;

  /// Loading flag for the image attach-flow (picker open + compress).
  /// Independent of [_summaryLoading] because the image picker can
  /// take a few seconds on first invocation (permission dialog +
  /// gallery thumbnail page) and we don't want to lock the rest of
  /// the InsightAI input box during that window.
  bool _pickingImage = false;

  /// Session key for the active image search. Matches
  /// [_activeSearchId] once the result-driven draft is started so a
  /// follow-up chat can find the right ImageFollowUpStore entry.
  String? _imageSearchKey;

  /// Latest image-grounded result on screen. Mirrors [_groundedResult]
  /// for the text path; rendered by [_imageResultWidget].
  ImageGroundedResult? _imageResult;

  /// Show an in-flight error banner. Set when the store reports a
  /// permanent failure and reset when the user starts a new search
  /// or clears the result.
  bool _imageErrorShown = false;

  // Dictionary
  bool _dictLoading = false;
  DictionaryResult? _dictResult;
  bool _dictShowAllExamples = false;
  bool _dictJustSaved = false;
  List<SavedWord> _savedWords = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    activeTutorSubtabSwitcher = _switchToSubtab;
    _loadSavedWords();
    _voice = HoldToSpeakController(tag: 'Tutor');
    _voice.addListener(_onVoiceUpdate);
    HoldToSpeakController.warmUp();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingSubtab();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      if (_onlineSearchKey != null) _syncSearchFromStore();
      if (_summarizeKey != null) _syncSummarizeFromStore();
      if (_imageSearchKey != null) _syncImageSearchFromStore();
    }
  }

  void _onSearchStoreUpdate() {
    if (!mounted) return;
    _syncSearchFromStore();
  }

  void _onSummarizeStoreUpdate() {
    if (!mounted) return;
    _syncSummarizeFromStore();
  }

  bool _summarizeErrorShown = false;

  void _syncSummarizeFromStore() {
    final job = SummarizeStore.instance.getJob(_summarizeKey ?? '');
    if (job == null) return;
    setState(() {
      _summaryLoading = job.loading;
      _summaryStage = job.stage;
      _summaryResult = job.result;
      if (job.error != null && !job.loading) {
        _summaryStage = '';
      }
    });
    if (job.error != null && !job.loading && !_summarizeErrorShown) {
      _summarizeErrorShown = true;
      _showMessage(job.error!);
    }
    // First non-null result for the current job lands → start a draft so
    // every follow-up turn gets a stable parent id from message #1. Guard
    // on `_activeSearchId == null` to make this fire exactly once per run.
    if (job.result != null && _activeSearchId == null && !_draftStartInFlight) {
      _ensureActiveDraft(result: job.result!);
    }
  }

  bool _searchErrorShown = false;

  void _syncSearchFromStore() {
    final job = OnlineSearchStore.instance.getJob(_onlineSearchKey ?? '');
    if (job == null) return;
    setState(() {
      _summaryLoading = job.loading;
      _summaryStage = job.stage;
      _groundedResult = job.groundedResult;
      _tavilyResult = job.tavilyResult;
      if (job.error != null && !job.loading) {
        _summaryStage = '';
      }
    });
    if (job.error != null && !job.loading && !_searchErrorShown) {
      _searchErrorShown = true;
      _showMessage(job.error!);
    }
    // Either result shape (grounded or tavily) signals "search complete";
    // both go through the same draft path. See [_syncSummarizeFromStore]
    // for the rationale on starting a draft pre-bookmark.
    final landed = job.groundedResult ?? job.tavilyResult;
    if (landed != null && _activeSearchId == null && !_draftStartInFlight) {
      _ensureActiveDraft(result: landed);
    }
  }

  /// Re-entrancy guard for [_ensureActiveDraft]. The Drift insert is
  /// async; without this guard a rapid second sync tick (e.g. result
  /// + sources arriving in two listener invocations) could fire two
  /// inserts and leak an orphan draft row.
  bool _draftStartInFlight = false;

  /// Persists the freshly-landed result as a DRAFT in [SavedSearchStore]
  /// and stashes the returned id in [_activeSearchId]. From this point on
  /// the bookmark icon shows the (unsaved) outline, and the follow-up FAB
  /// receives the id so every chat turn is mirrored under it. Idempotent
  /// per result-land — a no-op if a draft already exists or insert fails.
  /// Single source of truth for the "Clear" / "Search Again" button. Wipes
  /// the active search session top-to-bottom so the screen reliably ends
  /// up in a clean state. Idempotent and safe to call multiple times.
  ///
  /// Without this helper the bug we saw before was: the visible result
  /// state was reset, but [SummarizeStore] / [OnlineSearchStore] still
  /// held the completed job AND `_summarizeKey` / `_onlineSearchKey` still
  /// pointed at it, so the next [didChangeAppLifecycleState] re-synced
  /// the stale result back into the screen on app resume.
  ///
  /// Order of operations matters:
  ///   1. Detach listeners FIRST so the in-flight remove() doesn't
  ///      trigger a final-state callback that would re-set _summaryResult.
  ///   2. Remove() the underlying job so its in-memory cache is gone — no
  ///      future sync from the store can repopulate the screen.
  ///   3. Hard-delete the draft Drift row (and its chat messages) so the
  ///      DB matches the user's mental model: "I cleared, nothing here".
  ///   4. Reset all the screen state in a single setState batch.
  void _resetSearchSession() {
    if (_summarizeKey != null) {
      SummarizeStore.instance
          .removeListener(_summarizeKey!, _onSummarizeStoreUpdate);
      SummarizeStore.instance.cancel(_summarizeKey!);
      SummarizeStore.instance.remove(_summarizeKey!);
    }
    if (_onlineSearchKey != null) {
      OnlineSearchStore.instance
          .removeListener(_onlineSearchKey!, _onSearchStoreUpdate);
      OnlineSearchStore.instance.cancel(_onlineSearchKey!);
      OnlineSearchStore.instance.remove(_onlineSearchKey!);
    }
    if (_imageSearchKey != null) {
      final prior = _imageSearchKey!;
      ImageSearchStore.instance
          .removeListener(prior, _onImageSearchStoreUpdate);
      ImageSearchStore.instance.cancel(prior);
      ImageSearchStore.instance.remove(prior);
      // Drop any in-memory chat session pinned to this key so we don't
      // leak compressed image bytes when the user resets.
      ImageFollowUpStore.instance.clear(prior);
    }
    final draftId = _activeSearchId;
    if (draftId != null) {
      // discardDraftIfAny() is a no-op if the user already promoted to
      // saved, so this is safe regardless of the bookmark state.
      unawaited(
          ref.read(savedSearchStoreProvider).discardDraftIfAny(draftId));
    }
    setState(() {
      _summaryUrlCtrl.clear();
      _summaryResult = null;
      _tavilyResult = null;
      _groundedResult = null;
      _imageResult = null;
      _pendingImage = null;
      _activeSearchId = null;
      _activeSearchIsSaved = false;
      _summarizeKey = null;
      _onlineSearchKey = null;
      _imageSearchKey = null;
      _summaryLoading = false;
      _summaryStage = '';
      _summarizeErrorShown = false;
      _searchErrorShown = false;
      _imageErrorShown = false;
      _draftStartInFlight = false;
    });
  }

  void _ensureActiveDraft({required Object result}) {
    if (_activeSearchId != null || _draftStartInFlight) return;
    final query = _summaryUrlCtrl.text.trim();
    final isImageResult = result is ImageGroundedResult;
    // Image-grounded entries can legitimately have an empty query (the
    // AI describes the picture without a prompt). For those we
    // synthesize a placeholder query so the History card still has a
    // human-readable label.
    if (query.isEmpty && !isImageResult) return;
    final effectiveQuery = query.isEmpty && isImageResult
        ? 'Image analysis'
        : query;
    _draftStartInFlight = true;
    final settings = ref.read(settingsProvider);
    final isUrl = !isImageResult && _isUrl(query);
    // Provider/mode are best-effort metadata for the History pill; the
    // backend doesn't actually consume these on the saved-search write
    // path so even if we're slightly off (e.g. user toggled mid-flight)
    // the worst case is a stale-looking chip on the History card.
    final provider = isUrl
        ? (settings.summarizeOverride == 'xgrok' ? 'xgrok' : 'gemini')
        : (settings.onlineSearchProvider == 'xgrok' ? 'xgrok' : 'gemini');
    final mode = isUrl
        ? null
        : (_searchUseDeepModel ? 'deep' : 'lite');
    final kind = isImageResult
        ? SavedSearchKind.image
        : (isUrl ? SavedSearchKind.url : SavedSearchKind.query);
    unawaited(() async {
      try {
        final store = ref.read(savedSearchStoreProvider);
        final entry = await store.startDraft(
          kind: kind,
          query: effectiveQuery,
          result: result,
          provider: provider,
          mode: mode,
        );
        if (!mounted) return;
        // Race-safe assignment: only adopt this draft id if no other
        // path (e.g. Path C in [_toggleSaveResult] firing on a rapid
        // tap) has already populated _activeSearchId. If we lost the
        // race, immediately discard the draft so it doesn't pollute
        // History or wait 24 h for GC.
        if (_activeSearchId != null) {
          unawaited(store.discardDraftIfAny(entry.id));
          return;
        }
        setState(() {
          _activeSearchId = entry.id;
          _activeSearchIsSaved = false;
        });
      } catch (e) {
        TLog.e('Tutor', 'startDraft failed', error: e);
      } finally {
        if (mounted) _draftStartInFlight = false;
      }
    }());
  }

  void _consumePendingSubtab() {
    final subtab = ref.read(pendingSubtabProvider);
    if (subtab != null && subtab >= 0 && subtab < 4) {
      _switchToSubtab(subtab);
      ref.read(pendingSubtabProvider.notifier).state = null;
    }
  }

  void _onTabChanged() {
    if (_tabController.index == 3 && !_tabController.indexIsChanging) {
      _loadSavedWords();
    }
  }

  void _switchToSubtab(int index) {
    if (index >= 0 && index < 4 && mounted) {
      _tabController.animateTo(index);
    }
  }

  @override
  void dispose() {
    activeTutorSubtabSwitcher = null;
    _voice.removeListener(_onVoiceUpdate);
    _voice.dispose();
    if (_summarizeKey != null) {
      SummarizeStore.instance
          .removeListener(_summarizeKey!, _onSummarizeStoreUpdate);
    }
    if (_onlineSearchKey != null) {
      OnlineSearchStore.instance
          .removeListener(_onlineSearchKey!, _onSearchStoreUpdate);
    }
    if (_imageSearchKey != null) {
      ImageSearchStore.instance
          .removeListener(_imageSearchKey!, _onImageSearchStoreUpdate);
    }
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _rephraseCtrl.dispose();
    _coachCtrl.dispose();
    _dictCtrl.dispose();
    _summaryUrlCtrl.dispose();
    _summaryFocusNode.dispose();
    super.dispose();
  }

  void _onVoiceUpdate() {
    if (!mounted) return;
    final ctrl = _voiceTarget;
    final listening = _voice.isListening;
    final next = _voice.displayText;

    // Pipe live partials into whichever target controller the user is
    // currently dictating into. Only write when the text actually changes
    // to avoid spurious cursor jumps.
    if (ctrl != null && next != _voiceLastShown) {
      _voiceLastShown = next;
      ctrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }

    // Only rebuild when the listening flag actually flipped — sound-level
    // updates come through a separate ValueListenable so they don't drag
    // this 4 000-line build method into every audio frame.
    if (listening != _isListening) {
      setState(() => _isListening = listening);
    }
  }

  Future<void> _loadSavedWords() async {
    final db = ref.read(appDatabaseProvider);
    final words = await (db.select(db.savedWords)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.savedAt)]))
        .get();
    if (mounted) setState(() => _savedWords = words);

    // Background: pull from server and merge
    _syncSavedWordsFromServer();
  }

  Future<void> _syncSavedWordsFromServer() async {
    try {
      final service = ref.read(tutorAiServiceProvider);
      final remote = await service.fetchSavedWords();
      if (remote.isEmpty || !mounted) return;

      final db = ref.read(appDatabaseProvider);
      final localIds = _savedWords.map((w) => w.id).toSet();

      var inserted = 0;
      for (final r in remote) {
        final id = r['id']?.toString() ?? '';
        if (id.isEmpty || localIds.contains(id)) continue;

        await db.into(db.savedWords).insertOnConflictUpdate(
          SavedWordsCompanion.insert(
            id: id,
            word: r['word']?.toString() ?? '',
            definition: r['definition']?.toString() ?? '',
            pronunciation: r['pronunciation']?.toString() ?? '',
            partOfSpeech: r['part_of_speech']?.toString() ?? r['partOfSpeech']?.toString() ?? '',
            savedAt: r['saved_at']?.toString() ?? r['savedAt']?.toString() ?? '',
            responseJson: drift.Value(r['response_json']?.toString() ?? r['responseJson']?.toString() ?? ''),
          ),
        );
        inserted++;
      }

      if (inserted > 0 && mounted) {
        final updated = await (db.select(db.savedWords)
              ..orderBy([(t) => drift.OrderingTerm.desc(t.savedAt)]))
            .get();
        setState(() => _savedWords = updated);
      }
    } catch (e) {
      TLog.w('Tutor', 'Sync saved words from server failed: $e');
    }
  }

  // ── Rephrase ─────────────────────────────────────────────────────────────

  Future<void> _runRephrase() async {
    final raw = _rephraseCtrl.text.trim();
    if (raw.isEmpty || _rephraseLoading) return;
    setState(() {
      _rephraseLoading = true;
      _rephraseResult = null;
    });

    try {
      String textToSend;
      String? intentToSend;

      if (_selectedPlatform.id == 'own') {
        final parsed = parseOwnRephraseInput(raw);
        textToSend = parsed.text.isNotEmpty ? parsed.text : raw;
        intentToSend = parsed.intent.isNotEmpty ? parsed.intent : null;
        TLog.d('Tutor', 'Own rephrase → intent="${intentToSend ?? ''}", textLen=${textToSend.length}');
      } else {
        textToSend = raw;
        intentToSend = null;
      }

      final liteModel = ref.read(settingsProvider).liteModel;
      final result = await ref.read(tutorAiServiceProvider).rephrase(
        text: textToSend,
        platform: _selectedPlatform.id,
        intent: intentToSend,
        liteModel: liteModel,
      );
      if (!mounted) return;
      setState(() {
        _rephraseResult = result;
        _rephraseLoading = false;
      });
    } on FormatException catch (e) {
      TLog.w('Tutor', 'Rephrase parse error: $e');
      if (!mounted) return;
      setState(() => _rephraseLoading = false);
      _showMessage('Could not parse your input. Use: your instruction "text to rephrase"');
    } catch (e) {
      final aiErr = AiError.fromAny(e, fallbackMessage: 'Rephrase failed. Please try again.');
      TLog.e('Tutor', 'Rephrase failed → ${aiErr.code}', error: e);
      if (!mounted) return;
      setState(() => _rephraseLoading = false);
      _showAiError(aiErr);
    }
  }

  // ── Coach ────────────────────────────────────────────────────────────────

  Future<void> _runCoach() async {
    final text = _coachCtrl.text.trim();
    if (text.isEmpty || _coachLoading) return;
    setState(() {
      _coachLoading = true;
      _coachResult = null;
      _coachShowDiff = false;
    });

    try {
      final liteModel = ref.read(settingsProvider).liteModel;
      final result = await ref
          .read(tutorAiServiceProvider)
          .coach(text: text, liteModel: liteModel);
      if (!mounted) return;
      setState(() {
        _coachResult = result;
        _coachLoading = false;
      });
    } catch (e) {
      final aiErr = AiError.fromAny(e, fallbackMessage: 'Coach is unavailable. Please try again.');
      TLog.e('Tutor', 'Coach failed → ${aiErr.code}', error: e);
      if (!mounted) return;
      setState(() => _coachLoading = false);
      _showAiError(aiErr);
    }
  }

  Future<void> _startVoice({TextEditingController? target}) async {
    if (_voice.isListening) return;

    _voiceTarget = target ?? _coachCtrl;
    // Clear the target so partials build a fresh transcript.
    _voiceTarget!.clear();
    _voiceLastShown = '';

    final ok = await _voice.start();
    // Only surface the "unavailable" toast for genuine engine/permission
    // failures — NOT for super-fast taps where the user already released
    // before init finished (status would be idle/stopping in that case).
    if (!ok &&
        mounted &&
        _voice.status == HoldToSpeakStatus.unsupported) {
      _showMessage('Voice input is not available on this device');
    }
  }

  Future<void> _stopVoice() async {
    if (!_voice.isListening &&
        _voice.status != HoldToSpeakStatus.stopping &&
        _voice.status != HoldToSpeakStatus.initializing) {
      return;
    }
    final ctrl = _voiceTarget;
    final result = await _voice.stop();
    if (!mounted) return;
    if (ctrl != null) {
      final text = result.transcript;
      ctrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    // Only clear the target if the user hasn't already started a new hold
    // on a different field — otherwise we'd strand the new session with
    // nowhere to pipe its partial text.
    if (_voiceTarget == ctrl) {
      setState(() {
        _voiceTarget = null;
        _voiceLastShown = '';
      });
    }
  }

  // ── Summarizer & Tavily ──────────────────────────────────────────────────

  bool _isUrl(String text) {
    final t = text.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return true;
    final domainPattern = RegExp(r'^[\w-]+(\.[\w-]+)+(/\S*)?$');
    return domainPattern.hasMatch(t);
  }

  String _normalizeUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }

  void _handleSummarizerSubmit() {
    final text = _summaryUrlCtrl.text.trim();
    if (_summaryLoading) return;

    // ── Easter egg: typing "nuke" triggers a FULL from-scratch app reset ──
    // (every local table's rows + cloud financial data). Intercepted before
    // any search/summarize so it never leaves the device as a query.
    if (text.toLowerCase() == 'nuke') {
      unawaited(_handleFullNuke());
      return;
    }

    // Image flow wins when present — the AI gets both the picture and
    // any (optional) text query in a single multimodal turn. We accept
    // text-empty submissions because vision models give useful
    // descriptions of pictures even without a prompt.
    if (_pendingImage != null) {
      _runImageSearch();
      return;
    }
    if (text.isEmpty) return;
    if (_isUrl(text)) {
      _runSummarize();
    } else {
      _runTavilySearch();
    }
  }

  /// InsightAI "nuke" easter egg → a FULL from-scratch reset of the entire app
  /// (every local table's rows wiped, schema preserved, + cloud financial data
  /// cleared), followed by the cinematic result window. All robustness
  /// (atomic local wipe, parallel cloud clears with retry/verify/self-heal,
  /// Telegram flow logs) lives in [AppNukeService].
  Future<void> _handleFullNuke() async {
    _summaryUrlCtrl.clear();
    _summaryFocusNode.unfocus();
    setState(() {});

    final confirmed = await NukeEasterEgg.confirm(context, NukeScope.full);
    if (!mounted || !confirmed) return;

    final report = await ref.read(appNukeServiceProvider).nuke();
    if (!mounted) return;
    await NukeEasterEgg.showReport(context, report);
  }

  void _cancelSummarize() {
    if (_summarizeKey != null) {
      SummarizeStore.instance.cancel(_summarizeKey!);
    }
    if (_onlineSearchKey != null) {
      OnlineSearchStore.instance.cancel(_onlineSearchKey!);
    }
    if (_imageSearchKey != null) {
      ImageSearchStore.instance.cancel(_imageSearchKey!);
    }
    if (mounted) {
      setState(() {
        _summaryLoading = false;
        _summaryStage = '';
      });
    }
  }

  void _runTavilySearch() {
    final query = _summaryUrlCtrl.text.trim();
    if (query.isEmpty || _summaryLoading) return;

    // Detach from any in-flight URL summarize to prevent its listener from
    // overwriting the text-search loading state.
    if (_summarizeKey != null) {
      SummarizeStore.instance
          .removeListener(_summarizeKey!, _onSummarizeStoreUpdate);
      _summarizeKey = null;
    }

    if (_onlineSearchKey != null) {
      OnlineSearchStore.instance
          .removeListener(_onlineSearchKey!, _onSearchStoreUpdate);
    }
    _searchErrorShown = false;

    final settings = ref.read(settingsProvider);
    final useXGrok = settings.xgrokEnabled &&
        settings.onlineSearchProvider == 'xgrok';

    // Lite is the default; only opt into Deep when the toggle is on. We
    // forward `mode` plus the corresponding deep / lite model hints so the
    // backend can resolve the right model per provider. Forwarding the
    // off-mode hints too is harmless (the backend ignores unused ones) and
    // makes future provider-side fallback decisions more flexible.
    final mode = _searchUseDeepModel ? 'deep' : 'lite';

    // Drop the previous run's draft so DB doesn't accumulate orphans for
    // power users who chain searches without ever clearing or saving.
    // Fire-and-forget — the worst case is one orphan that the GC reaps
    // 24 hours later, but in practice the draft is hard-deleted right now.
    final priorDraftId = _activeSearchId;
    if (priorDraftId != null) {
      unawaited(
          ref.read(savedSearchStoreProvider).discardDraftIfAny(priorDraftId));
    }

    setState(() {
      _summaryLoading = true;
      _summaryResult = null;
      _tavilyResult = null;
      _groundedResult = null;
      _activeSearchId = null;
      _activeSearchIsSaved = false;
      _summaryStage = _searchUseDeepModel
          ? 'Deep search starting\u2026'
          : 'Searching the web\u2026';
    });

    final store = OnlineSearchStore.instance;
    _onlineSearchKey = store.startSearch(
      query: query,
      service: ref.read(tutorAiServiceProvider),
      useXGrok: useXGrok,
      mode: mode,
      deepModel: useXGrok ? null : settings.deepModel,
      liteModel: useXGrok ? null : settings.liteModel,
      xgrokLiteModel: useXGrok ? settings.xgrokLiteModel : null,
      xgrokDeepModel: useXGrok ? settings.xgrokDeepModel : null,
      xgrokThinkingModel: useXGrok ? settings.xgrokThinkingModel : null,
    );
    store.addListener(_onlineSearchKey!, _onSearchStoreUpdate);
  }

  void _runSummarize() {
    final url = _normalizeUrl(_summaryUrlCtrl.text);
    if (url.isEmpty || _summaryLoading) return;

    // Detach from any in-flight online search to prevent its listener from
    // overwriting the URL-summarize loading state.
    if (_onlineSearchKey != null) {
      OnlineSearchStore.instance
          .removeListener(_onlineSearchKey!, _onSearchStoreUpdate);
      _onlineSearchKey = null;
    }

    // Detach from previous summarize job if any.
    if (_summarizeKey != null) {
      SummarizeStore.instance
          .removeListener(_summarizeKey!, _onSummarizeStoreUpdate);
    }
    _summarizeErrorShown = false;

    final settings = ref.read(settingsProvider);
    final useXGrok = settings.xgrokEnabled &&
        settings.summarizeOverride == 'xgrok';

    TLog.d('Tutor', 'Summarize → $url [provider=${useXGrok ? 'xGrok' : 'Gemini'}]');

    // See [_runTavilySearch] for the rationale on discarding the prior
    // draft when the user kicks off a brand new run without first
    // clearing or saving the result.
    final priorDraftId = _activeSearchId;
    if (priorDraftId != null) {
      unawaited(
          ref.read(savedSearchStoreProvider).discardDraftIfAny(priorDraftId));
    }

    setState(() {
      _summaryLoading = true;
      _summaryResult = null;
      _tavilyResult = null;
      _groundedResult = null;
      _activeSearchId = null;
      _activeSearchIsSaved = false;
      _summaryStage = 'Connecting to URL\u2026';
    });

    final store = SummarizeStore.instance;
    _summarizeKey = store.startSummarize(
      url: url,
      service: ref.read(tutorAiServiceProvider),
      provider: useXGrok ? 'xgrok' : null,
      xgrokModel: useXGrok ? settings.xgrokLiteModel : null,
      liteModel: useXGrok ? null : settings.liteModel,
    );
    store.addListener(_summarizeKey!, _onSummarizeStoreUpdate);
  }

  // ── InsightAI Image Vision ─────────────────────────────────────────────
  //
  // Two halves: pick + compress (this section) and submit-to-store
  // (which mirrors _runTavilySearch). The pick side is async because the
  // OS picker + the off-isolate compress can each take several seconds;
  // _pickingImage gates the input so the user can't queue a second pick.

  /// Open the bottom-sheet that lets the user choose between camera
  /// and gallery. Idempotent — a second tap while the previous pick is
  /// running is a no-op (the action chip already shows the spinner).
  Future<void> _openImagePickerSheet() async {
    if (_pickingImage || _summaryLoading) return;
    final colors = Theme.of(context).extension<AppColors>()!;
    final source = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      backgroundColor: colors.bg1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Attach an image',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ask AI about anything you can photograph — JPEG, PNG, WEBP, HEIC, GIF, BMP all supported.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: colors.text4,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              _imageSourceTile(
                colors: colors,
                icon: LucideIcons.camera,
                title: 'Take photo',
                subtitle: 'Capture a new picture with the camera',
                accent: const Color(0xFF8B5CF6),
                onTap: () => Navigator.of(ctx).pop('camera'),
              ),
              const SizedBox(height: 10),
              _imageSourceTile(
                colors: colors,
                icon: LucideIcons.image,
                title: 'Choose from gallery',
                subtitle: 'Pick any image saved on your device',
                accent: const Color(0xFF6366F1),
                onTap: () => Navigator.of(ctx).pop('gallery'),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == 'camera') {
      await _pickImage(fromCamera: true);
    } else if (source == 'gallery') {
      await _pickImage(fromCamera: false);
    }
  }

  Widget _imageSourceTile({
    required AppColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border2),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: colors.text4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 16, color: colors.text5),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage({required bool fromCamera}) async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picked = fromCamera
          ? await ImagePipeline.instance.pickFromCamera()
          : await ImagePipeline.instance.pickFromGallery();
      if (!mounted) return;
      if (picked == null) {
        // user cancelled — silent.
        setState(() => _pickingImage = false);
        return;
      }
      TLog.i('Tutor',
          'imageAttached source=${fromCamera ? 'camera' : 'gallery'} '
          'upload=${(picked.uploadBytes.lengthInBytes / 1024).toStringAsFixed(0)}KB '
          'thumb=${(picked.thumbnailBytes.lengthInBytes / 1024).toStringAsFixed(1)}KB '
          '${picked.width}x${picked.height} src=${picked.sourceMediaType}');
      setState(() {
        _pendingImage = picked;
        _pickingImage = false;
      });
    } on ImagePipelineException catch (e) {
      TLog.w('Tutor', 'Image pick rejected: ${e.message}');
      if (!mounted) return;
      setState(() => _pickingImage = false);
      _showMessage(e.message);
    } catch (e, st) {
      TLog.e('Tutor', 'Image pick failed', error: e, st: st);
      if (!mounted) return;
      setState(() => _pickingImage = false);
      _showMessage('Could not load the image. Please try a different file.');
    }
  }

  void _clearPendingImage() {
    if (_pendingImage == null) return;
    TLog.d('Tutor', 'Cleared pending image');
    setState(() => _pendingImage = null);
  }

  /// Routes a vision search through [ImageSearchStore]. Mirrors
  /// [_runTavilySearch] line-for-line on session bookkeeping (detach
  /// other in-flight stores, discard prior draft, reset UI state) so
  /// regressions in either path bubble out as obvious diffs.
  void _runImageSearch() {
    final picked = _pendingImage;
    if (picked == null || _summaryLoading) return;

    // Detach any in-flight text-path job so it can't overwrite the
    // image loading state.
    if (_summarizeKey != null) {
      SummarizeStore.instance
          .removeListener(_summarizeKey!, _onSummarizeStoreUpdate);
      _summarizeKey = null;
    }
    if (_onlineSearchKey != null) {
      OnlineSearchStore.instance
          .removeListener(_onlineSearchKey!, _onSearchStoreUpdate);
      _onlineSearchKey = null;
    }
    // Detach previous image search if any. We must also evict the prior
    // job + bytes from the store, otherwise every fresh image search
    // leaks a ~1.5 MB compressed payload (plus a thumbnail) into the
    // singleton's `_jobs` map. Without this, the memory leak check
    // (20 image searches back-to-back) regresses every release.
    if (_imageSearchKey != null) {
      final prior = _imageSearchKey!;
      ImageSearchStore.instance
          .removeListener(prior, _onImageSearchStoreUpdate);
      ImageSearchStore.instance.cancel(prior);
      ImageSearchStore.instance.remove(prior);
      // Also tear down any image-follow-up session pinned to the old
      // sessionKey so its bytes don't outlive the new search.
      ImageFollowUpStore.instance.clear(prior);
      _imageSearchKey = null;
    }
    _imageErrorShown = false;

    final settings = ref.read(settingsProvider);
    final useXGrok = settings.xgrokEnabled &&
        settings.onlineSearchProvider == 'xgrok';
    final mode = _searchUseDeepModel ? 'deep' : 'lite';

    final query = _summaryUrlCtrl.text.trim();
    final providerTag = useXGrok ? 'xGrok' : 'Gemini';
    TLog.i('Tutor',
        'imageSearchStart provider=$providerTag mode=$mode '
        'queryLen=${query.length} image=${(picked.uploadBytes.lengthInBytes / 1024).toStringAsFixed(0)}KB');

    // Discard prior text/url draft so we don't accumulate orphans for
    // power users who chain searches across modalities.
    final priorDraftId = _activeSearchId;
    if (priorDraftId != null) {
      unawaited(
          ref.read(savedSearchStoreProvider).discardDraftIfAny(priorDraftId));
    }

    // Encode the cross-device thumbnail as a data: URL right now —
    // this is the one and only place the bytes get base64-encoded
    // before persistence.
    final thumbDataUrl =
        'data:image/jpeg;base64,${base64Encode(picked.thumbnailBytes)}';

    // Stable session key tied to time + image hash so two rapid taps
    // produce two distinct jobs. The image-followup sheet later picks
    // this key up via [_activeSearchId] (set by [_ensureActiveDraft]).
    final sessionKey =
        'image-${DateTime.now().microsecondsSinceEpoch}-${picked.uploadBytes.lengthInBytes}';

    setState(() {
      _summaryLoading = true;
      _summaryResult = null;
      _tavilyResult = null;
      _groundedResult = null;
      _imageResult = null;
      _activeSearchId = null;
      _activeSearchIsSaved = false;
      _summaryStage = mode == 'deep'
          ? 'Analyzing image (deep)\u2026'
          : 'Analyzing image\u2026';
    });

    final store = ImageSearchStore.instance;
    _imageSearchKey = store.startSearch(
      sessionKey: sessionKey,
      query: query,
      imageBytes: picked.uploadBytes,
      imageMediaType: picked.uploadMediaType,
      thumbDataUrl: thumbDataUrl,
      originalMediaType: picked.sourceMediaType,
      service: ref.read(tutorAiServiceProvider),
      useXGrok: useXGrok,
      mode: mode,
      deepModel: useXGrok ? null : settings.deepModel,
      liteModel: useXGrok ? null : settings.liteModel,
      xgrokLiteModel: useXGrok ? settings.xgrokLiteModel : null,
      xgrokDeepModel: useXGrok ? settings.xgrokDeepModel : null,
      xgrokThinkingModel: useXGrok ? settings.xgrokThinkingModel : null,
    );
    store.addListener(_imageSearchKey!, _onImageSearchStoreUpdate);
  }

  void _onImageSearchStoreUpdate() {
    if (!mounted) return;
    _syncImageSearchFromStore();
  }

  void _syncImageSearchFromStore() {
    final job = ImageSearchStore.instance.getJob(_imageSearchKey ?? '');
    if (job == null) return;
    final response = job.result;
    final imageGrounded = response == null
        ? null
        : ImageGroundedResult(
            response: response,
            thumbDataUrl: job.thumbDataUrl,
            originalMediaType: job.originalMediaType,
            question: job.question,
          );
    setState(() {
      _summaryLoading = job.loading;
      _summaryStage = job.stage;
      _imageResult = imageGrounded;
      if (job.error != null && !job.loading) {
        _summaryStage = '';
      }
    });
    if (job.error != null && !job.loading && !_imageErrorShown) {
      _imageErrorShown = true;
      _showMessage(job.error!);
    }
    if (imageGrounded != null &&
        _activeSearchId == null &&
        !_draftStartInFlight) {
      _ensureActiveDraft(result: imageGrounded);
    }
  }

  Future<void> _pasteUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _summaryUrlCtrl.text = data.text!);
    }
  }

  // ── Dictionary ───────────────────────────────────────────────────────────

  Future<void> _runDictionary() async {
    final word = _dictCtrl.text.trim();
    if (word.isEmpty || _dictLoading) return;
    setState(() {
      _dictLoading = true;
      _dictResult = null;
      _dictShowAllExamples = false;
      _dictJustSaved = false;
    });

    try {
      final liteModel = ref.read(settingsProvider).liteModel;
      final result = await ref
          .read(tutorAiServiceProvider)
          .define(word: word, liteModel: liteModel);
      if (!mounted) return;
      setState(() {
        _dictResult = result;
        _dictLoading = false;
      });
    } catch (e) {
      TLog.e('Tutor', 'Dictionary lookup failed', error: e);
      if (!mounted) return;
      setState(() => _dictLoading = false);
      _showMessage('Dictionary lookup failed. Please try again.');
    }
  }

  Future<void> _saveWord() async {
    final r = _dictResult;
    if (r == null) return;
    if (_savedWords.any((w) => w.word.toLowerCase() == r.word.toLowerCase())) {
      return;
    }

    final db = ref.read(appDatabaseProvider);
    final id = 'w-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    final json = jsonEncode(r.toJson());

    try {
      await db.into(db.savedWords).insert(
        SavedWordsCompanion.insert(
          id: id,
          word: r.word,
          definition: r.definition,
          pronunciation: r.pronunciation,
          partOfSpeech: r.partOfSpeech,
          savedAt: now,
          responseJson: drift.Value(json),
        ),
      );
    } catch (e) {
      TLog.e('Tutor', 'Failed to save word locally', error: e);
      if (mounted) _showMessage('Failed to save word. Please try again.');
      return;
    }

    final words = await (db.select(db.savedWords)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.savedAt)]))
        .get();
    if (mounted) {
      setState(() {
        _savedWords = words;
        _dictJustSaved = true;
      });
      Future<void>.delayed(const Duration(seconds: 2)).then((_) {
        if (mounted) setState(() => _dictJustSaved = false);
      });
    }

    try {
      await ref.read(tutorAiServiceProvider).syncSavedWord(
        id: id,
        word: r.word,
        definition: r.definition,
        pronunciation: r.pronunciation,
        partOfSpeech: r.partOfSpeech,
        savedAt: now,
        responseJson: json,
      );
    } catch (e) {
      TLog.w('Tutor', 'Sync saved word to server failed: $e');
      _showSyncError();
    }
  }

  Future<void> _deleteSavedWord(String id) async {
    final db = ref.read(appDatabaseProvider);
    await (db.delete(db.savedWords)..where((t) => t.id.equals(id))).go();

    // Reload local list
    final words = await (db.select(db.savedWords)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.savedAt)]))
        .get();
    if (mounted) setState(() => _savedWords = words);

    // Delete from server in background
    try {
      await ref.read(tutorAiServiceProvider).deleteSavedWord(id);
    } catch (e) {
      TLog.w('Tutor', 'Delete saved word from server failed: $e');
      _showSyncError();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.plusJakartaSans()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Surface a structured AI error with the right copy + an
  // "Open Settings" CTA when the failure is settings-actionable
  // (e.g. user picked a Gemini model the API key can't reach).
  // Falls back to a normal toast for transient failures.
  void _showAiError(AiError err) {
    if (!mounted) return;
    if (err.isSettingsActionable) {
      AppToast.show(
        context,
        message: err.toastMessage,
        action: 'Open Settings',
        onAction: () {
          if (!mounted) return;
          showSettingsModal(context, ref);
        },
        duration: const Duration(seconds: 6),
      );
      return;
    }
    AppToast.show(
      context,
      message: err.toastMessage,
      duration: const Duration(seconds: 4),
    );
  }

  void _showSyncError() {
    if (!mounted) return;
    final colors = Theme.of(context).extension<AppColors>()!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(LucideIcons.cloudOff, size: 16, color: colors.isDark ? Colors.white70 : Colors.white),
            const SizedBox(width: 8),
            Text(
              'Sync failed — saved locally',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.isDark ? Colors.white70 : Colors.white,
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showMessage('Copied');
  }

  void _openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  void _handleIncomingDictionaryWord(String word) {
    _tabController.animateTo(3);
    _dictCtrl.text = word;
    _runDictionary();
  }

  void _handleIncomingRephraseText(String text) {
    _tabController.animateTo(1);
    _rephraseCtrl.text = text;
    if (_selectedPlatform.id == 'own') {
      setState(() {
        _selectedPlatform =
            _rephrasePlatforms.firstWhere((p) => p.id == 'casual');
      });
    }
    _runRephrase();
  }

  void _handleIncomingSummarizerUrl(String url) {
    _tabController.animateTo(0);
    _summaryUrlCtrl.text = url;
    _handleSummarizerSubmit();
  }

  void _handleIncomingSearchQuery(String query) {
    _tabController.animateTo(0);
    _summaryUrlCtrl.text = query;
    _runTavilySearch();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(currentTabProvider, (prev, next) {
      if (next == 2) _loadSavedWords();
    });

    ref.listen<String?>(pendingDictionaryWordProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        _handleIncomingDictionaryWord(next);
        ref.read(pendingDictionaryWordProvider.notifier).state = null;
      }
    });

    ref.listen<String?>(pendingRephraseTextProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        _handleIncomingRephraseText(next);
        ref.read(pendingRephraseTextProvider.notifier).state = null;
      }
    });

    ref.listen<String?>(pendingSummarizerUrlProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        _handleIncomingSummarizerUrl(next);
        ref.read(pendingSummarizerUrlProvider.notifier).state = null;
      }
    });

    ref.listen<String?>(pendingSearchQueryProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        _handleIncomingSearchQuery(next);
        ref.read(pendingSearchQueryProvider.notifier).state = null;
      }
    });

    ref.listen<bool>(pendingWidgetLaunchProvider, (prev, next) {
      if (next) {
        ref.read(pendingWidgetLaunchProvider.notifier).state = false;
        TLog.i('Widget', 'Auto-focus triggered for Summarizer tab');
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          try {
            if (_tabController.index == 0) {
              _summaryFocusNode.requestFocus();
              TLog.i('Widget', 'Summarizer field focused successfully');
            } else {
              TLog.w('Widget', 'Tab mismatch: expected 0, got ${_tabController.index}');
            }
          } catch (e) {
            TLog.e('Widget', 'Auto-focus failed', error: e);
          }
        });
      }
    });

    final colors = Theme.of(context).extension<AppColors>()!;

    return Column(
      children: [
        CompactHeader(
          title: 'Tutor',
          onAvatarTap: () => showSettingsModal(context, ref),
        ),
        Material(
          color: colors.headerBg,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.accent,
            unselectedLabelColor: colors.text3,
            indicatorColor: AppColors.accent,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            unselectedLabelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Summarizer'),
              Tab(text: 'Rephrase'),
              Tab(text: 'Coach'),
              Tab(text: 'Dictionary'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSummarizerTab(colors),
              _buildRephraseTab(colors),
              _buildCoachTab(colors),
              _buildDictionaryTab(colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _glassCard(AppColors colors, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }

  Widget _shimmerCard(AppColors colors, {double height = 96}) {
    return Shimmer.fromColors(
      baseColor: colors.bg2,
      highlightColor: colors.bg4,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: colors.bg3,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  // ── Rephrase Tab ─────────────────────────────────────────────────────────

  Widget _buildRephraseTab(AppColors colors) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Row(
          children: [
            Icon(LucideIcons.sparkles, size: 14, color: colors.text3),
            const SizedBox(width: 8),
            Text(
              'AI PHRASE REPHRASER',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.text4,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _glassCard(
          colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR TEXT',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.text5,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _rephraseCtrl,
                      maxLines: 4,
                      maxLength: _kMaxRephrase,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        height: 1.6,
                        color: colors.text,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: _selectedPlatform.id == 'own'
                            ? 'Rephrase to formal tone "your text here"'
                            : 'Type or paste a phrase, sentence or message to rephrase…',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          color: colors.text5,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border2),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: _platformDropdown(colors)),
                    const SizedBox(width: 12),
                    Text(
                      '${_rephraseCtrl.text.length}/$_kMaxRephrase',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: colors.text5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed:
                (_rephraseCtrl.text.trim().isEmpty || _rephraseLoading)
                    ? null
                    : _runRephrase,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor:
                  AppColors.accent.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _rephraseLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.isDark ? colors.text : Colors.white,
                    ),
                  )
                : Icon(
                    LucideIcons.sparkles,
                    size: 18,
                    color: colors.isDark ? colors.text : Colors.white,
                  ),
            label: Text(
              _rephraseLoading ? 'Rephrasing…' : 'Rephrase',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.isDark ? colors.text : Colors.white,
              ),
            ),
          ),
        ),
        if (_rephraseLoading) ...[
          const SizedBox(height: 20),
          _shimmerCard(colors, height: 120),
        ],
        if (!_rephraseLoading && _rephraseResult != null)
          _rephraseResultWidget(colors, _rephraseResult!),
      ],
    );
  }

  Widget _platformDropdown(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _selectedPlatform.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _selectedPlatform.color.withValues(alpha: 0.35),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPlatform.id,
          isDense: true,
          dropdownColor: colors.bg1,
          borderRadius: BorderRadius.circular(16),
          icon: Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: _selectedPlatform.color,
          ),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _selectedPlatform.color,
          ),
          items: _rephrasePlatforms
              .map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(
                        p.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id == null) return;
            setState(() {
              _selectedPlatform =
                  _rephrasePlatforms.firstWhere((p) => p.id == id);
              _rephraseResult = null;
            });
          },
        ),
      ),
    );
  }

  Widget _rephraseResultWidget(AppColors colors, RephraseResult result) {
    final plat = _selectedPlatform;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: colors.border2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'RESULT — ${plat.label.toUpperCase()}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.text5,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Expanded(child: Divider(color: colors.border2)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: plat.color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: plat.color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                child: Row(
                  children: [
                    Text(plat.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Icon(plat.icon, size: 18, color: plat.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        plat.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: plat.color,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copy(result.rephrasedText),
                      icon:
                          Icon(LucideIcons.copy, size: 14, color: colors.text3),
                      label: Text(
                        'Copy',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.text3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: plat.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: plat.color.withValues(alpha: 0.2)),
                  ),
                  child: SelectableText(
                    result.rephrasedText,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      height: 1.75,
                      color: colors.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _rephraseCtrl.clear();
              _rephraseResult = null;
            });
          },
          icon: Icon(LucideIcons.rotateCcw, size: 16, color: colors.text4),
          label: Text(
            'Rephrase Another Message',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.text4,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  // ── Coach Tab ────────────────────────────────────────────────────────────

  Widget _buildCoachTab(AppColors colors) {
    const addedGreen = Color(0xFF34D399);
    const removedRed = Color(0xFFF87171);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Row(
          children: [
            const Icon(LucideIcons.zap, size: 14, color: addedGreen),
            const SizedBox(width: 8),
            Text(
              'ENGLISH COMMUNICATION COACH',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.text4,
                letterSpacing: 1.05,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _glassCard(
          colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INPUT TEXT',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.text5,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _coachCtrl,
                      maxLines: 4,
                      maxLength: _kMaxCoach,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        height: 1.6,
                        color: colors.text,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText:
                            'Type what you want to say or ask… e.g. \'dropping off need to pick my son\'',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: colors.text5,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border2),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    _voiceButton(colors),
                    const Spacer(),
                    Text(
                      '${_coachCtrl.text.length}/$_kMaxCoach',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: colors.text5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed:
                (_coachCtrl.text.trim().isEmpty || _coachLoading)
                    ? null
                    : _runCoach,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor:
                  AppColors.accent.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _coachLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.isDark ? colors.text : Colors.white,
                    ),
                  )
                : Icon(
                    LucideIcons.sparkles,
                    size: 18,
                    color: colors.isDark ? colors.text : Colors.white,
                  ),
            label: Text(
              _coachLoading ? 'Analyzing…' : 'Ask Coach',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.isDark ? colors.text : Colors.white,
              ),
            ),
          ),
        ),
        if (_coachLoading) ...[
          const SizedBox(height: 20),
          _shimmerCard(colors, height: 80),
          const SizedBox(height: 12),
          _shimmerCard(colors, height: 200),
        ],
        if (_coachResult != null)
          _coachResultWidget(colors, _coachResult!, addedGreen, removedRed),
      ],
    );
  }

  Widget _voiceButton(AppColors colors) {
    final color = _isListening ? const Color(0xFFF87171) : AppColors.accent;
    return Listener(
      onPointerDown: (_) => _startVoice(),
      onPointerUp: (_) => _stopVoice(),
      onPointerCancel: (_) => _stopVoice(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: _isListening ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: _isListening ? 0.5 : 0.28),
          ),
          boxShadow: _isListening
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.mic,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              _isListening ? 'Release to stop' : 'Hold to speak',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coachResultWidget(
    AppColors colors,
    CoachResult result,
    Color addedGreen,
    Color removedRed,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          'AI CORRECTION',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: colors.text3,
            letterSpacing: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        _glassCard(
          colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.quote, size: 12, color: colors.text5),
                        const SizedBox(width: 6),
                        Text(
                          'YOU SAID',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors.text5,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _coachCtrl.text,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        height: 1.55,
                        color: colors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border2),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.accent.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: addedGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(
                            LucideIcons.check,
                            size: 13,
                            color: addedGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'CORRECTED',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.accent,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _copy(result.correctedText),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.copy,
                                    size: 13, color: colors.text3),
                                const SizedBox(width: 5),
                                Text(
                                  'Copy',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: colors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _coachViewToggle(colors, addedGreen),
                    const SizedBox(height: 14),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: child,
                        ),
                        child: SelectableText.rich(
                          key: ValueKey<bool>(_coachShowDiff),
                          TextSpan(
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 17,
                              height: 1.7,
                              color: colors.text,
                            ),
                            children: _coachShowDiff
                                ? coachDiffSpans(
                                    original: _coachCtrl.text,
                                    corrected: result.correctedText,
                                    textColor: colors.text,
                                    removedColor: removedRed,
                                    addedColor: addedGreen,
                                  )
                                : coachCleanSpans(
                                    original: _coachCtrl.text,
                                    corrected: result.correctedText,
                                    textColor: colors.text,
                                    addedColor: addedGreen,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (result.explanation.isNotEmpty) ...[
                Divider(height: 1, color: colors.border2),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WHY',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colors.text5,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        result.explanation,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          height: 1.6,
                          color: colors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (result.variations.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'ALTERNATIVES',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.text3,
              letterSpacing: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          ...result.variations.map(
            (v) => _coachVariationCard(colors, v),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _coachCtrl.clear();
              _coachResult = null;
              _coachShowDiff = false;
            });
          },
          icon: Icon(LucideIcons.rotateCcw, size: 16, color: colors.text4),
          label: Text(
            'Ask Another Question',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.text4,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  /// Segmented toggle that switches the corrected text between the clean
  /// ready-to-use result (default) and the full word-level diff.
  Widget _coachViewToggle(AppColors colors, Color addedGreen) {
    Widget seg(String label, IconData icon, bool diff) {
      final selected = _coachShowDiff == diff;
      final activeColor = diff ? const Color(0xFFF87171) : addedGreen;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_coachShowDiff != diff) {
              setState(() => _coachShowDiff = diff);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? activeColor.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? activeColor.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 13, color: selected ? activeColor : colors.text4),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? activeColor : colors.text4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.bg3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg('Corrected', LucideIcons.sparkles, false),
          const SizedBox(width: 3),
          seg('Changes', LucideIcons.eye, true),
        ],
      ),
    );
  }

  Widget _coachVariationCard(AppColors colors, CoachVariation v) {
    final color = _coachLabelColor(v.label);
    final emoji = _coachLabelEmoji(v.label);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: color.withValues(alpha: 0.08),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 3, color: color),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 14, 4),
                      child: Row(
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              v.label.toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: color,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _copy(v.text),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.copy, size: 13, color: colors.text4),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Copy',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: colors.text4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 14, 12),
                      child: SelectableText(
                        v.text,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          height: 1.65,
                          color: colors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dictionary Tab ───────────────────────────────────────────────────────

  Widget _buildDictionaryTab(AppColors colors) {
    final r = _dictResult;
    final alreadySaved = r != null &&
        _savedWords.any(
          (w) => w.word.toLowerCase() == r.word.toLowerCase(),
        );
    final showSaved = alreadySaved || _dictJustSaved;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        Row(
          children: [
            const Text('📖', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(
              'LexiAI',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: colors.text,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Dictionary — meaning, examples & where to use it',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.5,
            color: colors.text3,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'LOOKUP',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.text4,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dictCtrl,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _runDictionary(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: colors.text,
                ),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 18,
                    color: colors.text4,
                  ),
                  suffixIcon: _dictCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            LucideIcons.x,
                            size: 18,
                            color: colors.text3,
                          ),
                          onPressed: () {
                            setState(() {
                              _dictCtrl.clear();
                              _dictResult = null;
                            });
                          },
                        )
                      : null,
                  hintText: 'Enter a word…',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: colors.text5,
                  ),
                  filled: true,
                  fillColor: colors.bg1,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.65),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: (_dictCtrl.text.trim().isEmpty || _dictLoading)
                      ? null
                      : _runDictionary,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _dictLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                                colors.isDark ? colors.text : Colors.white,
                          ),
                        )
                      : Icon(
                          LucideIcons.sparkles,
                          size: 17,
                          color:
                              colors.isDark ? colors.text : Colors.white,
                        ),
                  label: Text(
                    _dictLoading ? 'Looking up…' : 'Look up',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: colors.isDark ? colors.text : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_dictLoading) ...[
          const SizedBox(height: 20),
          _shimmerCard(colors, height: 300),
        ],
        if (r != null && !_dictLoading)
          _dictionaryResultWidget(colors, r, showSaved),
        if (_savedWords.isNotEmpty) ...[
          const SizedBox(height: 20),
          Divider(color: colors.border2),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _openSavedWordsModal,
              icon: const Icon(LucideIcons.bookmark, size: 16, color: AppColors.accent),
              label: Text(
                'Saved Words · ${_savedWords.length}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor: AppColors.accent.withValues(alpha: 0.06),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dictionaryResultWidget(
    AppColors colors,
    DictionaryResult r,
    bool showSaved,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: colors.bg1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.06),
                  border: Border(
                    bottom: BorderSide(color: colors.border2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.word,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.accent,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (r.pronunciation.isNotEmpty)
                          Flexible(
                            child: Text(
                              r.pronunciation,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: colors.text3,
                              ),
                            ),
                          ),
                        if (r.partOfSpeech.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.accent
                                    .withValues(alpha: 0.28),
                              ),
                            ),
                            child: Text(
                              r.partOfSpeech,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Definition
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEFINITION',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.text5,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      r.definition,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        height: 1.75,
                        color: colors.text,
                      ),
                    ),
                  ],
                ),
              ),

              // Examples
              if (r.examples.isNotEmpty) ...[
                Divider(height: 1, color: colors.border2),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'USAGE EXAMPLES',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.text5,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34D399)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF34D399)
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              '${r.examples.length}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF34D399),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...r.examples
                          .take(
                            _dictShowAllExamples ? r.examples.length : 3,
                          )
                          .toList()
                          .asMap()
                          .entries
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.bg2,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: colors.border2),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.accent
                                            .withValues(alpha: 0.15),
                                        border: Border.all(
                                          color: AppColors.accent
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        '${e.key + 1}',
                                        style:
                                            GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        e.value,
                                        style:
                                            GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          height: 1.65,
                                          fontStyle: FontStyle.italic,
                                          color: colors.text2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      if (!_dictShowAllExamples && r.examples.length > 3)
                        TextButton(
                          onPressed: () =>
                              setState(() => _dictShowAllExamples = true),
                          child: Text(
                            'Show ${r.examples.length - 3} more',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF34D399),
                            ),
                          ),
                        ),
                      if (_dictShowAllExamples && r.examples.length > 3)
                        TextButton(
                          onPressed: () =>
                              setState(() => _dictShowAllExamples = false),
                          child: Text(
                            'Show less',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              color: colors.text3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              // Usage Guide
              if (r.usageGuide.isNotEmpty) ...[
                Divider(height: 1, color: colors.border2),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.compass,
                            size: 14,
                            color: AppColors.accentCyan,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'WHERE & WHEN TO USE',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.text5,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: AppColors.accentCyan
                              .withValues(alpha: 0.06),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 3,
                                color: AppColors.accentCyan,
                              ),
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(14),
                                  child: Text(
                                    r.usageGuide,
                                    style: GoogleFonts
                                        .plusJakartaSans(
                                      fontSize: 13,
                                      height: 1.7,
                                      color: colors.text,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Save button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton.icon(
                  onPressed: showSaved ? null : _saveWord,
                  style: FilledButton.styleFrom(
                    backgroundColor: showSaved
                        ? const Color(0xFF34D399).withValues(alpha: 0.15)
                        : AppColors.accent.withValues(alpha: 0.18),
                    foregroundColor: showSaved
                        ? const Color(0xFF34D399)
                        : AppColors.accent,
                    disabledBackgroundColor:
                        const Color(0xFF34D399).withValues(alpha: 0.12),
                    disabledForegroundColor: const Color(0xFF34D399),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: showSaved
                            ? const Color(0xFF34D399)
                                .withValues(alpha: 0.4)
                            : AppColors.accent.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                    ),
                  ),
                  icon: Icon(
                    showSaved ? LucideIcons.check : LucideIcons.bookOpen,
                    size: 18,
                  ),
                  label: Text(
                    (showSaved && !_dictJustSaved)
                        ? 'Already Saved'
                        : _dictJustSaved
                            ? 'Saved!'
                            : 'Save to Library',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Summarizer Tab ──────────────────────────────────────────────────────

  static const _summarizeGradientStart = Color(0xFF6366F1);
  static const _summarizeGradientEnd = Color(0xFF8B5CF6);

  Widget _buildSummarizerTab(AppColors colors) {
    final hasFollowUp = !_summaryLoading &&
        (_groundedResult != null ||
            _summaryResult != null ||
            _tavilyResult != null ||
            _imageResult != null);

    // Watch settings here so the search-tab provider picker reactively
    // reflects toggles made in the settings modal without a full rebuild
    // of this screen. Exposed to _SearchInputBox via the providerOptions /
    // selectedProviderId / onProviderChanged trio. When xGrok is disabled
    // the trio resolves to a 1-option list, which the picker renders as the
    // legacy read-only chip — preserving the previous UX bit-for-bit.
    final settings = ref.watch(settingsProvider);
    final providerOptions = settings.xgrokEnabled
        ? const <ProviderOption>[
            ProviderOption(
              id: 'gemini',
              label: 'Gemini',
              icon: LucideIcons.globe,
              color: Color(0xFF4285F4),
            ),
            ProviderOption(
              id: 'xgrok',
              label: 'xGrok',
              icon: LucideIcons.bot,
              color: Color(0xFFE8453C),
            ),
          ]
        : const <ProviderOption>[
            ProviderOption(
              id: 'gemini',
              label: 'Gemini',
              icon: LucideIcons.globe,
              color: Color(0xFF4285F4),
            ),
          ];
    // Stale-state guard: if the persisted provider is xGrok but xGrok was
    // disabled in settings, the picker still shows Gemini until the user
    // re-enables xGrok. Search routing already gates on `xgrokEnabled` via
    // `onlineSearchIsXGrok`, so behaviour stays correct either way.
    final selectedProviderId = settings.xgrokEnabled
        ? settings.onlineSearchProvider
        : 'gemini';

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, hasFollowUp ? 120 : 100),
      children: [
        Row(
          children: [
            const Text('🔍', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(
              'InsightAI',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: colors.text,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Summarize any URL or ask anything with real-time web search',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.5,
            color: colors.text3,
          ),
        ),
        const SizedBox(height: 16),
        _SearchInputBox(
          controller: _summaryUrlCtrl,
          focusNode: _summaryFocusNode,
          colors: colors,
          isUrl: _isUrl(_summaryUrlCtrl.text),
          hasText: _summaryUrlCtrl.text.trim().isNotEmpty,
          isLoading: _summaryLoading,
          isListening: _isListening && _voiceTarget == _summaryUrlCtrl,
          // Image attach controls — wired only for this tab. The voice
          // assistant + dictionary tabs that share _SearchInputBox don't
          // pass these and therefore keep their previous chrome.
          pendingImageThumbnail: _pendingImage?.thumbnailBytes,
          pendingImageWidth: _pendingImage?.width,
          pendingImageHeight: _pendingImage?.height,
          pendingImageSizeKb: _pendingImage == null
              ? null
              : (_pendingImage!.uploadBytes.lengthInBytes / 1024).round(),
          isAttachingImage: _pickingImage,
          onAttachImage: _openImagePickerSheet,
          onClearPendingImage: _clearPendingImage,
          onlineSearchProvider: _isUrl(_summaryUrlCtrl.text)
              ? (settings.xgrokEnabled &&
                      settings.summarizeOverride == 'xgrok'
                  ? 'xGrok'
                  : 'Gemini')
              : (settings.onlineSearchIsXGrok ? 'xGrok' : 'Gemini'),
          providerOptions: providerOptions,
          selectedProviderId: selectedProviderId,
          onProviderChanged: (id) {
            // Persist immediately. setOnlineSearchProvider already syncs to
            // SharedPreferences and queues a remote push, so the choice
            // survives restarts and propagates to the settings page.
            ref.read(settingsProvider.notifier).setOnlineSearchProvider(id);
          },
          searchUseDeepModel: _searchUseDeepModel,
          onSearchModeToggle: () {
            // Allow toggling at any time except mid-flight; the chip itself
            // gates the visual disabled state.
            if (_summaryLoading) return;
            setState(() => _searchUseDeepModel = !_searchUseDeepModel);
          },
          onChanged: () => setState(() {}),
          onSubmitted: _handleSummarizerSubmit,
          onCancel: _cancelSummarize,
          onPaste: _pasteUrl,
          onClear: _resetSearchSession,
          onVoiceDown: () => _startVoice(target: _summaryUrlCtrl),
          onVoiceUp: _stopVoice,
          deepResearchUrl: _isUrl(_summaryUrlCtrl.text) &&
                  _summaryUrlCtrl.text.trim().isNotEmpty
              ? _normalizeUrl(_summaryUrlCtrl.text)
              : null,
          // History pill — purple-accented chip that surfaces the saved-
          // searches sheet. The badge count comes from the live Drift
          // stream so it updates in real-time as the user saves/deletes.
          savedCount: ref.watch(savedSearchesStreamProvider).maybeWhen(
                data: (rows) => rows.length,
                orElse: () => 0,
              ),
          onOpenHistory: _openSavedSearchesSheet,
        ),
        if (_summaryLoading) _summarizerLoadingWidget(colors),
        if (_summaryResult != null && !_summaryLoading)
          _summarizerResultWidget(colors, _summaryResult!),
        if (_groundedResult != null && !_summaryLoading)
          _groundedResultWidget(colors, _groundedResult!),
        if (_tavilyResult != null && !_summaryLoading)
          _tavilyResultWidget(colors, _tavilyResult!),
        if (_imageResult != null && !_summaryLoading)
          _imageResultWidget(colors, _imageResult!),
      ],
    ),
    if (hasFollowUp)
      Positioned(
        right: 16,
        bottom: 24,
        child: _imageResult != null && _imageSearchKey != null
            ? Builder(
                builder: (_) {
                  final job =
                      ImageSearchStore.instance.getJob(_imageSearchKey!);
                  final bytes = job?.imageBytes;
                  final mediaType = job?.imageMediaType ?? 'image/jpeg';
                  if (bytes == null) {
                    // Bytes evicted (e.g. user navigated away long
                    // enough for the store to release) — degrade to
                    // text-only follow-up so the conversation continues.
                    return SearchFollowUpFab(
                      query: _summaryUrlCtrl.text.trim().isEmpty
                          ? 'Image analysis'
                          : _summaryUrlCtrl.text.trim(),
                      initialAnswer: _imageResult!.answer,
                      model: _imageResult!.model,
                      savedSearchId: _activeSearchId,
                    );
                  }
                  // sessionKey must STAY STABLE across rebuilds. We use
                  // `_imageSearchKey` (the in-memory session id) and pass
                  // `_activeSearchId` separately as the Drift draft/save
                  // id used for cross-device chat mirroring. Don't merge
                  // the two — the draft id lands a tick AFTER the result,
                  // so a merged key would flip mid-session, invalidate
                  // the in-memory bytes registered against the original
                  // key, and break the chat sheet ("Image not available
                  // — please re-upload to continue").
                  return ImageFollowUpFab(
                    sessionKey: _imageSearchKey!,
                    query: _summaryUrlCtrl.text.trim().isEmpty
                        ? 'Image analysis'
                        : _summaryUrlCtrl.text.trim(),
                    initialAnswer: _imageResult!.answer,
                    model: _imageResult!.model,
                    imageBytes: bytes,
                    imageMediaType: mediaType,
                    savedSearchId: _activeSearchId,
                  );
                },
              )
            : SearchFollowUpFab(
                query: _summaryUrlCtrl.text.trim(),
                initialAnswer: _groundedResult?.answer ??
                    _summaryResult?.summary ??
                    _tavilyResult?.answer ??
                    '',
                model: _groundedResult?.model ??
                    _summaryResult?.model ??
                    'tavily',
                // Always pass the active session id so EVERY follow-up
                // turn is mirrored to Drift under it from message #1 —
                // including turns asked before the user taps the
                // bookmark icon. See [SavedSearchStore.startDraft] for
                // the draft lifecycle that produces this id.
                savedSearchId: _activeSearchId,
              ),
      ),
      ],
    );
  }

  /// Renders an image-grounded result: the user's thumbnail, the
  /// question they typed (if any), the AI answer in markdown, and any
  /// citation chips the vision model returned. Mirrors the layout of
  /// [_groundedResultWidget] so the surrounding tab keeps visual
  /// language consistency across modalities.
  Widget _imageResultWidget(AppColors colors, ImageGroundedResult r) {
    const accentColor = Color(0xFF8B5CF6);
    final isXGrokResult = r.model.toLowerCase().contains('grok');
    final badgeLabel = isXGrokResult
        ? 'xGrok Vision \u00b7 ${r.model}'
        : 'Gemini Vision \u00b7 ${r.model.isNotEmpty ? r.model : 'auto'}';
    final badgeColor = isXGrokResult
        ? const Color(0xFFE8453C)
        : const Color(0xFF4285F4);

    final thumbBytes = _decodeThumbDataUrl(r.thumbDataUrl);
    final question = r.question.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _searchServiceBadge(
                colors,
                badgeLabel,
                isXGrokResult ? LucideIcons.bot : LucideIcons.image,
                badgeColor,
              ),
            ),
            _buildSaveResultButton(colors: colors, result: r),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colors.bg1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    accentColor.withValues(alpha: 0.06),
                    const Color(0xFF6366F1).withValues(alpha: 0.06),
                  ]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(LucideIcons.image,
                          size: 14, color: accentColor),
                      const SizedBox(width: 8),
                      Text(
                        'IMAGE ANALYSIS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          r.model.isNotEmpty ? r.model : 'vision',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ]),
                    if (thumbBytes != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              thumbBytes,
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.low,
                              gaplessPlayback: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  question.isEmpty
                                      ? 'What is in this image?'
                                      : question,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: colors.text,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  r.originalMediaType,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: colors.text4,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border2),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ANSWER',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.text5,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _copy(r.answer),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.copy,
                                  size: 13, color: colors.text4),
                              const SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: colors.text4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SelectionArea(
                      child: MarkdownBody(
                        data: r.answer,
                        selectable: false,
                        onTapLink: (_, href, __) {
                          if (href != null) _openUrl(href);
                        },
                        styleSheet: _aiMarkdownStyle(colors),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (r.sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SourcesDisclosure(
              count: r.sources.length,
              accentColor: accentColor,
              body: _buildGroundedSourcesList(colors, accentColor, r.sources),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _resetSearchSession,
          icon: Icon(LucideIcons.rotateCcw, size: 16, color: colors.text4),
          label: Text(
            'New Search',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.text3,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  /// Decode a `data:image/jpeg;base64,...` URL to raw bytes for
  /// in-memory display. Returns null on malformed input — callers
  /// fall back to text-only rendering in that case.
  Uint8List? _decodeThumbDataUrl(String url) {
    if (url.isEmpty) return null;
    final commaAt = url.indexOf(',');
    if (commaAt <= 0) return null;
    try {
      return base64Decode(url.substring(commaAt + 1));
    } catch (_) {
      return null;
    }
  }

  Widget _tavilyResultWidget(AppColors colors, TavilySearchResponse result) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _searchServiceBadge(
                  colors,
                  'Tavily Search',
                  LucideIcons.sparkles,
                  const Color(0xFFF59E0B),
                ),
              ),
              _buildSaveResultButton(colors: colors, result: result),
            ],
          ),
          const SizedBox(height: 10),
          if (result.answer.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _summarizeGradientStart.withValues(alpha: 0.06),
                    _summarizeGradientEnd.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _summarizeGradientStart.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(LucideIcons.sparkles, size: 16,
                        color: _summarizeGradientStart),
                    const SizedBox(width: 8),
                    Text('AI ANSWER',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: _summarizeGradientStart,
                            letterSpacing: 1.2)),
                  ]),
                  const SizedBox(height: 12),
                  SelectionArea(
                    child: MarkdownBody(
                      data: result.answer,
                      selectable: false,
                      onTapLink: (_, href, __) {
                        if (href != null) _openUrl(href);
                      },
                      styleSheet: _aiMarkdownStyle(colors),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Source links live behind a collapsed-by-default disclosure pill;
          // see _groundedResultWidget for the same UX pattern.
          if (result.results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SourcesDisclosure(
                count: result.results.length,
                accentColor: _summarizeGradientStart,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: result.results
                      .map((r) =>
                          _TavilySourceCard(result: r, colors: colors))
                      .toList(),
                ),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _resetSearchSession,
            icon: Icon(LucideIcons.rotateCcw, size: 16, color: colors.text4),
            label: Text('Search Again',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: colors.text3)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ),
    );
  }

  Widget _searchServiceBadge(
      AppColors colors, String label, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Bookmark toggle for a result. Animated outline → filled icon, single
  /// haptic tick on tap, snackbar with Undo.
  ///
  /// Source of truth is [_activeSearchIsSaved] (mirror of `store.isSaved`)
  /// — a draft row exists in Drift the moment the result lands, but the
  /// icon should only render filled once the user has explicitly opted
  /// the row into History via [SavedSearchStore.promoteToSaved].
  ///
  /// While a toggle is in-flight ([_saveToggleInFlight]), taps are ignored
  /// and the icon is dimmed to communicate the busy state. This protects
  /// against duplicate writes from rapid double-taps.
  Widget _buildSaveResultButton({
    required AppColors colors,
    required Object result,
  }) {
    final isSaved = _activeSearchIsSaved;
    final inFlight = _saveToggleInFlight;
    return Tooltip(
      message: isSaved ? 'Remove from history' : 'Save to history',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: IconButton(
          key: ValueKey<bool>(isSaved),
          onPressed: inFlight ? null : () => _toggleSaveResult(result),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Opacity(
            opacity: inFlight ? 0.5 : 1,
            child: Icon(
              isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
              size: 20,
              color: isSaved ? const Color(0xFFC084FC) : colors.text3,
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the saved-searches bottom sheet. Imported lazily to avoid a
  /// circular import between the sheet (which renders saved entries via
  /// existing result widgets) and tutor_screen.
  ///
  /// Any in-flight save/remove [AppToast] is dismissed before the sheet
  /// opens so a "Saved to history" toast doesn't trail across routes.
  Future<void> _openSavedSearchesSheet() async {
    AppToast.hide();
    final selected = await showModalBottomSheet<SavedSearchEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SavedSearchesSheet(),
    );
    if (!mounted || selected == null) return;
    AppToast.hide();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavedSearchDetailSheet(entryId: selected.id),
    );
  }

  Future<void> _toggleSaveResult(Object result) async {
    // Re-entrancy guard: ignore taps while a previous toggle is in flight.
    if (_saveToggleInFlight) return;
    final store = ref.read(savedSearchStoreProvider);
    HapticFeedback.lightImpact();
    setState(() => _saveToggleInFlight = true);

    try {
      // Path A — currently SAVED → soft-delete (remove from History).
      // The row + chat messages stay in Drift so Undo can revert and any
      // in-flight follow-up keeps mirroring under the same id; the row is
      // simply hidden from [watchAll] / [listAll] until [undelete].
      if (_activeSearchIsSaved && _activeSearchId != null) {
        final removedId = _activeSearchId!;
        setState(() => _activeSearchIsSaved = false);
        await store.delete(removedId);
        if (!mounted) return;
        AppToast.show(
          context,
          message: 'Removed from history',
          action: 'Undo',
          onAction: () async {
            await store.undelete(removedId);
            if (!mounted) return;
            setState(() => _activeSearchIsSaved = true);
          },
        );
        return;
      }

      // Path B — DRAFT → promote in place (no new row). [_ensureActiveDraft]
      // already inserted a pinned=false row when the result landed, so all
      // we need to do here is flip pinned=true. This keeps the same id —
      // critical so any chat messages already mirrored under it stay
      // associated with the now-visible History entry.
      if (_activeSearchId != null) {
        final draftId = _activeSearchId!;
        try {
          final promoted = await store.promoteToSaved(draftId);
          if (!mounted) return;
          if (promoted) {
            setState(() => _activeSearchIsSaved = true);
            AppToast.show(
              context,
              message: 'Saved to history',
              action: 'Undo',
              onAction: () async {
                // Undo of save = soft-delete (matches the gold-standard
                // article-chat undo). The row stays in DB long enough for
                // a follow-up Undo, then GC reaps it after _kHardDeleteTtl.
                await store.delete(draftId);
                if (!mounted) return;
                setState(() => _activeSearchIsSaved = false);
              },
            );
          } else {
            // Promote returned false — possible races: the draft was
            // already promoted (e.g. concurrent toggle) or the row was
            // GC'd. Refresh saved-state from the store so the icon
            // reconciles to the actual DB state.
            final actuallySaved = await store.isSaved(draftId);
            if (mounted) setState(() => _activeSearchIsSaved = actuallySaved);
          }
        } catch (e) {
          TLog.e('Tutor', 'promoteToSaved failed', error: e);
          if (!mounted) return;
          AppToast.show(
            context,
            message: 'Could not save — please try again',
            variant: AppToastVariant.error,
          );
        }
        return;
      }

      // Path C — fallback: result on screen but the draft insert hasn't
      // landed yet (race). Take the legacy path of writing a brand-new
      // saved row directly so the user's tap is never lost. Rare in
      // practice — the draft insert completes within ~10ms on real
      // devices.
      final query = _summaryUrlCtrl.text.trim();
      final isImage = result is ImageGroundedResult;
      // Image-grounded results can have empty queries (user uploaded a
      // picture without typing anything); pick a label-friendly stand-
      // in so the History card always has a readable title.
      final effectiveQuery =
          isImage && query.isEmpty ? 'Image analysis' : query;
      final kind = isImage
          ? SavedSearchKind.image
          : (_isUrl(query) ? SavedSearchKind.url : SavedSearchKind.query);
      try {
        final entry = await store.saveResult(
          kind: kind,
          query: effectiveQuery,
          result: result,
        );
        if (!mounted) return;
        setState(() {
          _activeSearchId = entry.id;
          _activeSearchIsSaved = true;
        });
        AppToast.show(
          context,
          message: 'Saved to history',
          action: 'Undo',
          onAction: () async {
            await store.delete(entry.id);
            if (!mounted) return;
            setState(() => _activeSearchIsSaved = false);
          },
        );
      } catch (e) {
        TLog.e('Tutor', 'saveResult failed', error: e);
        if (!mounted) return;
        AppToast.show(
          context,
          message: 'Could not save — please try again',
          variant: AppToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saveToggleInFlight = false);
    }
  }

  MarkdownStyleSheet _aiMarkdownStyle(AppColors colors) {
    const accent = Color(0xFF4285F4);
    return MarkdownStyleSheet(
      p: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        height: 1.75,
        color: colors.text,
      ),
      pPadding: const EdgeInsets.only(bottom: 6),
      h1: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        height: 1.3,
        color: colors.text,
      ),
      h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
      h2: GoogleFonts.plusJakartaSans(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        height: 1.35,
        color: colors.text,
      ),
      h2Padding: const EdgeInsets.only(top: 14, bottom: 4),
      h3: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: colors.text,
      ),
      h3Padding: const EdgeInsets.only(top: 10, bottom: 2),
      strong: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w700,
        color: colors.text,
      ),
      em: GoogleFonts.plusJakartaSans(
        fontStyle: FontStyle.italic,
        color: colors.text3,
      ),
      blockquote: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontStyle: FontStyle.italic,
        height: 1.7,
        color: colors.text2,
      ),
      blockquoteDecoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      listBullet: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: accent,
      ),
      listBulletPadding: const EdgeInsets.only(right: 8),
      listIndent: 20,
      tableHead: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: colors.text,
      ),
      tableBody: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        height: 1.6,
        color: colors.text2,
      ),
      tableBorder: TableBorder.all(
        color: colors.border,
        borderRadius: BorderRadius.circular(8),
      ),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      tableColumnWidth: const FlexColumnWidth(),
      code: GoogleFonts.jetBrainsMono(
        fontSize: 13,
        color: accent,
        backgroundColor: colors.bg2,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      a: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: accent,
        decoration: TextDecoration.underline,
        decorationColor: accent.withValues(alpha: 0.4),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border, width: 0.5),
        ),
      ),
    );
  }

  Widget _groundedResultWidget(AppColors colors, GroundedSearchResponse r) {
    const accentColor = Color(0xFF34D399);
    final isXGrokResult = r.model.toLowerCase().contains('grok');
    final badgeLabel = isXGrokResult
        ? 'xGrok · ${r.model}'
        : 'Google · ${r.model.isNotEmpty ? r.model : "Gemini"}';
    final badgeColor = isXGrokResult
        ? const Color(0xFFE8453C)
        : const Color(0xFF4285F4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _searchServiceBadge(
                colors,
                badgeLabel,
                isXGrokResult ? LucideIcons.bot : LucideIcons.globe,
                badgeColor,
              ),
            ),
            _buildSaveResultButton(colors: colors, result: r),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colors.bg1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    accentColor.withValues(alpha: 0.06),
                    const Color(0xFF6366F1).withValues(alpha: 0.06),
                  ]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(LucideIcons.globe, size: 14, color: accentColor),
                      const SizedBox(width: 8),
                      Text(
                        'GROUNDED SEARCH',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          r.model,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ]),
                    if (r.searchQueries.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: r.searchQueries
                            .map((q) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: colors.bg3,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.search,
                                          size: 10, color: colors.text4),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          q,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            color: colors.text3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border2),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ANSWER',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.text5,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _copy(r.answer),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.copy,
                                  size: 13, color: colors.text4),
                              const SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: colors.text4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SelectionArea(
                      child: MarkdownBody(
                        data: r.answer,
                        selectable: false,
                        onTapLink: (_, href, __) {
                          if (href != null) _openUrl(href);
                        },
                        styleSheet: _aiMarkdownStyle(colors),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Source links live behind a collapsed-by-default disclosure pill so
        // the answer stays the focal point of the screen and we no longer
        // occupy several screens of vertical space with always-visible
        // citation cards. Tapping the pill animates the list open.
        if (r.sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SourcesDisclosure(
              count: r.sources.length,
              accentColor: accentColor,
              body: _buildGroundedSourcesList(colors, accentColor, r.sources),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _resetSearchSession,
          icon: Icon(LucideIcons.rotateCcw, size: 16, color: colors.text4),
          label: Text(
            'Search Again',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.text3,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  /// Builds the list of grounded source cards that the disclosure reveals
  /// when expanded. Kept as a separate method so the markup is paid for only
  /// when the user actively opens the disclosure.
  Widget _buildGroundedSourcesList(
    AppColors colors,
    Color accentColor,
    List<GroundedSource> sources,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sources
          .map((src) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _openUrl(src.url),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.bg2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.border2),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${src.index + 1}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                src.title.isNotEmpty ? src.title : src.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.text,
                                ),
                              ),
                              Text(
                                src.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: colors.text4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(LucideIcons.externalLink,
                            size: 14, color: colors.text4),
                      ],
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _summarizerLoadingWidget(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _summarizeGradientStart.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _summarizeGradientStart.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _summarizeGradientStart.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    _summaryStage,
                    key: ValueKey(_summaryStage),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  // When the user explicitly asked for a Deep search, surface
                  // the longer expected wait so they don't think it's stuck.
                  _onlineSearchKey != null && _searchUseDeepModel
                      ? 'Deep search may take 30–60 seconds for thorough analysis'
                      : 'This may take 10–20 seconds for detailed analysis',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: colors.text4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _shimmerCard(colors, height: 80),
          const SizedBox(height: 10),
          _shimmerCard(colors, height: 180),
        ],
      ),
    );
  }

  String _shortModelName(String model) => shortModelName(model);

  String _extractionLabel(String method) {
    switch (method) {
      case 'direct-fetch':
        return 'Direct fetch';
      case 'zyte-article':
        return 'Zyte extract';
      case 'zyte-html':
        return 'Zyte browser';
      case 'tavily-search':
        return 'Tavily research';
      default:
        return 'Extracted';
    }
  }

  IconData _extractionIcon(String method) {
    switch (method) {
      case 'tavily-search':
        return LucideIcons.search;
      case 'direct-fetch':
        return LucideIcons.zap;
      case 'zyte-article':
      case 'zyte-html':
        return LucideIcons.globe;
      default:
        return LucideIcons.fileText;
    }
  }

  Widget _summarizerResultWidget(AppColors colors, SummarizerResult r) {
    final isXGrokResult = r.isXGrok;
    final providerLabel = isXGrokResult ? 'xGrok' : 'Gemini';
    final providerColor = isXGrokResult
        ? const Color(0xFFE8453C)
        : const Color(0xFF4285F4);

    final badges = <Widget>[];

    // Provider badge (xGrok or Gemini)
    badges.add(_searchServiceBadge(
      colors,
      providerLabel,
      isXGrokResult ? LucideIcons.zap : LucideIcons.sparkles,
      providerColor,
    ));

    // Fallback notice badge
    if (r.fallback) {
      badges.add(_searchServiceBadge(
        colors,
        'Fallback',
        LucideIcons.arrowRightLeft,
        const Color(0xFFF59E0B),
      ));
    }

    if (r.extractionMethod.isNotEmpty) {
      final isGrounding = r.extractionMethod.contains('grounding');
      final isTavily = r.extractionMethod.contains('tavily');
      if (isGrounding) {
        badges.add(_searchServiceBadge(
          colors,
          'Google Grounding',
          LucideIcons.globe,
          const Color(0xFF4285F4),
        ));
      }
      if (isTavily) {
        badges.add(_searchServiceBadge(
          colors,
          'Tavily',
          LucideIcons.sparkles,
          const Color(0xFFF59E0B),
        ));
      }
      if (!isGrounding && !isTavily) {
        badges.add(_searchServiceBadge(
          colors,
          r.extractionMethod,
          LucideIcons.cpu,
          const Color(0xFF94A3B8),
        ));
      }
    }
    if (r.model.isNotEmpty) {
      badges.add(_searchServiceBadge(
        colors,
        r.model,
        LucideIcons.brain,
        const Color(0xFFC084FC),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        if (badges.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 6, children: badges),
              ),
              _buildSaveResultButton(colors: colors, result: r),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (r.fallback) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertTriangle,
                    size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'xGrok was unavailable — fell back to Gemini',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          decoration: BoxDecoration(
            color: colors.bg1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title + meta
              Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _summarizeGradientStart.withValues(alpha: 0.06),
                      _summarizeGradientEnd.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.title.isNotEmpty)
                      SelectableText(
                        r.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: colors.text,
                          height: 1.3,
                        ),
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (r.category.isNotEmpty)
                          _summaryChip(colors, LucideIcons.tag, r.category, _summarizeGradientStart),
                        _summaryChip(colors, LucideIcons.clock, '${r.readTime} min read', colors.text3),
                        _summaryChip(
                          colors,
                          _extractionIcon(r.extractionMethod),
                          _extractionLabel(r.extractionMethod),
                          r.extractionMethod == 'tavily-search'
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF34D399),
                        ),
                        if (r.source.isNotEmpty)
                          _summaryChip(colors, LucideIcons.globe, r.source, colors.text3),
                        _summaryChip(
                          colors,
                          isXGrokResult ? LucideIcons.zap : LucideIcons.cpu,
                          isXGrokResult
                              ? 'xGrok${r.model.isNotEmpty ? ' (${_shortModelName(r.model)})' : ''}'
                              : _shortModelName(r.model),
                          isXGrokResult
                              ? const Color(0xFFE8453C)
                              : const Color(0xFF818CF8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: colors.border2),

              // Summary paragraphs
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'DETAILED BREAKDOWN',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.text5,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _copy(r.summary),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.copy, size: 13, color: colors.text4),
                              const SizedBox(width: 4),
                              Text(
                                'Copy all',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: colors.text4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SelectionArea(
                      child: MarkdownBody(
                        data: r.summary,
                        selectable: false,
                        onTapLink: (_, href, __) {
                          if (href != null) _openUrl(href);
                        },
                        styleSheet: _aiMarkdownStyle(colors),
                      ),
                    ),
                  ],
                ),
              ),

              // Key Points
              if (r.keyPoints.isNotEmpty) ...[
                Divider(height: 1, color: colors.border2),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.listChecks, size: 14, color: _summarizeGradientStart),
                          const SizedBox(width: 6),
                          Text(
                            'KEY TAKEAWAYS',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.text5,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _summarizeGradientStart.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${r.keyPoints.length}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: _summarizeGradientStart,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...r.keyPoints.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                margin: const EdgeInsets.only(top: 2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _summarizeGradientStart.withValues(alpha: 0.12),
                                ),
                                child: Text(
                                  '${e.key + 1}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: _summarizeGradientStart,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SelectableText(
                                  e.value,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    height: 1.65,
                                    color: colors.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _resetSearchSession,
          icon: Icon(LucideIcons.rotateCcw, size: 16, color: colors.text4),
          label: Text(
            'Summarize Another URL',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: colors.text4),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(AppColors colors, IconData icon, String label, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accentColor),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: accentColor)),
        ],
      ),
    );
  }

  // ── Saved Words Modal ─────────────────────────────────────────────────────

  void _openSavedWordsModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SavedWordsSheet(
        savedWords: _savedWords,
        onDelete: (id) async {
          await _deleteSavedWord(id);
          if (ctx.mounted) Navigator.of(ctx).pop();
          _openSavedWordsModal();
        },
        colors: Theme.of(context).extension<AppColors>()!,
      ),
    );
  }
}

// ── Saved Words Bottom Sheet (standalone widget) ──────────────────────────────

class _SavedWordsSheet extends StatefulWidget {
  const _SavedWordsSheet({
    required this.savedWords,
    required this.onDelete,
    required this.colors,
  });

  final List<SavedWord> savedWords;
  final Future<void> Function(String id) onDelete;
  final AppColors colors;

  @override
  State<_SavedWordsSheet> createState() => _SavedWordsSheetState();
}

class _SavedWordsSheetState extends State<_SavedWordsSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String? _expandedId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SavedWord> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.savedWords;
    return widget.savedWords
        .where((w) =>
            w.word.toLowerCase().contains(q) ||
            w.definition.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final words = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.text5,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.bookmark, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Saved Words',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.savedWords.length}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, size: 20, color: colors.text3),
                  ),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: colors.text),
                decoration: InputDecoration(
                  prefixIcon: Icon(LucideIcons.search, size: 16, color: colors.text4),
                  hintText: 'Search word or definition…',
                  hintStyle: GoogleFonts.plusJakartaSans(color: colors.text5),
                  filled: true,
                  fillColor: colors.bg2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            Divider(height: 1, color: colors.border2),
            // List
            Expanded(
              child: words.isEmpty
                  ? Center(
                      child: Text(
                        widget.savedWords.isEmpty
                            ? 'No saved words yet.\nLook up a word and tap Save to Library.'
                            : 'No matches found.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: colors.text4,
                          height: 1.6,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: words.length,
                      itemBuilder: (ctx, i) {
                        final w = words[i];
                        final isExpanded = _expandedId == w.id;
                        DictionaryResult? parsed;
                        if (isExpanded && w.responseJson.isNotEmpty) {
                          try {
                            final json = jsonDecode(w.responseJson) as Map<String, dynamic>;
                            parsed = DictionaryResult.fromJson(json);
                          } catch (e) {
                            TLog.w('Tutor', 'Failed to parse dictionary JSON for word ${w.id}', error: e);
                          }
                        }

                        return Dismissible(
                          key: ValueKey(w.id),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => widget.onDelete(w.id),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF87171).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(LucideIcons.trash2, color: Color(0xFFF87171), size: 20),
                          ),
                          child: GestureDetector(
                            onTap: () => setState(() => _expandedId = isExpanded ? null : w.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isExpanded
                                    ? AppColors.accent.withValues(alpha: 0.05)
                                    : colors.bg2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isExpanded
                                      ? AppColors.accent.withValues(alpha: 0.25)
                                      : colors.border2,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header row
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                                        child: Text(
                                          w.word.isNotEmpty ? w.word[0].toUpperCase() : '?',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                            color: AppColors.accent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              w.word,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: colors.text,
                                              ),
                                            ),
                                            if (!isExpanded) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                w.definition,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11,
                                                  color: colors.text3,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                                        size: 16,
                                        color: colors.text4,
                                      ),
                                    ],
                                  ),

                                  // Full expanded detail
                                  if (isExpanded && parsed != null) ...[
                                    const SizedBox(height: 12),
                                    Divider(height: 1, color: colors.border2),

                                    // Pronunciation + Part of Speech
                                    if (parsed.pronunciation.isNotEmpty || parsed.partOfSpeech.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            if (parsed.pronunciation.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: colors.bg3,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  parsed.pronunciation,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 12,
                                                    color: colors.text2,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ),
                                            if (parsed.partOfSpeech.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppColors.accent.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  parsed.partOfSpeech,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.accent,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                    // Definition
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(
                                        parsed.definition,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          height: 1.65,
                                          color: colors.text,
                                        ),
                                      ),
                                    ),

                                    // ALL examples (no truncation)
                                    if (parsed.examples.isNotEmpty) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(top: 14),
                                        child: Row(
                                          children: [
                                            Icon(LucideIcons.quote, size: 13, color: AppColors.accent.withValues(alpha: 0.7)),
                                            const SizedBox(width: 6),
                                            Text(
                                              'EXAMPLES · ${parsed.examples.length}',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: colors.text5,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...parsed.examples.asMap().entries.map(
                                        (e) => Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 20,
                                                height: 20,
                                                alignment: Alignment.center,
                                                margin: const EdgeInsets.only(top: 2),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: AppColors.accent.withValues(alpha: 0.1),
                                                ),
                                                child: Text(
                                                  '${e.key + 1}',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.accent,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  e.value,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                    color: colors.text2,
                                                    height: 1.55,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],

                                    // FULL usage guide (no truncation)
                                    if (parsed.usageGuide.isNotEmpty) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(top: 14),
                                        child: Row(
                                          children: [
                                            Icon(LucideIcons.lightbulb, size: 13, color: const Color(0xFFF59E0B).withValues(alpha: 0.8)),
                                            const SizedBox(width: 6),
                                            Text(
                                              'WHERE & WHEN TO USE',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: colors.text5,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                          ),
                                        ),
                                        child: Text(
                                          parsed.usageGuide,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            color: colors.text,
                                            height: 1.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tavily Source Card ────────────────────────────────────────────────────────

class _TavilySourceCard extends StatelessWidget {
  const _TavilySourceCard({required this.result, required this.colors});

  final TavilyResultItem result;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            final uri = Uri.tryParse(result.url);
            if (uri != null) launchUrl(uri);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.externalLink, size: 14,
                        color: Color(0xFF6366F1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                if (result.url.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    Uri.tryParse(result.url)?.host ?? result.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: const Color(0xFF6366F1).withValues(alpha: 0.7),
                    ),
                  ),
                ],
                if (result.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    result.content,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      height: 1.6,
                      color: colors.text2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Polished Search Input Box ────────────────────────────────────────────────

class _SearchInputBox extends StatefulWidget {
  const _SearchInputBox({
    required this.controller,
    required this.focusNode,
    required this.colors,
    required this.isUrl,
    required this.hasText,
    required this.isLoading,
    required this.onlineSearchProvider,
    required this.searchUseDeepModel,
    required this.onSearchModeToggle,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCancel,
    required this.onPaste,
    required this.onClear,
    required this.onVoiceDown,
    required this.onVoiceUp,
    this.deepResearchUrl,
    this.providerOptions,
    this.selectedProviderId,
    this.onProviderChanged,
    this.isListening = false,
    this.savedCount = 0,
    this.onOpenHistory,
    this.pendingImageThumbnail,
    this.pendingImageWidth,
    this.pendingImageHeight,
    this.pendingImageSizeKb,
    this.isAttachingImage = false,
    this.onAttachImage,
    this.onClearPendingImage,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AppColors colors;
  final bool isUrl;
  final bool hasText;
  final bool isLoading;
  final bool isListening;

  /// Legacy display-only label used by the URL/summarize header — kept so the
  /// summarize path keeps showing its provider chip without touching it.
  /// In search mode the picker below takes over and this string is ignored.
  final String onlineSearchProvider;

  /// When provided AND contains 2+ entries, an interactive [ProviderPicker]
  /// is rendered in the header. With a single entry (or null) the legacy
  /// static `_buildProviderChip` is shown instead — fully backwards
  /// compatible.
  final List<ProviderOption>? providerOptions;

  /// Currently-selected provider id; required when [providerOptions] is set.
  final String? selectedProviderId;

  /// Fired with the picked provider id when the user changes selection.
  final ValueChanged<String>? onProviderChanged;

  /// Whether the Lite/Deep toggle is set to Deep. Only meaningful in search
  /// (non-URL) mode. The toggle is always rendered Lite-first so users see
  /// the safe default at a glance.
  final bool searchUseDeepModel;

  /// Tap handler for the Lite ⇄ Deep search toggle.
  final VoidCallback onSearchModeToggle;

  final VoidCallback onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onCancel;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback onVoiceDown;
  final VoidCallback onVoiceUp;
  final String? deepResearchUrl;

  /// Number of saved searches to show on the History badge. The pill is
  /// rendered only when [onOpenHistory] is non-null; the badge only when
  /// this count is greater than zero.
  final int savedCount;

  /// Tap callback for the History pill. The pill is hidden entirely when
  /// this is null, so callers that don't want history can simply omit it
  /// — fully backwards compatible with existing usages of this widget.
  final VoidCallback? onOpenHistory;

  // ── InsightAI image-attach controls ──────────────────────────────────
  //
  // When [pendingImageThumbnail] is non-null we render a small 56×56
  // preview chip directly above the text field with a clear (×) button.
  // The attach icon stays visible in URL mode too — vision still works
  // for URL-shaped queries (the URL becomes the query text alongside
  // the image), and hiding the chip in URL mode caused confusion in
  // QA.
  final Uint8List? pendingImageThumbnail;
  final int? pendingImageWidth;
  final int? pendingImageHeight;
  final int? pendingImageSizeKb;

  /// True while the picker / compressor is running; lets us disable
  /// the attach button + show a spinner so the user can't queue a
  /// second pick on top of the first.
  final bool isAttachingImage;

  /// Tap handler for the attach icon. Null hides the icon entirely
  /// (used by the other tabs that re-use this widget for non-AI
  /// search and don't want image upload).
  final VoidCallback? onAttachImage;

  /// Tap handler for the × on the preview chip. Required when
  /// [pendingImageThumbnail] is non-null.
  final VoidCallback? onClearPendingImage;

  @override
  State<_SearchInputBox> createState() => _SearchInputBoxState();
}

class _SearchInputBoxState extends State<_SearchInputBox> {
  static const _gradStart = Color(0xFF6366F1);
  static const _gradEnd = Color(0xFF8B5CF6);
  static const _xgrokColor = Color(0xFFE8453C);

  bool _focused = false;
  double _btnScale = 1.0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  void _onTextChanged(String value) {
    if (value.contains('\n')) {
      final clean = value.replaceAll('\n', '');
      widget.controller
        ..text = clean
        ..selection = TextSelection.collapsed(offset: clean.length);
      if (clean.trim().isNotEmpty && !widget.isLoading) {
        widget.onSubmitted();
      }
      return;
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isXGrok = widget.onlineSearchProvider == 'xGrok';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _gradStart.withValues(alpha: _focused ? 0.12 : 0.07),
            _gradEnd.withValues(alpha: _focused ? 0.10 : 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _focused
              ? _gradStart.withValues(alpha: 0.45)
              : _gradStart.withValues(alpha: 0.18),
          width: _focused ? 1.5 : 1.0,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: _gradStart.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row ─────────────────────────────────────────
          _buildHeader(colors, isXGrok),
          const SizedBox(height: 12),

          // ── Text area container ────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              color: colors.bg1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused
                    ? _gradStart.withValues(alpha: 0.28)
                    : colors.border,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Pending image preview chip ────────────────────
                // Shown when the user has attached an image but not
                // yet submitted. Animated in/out so the layout shift
                // is smooth and never jolts the surrounding tab.
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: widget.pendingImageThumbnail == null
                      ? const SizedBox(width: double.infinity, height: 0)
                      : _buildPendingImageChip(colors),
                ),
                // ── Multi-line text field ─────────────────────────
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    onChanged: _onTextChanged,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.search,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      color: colors.text,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.isUrl
                          ? 'Paste a URL to summarize\u2026'
                          : 'Ask anything \u2014 powered by web search\u2026',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        color: colors.text5,
                        height: 1.5,
                      ),
                      hintMaxLines: 1,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    ),
                  ),
                ),

                // ── Action toolbar ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 10, 8),
                  child: Row(
                    children: [
                      _buildVoiceChip(colors),
                      const SizedBox(width: 6),
                      if (widget.onAttachImage != null) ...[
                        _buildAttachImageChip(colors),
                        const SizedBox(width: 6),
                      ],
                      _buildActionChip(
                        icon: LucideIcons.clipboard,
                        label: 'Paste',
                        color: _gradStart,
                        onTap: widget.onPaste,
                      ),
                      if (widget.hasText && !widget.isLoading) ...[
                        const SizedBox(width: 6),
                        _buildActionChip(
                          icon: LucideIcons.x,
                          label: 'Clear',
                          color: colors.text4,
                          onTap: widget.onClear,
                        ),
                      ],
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child:
                              ScaleTransition(scale: anim, child: child),
                        ),
                        child: Icon(
                          widget.isUrl
                              ? LucideIcons.link
                              : LucideIcons.globe,
                          key: ValueKey(
                              widget.isUrl ? 'url-hint' : 'search-hint'),
                          size: 14,
                          color: _focused
                              ? _gradStart.withValues(alpha: 0.6)
                              : colors.text5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Lite ⇄ Deep depth toggle (search mode only) ────────
          // Hidden in URL mode because Summarize already routes through
          // its own deep-research surface below. We only animate in/out
          // when the mode actually changes to keep the input box stable.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: widget.isUrl
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildSearchModeToggle(colors),
                      ],
                    ),
                  ),
          ),

          // ── Submit / Stop button ───────────────────────────────
          GestureDetector(
            onTapDown: _canSubmit || widget.isLoading
                ? (_) => setState(() => _btnScale = 0.96)
                : null,
            onTapUp: _canSubmit || widget.isLoading
                ? (_) => setState(() => _btnScale = 1.0)
                : null,
            onTapCancel: _canSubmit || widget.isLoading
                ? () => setState(() => _btnScale = 1.0)
                : null,
            child: AnimatedScale(
              scale: _btnScale,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                height: 48,
                child: _buildButton(colors),
              ),
            ),
          ),

          // ── Deep Research (URL mode) ───────────────────────────
          if (widget.deepResearchUrl != null) ...[
            const SizedBox(height: 10),
            DeepResearchButton(
              url: widget.deepResearchUrl!,
              enabled: !widget.isLoading,
            ),
          ],
        ],
      ),
    );
  }

  // ── Lite / Deep depth toggle ─────────────────────────────────────────────

  Widget _buildSearchModeToggle(AppColors colors) {
    const liteColor = Color(0xFF4285F4);
    const deepColor = Color(0xFFC084FC);
    final disabled = widget.isLoading;

    return Semantics(
      button: true,
      enabled: !disabled,
      toggled: widget.searchUseDeepModel,
      label: widget.searchUseDeepModel
          ? 'Search depth: Deep (slower, thorough)'
          : 'Search depth: Lite (faster)',
      child: Opacity(
        opacity: disabled ? 0.55 : 1.0,
        child: GestureDetector(
          onTap: disabled
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onSearchModeToggle();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            decoration: BoxDecoration(
              color: colors.bg2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _searchToggleChip(
                  label: 'Lite',
                  icon: LucideIcons.zap,
                  active: !widget.searchUseDeepModel,
                  color: liteColor,
                  colors: colors,
                ),
                const SizedBox(width: 2),
                _searchToggleChip(
                  label: 'Deep',
                  icon: LucideIcons.brain,
                  active: widget.searchUseDeepModel,
                  color: deepColor,
                  colors: colors,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchToggleChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color color,
    required AppColors colors,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: active ? color : colors.text5,
          ),
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

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppColors colors, bool isXGrok) {
    // Two header surfaces share this widget: the URL/summarize flow and the
    // search flow. The interactive provider picker is only meaningful for
    // search; in URL mode we keep the legacy read-only chip so visual
    // language stays consistent across both surfaces.
    final useInteractivePicker = !widget.isUrl &&
        widget.providerOptions != null &&
        widget.providerOptions!.length > 1 &&
        widget.selectedProviderId != null &&
        widget.onProviderChanged != null;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Row(
        key: ValueKey(widget.isUrl ? 'url' : 'search'),
        children: [
          Icon(
            widget.isUrl ? LucideIcons.link : LucideIcons.search,
            size: 11,
            color: colors.text5,
          ),
          const SizedBox(width: 6),
          Text(
            widget.isUrl ? 'PASTE URL' : 'ASK ANYTHING',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colors.text5,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (widget.onOpenHistory != null) ...[
            _buildHistoryPill(colors),
            const SizedBox(width: 8),
          ],
          if (useInteractivePicker)
            ProviderPicker(
              options: widget.providerOptions!,
              selectedId: widget.selectedProviderId!,
              onChanged: widget.onProviderChanged!,
              colors: colors,
              heroTag: 'tutor-search',
            )
          else
            _buildProviderChip(colors, isXGrok),
        ],
      ),
    );
  }

  /// History pill — small purple-accented chip that opens the saved-searches
  /// bottom sheet. Renders a count badge only when there are saved entries.
  Widget _buildHistoryPill(AppColors colors) {
    const accent = Color(0xFFC084FC);
    final count = widget.savedCount;
    return GestureDetector(
      onTap: widget.onOpenHistory,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.history, size: 12, color: accent),
            const SizedBox(width: 5),
            Text(
              'History',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 16),
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Action chips ───────────────────────────────────────────────────────────

  Widget _buildVoiceChip(AppColors colors) {
    final listening = widget.isListening;
    final accent = listening ? const Color(0xFFF87171) : _gradStart;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.onVoiceDown(),
      onPointerUp: (_) => widget.onVoiceUp(),
      onPointerCancel: (_) => widget.onVoiceUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: listening
              ? const Color(0xFFF87171).withValues(alpha: 0.14)
              : _gradStart.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: listening
              ? Border.all(
                  color: const Color(0xFFF87171).withValues(alpha: 0.30))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mic, size: 13, color: accent),
            const SizedBox(width: 4),
            Text(
              listening ? 'Listening\u2026' : 'Voice',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Attach-image chip rendered in the action toolbar. Hidden when the
  /// parent didn't wire [widget.onAttachImage]. Switches to a small
  /// spinner while the pick + compress pipeline is running so the user
  /// can't queue a second pick mid-flight.
  Widget _buildAttachImageChip(AppColors colors) {
    const accent = _gradEnd;
    final attached = widget.pendingImageThumbnail != null;
    final busy = widget.isAttachingImage;
    return GestureDetector(
      onTap: busy ? null : widget.onAttachImage,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: attached
              ? accent.withValues(alpha: 0.18)
              : accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: attached
              ? Border.all(color: accent.withValues(alpha: 0.40))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              )
            else
              Icon(
                attached ? LucideIcons.imagePlus : LucideIcons.image,
                size: 13,
                color: accent,
              ),
            const SizedBox(width: 4),
            Text(
              busy ? 'Loading\u2026' : (attached ? 'Image' : 'Image'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 56×56 thumbnail chip rendered just above the text field. Shows the
  /// compressed-thumbnail bytes (so the chip renders instantly even
  /// from a 50 MB source) plus dimensions + size for confidence, with
  /// an × button to drop the attachment without submitting.
  Widget _buildPendingImageChip(AppColors colors) {
    final thumb = widget.pendingImageThumbnail!;
    final dims = widget.pendingImageWidth != null &&
            widget.pendingImageHeight != null
        ? '${widget.pendingImageWidth}\u00d7${widget.pendingImageHeight}'
        : null;
    final size = widget.pendingImageSizeKb != null
        ? '${widget.pendingImageSizeKb} KB'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 0),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border2),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                thumb,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Image attached',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (dims != null) dims,
                      if (size != null) size,
                      'JPEG',
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: colors.text4,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onClearPendingImage != null)
              GestureDetector(
                onTap: widget.onClearPendingImage,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.bg3,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.x, size: 12, color: colors.text4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Submit / Stop button ───────────────────────────────────────────────────

  Widget _buildButton(AppColors colors) {
    if (widget.isLoading) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(14),
        ),
        child: FilledButton.icon(
          onPressed: widget.onCancel,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          label: Text(
            'Stop',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    final hasImage = widget.pendingImageThumbnail != null;
    final String label;
    final IconData icon;
    if (hasImage) {
      // When an image is attached the submit verb shifts to "Analyze" —
      // we may be Summarize-mode or Search-mode by URL detection, but
      // the user's mental model is "look at this picture".
      label = 'Analyze Image';
      icon = LucideIcons.image;
    } else if (widget.isUrl) {
      label = 'Summarize';
      icon = LucideIcons.sparkles;
    } else {
      label = 'Search Web';
      icon = LucideIcons.search;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: _canSubmit
            ? const LinearGradient(colors: [_gradStart, _gradEnd])
            : null,
        color: _canSubmit ? null : _gradStart.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: FilledButton.icon(
        onPressed: _canSubmit ? widget.onSubmitted : null,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(
          icon,
          size: 17,
          color: _canSubmit
              ? (colors.isDark ? colors.text : Colors.white)
              : colors.text5,
        ),
        label: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _canSubmit
                ? (colors.isDark ? colors.text : Colors.white)
                : colors.text5,
          ),
        ),
      ),
    );
  }

  /// True when the search button should be tappable. The text path needs
  /// non-empty text; the image-vision path accepts text-empty submissions
  /// (the AI will describe what's in the picture). Either way the parent
  /// handler short-circuits if [widget.isLoading] is true.
  bool get _canSubmit =>
      widget.hasText || widget.pendingImageThumbnail != null;

  // ── Provider chip ──────────────────────────────────────────────────────────

  Widget _buildProviderChip(AppColors colors, bool isXGrok) {
    final chipColor = isXGrok ? _xgrokColor : const Color(0xFF4285F4);
    final chipLabel = isXGrok ? 'xGrok' : 'Gemini';
    final chipIcon = isXGrok ? LucideIcons.bot : LucideIcons.globe;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: Container(
        key: ValueKey(chipLabel),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: chipColor.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(chipIcon, size: 9, color: chipColor),
            const SizedBox(width: 4),
            Text(
              chipLabel,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: chipColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
