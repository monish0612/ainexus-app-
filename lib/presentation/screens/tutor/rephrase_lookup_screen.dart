import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/tutor_entities.dart';

/// Standalone rephrase screen that can be pushed on any navigation stack.
/// Preserves the underlying screen so back-swipe returns to it.
class RephraseLookupScreen extends ConsumerStatefulWidget {
  const RephraseLookupScreen({super.key, required this.text});

  final String text;

  @override
  ConsumerState<RephraseLookupScreen> createState() =>
      _RephraseLookupScreenState();
}

class _RephraseLookupScreenState extends ConsumerState<RephraseLookupScreen> {
  static const _platforms = [
    ('Own', Color(0xFF0D59F2)),
    ('Casual', Color(0xFF34D399)),
    ('Sarcastic', Color(0xFFF59E0B)),
    ('Twitter', Color(0xFF339AF0)),
    ('LinkedIn', Color(0xFF6366F1)),
    ('Slack', Color(0xFFC084FC)),
    ('Email', Color(0xFFFF6B6B)),
    ('WhatsApp', Color(0xFF51CF66)),
  ];

  bool _loading = true;
  RephraseResult? _result;
  String? _error;
  String _selectedPlatform = 'Own';

  @override
  void initState() {
    super.initState();
    _rephrase();
  }

  Future<void> _rephrase() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final platformId = _selectedPlatform.toLowerCase();
      final result = await ref.read(tutorAiServiceProvider).rephrase(
            text: widget.text,
            platform: platformId,
            intent: platformId == 'own' ? 'clear and natural' : null,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e, st) {
      TLog.e('RephraseLookup', 'Rephrase failed', error: e, st: st);
      if (!mounted) return;
      setState(() {
        _error = 'Rephrase failed. Please try again.';
        _loading = false;
      });
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
          'Rephrase',
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
              color: const Color(0xFFC084FC),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Rephrasing as $_selectedPlatform…',
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
              onPressed: _rephrase,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC084FC),
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

  Widget _buildResult(AppColors colors, RephraseResult r) {
    const accent = Color(0xFFC084FC);
    final preview = widget.text.length > 80
        ? '${widget.text.substring(0, 80)}…'
        : widget.text;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.bg2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ORIGINAL',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.text5,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  preview,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.5,
                    color: colors.text3,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _platforms.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final (name, color) = _platforms[i];
                final selected = name == _selectedPlatform;
                return GestureDetector(
                  onTap: () {
                    if (name == _selectedPlatform || _loading) return;
                    setState(() => _selectedPlatform = name);
                    _rephrase();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withValues(alpha: 0.15)
                          : colors.bg2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? color.withValues(alpha: 0.4)
                            : colors.border2,
                      ),
                    ),
                    child: Text(
                      name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? color : colors.text3,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
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
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.06),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(
                      bottom: BorderSide(color: colors.border2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.sparkles, size: 16, color: accent),
                      const SizedBox(width: 8),
                      Text(
                        _selectedPlatform.toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accent,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _copy(r.rephrasedText),
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
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    r.rephrasedText,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      height: 1.75,
                      color: colors.text,
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
}
