import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

/// Opens the live MonishNotes app (same Coolify site) from Nexus Cloud.
class NotesLauncher extends StatelessWidget {
  const NotesLauncher({super.key});

  static final Uri notesUri = Uri.parse('https://notes.monishlabs.com');

  Future<void> _open(BuildContext context) async {
    final ok = await launchUrl(notesUri, mode: LaunchMode.inAppBrowserView);
    if (!ok && context.mounted) {
      await launchUrl(notesUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: colors.navBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(LucideIcons.bookOpen, color: colors.text, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'MonishNotes',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                ),
                Text(
                  'Open',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: colors.text.withValues(alpha: 0.55),
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
