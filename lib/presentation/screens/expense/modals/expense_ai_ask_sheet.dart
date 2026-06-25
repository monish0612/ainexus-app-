import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/services/ai_categorize_service.dart' show keywordRules;
import '../../settings/settings_controller.dart';
import '../expense_timeframe_screen.dart';
import '../salary_screen.dart';

/// Opens the AI expense-search ask sheet. The user types a plain-English
/// question; Gemini (via backend) distils it into a structured query that we
/// run against the local DB and render in the editable results screen.
Future<void> showExpenseAiAskSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ExpenseAiAskSheet(),
  );
}

const _suggestions = <String>[
  "Today's expenses",
  'Highest expense',
  'Visualize last month',
  'Anything related to my car',
  'My salary this month',
  'Did I get a hike?',
  'Spending by category',
  'Last trip cost',
];

class _ExpenseAiAskSheet extends ConsumerStatefulWidget {
  const _ExpenseAiAskSheet();

  @override
  ConsumerState<_ExpenseAiAskSheet> createState() => _ExpenseAiAskSheetState();
}

class _ExpenseAiAskSheetState extends ConsumerState<_ExpenseAiAskSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit([String? preset]) async {
    final question = (preset ?? _ctrl.text).trim();
    if (question.isEmpty || _loading) return;
    HapticFeedback.selectionClick();
    if (preset != null) _ctrl.text = preset;
    setState(() => _loading = true);

    final service = ref.read(expenseAiSearchServiceProvider);
    final liteModel = ref.read(settingsProvider).liteModel;
    final spec = await service.query(
      question,
      categories: keywordRules.keys.toList(),
      liteModel: liteModel,
    );
    if (!mounted) return;

    // Salary/income questions route to the dedicated salary stats screen, which
    // holds the real numbers (the AI never sees or invents them).
    if (spec != null && spec.isSalaryTopic) {
      Navigator.of(context).pop();
      await showSalaryScreen(
        context,
        aiAnswer: spec.answer.isEmpty ? null : spec.answer,
      );
      return;
    }

    // Build the editable results timeframe — either from the AI spec or, if the
    // AI is unavailable, a graceful keyword-search fallback so results still show.
    final timeframe = spec == null
        ? ExpenseTimeframe(
            label: question.length > 28 ? '${question.substring(0, 28)}…' : question,
            startIso: null,
            seedSearch: question,
            aiAnswer: 'Showing keyword matches for "$question" '
                '(AI is offline — refine with the search box).',
          )
        : ExpenseTimeframe(
            label: spec.title,
            startIso: spec.startIso,
            endIso: spec.endIso,
            seedSearch: spec.search,
            seedSearchTerms: spec.searchTerms,
            seedCategory: spec.category,
            sort: spec.sort,
            aiAnswer: spec.answer.isEmpty ? null : spec.answer,
            chart: spec.chart,
          );

    Navigator.of(context).pop();
    await showExpenseTimeframeScreen(context, timeframe);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.text4,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        AppColors.accent,
                        AppColors.accent.withValues(alpha: 0.7),
                      ]),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(LucideIcons.sparkles,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ask AI',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          'Search your expenses in plain English',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: colors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: _InputBar(
                colors: colors,
                controller: _ctrl,
                focus: _focus,
                loading: _loading,
                onSubmit: () => _submit(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _suggestions)
                    _SuggestionChip(
                      colors: colors,
                      label: s,
                      onTap: _loading ? null : () => _submit(s),
                    ),
                ],
              ),
            ),
            SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.colors,
    required this.controller,
    required this.focus,
    required this.loading,
    required this.onSubmit,
  });

  final AppColors colors;
  final TextEditingController controller;
  final FocusNode focus;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              enabled: !loading,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: colors.text,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'e.g. how much did I spend on food today?',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  color: colors.text4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: loading ? null : onSubmit,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: loading ? colors.bg3 : AppColors.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    )
                  : const Icon(LucideIcons.arrowUp,
                      size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.colors,
    required this.label,
    required this.onTap,
  });

  final AppColors colors;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.text2,
          ),
        ),
      ),
    );
  }
}
