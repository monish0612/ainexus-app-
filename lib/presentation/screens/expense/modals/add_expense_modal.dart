import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../../core/platform/io_stub.dart';
import '../../../../core/platform/local_file_image.dart';
import '../../../../core/platform/ocr_stub.dart';
import '../../../../core/platform/platform_capabilities.dart';
import '../../../../core/services/background_task_coordinator.dart';
import '../../../../core/services/hold_to_speak_service.dart';
import '../../../../core/services/telegram_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/services/ai_categorize_service.dart';
import '../../../../domain/entities/expense_entities.dart';
import 'expense_success_modal.dart';

const List<String> kDefaultExpenseModalBanks = [
  'HDFC',
  'ICICI',
  'AXIS',
  'SCAPIA',
  'CASH',
];

class ExpenseSubmitPayload {
  const ExpenseSubmitPayload({
    required this.amount,
    required this.description,
    required this.category,
    required this.bank,
    required this.cardType,
    required this.isManualCategory,
    required this.date,
    this.comments = '',
  });

  final double amount;
  final String description;
  final String category;
  final String bank;
  final String cardType;
  final bool isManualCategory;
  final String date;
  final String comments;
}

typedef CategorizeFunction = Future<AICategoryResult> Function(
  String description,
  CategoryLearning learnings,
);

typedef SmartParseFunction = Future<SmartParseResult?> Function(String text);

Future<void> showAddExpenseModal(
  BuildContext context, {
  required CategoryLearning learnings,
  CategorizeFunction? categorize,
  SmartParseFunction? smartParse,
  required void Function(
    ExpenseSubmitPayload payload,
    bool finalIsManual,
    SuccessMeta meta,
  ) onAdd,
  required void Function(String description, String category) onTeachAI,
  List<String>? banks,
  String? initialImagePath,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddExpenseSheet(
      learnings: learnings,
      banks: banks ?? kDefaultExpenseModalBanks,
      categorize: categorize,
      smartParse: smartParse,
      onAdd: onAdd,
      onTeachAI: onTeachAI,
      initialImagePath: initialImagePath,
    ),
  );
}

// ─── Date option helper ──────────────────────────────────────────────────────

enum _DateOption { today, yesterday, nextMonth }

String _dateLabel(_DateOption opt) {
  switch (opt) {
    case _DateOption.today:
      return 'Today';
    case _DateOption.yesterday:
      return 'Yesterday';
    case _DateOption.nextMonth:
      return 'NM 1st';
  }
}

DateTime _resolveDate(_DateOption opt) {
  final now = DateTime.now();
  switch (opt) {
    case _DateOption.today:
      return now;
    case _DateOption.yesterday:
      return now.subtract(const Duration(days: 1));
    case _DateOption.nextMonth:
      return DateTime(now.year, now.month + 1, 1);
  }
}

String _formatDateShort(DateTime d) => DateFormat('dd MMM yyyy').format(d);

