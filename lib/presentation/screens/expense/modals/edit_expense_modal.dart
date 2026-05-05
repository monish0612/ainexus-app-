import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../domain/entities/expense_entities.dart';

import 'add_expense_modal.dart';

/// Edit existing expense (`EditExpenseModal.tsx`).
Future<void> showEditExpenseModal(
  BuildContext context, {
  required Expense expense,
  required void Function(Expense updated) onUpdate,
  List<String>? banks,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _EditExpenseSheet(
      expense: expense,
      banks: banks ?? kDefaultExpenseModalBanks,
      onUpdate: onUpdate,
    ),
  );
}

class _EditExpenseSheet extends StatefulWidget {
  const _EditExpenseSheet({
    required this.expense,
    required this.banks,
    required this.onUpdate,
  });

  final Expense expense;
  final List<String> banks;
  final void Function(Expense updated) onUpdate;

  @override
  State<_EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends State<_EditExpenseSheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descCtrl;
  late String _bank;
  late String _cardType;
  late String _category;
  var _showCategoryPicker = false;
  bool _hasAttemptedSubmit = false;
  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final e = widget.expense;
    _amountCtrl = TextEditingController(text: e.amount.toStringAsFixed(0));
    _descCtrl = TextEditingController(text: e.description);
    _bank = widget.banks.contains(e.bank) ? e.bank : widget.banks.first;
    _cardType = expenseCardTypes.contains(e.cardType)
        ? e.cardType
        : expenseCardTypes.first;
    _category = expenseCategories.contains(e.category)
        ? e.category
        : expenseCategories.last;
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
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

  void _save() {
    final n = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    final desc = _descCtrl.text.trim();
    if (n == null || n <= 0 || desc.isEmpty) {
      setState(() => _hasAttemptedSubmit = true);
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
      return;
    }
    widget.onUpdate(
      widget.expense.copyWith(
        amount: n,
        description: desc,
        category: _category,
        bank: _bank,
        cardType: _cardType,
        isManualCategory: true,
      ),
    );
    Navigator.of(context).pop();
  }

  bool get _valid {
    final n = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    return n != null && n > 0 && _descCtrl.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      Theme.of(context).textTheme,
    );
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final amountPreview = double.tryParse(
      _amountCtrl.text.replaceAll(',', ''),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.text4,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: AnimatedBuilder(
                  animation: _shakeCtrl,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(_shakeOffset, 0),
                    child: child,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit Expense',
                                style: textTheme.titleMedium?.copyWith(
                                  color: colors.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Modify the details below',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colors.text4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _amountError
                            ? const Color(0x0FEF4444)
                            : colors.bg2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _amountError
                              ? const Color(0xB3EF4444)
                              : colors.border,
                          width: _amountError ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '₹',
                            style: textTheme.headlineSmall?.copyWith(
                              color: _amountError
                                  ? const Color(0xB3EF4444)
                                  : colors.text4,
                              fontWeight: FontWeight.w700,
                              fontSize: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: textTheme.headlineSmall?.copyWith(
                                color: colors.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 32,
                                letterSpacing: -0.5,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
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
                            color: const Color(0xFFEF4444),
                          ),
                        ),
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descCtrl,
                      style: textTheme.bodyMedium?.copyWith(color: colors.text),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _descError
                            ? const Color(0x0FEF4444)
                            : colors.bg2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: _descError
                                ? const Color(0xB3EF4444)
                                : colors.border,
                            width: _descError ? 1.5 : 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: _descError
                                ? const Color(0xB3EF4444)
                                : colors.border,
                            width: _descError ? 1.5 : 1,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
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
                    const SizedBox(height: 16),
                    Text(
                      'CATEGORY',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.text4,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: colors.bg2,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(
                          () => _showCategoryPicker = !_showCategoryPicker,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.border),
                          ),
                          child: Row(
                            children: [
                              Text(
                                AppColors.categoryIcons[_category] ?? '📦',
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _category,
                                  style: textTheme.titleSmall?.copyWith(
                                    color: AppColors.categoryColors[_category] ??
                                        AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                LucideIcons.chevronDown,
                                size: 14,
                                color: colors.text4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_showCategoryPicker) ...[
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.8,
                        ),
                        itemCount: expenseCategories.length,
                        itemBuilder: (context, i) {
                          final cat = expenseCategories[i];
                          final c = AppColors.categoryColors[cat]!;
                          final sel = _category == cat;
                          return Material(
                            color: sel ? c.withValues(alpha: 0.13) : colors.bg2,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                setState(() {
                                  _category = cat;
                                  _showCategoryPicker = false;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: sel
                                        ? c.withValues(alpha: 0.7)
                                        : colors.border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      AppColors.categoryIcons[cat] ?? '📦',
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        cat,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: sel ? c : colors.text3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c,
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
                    const SizedBox(height: 16),
                    Text(
                      'BANK',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.text4,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                                  } else if (_cardType == 'Cash') {
                                    _cardType = expenseCardTypes.first;
                                  }
                                }),
                                selectedColor: const Color(0x337C63E2),
                                labelStyle: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _bank == b
                                      ? const Color(0xFFA78BFA)
                                      : colors.text3,
                                ),
                                side: BorderSide(
                                  color: _bank == b
                                      ? const Color(0x997C63E2)
                                      : colors.border,
                                ),
                                backgroundColor: colors.bg2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'PAYMENT TYPE',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.text4,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final ct in expenseCardTypes) ...[
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: ct == expenseCardTypes.last ? 0 : 8,
                              ),
                              child: Builder(builder: (context) {
                                final isCashBank = _bank == 'CASH';
                                final isCashType = ct == 'Cash';
                                final isDisabled = isCashBank
                                    ? !isCashType
                                    : isCashType;
                                return ChoiceChip(
                                  label: Text(
                                    '${_lead(ct)} $ct',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  selected: _cardType == ct,
                                  onSelected: isDisabled
                                      ? null
                                      : (_) =>
                                          setState(() => _cardType = ct),
                                  selectedColor: const Color(0x2634D399),
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
                                        ? const Color(0x8034D399)
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
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Save Changes',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
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

  static String _lead(String ct) {
    if (ct == 'Cash') return '💵';
    if (ct == 'CC') return '💳';
    return '🏦';
  }
}
