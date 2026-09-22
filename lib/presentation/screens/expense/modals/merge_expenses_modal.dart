import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/services/expense_merge.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../domain/entities/expense_entities.dart';
import '../../settings/settings_controller.dart' show Bank;
import '../widgets/expense_date_picker.dart';
import '../widgets/expense_merge_bar.dart';
import 'add_expense_modal.dart';

Future<Expense?> showMergeExpensesModal(
  BuildContext context, {
  required ExpenseMergePlan plan,
  required String mergedId,
  List<String>? banks,
  List<Bank>? bankConfigs,
}) {
  final names = bankConfigs != null && bankConfigs.isNotEmpty
      ? _distinctBankNames(bankConfigs)
      : (banks ?? kDefaultExpenseModalBanks);
  return showModalBottomSheet<Expense>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MergeExpensesSheet(
      plan: plan,
      mergedId: mergedId,
      banks: names,
      bankConfigs: bankConfigs ?? const [],
    ),
  );
}

List<String> _distinctBankNames(List<Bank> configs) {
  final seen = <String>{};
  final out = <String>[];
  for (final b in configs) {
    if (seen.add(b.name)) out.add(b.name);
  }
  return out;
}

class _MergeExpensesSheet extends StatefulWidget {
  const _MergeExpensesSheet({
    required this.plan,
    required this.mergedId,
    required this.banks,
    this.bankConfigs = const [],
  });

  final ExpenseMergePlan plan;
  final String mergedId;
  final List<String> banks;
  final List<Bank> bankConfigs;

  @override
  State<_MergeExpensesSheet> createState() => _MergeExpensesSheetState();
}

class _MergeExpensesSheetState extends State<_MergeExpensesSheet> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _commentsCtrl;
  late DateTime _pickedDay;
  late String _category;
  late String _bank;
  late String _cardType;
  bool _attempted = false;

  List<String> get _banks {
    final names = [...widget.banks];
    final planned = widget.plan.bank.trim();
    if (planned.isNotEmpty &&
        !names.any((b) => b.toLowerCase() == planned.toLowerCase())) {
      names.insert(0, planned);
    }
    return names;
  }

  Set<String> _allowedCardTypes(String bank) {
    if (bank.isEmpty) return expenseCardTypes.toSet();
    final configs = widget.bankConfigs
        .where((b) => b.name.toLowerCase() == bank.toLowerCase())
        .toList();
    if (configs.isNotEmpty) {
      return configs.map((b) => b.cardType).toSet();
    }
    if (bank.toUpperCase() == 'CASH') return {'Cash'};
    return {'DB', 'CC'};
  }

  void _reconcileCardTypeForBank(String bank) {
    final allowed = _allowedCardTypes(bank);
    if (allowed.length == 1) {
      _cardType = allowed.first;
    } else if (!allowed.contains(_cardType)) {
      _cardType = allowed.contains(expenseCardTypes.first)
          ? expenseCardTypes.first
          : allowed.first;
    }
  }

  static String _lead(String ct) {
    if (ct == 'Cash') return '💵';
    if (ct == 'CC') return '💳';
    return '🏦';
  }

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController();
    _commentsCtrl = TextEditingController();
    _pickedDay = widget.plan.loggedAt;
    _category = widget.plan.defaultCategory;
    final banks = _banks;
    _bank = banks.any(
            (b) => b.toLowerCase() == widget.plan.bank.toLowerCase())
        ? widget.plan.bank
        : (banks.isNotEmpty ? banks.first : widget.plan.bank);
    _cardType = expenseCardTypes.contains(widget.plan.cardType)
        ? widget.plan.cardType
        : expenseCardTypes.first;
    _reconcileCardTypeForBank(_bank);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      setState(() => _attempted = true);
      HapticFeedback.heavyImpact();
      return;
    }
    try {
      final expense = composeMergedExpense(
        plan: widget.plan,
        id: widget.mergedId,
        description: desc,
        category: _category,
        pickedDay: _pickedDay,
        bank: _bank,
        cardType: _cardType,
        comments: _commentsCtrl.text,
      );
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(expense);
    } on ExpenseMergeException {
      setState(() => _attempted = true);
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final descError = _attempted && _descCtrl.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'MERGE EXPENSES',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: const Color(0xFFC084FC),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatCurrency(widget.plan.total),
                    key: const ValueKey('expense_merge_total'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: colors.text,
                    ),
                  ),
                  Text(
                    '${widget.plan.count} transactions combined',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.text3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _descCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      if (_attempted) setState(() {});
                    },
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Description',
                      hintText: 'e.g. Danalashmi Flower Shop',
                      errorText: descError ? 'Enter a description' : null,
                      filled: true,
                      fillColor: colors.bg2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CATEGORY',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: colors.text4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: expenseCategories.map((cat) {
                      final sel = cat == _category;
                      final c =
                          AppColors.categoryColors[cat] ?? AppColors.accent;
                      return Material(
                        color: sel ? c.withValues(alpha: 0.18) : colors.bg2,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _category = cat);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Text(
                              '${AppColors.categoryIcons[cat] ?? '📦'} $cat',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: sel ? c : colors.text2,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  ExpenseDatePicker(
                    selectedDate: _pickedDay,
                    onChanged: (d) => setState(() => _pickedDay = d),
                    label: 'DATE & TIME',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Time stays ${TimeOfDay.fromDateTime(widget.plan.loggedAt).format(context)} from the latest selected row.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: colors.text4,
                    ),
                  ),
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
                        for (final b in _banks) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(b),
                              selected: _bank == b,
                              onSelected: (_) => setState(() {
                                HapticFeedback.selectionClick();
                                _bank = b;
                                _reconcileCardTypeForBank(b);
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
                              final isDisabled = _bank.isNotEmpty &&
                                  !_allowedCardTypes(_bank).contains(ct);
                              return ChoiceChip(
                                label: Text(
                                  '${_lead(ct)} $ct',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                selected: _cardType == ct,
                                onSelected: isDisabled
                                    ? null
                                    : (_) => setState(() => _cardType = ct),
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('📝', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(
                        'COMMENTS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.text4,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'optional',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: colors.text4,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentsCtrl,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 280,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    buildCounter: (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) =>
                        null,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.text,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colors.bg2,
                      hintText: 'Add a reminder or note',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: colors.text4,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          LucideIcons.stickyNote,
                          size: 16,
                          color: _commentsCtrl.text.trim().isNotEmpty
                              ? AppColors.accent
                              : colors.text4,
                        ),
                      ),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    key: kExpenseMergeSaveKey,
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Save merged expense',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