// ─── Main sheet ──────────────────────────────────────────────────────────────

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({
    required this.learnings,
    required this.banks,
    this.categorize,
    this.smartParse,
    required this.onAdd,
    required this.onTeachAI,
    this.initialImagePath,
  });

  final CategoryLearning learnings;
  final List<String> banks;
  final CategorizeFunction? categorize;
  final SmartParseFunction? smartParse;
  final void Function(
    ExpenseSubmitPayload payload,
    bool finalIsManual,
    SuccessMeta meta,
  ) onAdd;
  final void Function(String description, String category) onTeachAI;
  final String? initialImagePath;

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet>
    with SingleTickerProviderStateMixin {
  static const _scanPhases = [
    (text: 'Uploading image…', emoji: '📤', ms: 600),
    (text: 'Reading bill structure…', emoji: '🔍', ms: 1200),
    (text: 'Detecting amount & merchant…', emoji: '💰', ms: 1000),
    (text: 'AI categorizing expense…', emoji: '🧠', ms: 800),
  ];

  static const _pdfScanPhases = [
    (text: 'Loading PDF…', emoji: '📄', ms: 600),
    (text: 'Reading PDF pages…', emoji: '📖', ms: 1200),
    (text: 'Detecting amount & merchant…', emoji: '💰', ms: 1000),
    (text: 'AI categorizing expense…', emoji: '🧠', ms: 800),
  ];

  // Mode: 0 = Scan, 1 = Manual, 2 = Voice
  // On web the Scan mode is hidden (Google ML Kit OCR is Android-only),
  // so we open the modal in Manual mode by default.
  int _mode = PlatformCapabilities.canUseMlKitOcr ? 0 : 1;
  _ScanState _scanState = _ScanState.idle;
  int _scanPhaseIdx = 0;
  File? _capturedImage;
  bool _isPdf = false;

  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();
  final _imagePicker = ImagePicker();

  String _bank = '';
  String _cardType = '';
  String _category = 'Others';
  String? _aiCategory;
  String _confidence = 'default';
  bool _categoryIsManual = false;
  bool _hasLearned = false;
  bool _isLearning = false;
  bool _showCategoryPicker = false;
  bool _aiThinking = false;
  String _aiReasoning = '';

  // Validation
  bool _hasAttemptedSubmit = false;
  late final AnimationController _shakeCtrl;

  // Date
  _DateOption _dateOption = _DateOption.today;

  // ── Voice (hold-to-record) ─────────────────────────────────────────────
  // All STT robustness (silence-recovery, restart accumulation, error
  // backoff, sound-level monitoring) lives in [HoldToSpeakController].
  late final HoldToSpeakController _voice;
  bool _isListening = false;
  bool _voiceParsing = false;
  String _voiceText = '';

  /// Live partial text for the recording display. We use a [ValueNotifier]
  /// so the small "🔴 transcribed text" container can rebuild on every
  /// partial result without dragging the whole voice-mode `Container` (with
  /// its expensive `RadialGradient`) into the rebuild path. Without this
  /// indirection, every partial → `setState` → repaint of the gradient
  /// caused visible lag during fast dictation.
  final ValueNotifier<String> _voiceTextNotifier = ValueNotifier<String>('');

  Timer? _debounce;

  /// Stable per-modal-instance id used as the FG-service slot. Combined
  /// with the modal's hashCode so two simultaneous modal openings (e.g.
  /// share-intent stack) never collide on the same slot.
  late final String _scanSlotId =
      'expense_scan:${identityHashCode(this).toUnsigned(32)}';
  late final String _voiceSlotId =
      'expense_voice:${identityHashCode(this).toUnsigned(32)}';
  bool _scanSlotHeld = false;
  bool _voiceSlotHeld = false;

  void _acquireScanSlot(String label) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    _scanSlotHeld = true;
    unawaited(BackgroundTaskCoordinator.instance.acquire(
      _scanSlotId,
      label: label,
    ));
  }

  void _releaseScanSlot() {
    if (!_scanSlotHeld) return;
    _scanSlotHeld = false;
    unawaited(BackgroundTaskCoordinator.instance.release(_scanSlotId));
  }

  void _acquireVoiceSlot(String label) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    _voiceSlotHeld = true;
    unawaited(BackgroundTaskCoordinator.instance.acquire(
      _voiceSlotId,
      label: label,
    ));
  }

  void _releaseVoiceSlot() {
    if (!_voiceSlotHeld) return;
    _voiceSlotHeld = false;
    unawaited(BackgroundTaskCoordinator.instance.release(_voiceSlotId));
  }

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _descCtrl.addListener(_onDescriptionChanged);
    _voice = HoldToSpeakController(tag: 'AddExpense');
    _voice.addListener(_onVoiceUpdate);
    HoldToSpeakController.warmUp();

    if (widget.initialImagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processSharedImage(widget.initialImagePath!);
      });
    }
  }

  double get _shakeOffset {
    if (!_shakeCtrl.isAnimating) return 0;
    final t = _shakeCtrl.value;
    return sin(t * pi * 8) * 8 * (1 - t);
  }

  bool get _amountError =>
      _hasAttemptedSubmit &&
      (double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0) <= 0;

  bool get _descError =>
      _hasAttemptedSubmit && _descCtrl.text.trim().isEmpty;

  bool get _bankError =>
      _hasAttemptedSubmit && _bank.isEmpty;

  bool get _cardTypeError =>
      _hasAttemptedSubmit && _cardType.isEmpty;

  void _onVoiceUpdate() {
    if (!mounted) return;
    final text = _voice.displayText;
    final listening = _voice.isListening;

    // Live partials → push into the ValueNotifier *without* setState. Only
    // the small `Text(_voiceText)` widget (wrapped in a
    // [ValueListenableBuilder]) rebuilds. The huge surrounding `Container`
    // with its `RadialGradient` is unaffected — same trick the tutor
    // screen gets for free via `TextEditingController`.
    if (text != _voiceText) {
      _voiceText = text;
      _voiceTextNotifier.value = text;
    }

    // Listening flip drives the gradient color, mic ring, and helper text,
    // so we still need a setState — but it only happens twice per session
    // (start + stop) instead of once per partial result.
    if (listening != _isListening) {
      setState(() => _isListening = listening);
    }
  }

  Future<void> _processSharedImage(String path) async {
    if (!PlatformCapabilities.canUseMlKitOcr) return;
    // Promote the OCR + smart-parse pipeline to a foreground service so
    // the work survives screen-off / app minimisation. The slot is held
    // until the pipeline finishes (or the modal is disposed).
    _acquireScanSlot('\uD83D\uDCC4 Scanning shared image\u2026');
    setState(() {
      _isPdf = false;
      _capturedImage = File(path);
      _scanState = _ScanState.scanning;
      _scanPhaseIdx = 0;
    });

    if (!mounted) return;
    setState(() => _scanPhaseIdx = 0);
    await Future<void>.delayed(
      Duration(milliseconds: _scanPhases[0].ms),
    );

    if (!mounted) return;
    setState(() => _scanPhaseIdx = 1);
    String ocrText = '';
    try {
      final inputImage = InputImage.fromFilePath(path);
      final recognizer = TextRecognizer();
      final result = await recognizer.processImage(inputImage);
      ocrText = result.text;
      await recognizer.close();
    } catch (e) {
      TLog.w('AddExpense', 'OCR from shared image failed', error: e);
    }

    await _runExtractionPipeline(ocrText, 'shared_image');
    if (mounted) setState(() => _mode = 1);
  }

  @override
  void dispose() {
    // Drop any FG-service slots this modal instance still holds. We let
    // any in-flight LLM HTTP call complete naturally (the user dismissed
    // the modal but the work is fire-and-forget at this point), but the
    // OS-level wakelock is no longer justified.
    _releaseScanSlot();
    _releaseVoiceSlot();
    _voice.removeListener(_onVoiceUpdate);
    _voice.dispose();
    _voiceTextNotifier.dispose();
    _debounce?.cancel();
    _shakeCtrl.dispose();
    _descCtrl.removeListener(_onDescriptionChanged);
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  void _onDescriptionChanged() {
    if (_mode != 1) return;
    if (_categoryIsManual) return;
    final t = _descCtrl.text.trim();
    if (t.length < 3) {
      setState(() => _aiThinking = false);
      return;
    }
    setState(() => _aiThinking = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 480), () async {
      try {
        AICategoryResult r;
        if (widget.categorize != null) {
          r = await widget.categorize!(t, widget.learnings);
        } else {
          r = categorizeLocal(t, widget.learnings);
        }
        if (!mounted) return;
        setState(() {
          _category = r.category;
          _aiCategory = r.category;
          _confidence = r.confidence;
          _aiReasoning = r.reasoning;
          _aiThinking = false;
        });
      } catch (e) {
        TLog.w('AddExpense', 'Auto-categorize failed', error: e);
        if (mounted) setState(() => _aiThinking = false);
      }
    });
  }

  // ── Voice (hold-to-record) ─────────────────────────────────────────────────

  Future<void> _startListening() async {
    if (_voice.isListening) return;
    _voiceText = '';
    _voiceTextNotifier.value = '';
    final ok = await _voice.start();
    // Only log "unavailable" for genuine engine/permission failures, not
    // fast-tap aborts where the user released before init finished.
    if (!ok && mounted && _voice.status == HoldToSpeakStatus.unsupported) {
      TLog.w('AddExpense', 'Voice unavailable on this device');
    }
  }

  Future<void> _stopListeningAndParse() async {
    if (!_voice.isListening &&
        _voice.status != HoldToSpeakStatus.stopping &&
        _voice.status != HoldToSpeakStatus.initializing) {
      return;
    }

    final voiceResult = await _voice.stop();
    if (!mounted) return;

    final finalText = voiceResult.transcript;
    _voiceText = finalText;
    _voiceTextNotifier.value = finalText;

    TLog.i(
      'AddExpense',
      'Voice hold ended (${finalText.length} chars, '
      '${voiceResult.duration.inMilliseconds}ms, '
      '${voiceResult.restartCount} restarts) → '
      '"${finalText.length > 60 ? '${finalText.substring(0, 60)}…' : finalText}"',
    );

    setState(() {
      _isListening = false;
      _voiceParsing = true;
    });

    if (finalText.isEmpty) {
      TLog.d('AddExpense', '🎙️ Voice empty — skipping parse');
      if (mounted) setState(() => _voiceParsing = false);
      return;
    }

    // Voice smart-parse fires an LLM call (potentially up to 20 s on
    // slow networks). Promote it to a foreground service so the request
    // survives screen-off / app minimisation if the user pockets the
    // phone right after release.
    _acquireVoiceSlot('\uD83C\uDF99\uFE0F Parsing voice expense\u2026');

    final sw = Stopwatch()..start();
    SmartParseResult? result;
    try {
      if (widget.smartParse != null) {
        result = await widget
            .smartParse!(finalText)
            .timeout(const Duration(seconds: 20));
      }
    } on TimeoutException {
      sw.stop();
      TLog.e('AddExpense',
          '🎙️ Voice smart-parse timed out after ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      sw.stop();
      TLog.e('AddExpense',
          '🎙️ Voice smart-parse error (${sw.elapsedMilliseconds}ms)',
          error: e);
    }
    sw.stop();
    _releaseVoiceSlot();

    if (!mounted) return;

    // User may have switched away from voice mode during parse — respect that
    final stayInVoiceFlow = _mode == 2 || _voiceParsing;

    if (result != null && result.amount > 0) {
      final parsedBank = result.bank.isNotEmpty &&
              widget.banks.contains(result.bank)
          ? result.bank
          : 'CASH';
      final parsedCard = parsedBank == 'CASH'
          ? 'Cash'
          : (result.cardType.isNotEmpty ? result.cardType : 'DB');

      TLog.i('AddExpense',
          '🎙️ Voice parsed ✓ ${sw.elapsedMilliseconds}ms → '
          '₹${result.amount.toStringAsFixed(0)} | ${result.description} | '
          '$parsedBank/$parsedCard | ${result.category}');

      HapticFeedback.mediumImpact();
      setState(() {
        _amountCtrl.text = result!.amount.toStringAsFixed(0);
        _descCtrl.text = result.description;
        _bank = parsedBank;
        _cardType = parsedCard;
        _category = result.category;
        _aiCategory = result.category;
        _confidence = 'matched';
        _aiReasoning = 'AI parsed from voice input';
        _voiceParsing = false;
        if (stayInVoiceFlow) _mode = 1;
      });
    } else {
      TLog.w('AddExpense',
          '🎙️ Voice parse fallback ${sw.elapsedMilliseconds}ms — '
          'raw text to manual mode');

      HapticFeedback.lightImpact();
      setState(() {
        if (stayInVoiceFlow) _descCtrl.text = _voiceText;
        _voiceParsing = false;
        if (stayInVoiceFlow) _mode = 1;
      });
    }
  }

  // ── Scan / PDF ─────────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    if (!PlatformCapabilities.canUseMlKitOcr) return;
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked == null || !mounted) return;

    // Promote the OCR + smart-parse pipeline to a foreground service so
    // the work survives screen-off / app minimisation while scanning.
    _acquireScanSlot('\uD83D\uDCF8 Scanning bill\u2026');
    setState(() {
      _isPdf = false;
      _capturedImage = File(picked.path);
      _scanState = _ScanState.scanning;
      _scanPhaseIdx = 0;
    });

    if (!mounted) return;
    setState(() => _scanPhaseIdx = 0);
    await Future<void>.delayed(
      Duration(milliseconds: _scanPhases[0].ms),
    );

    if (!mounted) return;
    setState(() => _scanPhaseIdx = 1);
    String ocrText = '';
    try {
      final inputImage = InputImage.fromFilePath(picked.path);
      final recognizer = TextRecognizer();
      final result = await recognizer.processImage(inputImage);
      ocrText = result.text;
      await recognizer.close();
    } catch (e) {
      TLog.w('AddExpense', 'OCR recognition failed', error: e);
    }

    await _runExtractionPipeline(ocrText, 'image');
  }

  Future<void> _pickPdf() async {
    if (!PlatformCapabilities.canUseMlKitOcr) return;
    final overall = Stopwatch()..start();

    // ── Step 1: Open the system file picker ────────────────────────────────
    FilePickerResult? result;
    try {
      TLog.d('AddExpense', '📄 Opening PDF picker…');
      // `withData: true` + `withReadStream: true` together aren't supported by
      // file_picker, so we ask for bytes (works for every SAF / cloud
      // provider) and also keep the cached `path` when the platform supplies
      // one. The resolver below picks whichever is usable.
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
    } catch (e, st) {
      TLog.e('AddExpense', 'PDF picker threw', error: e, st: st);
      _showPdfError('Could not open the file picker. Please try again.');
      return;
    }

    if (result == null) {
      TLog.d('AddExpense', '📄 PDF picker cancelled by user');
      return;
    }
    if (result.files.isEmpty) {
      TLog.w('AddExpense', '📄 PDF picker returned an empty file list');
      _showPdfError('No file was selected.');
      return;
    }
    if (!mounted) return;

    final picked = result.files.first;
    TLog.i(
      'AddExpense',
      '📄 PDF picked: ${picked.name} (${picked.size} bytes, '
      'hasPath=${picked.path != null}, hasBytes=${picked.bytes != null}, '
      'hasStream=${picked.readStream != null})',
    );

    // ── Step 2: Resolve to a usable bytes/path source ──────────────────────
    Uint8List? workingBytes;
    String? workingPath;
    try {
      final resolved = await _resolvePdfSource(picked);
      workingBytes = resolved.bytes;
      workingPath = resolved.path;
    } catch (e, st) {
      TLog.e('AddExpense', 'PDF source resolution failed', error: e, st: st);
      _showPdfError(
        'Could not read the selected PDF. Try downloading it locally first, '
        'then pick it again.',
      );
      return;
    }

    if (workingBytes == null && workingPath == null) {
      TLog.e(
        'AddExpense',
        '❌ Unresolvable PDF source: name=${picked.name}, '
        'size=${picked.size}, path=${picked.path}',
      );
      _showPdfError(
        'This PDF could not be opened. Try a different file, or save it to '
        'your device first.',
      );
      return;
    }

    if (!mounted) return;

    // ── Step 3: Show scanning UI ──────────────────────────────────────────
    // Promote PDF rendering + OCR + smart-parse to a foreground service so
    // the (potentially long) pipeline survives screen-off / app
    // minimisation.
    _acquireScanSlot('\uD83D\uDCC4 Scanning PDF\u2026');
    setState(() {
      _isPdf = true;
      _capturedImage = null;
      _scanState = _ScanState.scanning;
      _scanPhaseIdx = 0;
    });

    await Future<void>.delayed(
      Duration(milliseconds: _pdfScanPhases[0].ms),
    );
    if (!mounted) return;
    setState(() => _scanPhaseIdx = 1);

    // ── Step 4: Open + render + OCR with retries ──────────────────────────
    String ocrText;
    int pagesProcessed = 0;
    try {
      final processed = await _processPdfPages(
        bytes: workingBytes,
        path: workingPath,
      );
      ocrText = processed.text;
      pagesProcessed = processed.pages;
    } on _EncryptedPdfException {
      overall.stop();
      TLog.w(
        'AddExpense',
        '🔒 PDF is encrypted/password-protected (${overall.elapsedMilliseconds}ms)',
      );
      _resetScanIdle();
      _showPdfError(
        'This PDF is password-protected. Open it elsewhere and re-export an '
        'unprotected copy.',
      );
      return;
    } catch (e, st) {
      overall.stop();
      TLog.e(
        'AddExpense',
        'PDF processing failed (${overall.elapsedMilliseconds}ms)',
        error: e,
        st: st,
      );
      _resetScanIdle();
      // Android's PdfRenderer swallows SecurityException into a generic
      // "Unknown error", so we can't reliably tell encrypted apart from
      // damaged here — surface both possibilities in the user copy.
      _showPdfError(
        'Could not read this PDF. It may be password-protected, damaged, or '
        'in an unsupported format.',
      );
      return;
    }

    overall.stop();
    TLog.i(
      'AddExpense',
      '📄 PDF OCR done in ${overall.elapsedMilliseconds}ms, '
      '${ocrText.length} chars from $pagesProcessed page(s)',
    );

    if (ocrText.trim().isEmpty) {
      TLog.w(
        'AddExpense',
        '📄 PDF rendered ($pagesProcessed page(s)) but OCR returned no text — '
        'image-only or blank document',
      );
      _resetScanIdle();
      _showPdfError(
        'No readable text found in this PDF. Try a sharper scan or a '
        'text-based PDF.',
      );
      return;
    }

    await _runExtractionPipeline(ocrText, 'pdf');
  }

  /// Resolve an arbitrary [PlatformFile] into something we can actually feed
  /// to `pdfx`. Handles three distinct provider behaviours:
  ///
  ///   1. Bytes already loaded by `file_picker` (`withData: true` succeeded).
  ///   2. A cached local `path` (most common on Android/iOS).
  ///   3. Only a `readStream` (some custom SAF DocumentsProviders / iCloud).
  ///
  /// At least one of [bytes] or [path] is returned non-null on success.
  Future<({Uint8List? bytes, String? path})> _resolvePdfSource(
    PlatformFile picked,
  ) async {
    if (picked.bytes != null && picked.bytes!.isNotEmpty) {
      TLog.d('AddExpense', '📄 Using in-memory bytes (${picked.bytes!.length} B)');
      return (bytes: picked.bytes, path: null);
    }

    final p = picked.path;
    if (p != null) {
      try {
        final f = File(p);
        if (await f.exists()) {
          final size = await f.length();
          if (size > 0) {
            TLog.d('AddExpense', '📄 Using cached file path ($size B): $p');
            return (bytes: null, path: p);
          }
        }
      } catch (e) {
        TLog.w('AddExpense', 'Path probe failed for $p', error: e);
      }
    }

    final stream = picked.readStream;
    if (stream != null) {
      final tempDir = await getTemporaryDirectory();
      final outPath =
          '${tempDir.path}/nexus_picked_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final sink = File(outPath).openWrite();
      var bytesWritten = 0;
      try {
        await for (final chunk in stream) {
          sink.add(chunk);
          bytesWritten += chunk.length;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      TLog.d('AddExpense', '📄 Drained readStream → $outPath ($bytesWritten B)');
      if (bytesWritten > 0) {
        return (bytes: null, path: outPath);
      }
    }

    return (bytes: null, path: null);
  }

  /// Open the PDF, render up to 5 pages, OCR each one. Every step has a
  /// dedicated retry/fallback so a single bad page never breaks the whole
  /// flow:
  ///
  ///   * `PdfDocument.open*` retries once on transient I/O errors and
  ///     surfaces [_EncryptedPdfException] when the failure is
  ///     password-related.
  ///   * Page rendering walks 2.0 → 1.5 → 1.0 scale, so an OOM at high
  ///     resolution falls back to a smaller bitmap instead of aborting.
  ///   * OCR retries once on timeout/transient ML Kit failures.
  ///
  /// Returns the concatenated OCR text and the number of pages that produced
  /// any text. Throws on hard failures (no usable source, all attempts
  /// exhausted, encryption).
  Future<({String text, int pages})> _processPdfPages({
    Uint8List? bytes,
    String? path,
  }) async {
    pdfx.PdfDocument? document;
    Object? lastOpenError;

    for (var attempt = 0; attempt < 2 && document == null; attempt++) {
      try {
        if (bytes != null) {
          document = await pdfx.PdfDocument.openData(bytes);
        } else if (path != null) {
          document = await pdfx.PdfDocument.openFile(path);
        } else {
          throw StateError('No PDF source provided');
        }
      } catch (e, st) {
        lastOpenError = e;
        final msg = e.toString().toLowerCase();
        if (msg.contains('password') ||
            msg.contains('encrypted') ||
            msg.contains('crypt')) {
          throw _EncryptedPdfException();
        }
        TLog.w(
          'AddExpense',
          'PdfDocument open attempt ${attempt + 1} failed',
          error: e,
          st: st,
        );
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }

    if (document == null) {
      throw lastOpenError ?? StateError('Failed to open PDF');
    }

    final maxPages = min(document.pagesCount, 5);
    final tempDir = await getTemporaryDirectory();
    TLog.d(
      'AddExpense',
      'PDF pages: ${document.pagesCount}, processing $maxPages',
    );

    final buffer = StringBuffer();
    var pagesWithText = 0;

    try {
      for (var i = 1; i <= maxPages; i++) {
        if (!mounted) break;

        // pdfx caches PdfPage objects in `_pages[pageNumber-1]` and does NOT
        // clear that slot on `page.close()`. Closing the page between scale
        // retries would make every subsequent `getPage(i)` return the same
        // already-closed object, and `page.render()` would throw
        // `PdfPageAlreadyClosedException`. So we open the page exactly once
        // and only retry the `render` call across progressively smaller
        // scales (the OOM-prone step).
        Uint8List? renderedBytes;
        pdfx.PdfPage? page;
        try {
          try {
            page = await document.getPage(i);
          } catch (e, st) {
            TLog.w(
              'AddExpense',
              'Page $i: getPage failed',
              error: e,
              st: st,
            );
          }

          if (page != null) {
            for (final scale in const <double>[2.0, 1.5, 1.0]) {
              try {
                final image = await page.render(
                  width: page.width * scale,
                  height: page.height * scale,
                  format: pdfx.PdfPageImageFormat.png,
                );
                renderedBytes = image?.bytes;
                if (renderedBytes != null) break;
              } catch (e) {
                TLog.w(
                  'AddExpense',
                  'Page $i render at ${scale}x failed',
                  error: e,
                );
              }
            }
          }
        } finally {
          try {
            await page?.close();
          } catch (_) {}
        }

        if (renderedBytes == null) {
          TLog.w(
            'AddExpense',
            'Page $i: skipping (all render attempts failed)',
          );
          continue;
        }

        final tempPath = '${tempDir.path}/nexus_pdf_p$i.png';
        try {
          await File(tempPath).writeAsBytes(renderedBytes);
        } catch (e, st) {
          TLog.w(
            'AddExpense',
            'Page $i: temp write failed',
            error: e,
            st: st,
          );
          continue;
        }

        if (i == 1 && mounted) {
          setState(() => _capturedImage = File(tempPath));
        }

        var pageText = '';
        for (var attempt = 0; attempt < 2; attempt++) {
          TextRecognizer? recognizer;
          try {
            recognizer = TextRecognizer();
            final ocrResult = await recognizer
                .processImage(InputImage.fromFilePath(tempPath))
                .timeout(const Duration(seconds: 30));
            pageText = ocrResult.text;
            break;
          } on TimeoutException {
            TLog.w(
              'AddExpense',
              'Page $i OCR timed out (attempt ${attempt + 1})',
            );
          } catch (e) {
            TLog.w(
              'AddExpense',
              'Page $i OCR failed (attempt ${attempt + 1})',
              error: e,
            );
          } finally {
            try {
              await recognizer?.close();
            } catch (_) {}
          }
        }

        if (pageText.isNotEmpty) {
          buffer.writeln(pageText);
          pagesWithText++;
        }

        if (i > 1) {
          try {
            await File(tempPath).delete();
          } catch (_) {}
        }
      }
    } finally {
      try {
        await document.close();
      } catch (_) {}
    }

    return (text: buffer.toString(), pages: pagesWithText);
  }

  void _resetScanIdle() {
    // Release the FG-service slot whenever we drop back to idle —
    // there's no scan pipeline left to protect from Doze.
    _releaseScanSlot();
    if (!mounted) return;
    setState(() {
      _scanState = _ScanState.idle;
      _capturedImage = null;
      _isPdf = false;
    });
  }

  void _showPdfError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.fileText, size: 16, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.95),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  /// Shared extraction pipeline: smart-parse → regex fallback → local categorize → apply results.
  ///
  /// Wrapped in a try-finally so the FG-service slot is always released
  /// even if `widget.categorize` / `widget.smartParse` throws an
  /// uncaught exception mid-flight. Without this guard a transient AI
  /// failure could leave the OS-level wakelock held until the modal is
  /// disposed, which on long-lived sessions could surface as a stuck
  /// "✨ Nexus AI working" notification.
  Future<void> _runExtractionPipeline(String ocrText, String source) async {
    try {
      await _runExtractionPipelineInner(ocrText, source);
    } finally {
      _releaseScanSlot();
    }
  }

  Future<void> _runExtractionPipelineInner(String ocrText, String source) async {
    if (!mounted) return;
    setState(() => _scanPhaseIdx = 2);
    await Future<void>.delayed(
      Duration(milliseconds: _scanPhases[2].ms),
    );

    if (!mounted) return;
    setState(() => _scanPhaseIdx = 3);

    String extractedDesc = '';
    String extractedAmount = '';
    String extractedCategory = 'Others';
    String extractedConfidence = 'default';
    String extractedReasoning = '';
    String extractedBank = '';
    String extractedCardType = '';

    if (ocrText.isNotEmpty) {
      final trimmedOcr =
          ocrText.length > 5000 ? ocrText.substring(0, 5000) : ocrText;

      if (widget.smartParse != null) {
        try {
          final parsed = await widget.smartParse!(trimmedOcr);
          if (parsed != null && mounted) {
            extractedDesc = parsed.description;
            extractedAmount =
                parsed.amount > 0 ? parsed.amount.toStringAsFixed(0) : '';
            extractedCategory = parsed.category;
            extractedBank = parsed.bank;
            extractedCardType = parsed.cardType;
            extractedConfidence = 'matched';
            extractedReasoning = 'AI extracted from $source';
          }
        } catch (e) {
          TLog.w('AddExpense', 'Smart-parse failed for $source', error: e);
        }
      }

      if (extractedAmount.isEmpty) {
        final amtMatch = RegExp(
          r'(?:total|invoice total|grand total|amount|net)[:\s]*(?:rs\.?|₹)?\s*([\d,]+(?:\.\d+)?)',
          caseSensitive: false,
        ).firstMatch(trimmedOcr);
        if (amtMatch != null) {
          extractedAmount = amtMatch.group(1)!.replaceAll(',', '');
        }
      }

      if (extractedDesc.isEmpty) {
        final nameMatch = RegExp(
          r'(?:restaurant name|merchant|store|shop|from)[:\s]*(.+)',
          caseSensitive: false,
        ).firstMatch(trimmedOcr);
        if (nameMatch != null) {
          extractedDesc = nameMatch.group(1)!.trim();
        }
      }

      if (extractedConfidence == 'default' && extractedDesc.isNotEmpty) {
        AICategoryResult r;
        if (widget.categorize != null) {
          r = await widget.categorize!(extractedDesc, widget.learnings);
        } else {
          r = categorizeLocal(extractedDesc, widget.learnings);
        }
        if (mounted) {
          extractedCategory = r.category;
          extractedConfidence = r.confidence;
          extractedReasoning = r.reasoning;
        }
      }
    }

    await Future<void>.delayed(
      Duration(milliseconds: _scanPhases[3].ms),
    );
    if (!mounted) return;

    // Resolve bank/cardType: use LLM result if valid, else default to CASH
    final finalBank = extractedBank.isNotEmpty &&
            widget.banks.contains(extractedBank)
        ? extractedBank
        : 'CASH';
    final finalCardType = finalBank == 'CASH'
        ? 'Cash'
        : (extractedCardType.isNotEmpty ? extractedCardType : 'DB');

    setState(() {
      if (extractedAmount.isNotEmpty) _amountCtrl.text = extractedAmount;
      if (extractedDesc.isNotEmpty) _descCtrl.text = extractedDesc;
      _category = extractedCategory;
      _aiCategory = extractedCategory;
      _confidence = extractedConfidence;
      _aiReasoning = extractedReasoning;
      _categoryIsManual = false;
      _bank = finalBank;
      _cardType = finalCardType;
      _scanState = _ScanState.done;
    });
    // Slot release happens in the wrapping [_runExtractionPipeline]'s
    // finally block so it fires on success and on every unexpected
    // throw alike.
  }

  // ── Teach AI ───────────────────────────────────────────────────────────────

  Future<void> _teachAi() async {
    final d = _descCtrl.text.trim();
    if (d.isEmpty || _isLearning || _hasLearned) return;
    setState(() => _isLearning = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    widget.onTeachAI(d, _category);
    setState(() {
      _isLearning = false;
      _hasLearned = true;
      _confidence = 'learned';
      _categoryIsManual = false;
      _aiCategory = _category;
    });
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColors>()!;
        return AlertDialog(
          backgroundColor: colors.bg1,
          title: Text(
            'Teach AI',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          content: Text(
            'AI will remember this description pattern for category "$_category".',
            style: GoogleFonts.plusJakartaSans(color: colors.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'OK',
                style:
                    GoogleFonts.plusJakartaSans(color: AppColors.accent),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  void _submit() {
    final n = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    final desc = _descCtrl.text.trim();
    final hasAmount = n != null && n > 0;
    final hasDesc = desc.isNotEmpty;
    final hasBank = _bank.isNotEmpty;
    final hasCardType = _cardType.isNotEmpty;

    if (!hasAmount || !hasDesc || !hasBank || !hasCardType) {
      setState(() => _hasAttemptedSubmit = true);
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
      return;
    }

    final finalIsManual = _categoryIsManual && !_hasLearned;
    final conf = _categoryIsManual && !_hasLearned ? 'manual' : _confidence;
    final resolvedDate = _resolveDate(_dateOption);

    widget.onAdd(
      ExpenseSubmitPayload(
        amount: n!,
        description: desc,
        category: _category,
        bank: _bank,
        cardType: _cardType,
        isManualCategory: _categoryIsManual,
        date: resolvedDate.toIso8601String(),
        comments: _commentsCtrl.text.trim(),
      ),
      finalIsManual,
      SuccessMeta(
        confidence: conf,
        reasoning: _aiReasoning,
        capturedImagePath: null,
      ),
    );
    Navigator.of(context).pop();
  }

  bool get _canSubmit {
    final n = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    return n != null &&
        n > 0 &&
        _descCtrl.text.trim().isNotEmpty &&
        _bank.isNotEmpty &&
        _cardType.isNotEmpty;
  }

  bool get _showWand =>
      !_hasLearned &&
      _descCtrl.text.trim().length >= 3 &&
      (_categoryIsManual || _confidence == 'default');

  bool get _showBankBlock =>
      _mode == 1 ||
      _scanState == _ScanState.done ||
      (_mode == 2 && !_voiceParsing && _amountCtrl.text.isNotEmpty);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      Theme.of(context).textTheme,
    );
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.text4,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add Expense',
                      style: textTheme.titleMedium?.copyWith(
                        color: colors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Mode selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ModeTabs(
                mode: _mode,
                colors: colors,
                textTheme: textTheme,
                onSelect: (m) {
                  if (m == _mode) return;
                  // Stop speech engine when leaving voice mode
                  if (_mode == 2 && _voice.isListening) {
                    unawaited(_voice.cancel());
                  }
                  setState(() {
                    _mode = m;
                    _hasAttemptedSubmit = false;
                    if (m == 0) {
                      _scanState = _ScanState.idle;
                      _capturedImage = null;
                      _isPdf = false;
                      _amountCtrl.clear();
                      _descCtrl.clear();
                    }
                    if (m != 2) {
                      _isListening = false;
                      _voiceParsing = false;
                    }
                  });
                },
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: AnimatedBuilder(
                  animation: _shakeCtrl,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(_shakeOffset, 0),
                    child: child,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_mode == 0) _buildScan(colors, textTheme),
                      if (_mode == 1) _buildManual(colors, textTheme),
                      if (_mode == 2) _buildVoice(colors, textTheme),
                      if (_showBankBlock) ...[
                        const SizedBox(height: 12),
                        _buildDateSelector(colors, textTheme),
                        const SizedBox(height: 16),
                        _buildBankPayment(colors, textTheme),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Date selector ──────────────────────────────────────────────────────────

  Widget _buildDateSelector(AppColors colors, TextTheme textTheme) {
    final resolvedDate = _resolveDate(_dateOption);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormLabel('EXPENSE DATE', colors),
        Row(
          children: [
            for (final opt in _DateOption.values) ...[
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: opt == _DateOption.values.last ? 0 : 8,
                  ),
                  child: ChoiceChip(
                    label: Text(
                      _dateLabel(opt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: _dateOption == opt,
                    onSelected: (_) => setState(() => _dateOption = opt),
                    selectedColor: const Color(0x380D59F2),
                    labelStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _dateOption == opt
                          ? AppColors.accent
                          : colors.text3,
                    ),
                    side: BorderSide(
                      color: _dateOption == opt
                          ? AppColors.accent.withValues(alpha: 0.5)
                          : colors.border,
                    ),
                    backgroundColor: colors.bg2,
                  ),
                ),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '📅 ${_formatDateShort(resolvedDate)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accent.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }

  // ── Voice mode ─────────────────────────────────────────────────────────────

  Widget _buildVoice(AppColors colors, TextTheme textTheme) {
    if (_voiceParsing) {
      return _VoiceParsingLoader(
        voiceText: _voiceText,
        colors: colors,
        textTheme: textTheme,
      );
    }

    if (_amountCtrl.text.isNotEmpty && _mode == 2) {
      return _buildManual(colors, textTheme);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _isListening
                  ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                  : AppColors.accent.withValues(alpha: 0.3),
            ),
            gradient: RadialGradient(
              colors: [
                (_isListening
                        ? const Color(0xFFEF4444)
                        : AppColors.accent)
                    .withValues(alpha: _isListening ? 0.12 : 0.06),
                colors.bg1.withValues(alpha: 0),
              ],
              center: const Alignment(0, -0.3),
              radius: 1.2,
            ),
          ),
          child: Column(
            children: [
              Text(
                _isListening ? 'Listening…' : 'Voice Expense',
                style: textTheme.titleMedium?.copyWith(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isListening
                    ? 'Release to parse'
                    : 'Hold the mic and speak naturally',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.text4,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _HoldToRecordMic(
                isListening: _isListening,
                onHoldStart: _startListening,
                onHoldEnd: _stopListeningAndParse,
              ),
              const SizedBox(height: 16),
              Text(
                _isListening ? '🔴 Recording' : 'Hold to record',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _isListening
                      ? const Color(0xFFEF4444)
                      : colors.text5,
                ),
              ),
              if (_isListening)
                ValueListenableBuilder<String>(
                  valueListenable: _voiceTextNotifier,
                  builder: (context, partial, _) {
                    if (partial.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.bg2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                partial,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colors.text,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              if (!_isListening) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FeaturePill(text: '🔢 Auto Amount', colors: colors),
                    _FeaturePill(text: '🏦 Bank Detect', colors: colors),
                    _FeaturePill(text: '🏷️ AI Category', colors: colors),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Scan mode ──────────────────────────────────────────────────────────────

  Widget _buildScan(AppColors colors, TextTheme textTheme) {
    if (_scanState == _ScanState.idle) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x667C3AED)),
          gradient: RadialGradient(
            colors: [
              const Color(0x147C3AED),
              colors.bg1.withValues(alpha: 0),
            ],
            center: const Alignment(0, -0.3),
            radius: 1.2,
          ),
        ),
        child: Column(
          children: [
            const Text('🧾', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            Text(
              'Scan Your Bill',
              style: textTheme.titleMedium?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI will extract the total amount, merchant name and automatically categorize. Supports photos and PDF bills.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colors.text4,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _FeaturePill(text: '🔢 Auto Amount', colors: colors),
                _FeaturePill(text: '🏪 Shop Name', colors: colors),
                _FeaturePill(text: '🏷️ AI Category', colors: colors),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(LucideIcons.camera, size: 16),
                    label: const Text('Camera'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: Icon(LucideIcons.image,
                        size: 16, color: colors.text2),
                    label: Text(
                      'Gallery',
                      style: TextStyle(color: colors.text2),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickPdf,
                    icon: Icon(LucideIcons.fileText,
                        size: 16, color: const Color(0xFFEF4444)),
                    label: Text(
                      'PDF',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.text2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_scanState == _ScanState.scanning || _scanState == _ScanState.done) {
      final phases = _isPdf ? _pdfScanPhases : _scanPhases;
      final phase = phases[_scanPhaseIdx];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 200,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_capturedImage != null)
                    LocalFileImage(
                      path: _capturedImage!.path,
                      fit: BoxFit.cover,
                    )
                  else if (_isPdf)
                    Container(
                      color: colors.bg3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.fileText,
                              size: 48,
                              color: const Color(0xFFEF4444).withValues(alpha: 0.7)),
                          const SizedBox(height: 8),
                          Text(
                            'Processing PDF…',
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.text3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ColoredBox(color: colors.bg3),
                  if (_scanState == _ScanState.scanning)
                    Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Text(phase.emoji,
                                    style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    phase.text,
                                    style:
                                        textTheme.labelLarge?.copyWith(
                                      color: const Color(0xFFC4B5FD),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_scanState == _ScanState.done)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xE622C55E),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xB322C55E),
                                  blurRadius: 28,
                                ),
                              ],
                            ),
                            child: const Icon(
                              LucideIcons.check,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isPdf ? 'PDF Extracted ✓' : 'Bill Extracted ✓',
                            style: textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF86EFAC),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_scanState == _ScanState.done)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _scanState = _ScanState.idle;
                              _capturedImage = null;
                              _isPdf = false;
                              _hasAttemptedSubmit = false;
                              _amountCtrl.clear();
                              _descCtrl.clear();
                              _bank = '';
                              _cardType = '';
                              _category = 'Others';
                              _aiCategory = null;
                              _confidence = 'default';
                              _aiReasoning = '';
                              _categoryIsManual = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.rotateCcw,
                                  size: 11,
                                  color: colors.text2,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Rescan',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colors.text2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_scanState == _ScanState.done) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x1422C55E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x3822C55E)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.sparkles,
                      size: 14, color: Color(0xFF34D399)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI extracted the bill — review & edit before logging',
                      style: textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF86EFAC),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormLabel('AMOUNT', colors),
            _AmountField(
              controller: _amountCtrl,
              colors: colors,
              textTheme: textTheme,
              large: false,
              hasError: _amountError,
              onChanged: (_) => setState(() {}),
            ),
            _FormLabel('MERCHANT / DESCRIPTION', colors),
            TextField(
              controller: _descCtrl,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w500,
              ),
              decoration: _fieldDecoration(colors, hasError: _descError).copyWith(
                hintText: 'e.g. Swiggy, Apollo Pharmacy…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_descError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Enter a description',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _CategorySection(
              colors: colors,
              textTheme: textTheme,
              category: _category,
              aiCategory: _aiCategory,
              confidence: _confidence,
              categoryIsManual: _categoryIsManual,
              showWand: _showWand,
              isLearning: _isLearning,
              hasLearned: _hasLearned,
              showPicker: _showCategoryPicker,
              onTogglePicker: () => setState(
                () => _showCategoryPicker = !_showCategoryPicker,
              ),
              onSelectCategory: (c) {
                setState(() {
                  _category = c;
                  _categoryIsManual = true;
                  _hasLearned = false;
                  _showCategoryPicker = false;
                });
              },
              onTeachAI: _teachAi,
            ),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }

  // ── Manual mode ────────────────────────────────────────────────────────────

  Widget _buildManual(AppColors colors, TextTheme textTheme) {
    final amountPreview = double.tryParse(
      _amountCtrl.text.replaceAll(',', ''),
    );
    const errorRed = Color(0xFFEF4444);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _amountError
                  ? errorRed.withValues(alpha: 0.7)
                  : const Color(0x477C3AED),
              width: _amountError ? 1.5 : 1,
            ),
            gradient: LinearGradient(
              colors: _amountError
                  ? [const Color(0x1FEF4444), const Color(0x0FEF4444)]
                  : [const Color(0x1F7C3AED), const Color(0x0F6366F1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '₹',
                    style: textTheme.displaySmall?.copyWith(
                      color: _amountError
                          ? errorRed.withValues(alpha: 0.7)
                          : const Color(0xB3A78BFA),
                      fontWeight: FontWeight.w800,
                      fontSize: 30,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: textTheme.displaySmall?.copyWith(
                        color: colors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 36,
                        letterSpacing: -0.5,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '0',
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_amountCtrl.text.isNotEmpty &&
                      (double.tryParse(
                              _amountCtrl.text.replaceAll(',', '')) ??
                          0) >
                      0)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x3322C55E),
                        border: Border.all(color: const Color(0x6622C55E)),
                      ),
                      child: const Icon(
                        LucideIcons.check,
                        size: 14,
                        color: Color(0xFF34D399),
                      ),
                    ),
                ],
              ),
              if (amountPreview != null && amountPreview > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    formatCurrency(amountPreview),
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.text3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_amountError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Enter an amount greater than 0',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: errorRed,
              ),
            ),
          ),
        const SizedBox(height: 16),
        _FormLabel('DESCRIPTION', colors),
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextField(
              controller: _descCtrl,
              style: textTheme.bodyMedium?.copyWith(color: colors.text),
              decoration: _fieldDecoration(colors, hasError: _descError).copyWith(
                hintText: 'e.g. Swiggy dinner, Uber ride…',
              ),
              onChanged: (_) {
                setState(() {
                  if (_hasLearned) _hasLearned = false;
                });
              },
            ),
            if (_aiThinking)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (i) => Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _DotPulse(delay: i * 150),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_descError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Enter a description',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: errorRed,
              ),
            ),
          ),
        const SizedBox(height: 8),
        _CategorySection(
          colors: colors,
          textTheme: textTheme,
          category: _category,
          aiCategory: _aiCategory,
          confidence: _confidence,
          categoryIsManual: _categoryIsManual,
          showWand: _showWand,
          isLearning: _isLearning,
          hasLearned: _hasLearned,
          showPicker: _showCategoryPicker,
          onTogglePicker: () =>
              setState(() => _showCategoryPicker = !_showCategoryPicker),
          onSelectCategory: (c) {
            setState(() {
              _category = c;
              _categoryIsManual = true;
              _hasLearned = false;
              _showCategoryPicker = false;
            });
          },
          onTeachAI: _teachAi,
        ),
      ],
    );
  }

  // ── Bank / payment ─────────────────────────────────────────────────────────

  Widget _buildBankPayment(AppColors colors, TextTheme textTheme) {
    const errorRed = Color(0xFFEF4444);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _FormLabel('BANK', colors)),
            if (_bankError)
              Text(
                'Required',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: errorRed,
                ),
              ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: _bankError
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: errorRed.withValues(alpha: 0.4),
                  ),
                )
              : null,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: _bankError
                ? const EdgeInsets.symmetric(horizontal: 4)
                : EdgeInsets.zero,
            child: Row(
              children: [
                for (final b in widget.banks) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(b),
                      selected: _bank == b,
                      onSelected: (_) => setState(() {
                        _bank = b;
                        if (b == 'CASH') {
                          _cardType = 'Cash';
                        } else if (_cardType == 'Cash' || _cardType.isEmpty) {
                          _cardType = '';
                        }
                      }),
                      selectedColor: const Color(0x387C3AED),
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _bank == b
                            ? const Color(0xFFA78BFA)
                            : colors.text3,
                      ),
                      side: BorderSide(
                        color: _bank == b
                            ? const Color(0xA67C3AED)
                            : _bankError
                                ? errorRed.withValues(alpha: 0.3)
                                : colors.border,
                      ),
                      backgroundColor: colors.bg2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _FormLabel('PAYMENT TYPE', colors)),
            if (_cardTypeError)
              Text(
                'Required',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: errorRed,
                ),
              ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: _cardTypeError
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: errorRed.withValues(alpha: 0.4),
                  ),
                )
              : null,
          child: Row(
            children: [
              for (final ct in expenseCardTypes) ...[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: ct == expenseCardTypes.last ? 0 : 8,
                      left: _cardTypeError && ct == expenseCardTypes.first
                          ? 4
                          : 0,
                    ),
                    child: Builder(builder: (context) {
                      final isCashBank = _bank == 'CASH';
                      final isCashType = ct == 'Cash';
                      final isDisabled = isCashBank
                          ? !isCashType
                          : (_bank.isNotEmpty && isCashType);
                      return ChoiceChip(
                        label: Text(
                          '${_cardEmoji(ct)} $ct',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _cardType == ct,
                        onSelected: isDisabled
                            ? null
                            : (_) => setState(() => _cardType = ct),
                        selectedColor: const Color(0x2E34D399),
                        labelStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDisabled
                              ? colors.text5
                              : _cardType == ct
                                  ? const Color(0xFF34D399)
                                  : colors.text3,
                        ),
                        side: BorderSide(
                          color: _cardType == ct
                              ? const Color(0x8C34D399)
                              : _cardTypeError
                                  ? errorRed.withValues(alpha: 0.3)
                                  : colors.border,
                        ),
                        backgroundColor: colors.bg2,
                        disabledColor: colors.bg2,
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CommentsField(
          controller: _commentsCtrl,
          colors: colors,
          textTheme: textTheme,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(LucideIcons.check, size: 18, color: Colors.white),
          label: Text(
            'Log Expense',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: Colors.white,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  static String _cardEmoji(String ct) {
    if (ct == 'Cash') return '💵';
    if (ct == 'CC') return '💳';
    return '🏦';
  }

  InputDecoration _fieldDecoration(AppColors colors, {bool hasError = false}) {
    const errorRed = Color(0xFFEF4444);
    final borderColor = hasError ? errorRed.withValues(alpha: 0.7) : colors.border;
    return InputDecoration(
      filled: true,
      fillColor: hasError
          ? errorRed.withValues(alpha: 0.06)
          : colors.bg2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor, width: hasError ? 1.5 : 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor, width: hasError ? 1.5 : 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: hasError ? errorRed : colors.border,
          width: hasError ? 1.5 : 1,
        ),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

enum _ScanState { idle, scanning, done }

/// Sentinel thrown by [_processPdfPages] when the underlying PDF requires a
/// password. Caught at the [_pickPdf] boundary to render a dedicated error
/// message instead of the generic "could not read this PDF" copy.
class _EncryptedPdfException implements Exception {}

// ─── Mode tabs (3 modes now) ─────────────────────────────────────────────────

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({
    required this.mode,
    required this.colors,
    required this.textTheme,
    required this.onSelect,
  });

  final int mode;
  final AppColors colors;
  final TextTheme textTheme;
  final void Function(int mode) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Scan-Bill tab is hidden on web (on-device OCR is Android-only).
          if (PlatformCapabilities.canUseMlKitOcr)
            Expanded(
              child: _ModeCell(
                selected: mode == 0,
                icon: '📷',
                title: 'Scan Bill',
                subtitle: 'AI Powered',
                onTap: () => onSelect(0),
              ),
            ),
          Expanded(
            child: _ModeCell(
              selected: mode == 1,
              icon: '✏️',
              title: 'Manual',
              subtitle: 'Type It In',
              onTap: () => onSelect(1),
            ),
          ),
          Expanded(
            child: _ModeCell(
              selected: mode == 2,
              icon: '🎤',
              title: 'Voice',
              subtitle: 'Speak It',
              onTap: () => onSelect(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCell extends StatelessWidget {
  const _ModeCell({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Material(
      color: selected ? const Color(0xFF6366F1) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : colors.text3,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 8,
                        color: selected
                            ? Colors.white.withValues(alpha: 0.6)
                            : colors.text5,
                        letterSpacing: 0.3,
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
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text, this.colors);

  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: colors.text4,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

/// Optional free-form "Comments" / reminder field shown across all add-expense
/// flows (manual, voice, PDF/scan). Live character counter, collapses to a
/// single helper line until tapped. Stored verbatim on the expense.
class _CommentsField extends StatefulWidget {
  const _CommentsField({
    required this.controller,
    required this.colors,
    required this.textTheme,
  });

  final TextEditingController controller;
  final AppColors colors;
  final TextTheme textTheme;

  @override
  State<_CommentsField> createState() => _CommentsFieldState();
}

class _CommentsFieldState extends State<_CommentsField> {
  static const int _maxChars = 280;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final textTheme = widget.textTheme;
    final len = widget.controller.text.characters.length;
    final hasText = widget.controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  const Text('📝', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  _FormLabel('COMMENTS', colors),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'optional',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: colors.text5,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasText)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$len/$_maxChars',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: len > _maxChars
                        ? const Color(0xFFEF4444)
                        : colors.text5,
                  ),
                ),
              ),
          ],
        ),
        TextField(
          controller: widget.controller,
          minLines: 1,
          maxLines: 4,
          maxLength: _maxChars,
          textCapitalization: TextCapitalization.sentences,
          style: textTheme.bodyMedium?.copyWith(color: colors.text),
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
              null,
          decoration: InputDecoration(
            filled: true,
            fillColor: colors.bg2,
            hintText: 'Add a reminder or note — e.g. "split with Riya", '
                '"reimburse from office"',
            hintMaxLines: 2,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: colors.text5,
              height: 1.4,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(
                LucideIcons.stickyNote,
                size: 16,
                color: hasText ? AppColors.accent : colors.text4,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: hasText
                    ? AppColors.accent.withValues(alpha: 0.4)
                    : colors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.colors,
    required this.textTheme,
    required this.large,
    this.hasError = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final AppColors colors;
  final TextTheme textTheme;
  final bool large;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    const errorRed = Color(0xFFEF4444);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: hasError ? errorRed.withValues(alpha: 0.06) : colors.bg2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError ? errorRed.withValues(alpha: 0.7) : colors.border,
              width: hasError ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(
                '₹',
                style: textTheme.titleLarge?.copyWith(
                  color: hasError
                      ? errorRed.withValues(alpha: 0.7)
                      : colors.text4,
                  fontWeight: FontWeight.w700,
                  fontSize: large ? 28 : 22,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: textTheme.titleLarge?.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: large ? 32 : 26,
                    letterSpacing: -0.5,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Enter an amount greater than 0',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: errorRed,
              ),
            ),
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }
}

// ─── Category section (supports 26 categories) ──────────────────────────────

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.colors,
    required this.textTheme,
    required this.category,
    required this.aiCategory,
    required this.confidence,
    required this.categoryIsManual,
    required this.showWand,
    required this.isLearning,
    required this.hasLearned,
    required this.showPicker,
    required this.onTogglePicker,
    required this.onSelectCategory,
    required this.onTeachAI,
  });

  final AppColors colors;
  final TextTheme textTheme;
  final String category;
  final String? aiCategory;
  final String confidence;
  final bool categoryIsManual;
  final bool showWand;
  final bool isLearning;
  final bool hasLearned;
  final bool showPicker;
  final VoidCallback onTogglePicker;
  final void Function(String) onSelectCategory;
  final VoidCallback onTeachAI;

  @override
  Widget build(BuildContext context) {
    final catColor =
        AppColors.categoryColors[category] ?? AppColors.accent;
    final icon = AppColors.categoryIcons[category] ?? '📦';

    Widget? badge;
    if (!categoryIsManual && confidence != 'default') {
      final meta = _confBadge(confidence);
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: meta.bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.sparkles, size: 8, color: meta.fg),
            const SizedBox(width: 4),
            Text(
              _confidenceBadgeLabel(confidence),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: meta.fg,
              ),
            ),
          ],
        ),
      );
    } else if (hasLearned) {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x2E818CF8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.brain,
                size: 8, color: Color(0xFF818CF8)),
            const SizedBox(width: 4),
            Text(
              'AI Learned ✓',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF818CF8),
              ),
            ),
          ],
        ),
      );
    } else if (categoryIsManual) {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x26FBBF24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '✎ Manual',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFBBF24),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormLabel('CATEGORY', colors),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Material(
                color: colors.bg2,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTogglePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: showPicker
                            ? catColor.withValues(alpha: 0.5)
                            : colors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(icon,
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            category,
                            style: textTheme.titleSmall?.copyWith(
                              color: catColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          badge,
                          const SizedBox(width: 6),
                        ],
                        Icon(
                          LucideIcons.chevronDown,
                          size: 13,
                          color: colors.text4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showWand) ...[
              const SizedBox(width: 8),
              Material(
                color: isLearning
                    ? const Color(0x33F59E0B)
                    : const Color(0x337C3AED),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTeachAI,
                  child: Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isLearning
                            ? const Color(0x80F59E0B)
                            : const Color(0x807C3AED),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLearning
                              ? LucideIcons.brain
                              : LucideIcons.wand2,
                          size: 16,
                          color: isLearning
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFA78BFA),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isLearning ? 'LEARNING' : 'TEACH AI',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: isLearning
                                ? const Color(0xFFFCD34D)
                                : const Color(0xFFA78BFA),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (showWand && !isLearning)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              categoryIsManual
                  ? '🪄 Tap Teach AI to remember this correction for future similar expenses'
                  : '🪄 Pick the right category, then tap Teach AI so it learns for next time',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: colors.text4,
              ),
            ),
          ),
        if (hasLearned)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1A818CF8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x40818CF8)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.brain,
                      size: 12, color: Color(0xFF818CF8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI learned: future "$category" expenses like this will be auto-detected',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFA78BFA),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (showPicker) ...[
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.6,
            ),
            itemCount: expenseCategories.length,
            itemBuilder: (context, i) {
              final cat = expenseCategories[i];
              final c =
                  AppColors.categoryColors[cat] ?? AppColors.accent;
              final sel = category == cat;
              return Material(
                color: sel ? c.withValues(alpha: 0.13) : colors.bg2,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelectCategory(cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel
                            ? c.withValues(alpha: 0.7)
                            : colors.border,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          AppColors.categoryIcons[cat] ?? '📦',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            cat,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: sel ? c : colors.text3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  ({Color fg, Color bg}) _confBadge(String c) {
    switch (c) {
      case 'learned':
        return (
          fg: const Color(0xFF818CF8),
          bg: const Color(0x2E818CF8),
        );
      case 'matched':
        return (
          fg: const Color(0xFF34D399),
          bg: const Color(0x2E34D399),
        );
      default:
        return (
          fg: const Color(0x61FFFFFF),
          bg: const Color(0x12FFFFFF),
        );
    }
  }

  static String _confidenceBadgeLabel(String c) {
    switch (c) {
      case 'learned':
        return 'AI Learned';
      case 'matched':
        return 'AI Detected';
      default:
        return 'Undetected';
    }
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.text, required this.colors});

  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x2E7C3AED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x4D7C3AED)),
      ),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFA78BFA),
        ),
      ),
    );
  }
}

