import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../domain/entities/news_entities.dart';

/// Icon used on category chips, badges, and saved rows.
IconData newsCategoryIcon(String category) {
  switch (category) {
    case 'Finance':
      return LucideIcons.trendingUp;
    case 'AI News':
      return LucideIcons.cpu;
    case 'Movies':
      return LucideIcons.film;
    case 'General':
      return LucideIcons.globe;
    default:
      return LucideIcons.newspaper;
  }
}

/// Category accent parsed from [CAT_COLOR]. Shared by feed cards, the
/// article reader, and Saved so every surface stays in sync.
Color newsCategoryColor(String category) {
  final hex = CAT_COLOR[category] ?? '#818CF8';
  final value = hex.replaceFirst('#', '');
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return const Color(0xFF818CF8);
  return Color(parsed + 0xFF000000);
}

/// Bottom category rail + list padding so cards clear the dock and FAB.
const double kNewsCategoryRailHeight = 56;
const double kNewsFeedBottomInset = 160;
const EdgeInsets kNewsSnackBarMargin = EdgeInsets.fromLTRB(20, 0, 20, 88);
