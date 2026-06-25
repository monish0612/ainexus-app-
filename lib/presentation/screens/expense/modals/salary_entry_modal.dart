import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../domain/entities/salary_entities.dart';

/// Bottom sheet to enter / update the in-hand salary for a given month.
/// Defaults to the current month (the monthly "reset" entry).
Future<void> showSalaryEntryModal(
  BuildContext context, {
  String? month,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SalaryEntrySheet(month: month ?? monthKeyOf(DateTime.now())),
  );
}

class _SalaryEntrySheet extends ConsumerStatefulWidget {
  const _SalaryEntrySheet({required this.month});

  final String month;

  @override
  ConsumerState<_SalaryEntrySheet> createState() => _SalaryEntrySheetState();
}

class _SalaryEntrySheetState extends ConsumerState<_SalaryEntrySheet> {
  late final TextEditingController _controller;
  double? _existing;
  double? _previous;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => setState(() {}));
    _prime();
  }

  Future<void> _prime() async {
    final repo = ref.read(salaryRepositoryProvider);
    final all = await repo.getSalaries();
    SalaryEntry? cur;
    double? prev;
    for (final e in all) {
      if (e.month == widget.month) {
        cur = e;
      } else if (e.month.compareTo(widget.month) < 0 && prev == null) {
        prev = e.amount;
      }
    }
    if (!mounted) return;
    setState(() {
      _existing = cur?.amount;
      _previous = prev;
      if (cur != null && cur.amount > 0) {
        _controller.text = cur.amount.toStringAsFixed(0);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _entered {
    final raw = _controller.text.replaceAll(',', '').trim();
    return double.tryParse(raw);
  }

  double? get _hikePct {
    final n = _entered;
    final p = _previous;
    if (n == null || n <= 0 || p == null || p <= 0) return null;
    return ((n - p) / p) * 100;
  }

  Future<void> _save() async {
    final n = _entered;
    if (n == null || n <= 0 || _saving) return;
    setState(() => _saving = true);
    final repo = ref.read(salaryRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final synced = await repo.setSalaryForMonth(widget.month, n);
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? 'Salary saved for ${monthKeyLabel(widget.month)}'
              : 'Saved locally — will sync when online',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textTheme =
        GoogleFonts.plusJakartaSansTextTheme(Theme.of(context).textTheme);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final hike = _hikePct;
    final canSave = (_entered ?? 0) > 0 && !_saving;

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
                    Text('💰', style: textTheme.titleLarge),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _existing != null && _existing! > 0
                                ? 'Update Salary'
                                : 'Monthly Salary',
                            style: textTheme.titleMedium?.copyWith(
                              color: colors.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'In-hand for ${monthKeyLabel(widget.month)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_previous != null) ...[
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
                          'Previous month',
                          style: textTheme.bodySmall
                              ?.copyWith(color: colors.text3),
                        ),
                        const Spacer(),
                        Text(
                          formatCurrency(_previous!),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.bg2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: hike != null && hike != 0
                          ? (hike > 0
                              ? const Color(0x5551CF66)
                              : const Color(0x55FF6B6B))
                          : colors.border,
                    ),
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
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: textTheme.headlineSmall?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 32,
                            letterSpacing: -0.5,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Enter salary',
                            hintStyle: textTheme.headlineSmall?.copyWith(
                              color: colors.text5,
                              fontWeight: FontWeight.w700,
                              fontSize: 24,
                            ),
                          ),
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                      if (hike != null && hike.abs() >= 0.05)
                        _HikeBadge(pct: hike, textTheme: textTheme),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: colors.bg3,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save salary',
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

class _HikeBadge extends StatelessWidget {
  const _HikeBadge({required this.pct, required this.textTheme});

  final double pct;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final up = pct > 0;
    final color = up ? const Color(0xFF51CF66) : const Color(0xFFFF6B6B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down,
              size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            '${up ? '+' : ''}${pct.toStringAsFixed(1)}%',
            style: textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
