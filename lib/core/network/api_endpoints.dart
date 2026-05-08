import '../constants/app_constants.dart';

abstract final class ApiEndpoints {
  static String get _base => AppConstants.baseUrl;

  // Expense Management
  static String get expenses => '$_base/api/v1/expenses';
  static String expense(String id) => '$_base/api/v1/expenses/$id';

  // Budget
  static String get budget => '$_base/api/v1/budget';
  static String get budgetHistory => '$_base/api/v1/budget/history';

  // AI
  static String get aiCategorize => '$_base/api/v1/ai/categorize';
  static String get aiRephrase => '$_base/api/v1/ai/rephrase';
  static String get aiCorrect => '$_base/api/v1/ai/correct';
  static String get aiDefine => '$_base/api/v1/ai/define';
  static String get aiSummarize => '$_base/api/v1/ai/summarize';
  static String get aiSummarizeArticlesBatch =>
      '$_base/api/v1/ai/summarize-articles-batch';
  static String get aiSearch => '$_base/api/v1/ai/search';
  static String get aiGroundedSearch => '$_base/api/v1/ai/grounded-search';
  static String get aiArticleFollowup => '$_base/api/v1/ai/article-followup';
  static String get aiDeepResearch => '$_base/api/v1/ai/deep-research';
  static String get aiSearchFollowup => '$_base/api/v1/ai/search-followup';
  static String get aiSummarizeHistory => '$_base/api/v1/ai/summarize-history';

  // News
  static String get news => '$_base/api/v1/news';
  static String get newsRefresh => '$_base/api/v1/news/refresh';
  static String get newsMarkAllRead => '$_base/api/v1/news/mark-all-read';
  static String get newsXFeedSync => '$_base/api/v1/news/x-feed/sync';
  static String get newsXFeedStatus => '$_base/api/v1/news/x-feed/status';
  static String article(String id) => '$_base/api/v1/news/$id';
  static String articleSave(String id) => '$_base/api/v1/news/$id/save';
  static String articleRead(String id) => '$_base/api/v1/news/$id/read';

  // Cloud
  static String get cloudFiles => '$_base/api/v1/cloud/files';
  static String get cloudUpload => '$_base/api/v1/cloud/upload';
  static String get cloudSyncHistory => '$_base/api/v1/cloud/sync-history';

  // Auth
  static String get login => '$_base/api/v1/auth/login';
  static String get register => '$_base/api/v1/auth/register';

  // Saved Words
  static String get savedWords => '$_base/api/v1/saved-words';
  static String savedWord(String id) => '$_base/api/v1/saved-words/$id';

  // Article Chats
  static String articleChats(String articleId) =>
      '$_base/api/v1/article-chats/$articleId';
  static String articleChatSummary(String articleId) =>
      '$_base/api/v1/article-chats/$articleId/summary';

  // AI Smart Parse (voice expense)
  static String get aiSmartParse => '$_base/api/v1/ai/smart-parse';

  // Category Learnings
  static String get categoryLearnings => '$_base/api/v1/category-learnings';
  static String get categoryLearningsBatch => '$_base/api/v1/category-learnings/batch';

  // App Settings (server-side key-value store)
  static String get appSettings => '$_base/api/v1/app-settings';

  // User Preferences (cross-device settings sync)
  static String get userPreferences => '$_base/api/v1/user-preferences';
  static String get userPreferencesBatch =>
      '$_base/api/v1/user-preferences/batch';

  // Sync
  static String get sync => '$_base/api/v1/sync';
}
