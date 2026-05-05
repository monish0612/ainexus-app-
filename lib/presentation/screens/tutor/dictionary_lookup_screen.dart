import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/tutor_entities.dart';

/// Lightweight full-screen dictionary lookup pushed on top of an article.
/// Swiping back returns to the article underneath.
class DictionaryLookupScreen extends ConsumerStatefulWidget {
  const DictionaryLookupScreen({super.key, required this.word});

  final String word;

  @override
  ConsumerState<DictionaryLookupScreen> createState() =>
      _DictionaryLookupScreenState();
}

class _DictionaryLookupScreenState
    extends ConsumerState<DictionaryLookupScreen> {
  bool _loading = true;
  DictionaryResult? _result;
  String? _error;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    try {
      final result =
          await ref.read(tutorAiServiceProvider).define(word: widget.word);
      if (!mounted) return;

      final db = ref.read(appDatabaseProvider);
      final existing = await (db.select(db.savedWords)
            ..where(
              (t) => t.word.lower().equals(widget.word.trim().toLowerCase()),
            ))
          .getSingleOrNull();

      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _saved = existing != null;
      });
    } catch (e) {
      TLog.e('Dictionary', 'Lookup failed', error: e);
      if (!mounted) return;
      setState(() {
        _error = 'Lookup failed. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _saveWord() async {
    final r = _result;
    if (r == null || _saved || _saving) return;

    setState(() => _saving = true);

    try {
      final db = ref.read(appDatabaseProvider);

      final existing = await (db.select(db.savedWords)
            ..where(
              (t) => t.word.lower().equals(r.word.trim().toLowerCase()),
            ))
          .getSingleOrNull();

      if (existing != null) {
        if (!mounted) return;
        setState(() {
          _saved = true;
          _saving = false;
        });
        return;
      }

      final rng = Random();
      final id =
          'w-${DateTime.now().microsecondsSinceEpoch}-${rng.nextInt(0xFFFF).toRadixString(16)}';
      final now = DateTime.now().toIso8601String();
      final json = jsonEncode(r.toJson());

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

      if (!mounted) return;
      setState(() {
        _saved = true;
        _saving = false;
      });

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
        TLog.w('DictLookup', 'Server sync failed for "${r.word}": $e');
      }
    } catch (e, st) {
      TLog.e('DictLookup', 'Save failed for "${r.word}"', error: e, st: st);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Save failed — please try again',
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
          ),
          backgroundColor: const Color(0xFFFF6B6B),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied',
          style: GoogleFonts.plusJakartaSans(color: Colors.white),
        ),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.headerBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: colors.text, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Dictionary',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: _loading
          ? _buildLoading(colors)
          : _error != null
              ? _buildError(colors)
              : _result != null
                  ? _buildResult(colors, _result!)
                  : const SizedBox.shrink(),
    );
  }

  Widget _buildLoading(AppColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Looking up "${widget.word}"…',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: colors.text3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle, size: 40, color: colors.text4),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                color: colors.text2,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _lookup();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(AppColors colors, DictionaryResult r) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border(
                      bottom: BorderSide(color: colors.border2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.word,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accent,
                                height: 1.1,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _copy(
                              '${r.word} — ${r.definition}',
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: colors.bg2,
                              side: BorderSide(color: colors.border),
                            ),
                            icon: Icon(
                              LucideIcons.copy,
                              size: 16,
                              color: colors.text3,
                            ),
                          ),
                        ],
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
                                  color:
                                      AppColors.accent.withValues(alpha: 0.28),
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
                      SelectableText(
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
                        for (var i = 0; i < r.examples.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.bg2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.border2),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                      '${i + 1}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SelectableText(
                                      r.examples[i],
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        height: 1.65,
                                        color: colors.text2,
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

                if (r.usageGuide.isNotEmpty) ...[
                  Divider(height: 1, color: colors.border2),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'USAGE GUIDE',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors.text5,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          r.usageGuide,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            height: 1.72,
                            color: colors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                Divider(height: 1, color: colors.border2),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _SaveButton(
                    saved: _saved,
                    saving: _saving,
                    colors: colors,
                    onSave: _saveWord,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.saved,
    required this.saving,
    required this.colors,
    required this.onSave,
  });

  final bool saved;
  final bool saving;
  final AppColors colors;
  final VoidCallback onSave;

  static const _green = Color(0xFF34D399);

  @override
  Widget build(BuildContext context) {
    final isSaved = saved && !saving;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Material(
        color: isSaved
            ? _green.withValues(alpha: 0.1)
            : AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: isSaved ? null : onSave,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSaved
                    ? _green.withValues(alpha: 0.3)
                    : AppColors.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (saving)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                else
                  Icon(
                    isSaved ? LucideIcons.bookmarkMinus : LucideIcons.bookmark,
                    size: 18,
                    color: isSaved ? _green : AppColors.accent,
                  ),
                const SizedBox(width: 10),
                Text(
                  isSaved ? 'Saved to Library' : 'Save to Library',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSaved ? _green : AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
