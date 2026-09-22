import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/expense_logged_at.dart';

/// Minimal expense row model for list items (matches React `Expense` fields used in UI).
class ExpenseData {
  const ExpenseData({
    required this.id,
    required this.amount,
    required this.description,
    required this.category,
    required this.bank,
    required this.cardType,
    required this.date,
    this.isManualCategory = false,
    this.comments = '',
  });

  final String id;
  final double amount;
  final String description;
  final String category;
  final String bank;
  final String cardType;
  final String date;
  final bool isManualCategory;
  final String comments;
}

/// Swipeable expense row matching [docs/figma_source/ExpenseItem.tsx] behavior and layout.
class ExpenseItem extends StatefulWidget {
  const ExpenseItem({
    super.key,
    required this.expense,
    required this.onEdit,
    required this.onDelete,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.onExitSelection,
  });

  final ExpenseData expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Optional row tap (e.g. open a full detail view). When the swipe actions
  /// are revealed, a tap closes them instead of firing this.
  final VoidCallback? onTap;

  /// Long-press enters multi-select. Ignored while swipe actions are mid-drag.
  final VoidCallback? onLongPress;

  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  /// Swipe-right / swipe-back while selecting leaves checkbox mode.
  final VoidCallback? onExitSelection;

  @override
  State<ExpenseItem> createState() => _ExpenseItemState();
}

