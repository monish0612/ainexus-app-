import '../../../domain/entities/news_entities.dart';

/// Chip order shown on the News category rail.
const List<String> kNewsCategoryRailLabels = <String>[
  'All',
  'AI News',
  'Finance',
  'Movies',
  'General',
];

/// Unread, unsaved articles across **every** category (All / AI News /
/// Finance / Movies / General). Saved and already-read rows never appear
/// in the feed; they live in Saved or are gone after Clear All.
List<Article> unreadUnsavedArticles(List<Article> all) {
  return [
    for (final a in all)
      if (!a.isRead && !a.isSaved) a,
  ];
}

/// Feed for the selected rail chip. `All` is the full unread+unsaved pile,
/// including Movies and General.
List<Article> newsFeedForCategory(
  List<Article> unreadUnsaved,
  String category,
) {
  if (category == 'All') return unreadUnsaved;
  return [
    for (final a in unreadUnsaved)
      if (a.category == category) a,
  ];
}

int newsCategoryCount(List<Article> unreadUnsaved, String category) {
  return newsFeedForCategory(unreadUnsaved, category).length;
}
