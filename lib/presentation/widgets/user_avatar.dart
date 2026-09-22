import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Circular avatar used on headers and the Settings profile card.
///
/// When [photoPath] points at a readable file, that JPEG is shown. Otherwise
/// the 😎 fallback matches the previous chrome so News / Tutor / Cloud look
/// unchanged until a photo is set.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.size,
    this.photoPath,
    this.onTap,
    this.showEditBadge = false,
    this.fallbackEmoji = '😎',
    this.busy = false,
    this.hitSize,
    this.semanticLabel,
  });

  final double size;
  final String? photoPath;
  final VoidCallback? onTap;
  final bool showEditBadge;
  final String fallbackEmoji;
  final bool busy;

  /// Minimum tap target. Visual diameter stays [size].
  final double? hitSize;

  /// Spoken name when [onTap] is set. Headers default to Settings.
  final String? semanticLabel;

  bool get _hasFile {
    if (kIsWeb) return false;
    final path = photoPath;
    if (path == null || path.isEmpty) return false;
    try {
      return FileSystemEntity.isFileSync(path);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final ring = colors?.headerBg ?? colors?.bg ?? const Color(0xFF000000);
    final fill = (colors == null || colors.isDark)
        ? const Color(0xFF111111)
        : Colors.white;
    final inset = size >= 48 ? 2.5 : 2.0;
    final face = busy
        ? Center(
            child: SizedBox(
              width: size * 0.36,
              height: size * 0.36,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          )
        : _hasFile
            ? Image.file(
                File(photoPath!),
                key: ValueKey(photoPath),
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _EmojiFallback(
                  size: size,
                  emoji: fallbackEmoji,
                  fill: fill,
                ),
              )
            : _EmojiFallback(size: size, emoji: fallbackEmoji, fill: fill);

    final hit = (hitSize != null && hitSize! > size) ? hitSize! : size;
    final spoken = onTap == null ? null : (semanticLabel ?? 'Settings');

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: spoken,
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('user-avatar'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: hit,
          height: hit,
          child: Center(
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppColors.accent, AppColors.accentCyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    padding: EdgeInsets.all(inset),
                    child: ClipOval(child: face),
                  ),
                  if (showEditBadge && !busy)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: ring, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 11,
                          color: Colors.white,
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

class _EmojiFallback extends StatelessWidget {
  const _EmojiFallback({
    required this.size,
    required this.emoji,
    required this.fill,
  });

  final double size;
  final String emoji;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: fill,
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.42)),
      ),
    );
  }
}
