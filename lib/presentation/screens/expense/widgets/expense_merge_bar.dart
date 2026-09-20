import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

const Key kExpenseMergeBarKey = ValueKey('expense_merge_bar');
const Key kExpenseMergeSubmitKey = ValueKey('expense_merge_submit');
const Key kExpenseMergeSaveKey = ValueKey('expense_merge_save');

/// Intercepts Android predictive back / system back while merge-select is on,
/// so a swipe-back exits checkbox mode instead of leaving the screen.
class ExpenseSelectionScope extends StatelessWidget {
  const ExpenseSelectionScope({
    super.key,
    required this.active,
    required this.onCancel,
    required this.child,
  });

  final bool active;
  final VoidCallback onCancel;
  final Widget child;

  Future<bool> _handleBack() async {
    HapticFeedback.selectionClick();
    onCancel();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Always wrap so the child keeps the same Element slot. Swapping this
    // tree on long-press remounts the expense list and jumps scroll to top.
    Widget tree = PopScope(
      canPop: !active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && active) onCancel();
      },
      child: child,
    );
    if (Router.maybeOf(context) != null) {
      tree = BackButtonListener(
        onBackButtonPressed: () async {
          if (!active) return false;
          return _handleBack();
        },
        child: tree,
      );
    }
    return tree;
  }
}

/// Bottom selection chrome. Merge is offered only when 2+ rows are checked.
class ExpenseMergeActionBar extends StatelessWidget {
  const ExpenseMergeActionBar({
    super.key,
    required this.selectedCount,
    required this.total,
    required this.onMerge,
    required this.onCancel,
  });

  final int selectedCount;
  final double total;
  final VoidCallback onMerge;
  final VoidCallback onCancel;

  bool get canMerge => selectedCount >= 2;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Material(
      key: kExpenseMergeBarKey,
      color: colors.isDark ? const Color(0xF2141118) : Colors.white,
      elevation: 12,
      shadowColor: kSearchGlow(colors),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFC084FC).withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFC084FC).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$selectedCount',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFE9D5FF),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedCount == 1
                        ? '1 selected'
                        : '$selectedCount selected',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                  Text(
                    canMerge
                        ? 'Total ${formatCurrency(total)}'
                        : 'Select one more to merge',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.text3,
                    ),
                  ),
                ],
              ),
            ),
            if (canMerge)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilledButton.icon(
                  key: kExpenseMergeSubmitKey,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    onMerge();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(LucideIcons.gitMerge, size: 14),
                  label: Text(
                    'Merge',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Cancel',
              onPressed: onCancel,
              visualDensity: VisualDensity.compact,
              icon: Icon(LucideIcons.x, size: 18, color: colors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

Color kSearchGlow(AppColors colors) => colors.isDark
    ? const Color(0xFFC084FC).withValues(alpha: 0.28)
    : const Color(0xFF7C3AED).withValues(alpha: 0.16);
