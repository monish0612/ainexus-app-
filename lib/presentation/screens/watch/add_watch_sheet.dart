import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/price_watch/price_models.dart';
import '../../../data/services/price_watch/price_parse.dart';
import '../../../data/services/price_watch/store_url.dart';
import '../../../data/services/price_watch/watch_facade.dart';
import '../../../data/services/price_watch/watch_store.dart';
import 'watch_providers.dart';

Future<String?> showAddWatchSheet(
  BuildContext context,
  WidgetRef ref, {
  String? seedUrl,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddWatchSheet(seedUrl: seedUrl),
  );
}

class _AddWatchSheet extends ConsumerStatefulWidget {
  const _AddWatchSheet({this.seedUrl});
  final String? seedUrl;

  @override
  ConsumerState<_AddWatchSheet> createState() => _AddWatchSheetState();
}

class _AddWatchSheetState extends ConsumerState<_AddWatchSheet> {
  late final TextEditingController _url;
  late final TextEditingController _target;
  bool _busy = false;
  String? _error;
  WatchPreview? _preview;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.seedUrl ?? '');
    _target = TextEditingController();
    if (_url.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _previewUrl());
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _previewUrl() async {
    setState(() {
      _error = null;
      _preview = null;
    });
    final raw = _url.text.trim();
    if (canonicalizeWatchUrl(raw) == null) {
      setState(
        () => _error =
            'Need a product page — search, category and restaurant menus will not work.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final preview = await ref.read(watchFacadeProvider).preview(raw);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _busy = false;
        _url.text = preview.canon.url;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    var preview = _preview;
    if (preview == null) {
      await _previewUrl();
      preview = _preview;
      if (preview == null) return;
    }
    setState(() => _busy = true);
    try {
      final item = await ref.read(watchFacadeProvider).addFromPreview(
            preview,
            targetPrice: parsePrice(_target.text),
          );
      TLog.i('Watch', 'Saved ${item.store.id} ${item.id}');
      if (!mounted) return;
      Navigator.of(context).pop(item.id);
    } on WatchDuplicateException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(e.existingId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final canon = _preview?.canon ?? canonicalizeWatchUrl(_url.text);
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
        ),
        child: SingleChildScrollView(
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Watch a price',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Amazon · Flipkart · Myntra · Ajio · Nykaa · Croma and more. '
                'History starts when you add it.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  height: 1.4,
                  color: colors.text3,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _previewUrl(),
                style: GoogleFonts.plusJakartaSans(color: colors.text, fontSize: 14),
                decoration: _field(colors, 'Paste product page URL'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.plusJakartaSans(color: colors.text, fontSize: 14),
                decoration: _field(colors, 'Target price (optional)'),
              ),
              if (canon != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      canon.store.label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ],
              if (_preview != null && !_busy) ...[
                const SizedBox(height: 14),
                _PreviewCard(hit: _preview!.hit, colors: colors),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _previewUrl,
                      child: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Watch'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _field(AppColors colors, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(color: colors.text4, fontSize: 13),
      filled: true,
      fillColor: colors.bg2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.border),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.hit, required this.colors});
  final ScrapeHit hit;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          if (hit.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                hit.imageUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 56, height: 56),
              ),
            )
          else
            const SizedBox(width: 56, height: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.name.isEmpty ? 'Product' : hit.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatInr(hit.price),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