class _DotPulse extends StatefulWidget {
  const _DotPulse({required this.delay});

  final int delay;

  @override
  State<_DotPulse> createState() => _DotPulseState();
}

class _DotPulseState extends State<_DotPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    Future<void>.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_c),
      child: Container(
        width: 4,
        height: 4,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF818CF8),
        ),
      ),
    );
  }
}

// ─── Hold-to-Record mic button ──────────────────────────────────────────────

class _HoldToRecordMic extends StatefulWidget {
  const _HoldToRecordMic({
    required this.isListening,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool isListening;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  State<_HoldToRecordMic> createState() => _HoldToRecordMicState();
}

class _HoldToRecordMicState extends State<_HoldToRecordMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  /// Tracks the user's finger, NOT the engine state. The parent's
  /// `widget.isListening` flips only after the speech engine reaches its
  /// `listening` status (~50-200 ms after onHoldStart). On a faster tap,
  /// gating `onHoldEnd` with `widget.isListening` would skip the stop call
  /// and leave the engine recording silently forever.
  bool _userHolding = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didUpdateWidget(_HoldToRecordMic old) {
    super.didUpdateWidget(old);
    if (widget.isListening && !old.isListening) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.isListening && old.isListening) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent _) {
    if (_userHolding) return;
    _userHolding = true;
    widget.onHoldStart();
  }

