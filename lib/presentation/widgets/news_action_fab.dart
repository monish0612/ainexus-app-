import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';

/// Two scopes the FAB sheet exposes when a category chip is active.
enum NewsFabScope { all, currentCategory }

enum NewsFabAction { summarize, clearAll }

/// Animated speed-dial FAB used by News > For You.
///
/// Collapsed: gradient circle with a sparkles icon and a slow scale-pulse.
/// Expanded: dims the background with a [BackdropFilter] blur, slides up two
/// glassmorphism action cards (Summarize, Clear All), a compact scope toggle
/// when a category is active, and a footer chip reminding the user that
/// Saved articles are never touched.
///
/// The FAB is a single self-contained `Stack` overlay so it can be dropped
/// onto any tab. It only renders when [unreadCount] > 0.
class NewsActionFab extends StatefulWidget {
  const NewsActionFab({
    super.key,
    required this.colors,
    required this.unreadCount,
    required this.unreadCountInCategory,
    required this.activeCategory,
    required this.onAction,
  });

  final AppColors colors;

  /// Total unread+unsaved across ALL categories.
  final int unreadCount;

  /// Unread+unsaved in the currently-selected category chip (== unreadCount
  /// when "All" is selected). Used to label the segmented toggle.
  final int unreadCountInCategory;

  /// `'All'` if no category filter, otherwise the category name (e.g. `Finance`).
  final String activeCategory;

  /// Fires after the user picks an action and (for Clear All) confirms it.
  /// The host is responsible for the actual repo calls + navigation.
  final void Function(NewsFabAction action, NewsFabScope scope) onAction;

  @override
  State<NewsActionFab> createState() => _NewsActionFabState();
}