class _ExpenseItemState extends State<ExpenseItem>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 130;

  late final AnimationController _snapCtrl;
  Animation<double>? _snapAnim;
  VoidCallback? _snapListener;

  double _offset = 0;
  bool _revealed = false;
  double _dragAccumDx = 0;
  double _backDx = 0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant ExpenseItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectionMode && !oldWidget.selectionMode && _offset != 0) {
      _snapTo(0);
    }
    if (!widget.selectionMode && oldWidget.selectionMode && _backDx != 0) {
      _backDx = 0;
    }
  }

  @override
  void dispose() {
    _removeSnapListener();
    _snapCtrl.dispose();
    super.dispose();
  }

  void _removeSnapListener() {
    if (_snapListener != null && _snapAnim != null) {
      _snapAnim!.removeListener(_snapListener!);
      _snapListener = null;
      _snapAnim = null;
    }
  }

  void _snapTo(double target) {
    _snapCtrl.stop();
    _removeSnapListener();
    final start = _offset;
    _snapAnim = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(
        parent: _snapCtrl,
        curve: Curves.easeOutCubic,
      ),
    );
    _snapListener = () {
      if (!mounted || _snapAnim == null) return;
      setState(() => _offset = _snapAnim!.value);
    };
    _snapAnim!.addListener(_snapListener!);
    _snapCtrl.duration = const Duration(milliseconds: 280);
    _snapCtrl.forward(from: 0).then((_) {
      _removeSnapListener();
      if (!mounted) return;
      setState(() {
        _offset = target;
        _revealed = target <= -_revealWidth + 0.5;
      });
    });
  }

  void _onSelectionDragStart(DragStartDetails _) {
    _backDx = 0;
  }

  void _onSelectionDragUpdate(DragUpdateDetails details) {
    final next = (_backDx + details.delta.dx).clamp(0.0, 72.0);
    if (next == _backDx) return;
    setState(() => _backDx = next);
  }

  void _onSelectionDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final commit = _backDx > 44 || velocity > 650;
    final dx = _backDx;
    setState(() => _backDx = 0);
    if (commit && dx > 12 && widget.onExitSelection != null) {
      HapticFeedback.lightImpact();
      widget.onExitSelection!();
    }
  }

  void _onHorizontalDragStart(DragStartDetails _) {
    if (_snapCtrl.isAnimating) {
      _snapCtrl.stop();
      _removeSnapListener();
    }
    _dragAccumDx = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _dragAccumDx += details.delta.dx;
    final base = _revealed ? -_revealWidth : 0.0;
    final next = (base + _dragAccumDx).clamp(-_revealWidth, 0.0);
    setState(() => _offset = next);
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    if (_revealed) {
      if (_dragAccumDx > 30) {
        _snapTo(0);
      } else {
        _snapTo(-_revealWidth);
      }
    } else {
      if (_dragAccumDx < -48) {
        _snapTo(-_revealWidth);
      } else {
        _snapTo(0);
      }
    }
  }

  void _afterCloseThen(VoidCallback action) {
    _snapTo(0);
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) action();
    });
  }

  static String _cardLeadingEmoji(String cardType) {
    if (cardType == 'Cash') return '💵';
    if (cardType == 'Credit Card') return '💳';
    return '🏦';
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final e = widget.expense;

    final categoryColor =
        AppColors.categoryColors[e.category] ?? AppColors.categoryOthers;
    final categoryIcon = AppColors.categoryIcons[e.category] ??
        AppColors.categoryIcons['Others']!;

    const neutralBank = Color(0xFF555555);
    final bankColor = AppColors.bankColors[e.bank] ?? neutralBank;
    final isNeutralBank = bankColor == neutralBank;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (!widget.selectionMode)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _revealWidth,
              child: Row(
                children: [
                  Expanded(
                    child: _SwipeActionButton(
                      onTap: () => _afterCloseThen(widget.onEdit),
                      background:
                          const Color(0xFF6366F1).withValues(alpha: 0.28),
                      borderTop:
                          const Color(0xFF6366F1).withValues(alpha: 0.35),
                      borderBottom:
                          const Color(0xFF6366F1).withValues(alpha: 0.35),
                      borderRight: Colors.transparent,
                      borderRadius: BorderRadius.zero,
                      iconBoxBg: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      iconBoxBorder:
                          const Color(0xFF818CF8).withValues(alpha: 0.5),
                      icon: LucideIcons.pencil,
                      iconColor: const Color(0xFF818CF8),
                      label: 'EDIT',
                      labelColor: const Color(0xFF818CF8),
                    ),
                  ),
                  Expanded(
                    child: _SwipeActionButton(
                      onTap: () => _afterCloseThen(widget.onDelete),
                      background:
                          const Color(0xFFEF4444).withValues(alpha: 0.22),
                      borderTop:
                          const Color(0xFFEF4444).withValues(alpha: 0.35),
                      borderBottom:
                          const Color(0xFFEF4444).withValues(alpha: 0.35),
                      borderRight:
                          const Color(0xFFEF4444).withValues(alpha: 0.35),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      iconBoxBg:
                          const Color(0xFFEF4444).withValues(alpha: 0.22),
                      iconBoxBorder:
                          const Color(0xFFEF4444).withValues(alpha: 0.5),
                      icon: LucideIcons.trash2,
                      iconColor: const Color(0xFFEF4444),
                      label: 'DELETE',
                      labelColor: const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
          Transform.translate(
            offset: Offset(
              widget.selectionMode ? _backDx : _offset,
              0,
            ),
            child: GestureDetector(
              onHorizontalDragStart: widget.selectionMode
                  ? _onSelectionDragStart
                  : _onHorizontalDragStart,
              onHorizontalDragUpdate: widget.selectionMode
                  ? _onSelectionDragUpdate
                  : _onHorizontalDragUpdate,
              onHorizontalDragEnd: widget.selectionMode
                  ? _onSelectionDragEnd
                  : _onHorizontalDragEnd,
              onLongPress: widget.onLongPress == null
                  ? null
                  : () {
                      if (_revealed) _snapTo(0);
                      HapticFeedback.mediumImpact();
                      widget.onLongPress!();
                    },
              onTap: () {
                if (widget.selectionMode) {
                  HapticFeedback.selectionClick();
                  widget.onToggleSelect?.call();
                  return;
                }
                if (widget.onTap == null) return;
                if (_revealed) {
                  _snapTo(0);
                } else {
                  widget.onTap!();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? Color.alphaBlend(
                          const Color(0xFF7C3AED).withValues(alpha: 0.16),
                          c.bg1,
                        )
                      : c.bg1,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.selected ? const Color(0xFFC084FC) : c.border,
                    width: widget.selected ? 1.6 : 1,
                  ),
                  boxShadow: widget.selected
                      ? const [
                          BoxShadow(
                            color: Color(0x337C3AED),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerLeft,
                      child: widget.selectionMode
                          ? Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: _MergeCheckbox(
                                key: ValueKey('merge-check-${e.id}'),
                                selected: widget.selected,
                              ),
                            )
                          : const SizedBox(width: 0, height: 24),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: categoryColor.withAlpha(0x18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: categoryColor.withAlpha(0x35),
                        ),
                      ),
                      child: Text(
                        categoryIcon,
                        style: const TextStyle(fontSize: 19),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            e.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 0,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _CategoryChip(
                                label: e.category,
                                color: categoryColor,
                              ),
                              _DotSeparator(color: c.text5),
                              _BankChip(
                                label: e.bank,
                                bankColor: bankColor,
                                neutralText: c.text3,
                                isNeutral: isNeutralBank,
                              ),
                              _DotSeparator(color: c.text5),
                              Text(
                                '${_cardLeadingEmoji(e.cardType)} ${e.cardType}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: c.text3,
                                ),
                              ),
                            ],
                          ),
                          if (e.comments.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('📝', style: TextStyle(fontSize: 9)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    e.comments.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w400,
                                      color: c.text4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '-${formatCurrency(e.amount)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                        Text(
                          formatExpenseStamp(e.date, comments: e.comments),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            color: c.text4,
                          ),
                        ),
                        if (!widget.selectionMode) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _SwipeHintDot(
                                revealed: _revealed,
                                index: 0,
                              ),
                              const SizedBox(width: 2),
                              _SwipeHintDot(
                                revealed: _revealed,
                                index: 1,
                              ),
                              const SizedBox(width: 2),
                              _SwipeHintDot(
                                revealed: _revealed,
                                index: 2,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.onTap,
    required this.background,
    required this.borderTop,
    required this.borderBottom,
    required this.borderRight,
    required this.borderRadius,
    required this.iconBoxBg,
    required this.iconBoxBorder,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
  });

  final VoidCallback onTap;
  final Color background;
  final Color borderTop;
  final Color borderBottom;
  final Color borderRight;
  final BorderRadius borderRadius;
  final Color iconBoxBg;
  final Color iconBoxBorder;
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: background,
              borderRadius: borderRadius,
              border: Border(
                top: BorderSide(color: borderTop),
                bottom: BorderSide(color: borderBottom),
                right: BorderSide(color: borderRight),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBoxBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: iconBoxBorder, width: 1.5),
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: labelColor,
                    letterSpacing: 0.8,
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(0x22),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

class _BankChip extends StatelessWidget {
  const _BankChip({
    required this.label,
    required this.bankColor,
    required this.neutralText,
    required this.isNeutral,
  });

  final String label;
  final Color bankColor;
  final Color neutralText;
  final bool isNeutral;

  @override
  Widget build(BuildContext context) {
    final fg = isNeutral ? neutralText : bankColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bankColor.withAlpha(0x28),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: fg,
        ),
      ),
    );
  }
}

class _DotSeparator extends StatelessWidget {
  const _DotSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '·',
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

class _MergeCheckbox extends StatelessWidget {
  const _MergeCheckbox({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1 : 0.94,
      duration: const Duration(milliseconds: 220),
      curve: selected ? Curves.easeOutBack : Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFC4B5FD),
                    Color(0xFF7C3AED),
                  ],
                )
              : null,
          color: selected ? null : Colors.transparent,
          border: Border.all(
            color: selected
                ? const Color(0x00C084FC)
                : const Color(0xFF64748B).withValues(alpha: 0.85),
            width: selected ? 0 : 1.7,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x667C3AED),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: IgnorePointer(
          child: AnimatedScale(
            scale: selected ? 1 : 0.4,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 140),
              child: const Icon(
                Icons.check_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeHintDot extends StatelessWidget {
  const _SwipeHintDot({
    required this.revealed,
    required this.index,
  });

  final bool revealed;
  final int index;

  @override
  Widget build(BuildContext context) {
    final o = revealed
        ? (0.7 - index * 0.2).clamp(0.0, 1.0)
        : (0.15 - index * 0.04).clamp(0.0, 1.0);
    final Color dotColor = revealed
        ? const Color(0xFFEF4444).withValues(alpha: o)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.4 * o);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
      ),
    );
  }
}
