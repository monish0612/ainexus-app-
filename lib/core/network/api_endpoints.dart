import '../constants/app_constants.dart';

abstract final class ApiEndpoints {
  static String get _base => AppConstants.baseUrl;

  // Expense Management
  static String get expenses => '$_base/api/v1/expenses';
  static String expense(String id) => '$_base/api/v1/expenses/$id';

  /// Cross-device delete sync — pull-only endpoint that returns expense
  /// tombstones newer than the optional `since` ISO-8601 timestamp.
  static String get expenseTombstones =>
      '$_base/api/v1/expenses/tombstones';

  // Budget
  static String get budget => '$_base/api/v1/budget';
  static String get budgetHistory => '$_base/api/v1/budget/history';

  // Salary (monthly in-hand income — one entry per 'YYYY-MM')
  static String get salary => '$_base/api/v1/salary';
  static String get salaryHistory => '$_base/api/v1/salary/history';

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

  /// Live directory of Gemini models the backend's GOOGLE_API_KEY can
  /// invoke. Used by the Settings sheet to render a dynamic picker so
  /// the user never types a model id Google hasn't shipped yet (or has
  /// retired). Backed by Google's `/v1beta/models` endpoint, cached
  /// 5 min server-side.
  static String get aiModels => '$_base/api/v1/ai/models';

  // ── InsightAI Image (vision) ───────────────────────────────────────────
  // Dedicated vision endpoints that accept a base64-encoded image +
  // optional text query. The backend routes the request to the
  // multimodal variant of the user-selected provider (Gemini Vision
  // for `provider=gemini`, Grok Vision for `provider=xgrok`) and
  // returns the same `GroundedSearchResponse` shape as the text path
  // so the UI / save-sync layer can reuse all existing plumbing.
  static String get aiImageSearch => '$_base/api/v1/ai/image-search';
  static String get aiImageFollowup => '$_base/api/v1/ai/image-followup';

  // News
  static String get news => '$_base/api/v1/news';
  static String get newsRefresh => '$_base/api/v1/news/refresh';
  static String get newsMarkAllRead => '$_base/api/v1/news/mark-all-read';

  /// Easter-egg "nuke": deletes EVERY article server-side, including saved
  /// ones, and tombstones their guids so the feed sync can't re-import them.
  static String get newsNuke => '$_base/api/v1/news/nuke';
  static String get newsXFeedSync => '$_base/api/v1/news/x-feed/sync';
  static String get newsXFeedStatus => '$_base/api/v1/news/x-feed/status';
  static String article(String id) => '$_base/api/v1/news/$id';
  static String articleSave(String id) => '$_base/api/v1/news/$id/save';
  static String articleRead(String id) => '$_base/api/v1/news/$id/read';

  // Cloud
  static String get cloudFiles => '$_base/api/v1/cloud/files';
  static String get cloudUpload => '$_base/api/v1/cloud/upload';
  static String get cloudSyncHistory => '$_base/api/v1/cloud/sync-history';

  /// Token broker — returns a short-lived Google Drive access token so the app
  /// can talk to Drive directly without embedding the service-account key.
  static String get cloudDriveToken => '$_base/api/v1/cloud/token';

  // Auth
  static String get login => '$_base/api/v1/auth/login';
  static String get register => '$_base/api/v1/auth/register';
  /// App JWT mint. Must be a full URL (not `/api/...`) so Dio does not
  /// drop the `/nexusai` path prefix via URI resolve.
  static String get appLogin => '$_base/api/v1/auth/app-login';

  // Saved Words
  static String get savedWords => '$_base/api/v1/saved-words';
  static String savedWord(String id) => '$_base/api/v1/saved-words/$id';

  /// Cross-device delete sync — pull-only endpoint that returns saved-word
  /// tombstones newer than the optional `since` ISO-8601 timestamp.
  static String get savedWordTombstones =>
      '$_base/api/v1/saved-words/tombstones';

  // Article Chats
  static String articleChats(String articleId) =>
      '$_base/api/v1/article-chats/$articleId';
  static String articleChatSummary(String articleId) =>
      '$_base/api/v1/article-chats/$articleId/summary';

  // Saved Searches (InsightAI bookmarked URL-summaries / text searches with
  // persistent follow-up chats). Mirrors the article-chats wire shape so the
  // sync semantics are identical and battle-tested.
  static String get savedSearches => '$_base/api/v1/saved-searches';
  static String savedSearch(String id) => '$_base/api/v1/saved-searches/$id';
  static String savedSearchChats(String id) =>
      '$_base/api/v1/saved-searches/$id/chat';
  static String savedSearchChatSummary(String id) =>
      '$_base/api/v1/saved-searches/$id/summary';
  // Cross-device delete sync — pull-only endpoint that returns tombstones
  // newer than the optional `since` ISO-8601 timestamp.
  static String get savedSearchTombstones =>
      '$_base/api/v1/saved-searches/tombstones';

  // AI Smart Parse (voice expense)
  static String get aiSmartParse => '$_base/api/v1/ai/smart-parse';

  // AI Expense Query (natural-language → structured local query spec)
  static String get aiExpenseQuery => '$_base/api/v1/ai/expense-query';

  // AI Expense Insight (computed facts → generative, grounded recommendation)
  static String get aiExpenseInsight => '$_base/api/v1/ai/expense-insight';

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

  // Cross-device reset epoch — a nuke bumps the generation here; every device
  // compares it on launch/resume and wipes its local copy when it falls behind.
  static String get dataReset => '$_base/api/v1/data-reset';
}
