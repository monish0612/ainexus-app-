import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/saved_search.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SavedSearchesSheet — bottom-sheet history view for InsightAI saved items
// ─────────────────────────────────────────────────────────────────────────────
//
// Behaviour:
//   • Live list backed by `savedSearchesStreamProvider` (Drift `.watch()`).
//   • Filter input (substring match across query + title; case-insensitive).
//   • Grouped by Today / Yesterday / This Week / Older — matches the
//     mental model users already have from email and chat lists.
//   • Swipe-to-delete with a 4s undo snackbar (mirrors Gmail conventions).
//   • Tap a row to dismiss the sheet, returning the entry. The caller is
//     expected to push the detail sheet for the chosen entry.

class SavedSearchesSheet extends ConsumerStatefulWidget {
  const SavedSearchesSheet({super.key});

  @override
  ConsumerState<SavedSearchesSheet> createState() => _SavedSearchesSheetState();
}

class _SavedSearchesSheetState extends ConsumerState<SavedSearchesSheet> {
  final TextEditingController _filterCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final stream = ref.watch(savedSearchesStreamProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // SafeArea(top: false) keeps the rounded grabber edge flush with
        // the visible top of the sheet while reserving the bottom system
        // inset (gesture-nav bar) so list rows aren't clipped by it.
        child: SafeArea(
          top: false,
          child: Column(
          children: [
            _buildGrabber(colors),
            _buildHeader(colors, stream.maybeWhen(
              data: (rows) => rows.length,
              orElse: () => 0,
            )),
            _buildFilter(colors),
            const SizedBox(height: 8),
            Expanded(
              child: stream.when(
                data: (rows) => _buildList(colors, rows, scrollController),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) {
                  TLog.w('SavedSearchesSheet', 'stream error', error: e);
                  return _buildEmpty(
                    colors,
                    icon: LucideIcons.alertTriangle,
                    title: 'Couldn\'t load saved searches',
                    body: 'Pull down and try again — they\'re still safe on '
                        'your device.',
                  );
                },
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrabber(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: colors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(AppColors colors, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 8),
      child: Row(
        children: [
          const Icon(LucideIcons.history, size: 18, color: Color(0xFFC084FC)),
          const SizedBox(width: 8),
          Text(
            'Saved searches',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
          const SizedBox(width: 8),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFC084FC).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFC084FC),
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(LucideIcons.x, size: 20, color: colors.text3),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildFilter(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _filterCtrl,
        onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Filter saved searches\u2026',
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: colors.text5,
          ),
          prefixIcon: Icon(LucideIcons.search, size: 18, color: colors.text5),
          suffixIcon: _filter.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _filterCtrl.clear();
                    setState(() => _filter = '');
                  },
                  icon: Icon(LucideIcons.x, size: 16, color: colors.text5),
                ),
          filled: true,
          fillColor: colors.bg1,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFC084FC), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    AppColors colors,
    List<SavedSearchEntry> rows,
    ScrollController controller,
  ) {
    if (rows.isEmpty) {
      return _buildEmpty(
        colors,
        icon: LucideIcons.bookmark,
        title: 'No saved searches yet',
        body: 'Bookmark a search or summary to keep it forever — it syncs '
            'across devices automatically.',
      );
    }

    final filtered = _filter.isEmpty
        ? rows
        : rows
            .where((e) =>
                e.query.toLowerCase().contains(_filter) ||
                e.title.toLowerCase().contains(_filter))
            .toList(growable: false);

    if (filtered.isEmpty) {
      return _buildEmpty(
        colors,
        icon: LucideIcons.searchX,
        title: 'No matches',
        body: 'Try a different filter term.',
      );
    }

    final groups = _groupByRecency(filtered);

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              child: Text(
                group.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: colors.text5,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            for (final entry in group.entries) _buildRow(colors, entry),
          ],
        );
      },
    );
  }

  Widget _buildRow(AppColors colors, SavedSearchEntry entry) {
    final iconData = entry.kind == SavedSearchKind.url
        ? LucideIcons.link
        : LucideIcons.search;
    final accent = entry.kind == SavedSearchKind.url
        ? const Color(0xFF4285F4)
        : const Color(0xFFC084FC);

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(LucideIcons.trash2,
            color: Color(0xFFEF4444), size: 22),
      ),
      onDismissed: (_) => _onDelete(entry),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).maybePop<SavedSearchEntry>(entry);
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.bg1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconData, color: accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title.isNotEmpty ? entry.title : entry.query,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: colors.text4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 16, color: colors.text5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(
    AppColors colors, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFC084FC).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.bookmark,
                  color: Color(0xFFC084FC), size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: colors.text4,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(SavedSearchEntry entry) {
    final ts = DateTime.tryParse(entry.updatedAt);
    final relative = ts == null ? '' : _relativeTime(ts.toLocal());
    final parts = <String>[
      if (relative.isNotEmpty) relative,
      if (entry.responseType.isNotEmpty) _prettyType(entry.responseType),
    ];
    return parts.join(' \u00B7 ');
  }

  static String _prettyType(String t) {
    switch (t) {
      case SavedSearchResponseType.summarizer:
        return 'Summary';
      case SavedSearchResponseType.grounded:
        return 'Grounded';
      case SavedSearchResponseType.tavily:
        return 'Tavily';
      default:
        return t;
    }
  }

  static String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 1) return '1m ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _onDelete(SavedSearchEntry entry) async {
    final store = ref.read(savedSearchStoreProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    HapticFeedback.lightImpact();
    await store.delete(entry.id);
    final label = entry.title.isEmpty ? entry.query : entry.title;
    final shortLabel = label.length > 36 ? '${label.substring(0, 33)}\u2026' : label;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Text(
        'Removed "$shortLabel"',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      backgroundColor: const Color(0xFF1F2937),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(milliseconds: 2200),
      action: SnackBarAction(
        label: 'Undo',
        textColor: const Color(0xFFC084FC),
        onPressed: () => store.undelete(entry.id),
      ),
    ));
  }

  // ── Grouping ──────────────────────────────────────────────────────────────

  List<_RecencyGroup> _groupByRecency(List<SavedSearchEntry> rows) {
    final today = <SavedSearchEntry>[];
    final yesterday = <SavedSearchEntry>[];
    final thisWeek = <SavedSearchEntry>[];
    final older = <SavedSearchEntry>[];

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday =
        startOfToday.subtract(const Duration(days: 1));
    final startOfWeek =
        startOfToday.subtract(const Duration(days: 7));

    for (final e in rows) {
      final ts = DateTime.tryParse(e.updatedAt)?.toLocal();
      if (ts == null) {
        older.add(e);
        continue;
      }
      if (ts.isAfter(startOfToday)) {
        today.add(e);
      } else if (ts.isAfter(startOfYesterday)) {
        yesterday.add(e);
      } else if (ts.isAfter(startOfWeek)) {
        thisWeek.add(e);
      } else {
        older.add(e);
      }
    }

    return [
      if (today.isNotEmpty) _RecencyGroup('TODAY', today),
      if (yesterday.isNotEmpty) _RecencyGroup('YESTERDAY', yesterday),
      if (thisWeek.isNotEmpty) _RecencyGroup('THIS WEEK', thisWeek),
      if (older.isNotEmpty) _RecencyGroup('OLDER', older),
    ];
  }
}

class _RecencyGroup {
  const _RecencyGroup(this.label, this.entries);
  final String label;
  final List<SavedSearchEntry> entries;
}
