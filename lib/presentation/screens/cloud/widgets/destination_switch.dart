import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/nas_file.dart';
import '../../../providers/cloud_destination_provider.dart';
import '../stats/widgets/stats_chrome.dart';

/// Picks where the Cloud tab reads from and writes to.
///
/// The one thing this control exists to prevent is an upload landing somewhere
/// the owner did not intend. Everything about it follows from that:
///
///   • it lives directly above the file list, never inside a menu, so the
///     current target is on screen at the instant the upload button is tapped;
///   • the selected side is filled and coloured while the other is drawn in
///     the muted palette, so the answer is readable at a glance rather than by
///     comparing two similar pills;
///   • the sliding indicator is animated, so switching *reads* as the list
///     being replaced rather than as a filter being applied to one list;
///   • a NAS with no credential on the server is rendered plainly unavailable
///     and cannot be selected, rather than accepting the tap and failing later
///     with a file already chosen.
class DestinationSwitch extends ConsumerWidget {
  const DestinationSwitch({super.key, this.onChanged});

  /// Called after the selection has changed, so the screen can reload.
  final ValueChanged<CloudDestination>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final view = ref.watch(cloudDestinationViewProvider);
    final nasBlocked = !view.nas.selectable;

    Future<void> pick(CloudDestination d) async {
      if (d == view.selected) return;
      if (d == CloudDestination.nas && nasBlocked) return;
      await ref.read(cloudDestinationProvider.notifier).select(d);
      // Re-check on the way in: he may have switched the NAS on since the
      // status was last fetched, and arriving at a stale "not responding"
      // screen when it is in fact up would be its own small betrayal.
      if (d == CloudDestination.nas) {
        unawaited(ref.read(nasAvailabilityProvider.notifier).refresh());
      }
      onChanged?.call(d);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final half = (constraints.maxWidth - 8) / 2;
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border),
                      ),
                    ),
                  ),
                  // The travelling highlight. Curves.easeOutCubic rather than a
                  // linear slide so it arrives settled instead of stopping dead.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: view.isNas ? half + 4 : 4,
                    top: 4,
                    bottom: 4,
                    width: half,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _Segment(
                          icon: LucideIcons.cloud,
                          label: 'Google Drive',
                          selected: !view.isNas,
                          onTap: () => pick(CloudDestination.drive),
                        ),
                      ),
                      Expanded(
                        child: _Segment(
                          icon: LucideIcons.hardDrive,
                          label: 'NAS',
                          selected: view.isNas,
                          disabled: nasBlocked,
                          onTap: () => pick(CloudDestination.nas),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 9),
          _TargetLine(view: view),
        ],
      ),
    );
  }
}

/// One half of the control.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final color = disabled
        ? colors.text4
        : selected
            ? AppColors.accent
            : colors.text3;

    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: '$label storage${disabled ? ', unavailable' : ''}',
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(disabled ? LucideIcons.lock : icon, size: 15, color: color),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sentence under the control that names the destination in full.
///
/// The segmented control alone says "NAS" in three letters. This says where on
/// the NAS, which is the difference between trusting the label and knowing the
/// path — and when the NAS cannot be written to, it says that instead, so the
/// state is legible before a file is chosen rather than after.
class _TargetLine extends StatelessWidget {
  const _TargetLine({required this.view});

  final CloudDestinationView view;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    late final IconData icon;
    late final String text;
    late final Color tint;

    if (!view.isNas) {
      icon = LucideIcons.upload;
      text = 'Uploads go to Google Drive';
      tint = colors.text4;
    } else {
      switch (view.nas.state) {
        case NasStorageState.ready:
          icon = LucideIcons.upload;
          text = 'Uploads go to ${view.nas.root.isEmpty ? 'the NAS' : view.nas.root}';
          tint = colors.text4;
        case NasStorageState.unknown:
          icon = LucideIcons.loader;
          text = 'Checking the NAS…';
          tint = colors.text4;
        case NasStorageState.unreachable:
          icon = LucideIcons.powerOff;
          text = 'The NAS is not responding — it may be switched off';
          tint = toneColor(StatTone.warn, colors);
        case NasStorageState.badCredential:
          icon = LucideIcons.keyRound;
          text = 'The server\'s NAS password was rejected';
          tint = toneColor(StatTone.bad, colors);
        case NasStorageState.notConfigured:
          icon = LucideIcons.lock;
          text = 'NAS storage is not set up on the server yet';
          tint = toneColor(StatTone.warn, colors);
      }
    }

    // Keyed on the text so a change cross-fades rather than snapping, which
    // makes a switch feel like the same control changing its mind.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Row(
        key: ValueKey(text),
        children: [
          Icon(icon, size: 12.5, color: tint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: tint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
