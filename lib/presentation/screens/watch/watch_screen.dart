import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/price_watch/price_models.dart';
import '../../../data/services/price_watch/store_url.dart';
import '../../../presentation/widgets/swipe_to_delete.dart';
import 'add_watch_sheet.dart';
import 'watch_providers.dart';
import 'widgets/watch_card.dart';
import 'widgets/watch_detail_sheet.dart';

class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key, this.openProductId});

  final String? openProductId;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  WatchStore? _filter;
  bool _checking = false;
  String? _opened;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _opened = widget.openProductId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_catchUp());
      unawaited(ref.read(watchFacadeProvider).markAlertsRead());
      if (_opened != null) unawaited(_openById(_opened!));
    });
  }

  Future<void> _catchUp() async {
    setState(() => _checking = true);
    try {
      final facade = ref.read(watchFacadeProvider);
      final results = await facade.checkDue(force: true);
      final notifier = ref.read(watchNotifierProvider);
      await notifier.ensureChannel();
      for (final r in results) {
        if (!r.ok || r.pending || r.reasons.isEmpty || r.price == null) continue;
        final item = await ref.read(watchRepositoryProvider).getById(r.itemId);
        if (item == null) continue;
        await notifier.showChange(
          item: item,
          oldPrice: r.oldPrice ?? item.currentPrice,
          newPrice: r.price!,
          reasons: r.reasons,
        );
      }
    } catch (e) {
      TLog.w('Watch', 'Catch-up failed: $e', error: e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _add({String? seedUrl}) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      final id = await showAddWatchSheet(context, ref, seedUrl: seedUrl);
      if (!mounted || id == null) return;
      final item = await ref.read(watchRepositoryProvider).getById(id);
      if (!mounted || item == null) return;
      await _openDetail(item);
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _openById(String id) async {
    final item = await ref.read(watchRepositoryProvider).getById(id);
    if (!mounted || item == null) return;
    setState(() => _opened = id);
    await _openDetail(item);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingWatchUrlProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      ref.read(pendingWatchUrlProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_add(seedUrl: next));
      });
    });
    ref.listen<String?>(pendingWatchProductIdProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      ref.read(pendingWatchProductIdProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openById(next));
      });
    });
    final colors = Theme.of(context).extension<AppColors>()!;
    final itemsAsync = ref.watch(watchItemsProvider);
    final unread = ref.watch(watchUnreadProvider).valueOrNull ?? 0;
    final all = itemsAsync.valueOrNull ?? [];
    final items = all.where((p) => _filter == null || p.store == _filter).toList();
    final filterStores = <WatchStore?>[
      null,
      ...{for (final p in all) p.store},
    ];

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _WatchHeader(
              colors: colors,
              unread: unread,
              checking: _checking,
              onBack: () => Navigator.of(context).pop(),
              onAdd: () => _add(),
              onRefresh: _catchUp,
            ),
            if (all.isNotEmpty)
              _StoreFilters(
                stores: filterStores,
                selected: _filter,
                onChanged: (s) => setState(() => _filter = s),
                colors: colors,
              ),
            Expanded(
              child: itemsAsync.isLoading && items.isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : items.isEmpty
                      ? _EmptyWatch(colors: colors, onAdd: () => _add())
                      : RefreshIndicator(
                          onRefresh: _catchUp,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final item = items[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SwipeToDelete(
                                  key: ValueKey(item.id),
                                  borderRadius: 18,
                                  headline: 'Delete this watch?',
                                  title: item.name,
                                  message:
                                      'This price watch will be removed from your list.',
                                  onDelete: () =>
                                      ref.read(watchFacadeProvider).delete(item.id),
                                  child: WatchCard(
                                    item: item,
                                    colors: colors,
                                    highlighted: item.id == _opened,
                                    onTap: () => _openDetail(item),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(WatchItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WatchDetailSheet(itemId: item.id),
    );
  }
}

class _WatchHeader extends StatelessWidget {
  const _WatchHeader({
    required this.colors,
    required this.unread,
    required this.checking,
    required this.onBack,
    required this.onAdd,
    required this.onRefresh,
  });

  final AppColors colors;
  final int unread;
  final bool checking;
  final VoidCallback onBack;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(LucideIcons.chevronLeft, color: colors.text),
          ),
          Expanded(
            child: Text(
              'Watch',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: colors.text,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '$unread new',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          IconButton(
            onPressed: checking ? null : onRefresh,
            icon: checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(LucideIcons.refreshCw, color: colors.text2, size: 20),
          ),
          IconButton(
            onPressed: onAdd,
            icon: Icon(LucideIcons.plus, color: colors.text),
          ),
        ],
      ),
    );
  }
}

class _StoreFilters extends StatelessWidget {
  const _StoreFilters({
    required this.stores,
    required this.selected,
    required this.onChanged,
    required this.colors,
  });

  final List<WatchStore?> stores;
  final WatchStore? selected;
  final ValueChanged<WatchStore?> onChanged;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: stores.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final store = stores[i];
          final on = selected == store;
          final label = store?.label ?? 'All';
          return GestureDetector(
            onTap: () => onChanged(store),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: on ? colors.bg3 : colors.bg2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? colors.border : colors.border2),
              ),
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? colors.text : colors.text3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyWatch extends StatelessWidget {
  const _EmptyWatch({required this.colors, required this.onAdd});
  final AppColors colors;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.tag, size: 36, color: colors.text4),
            const SizedBox(height: 12),
            Text(
              'Watch live prices',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Paste a product page from Amazon, Flipkart, Myntra, Ajio, Nykaa, Croma and other stores. Search and menus are ignored.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.45,
                color: colors.text3,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('Add a product')),
          ],
        ),
      ),
    );
  }
}
