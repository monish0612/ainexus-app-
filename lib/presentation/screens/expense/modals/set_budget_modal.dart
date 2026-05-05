import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Bottom sheet to set monthly budget (`SetBudgetModal.tsx`).
Future<void> showSetBudgetModal(
  BuildContext context, {
  required double currentBudget,
  required void Function(double amount) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SetBudgetSheet(
      currentBudget: currentBudget,
      onSave: onSave,
    ),
  );
}

class _SetBudgetSheet extends StatefulWidget {
  const _SetBudgetSheet({
    required this.currentBudget,
    required this.onSave,
  });

  final double currentBudget;
  final void Function(double amount) onSave;

  @override
  State<_SetBudgetSheet> createState() => _SetBudgetSheetState();
}

class _SetBudgetSheetState extends State<_SetBudgetSheet> {
  late final TextEditingController _controller;
  static const _presets = [5000, 10000, 20000, 50000];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentBudget > 0
          ? widget.currentBudget.toStringAsFixed(0)
          : '',
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _controller.text.replaceAll(',', '');
    final n = double.tryParse(raw);
    if (n != null && n > 0) {
      widget.onSave(n);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(Theme.of(context).textTheme);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: colors.border),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Set Budget',
                        style: textTheme.titleMedium?.copyWith(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.currentBudget > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.bg2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Current budget',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.text3,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatCurrency(widget.currentBudget),
                          style: textTheme.titleSmall?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.bg2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '₹',
                        style: textTheme.headlineSmall?.copyWith(
                          color: colors.text4,
                          fontWeight: FontWeight.w700,
                          fontSize: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          keyboardType: TextInputType.number,
                          style: textTheme.headlineSmall?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 32,
                            letterSpacing: -0.5,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Enter budget',
                            hintStyle: textTheme.headlineSmall?.copyWith(
                              color: colors.text5,
                              fontWeight: FontWeight.w700,
                              fontSize: 24,
                            ),
                          ),
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (var i = 0; i < _presets.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _PresetChip(
                          amount: _presets[i],
                          selected: _controller.text == '${_presets[i]}',
                          colors: colors,
                          textTheme: textTheme,
                          onTap: () {
                            setState(() {
                              _controller.text = '${_presets[i]}';
                            });
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _controller.text.trim().isEmpty ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: colors.bg3,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Save',
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
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.amount,
    required this.selected,
    required this.colors,
    required this.textTheme,
    required this.onTap,
  });

  final int amount;
  final bool selected;
  final AppColors colors;
  final TextTheme textTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = amount >= 1000 ? '₹${amount ~/ 1000}k' : '₹$amount';
    return Material(
      color: selected ? const Color(0x337C3AED) : colors.bg2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0x807C3AED)
                  : colors.border,
            ),
          ),
          child: Text(
            label,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: selected ? const Color(0xFFA78BFA) : colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}
