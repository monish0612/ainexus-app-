import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/services/sms_auto_expense/sms_auto_expense_service.dart';
import '../../../../domain/entities/expense_entities.dart';

const _accent = Color(0xFF0D59F2);
const _good = Color(0xFF22C55E);

/// Bottom review / logged toast for SMS auto-expense. Sits above the nav
/// bar; does not open the add-expense modal.
class SmsExpenseReviewHost extends ConsumerWidget {
  const SmsExpenseReviewHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(smsAutoExpenseProvider);
    if (ui.review == null && ui.toast == null) {
      return const SizedBox.shrink();
    }
    final bottom =
        MediaQuery.viewPaddingOf(context).bottom + AppConstants.navHeight + 10;
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottom,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: ui.review != null
            ? _ReviewCard(
                key: ValueKey('review-${ui.review!.item.id}'),
                review: ui.review!,
                busy: ui.busy,
                saveError: ui.saveError,
                waitingCount: ui.waitingCount,
              )
            : _ToastCard(
                key: ValueKey('toast-${ui.toast!.expenseId}'),
                toast: ui.toast!,
              ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({
    super.key,
    required this.review,
    required this.busy,
    this.saveError,
    this.waitingCount = 0,
  });

  final SmsReview review;
  final bool busy;
  final String? saveError;
  final int waitingCount;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _pickCategory = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final review = widget.review;
    final debit = review.debit;
    final emoji = AppColors.categoryIcons[review.category] ?? '📦';
    final paise = debit.amount != debit.amount.roundToDouble();

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadowColor,
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.text5,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(LucideIcons.wand2, size: 16, color: _accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.waitingCount > 0
                        ? 'Debit detected · ${widget.waitingCount} more waiting'
                        : 'Debit detected',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.text3,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Text(
                  '${debit.bank} · ${debit.cardType}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              formatCurrency(debit.amount, showDecimal: paise),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: colors.text,
                letterSpacing: -0.8,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              review.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  onTap: widget.busy
                      ? null
                      : () => setState(() => _pickCategory = !_pickCategory),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.bg2,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      '$emoji  ${review.category}  ▾',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    review.stamp,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: colors.text3,
                    ),
                  ),
                ),
              ],
            ),
            if (_pickCategory) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 132,
                child: GridView.builder(
                  itemCount: expenseCategories.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 2.6,
                  ),
                  itemBuilder: (context, i) {
                    final cat = expenseCategories[i];
                    final on = cat == review.category;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref
                            .read(smsAutoExpenseProvider.notifier)
                            .setReviewCategory(cat);
                        setState(() => _pickCategory = false);
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on
                              ? _accent.withValues(alpha: 0.14)
                              : colors.bg2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: on ? _accent : colors.border,
                          ),
                        ),
                        child: Text(
                          cat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (widget.saveError != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  widget.saveError!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.busy
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            ref
                                .read(smsAutoExpenseProvider.notifier)
                                .rejectCurrent();
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.text2,
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(
                      'Reject',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.busy
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            ref
                                .read(smsAutoExpenseProvider.notifier)
                                .approveCurrent();
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                    child: widget.busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Approve',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToastCard extends ConsumerWidget {
  const _ToastCard({super.key, required this.toast});

  final SmsToast toast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final emoji = AppColors.categoryIcons[toast.category] ?? '📦';
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _good.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: colors.shadowColor,
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.checkCircle2, size: 18, color: _good),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Logged ${formatCurrency(toast.amount)} · $emoji ${toast.description}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(smsAutoExpenseProvider.notifier).undoToast();
              },
              child: Text(
                'Undo',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  color: _accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