  void _onUp(PointerUpEvent _) {
    if (!_userHolding) return;
    _userHolding = false;
    widget.onHoldEnd();
  }

  void _onCancel(PointerCancelEvent _) {
    if (!_userHolding) return;
    _userHolding = false;
    widget.onHoldEnd();
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);

    return Listener(
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: SizedBox(
        width: 140,
        height: 140,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer ring — uses opacity-only pulse (no size change)
            AnimatedOpacity(
              opacity: widget.isListening ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  final t = _pulseCtrl.value;
                  return Transform.scale(
                    scale: 1.0 + t * 0.12,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: red.withValues(alpha: 0.12 + t * 0.08),
                          width: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Inner ring — subtle breathing
            AnimatedOpacity(
              opacity: widget.isListening ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  final t = _pulseCtrl.value;
                  return Transform.scale(
                    scale: 1.0 + t * 0.06,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: red.withValues(alpha: 0.15 + t * 0.1),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Main mic circle — fixed size, animated color
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: widget.isListening
                      ? [
                          red.withValues(alpha: 0.35),
                          red.withValues(alpha: 0.12),
                        ]
                      : [
                          AppColors.accent.withValues(alpha: 0.15),
                          AppColors.accent.withValues(alpha: 0.04),
                        ],
                ),
                border: Border.all(
                  color: widget.isListening
                      ? red.withValues(alpha: 0.6)
                      : AppColors.accent.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: widget.isListening
                    ? [
                        BoxShadow(
                          color: red.withValues(alpha: 0.25),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                LucideIcons.mic,
                color: widget.isListening ? red : AppColors.accent,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Voice parsing loader (creative, real-time) ──────────────────────────────

class _VoiceParsingLoader extends StatefulWidget {
  const _VoiceParsingLoader({
    required this.voiceText,
    required this.colors,
    required this.textTheme,
  });

  final String voiceText;
  final AppColors colors;
  final TextTheme textTheme;

  @override
  State<_VoiceParsingLoader> createState() => _VoiceParsingLoaderState();
}

class _VoiceParsingLoaderState extends State<_VoiceParsingLoader>
    with SingleTickerProviderStateMixin {
  static const _stages = [
    (emoji: '🎯', text: 'Extracting amount…'),
    (emoji: '📝', text: 'Cleaning description…'),
    (emoji: '🏦', text: 'Detecting bank & card…'),
    (emoji: '🏷️', text: 'Categorizing expense…'),
  ];

  late final AnimationController _ctrl;
  int _stageIdx = 0;
  Timer? _stageTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _stageTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() {
        _stageIdx = (_stageIdx + 1) % _stages.length;
      });
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stages[_stageIdx];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        gradient: RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.1),
            widget.colors.bg1.withValues(alpha: 0),
          ],
          center: const Alignment(0, -0.3),
          radius: 1.2,
        ),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  return Container(
                    width: 60 + _ctrl.value * 8,
                    height: 60 + _ctrl.value * 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.accent
                            .withValues(alpha: 0.2 + _ctrl.value * 0.15),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  LucideIcons.brain,
                  color: AppColors.accent,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Row(
              key: ValueKey(_stageIdx),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(stage.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  stage.text,
                  style: widget.textTheme.titleSmall?.copyWith(
                    color: widget.colors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (widget.voiceText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.colors.bg2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.colors.border),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.quote,
                      size: 14, color: widget.colors.text4),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.voiceText,
                      style: widget.textTheme.bodyMedium?.copyWith(
                        color: widget.colors.text2,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              4,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: i == _stageIdx ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == _stageIdx
                        ? AppColors.accent
                        : AppColors.accent.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