class _NewsActionFabState extends State<NewsActionFab>
    with TickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  late final Animation<double> _expand;
  late final AnimationController _pulseCtrl;
  bool _open = false;
  NewsFabScope _scope = NewsFabScope.all;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _expand = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      HapticFeedback.lightImpact();
      _expandCtrl.forward();
    } else {
      _expandCtrl.reverse();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _expandCtrl.reverse();
  }

  int get _scopeCount {
    if (widget.activeCategory == 'All') return widget.unreadCount;
    return _scope == NewsFabScope.all
        ? widget.unreadCount
        : widget.unreadCountInCategory;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.unreadCount <= 0) return const SizedBox.shrink();

    return Stack(
      children: [
        // ── Backdrop dim + blur (only when expanded) ────────────────────
        if (_expandCtrl.value > 0 || _open)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _expand,
              builder: (_, __) {
                if (_expand.value <= 0) return const SizedBox.shrink();
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: 12 * _expand.value,
                      sigmaY: 12 * _expand.value,
                    ),
                    child: ColoredBox(
                      color: Colors.black
                          .withValues(alpha: 0.45 * _expand.value),
                    ),
                  ),
                );
              },
            ),
          ),

        // ── Action cards (slide + fade up) ──────────────────────────────
        Positioned(
          right: 16,
          bottom: 96,
          child: AnimatedBuilder(
            animation: _expand,
            builder: (_, __) {
              if (_expand.value <= 0) return const SizedBox.shrink();
              return IgnorePointer(
                ignoring: !_open,
                child: Opacity(
                  opacity: _expand.value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - _expand.value) * 16),
                    child: _SheetContent(
                      colors: widget.colors,
                      activeCategory: widget.activeCategory,
                      scope: _scope,
                      onScope: (s) => setState(() => _scope = s),
                      countInScope: _scopeCount,
                      onSummarize: () {
                        _close();
                        Future<void>.delayed(
                          const Duration(milliseconds: 220),
                          () => widget.onAction(
                            NewsFabAction.summarize,
                            _scope,
                          ),
                        );
                      },
                      onClearAll: () {
                        _close();
                        Future<void>.delayed(
                          const Duration(milliseconds: 220),
                          () => widget.onAction(
                            NewsFabAction.clearAll,
                            _scope,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // ── The FAB itself ─────────────────────────────────────────────
        Positioned(
          right: 16,
          bottom: 24,
          child: _FabCircle(
            pulse: _pulseCtrl,
            expand: _expand,
            unreadCount: widget.unreadCount,
            onTap: _toggle,
          ),
        ),
      ],
    );
  }
}

class _FabCircle extends StatelessWidget {
  const _FabCircle({
    required this.pulse,
    required this.expand,
    required this.unreadCount,
    required this.onTap,
  });

  final AnimationController pulse;
  final Animation<double> expand;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pulse, expand]),
      builder: (_, __) {
        final scale = 1.0 + 0.04 * pulse.value;
        final rotate = expand.value * 0.785; // 45deg
        return Transform.scale(
          scale: scale,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Ink(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: const Color(0xFFA855F7).withValues(alpha: 0.30),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: rotate,
                      child: const Icon(
                        LucideIcons.sparkles,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetContent extends StatelessWidget {
  const _SheetContent({
    required this.colors,
    required this.activeCategory,
    required this.scope,
    required this.onScope,
    required this.countInScope,
    required this.onSummarize,
    required this.onClearAll,
  });

  final AppColors colors;
  final String activeCategory;
  final NewsFabScope scope;
  final ValueChanged<NewsFabScope> onScope;
  final int countInScope;
  final VoidCallback onSummarize;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final width = (screenW - 32).clamp(280.0, 360.0);
    final hasFilter = activeCategory != 'All';

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: colors.isDark
                ? const Color(0xCC0B0B12)
                : const Color(0xF2FFFFFF),
            border: Border.all(
              color: colors.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasFilter) ...[
                  _ScopeToggle(
                    colors: colors,
                    activeCategory: activeCategory,
                    scope: scope,
                    onScope: onScope,
                  ),
                  const SizedBox(height: 12),
                ],
                _ActionRow(
                  icon: LucideIcons.sparkles,
                  iconBg: const Color(0xFF6366F1),
                  iconBg2: const Color(0xFFA855F7),
                  title: 'Summarize',
                  subtitle:
                      'Quick AI summary of $countInScope unread article${countInScope == 1 ? '' : 's'}',
                  colors: colors,
                  onTap: onSummarize,
                ),
                const SizedBox(height: 10),
                _ActionRow(
                  icon: LucideIcons.eraser,
                  iconBg: const Color(0xFFEF4444),
                  iconBg2: const Color(0xFFF97316),
                  title: 'Clear All',
                  subtitle: 'Mark $countInScope as read',
                  destructive: true,
                  colors: colors,
                  onTap: onClearAll,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      LucideIcons.bookmark,
                      size: 12,
                      color: colors.text4,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Saved articles are never touched',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colors.text3,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopeToggle extends StatelessWidget {
  const _ScopeToggle({
    required this.colors,
    required this.activeCategory,
    required this.scope,
    required this.onScope,
  });

  final AppColors colors;
  final String activeCategory;
  final NewsFabScope scope;
  final ValueChanged<NewsFabScope> onScope;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _toggleSegment(
            label: 'All categories',
            selected: scope == NewsFabScope.all,
            onTap: () => onScope(NewsFabScope.all),
          ),
          _toggleSegment(
            label: activeCategory,
            selected: scope == NewsFabScope.currentCategory,
            onTap: () => onScope(NewsFabScope.currentCategory),
          ),
        ],
      ),
    );
  }

  Widget _toggleSegment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final selectedFill = colors.isDark
        ? const Color(0xFF1A1A24)
        : Colors.white;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? selectedFill : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.text : colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.iconBg,
    required this.iconBg2,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconBg2;
  final String title;
  final String subtitle;
  final AppColors colors;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: destructive
                  ? const Color(0x33EF4444)
                  : colors.border,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [iconBg, iconBg2],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: iconBg.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: destructive
                            ? const Color(0xFFEF4444)
                            : colors.text,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: colors.text3,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: colors.text4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
