import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/database/app_database.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/news_repository.dart';
import '../../data/repositories/salary_repository.dart';
import '../../data/services/ai_categorize_service.dart';
import '../../data/services/expense_ai_search_service.dart';
import '../../data/services/news_summarize_service.dart';
import '../../data/services/tutor_ai_service.dart';
import '../../data/services/user_preferences_service.dart';
import '../../domain/entities/saved_search.dart';
import '../network/api_client.dart';
import '../services/image_search_store.dart';
import '../services/saved_search_store.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  ),
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(sharedPreferencesProvider),
  );
});

final salaryRepositoryProvider = Provider<SalaryRepository>((ref) {
  return SalaryRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(sharedPreferencesProvider),
  );
});

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(apiClientProvider),
  );
});

final aiCategorizeServiceProvider = Provider<AICategorizeService>((ref) {
  return AICategorizeService(ref.watch(apiClientProvider));
});

final expenseAiSearchServiceProvider = Provider<ExpenseAiSearchService>((ref) {
  return ExpenseAiSearchService(ref.watch(apiClientProvider));
});

final tutorAiServiceProvider = Provider<TutorAiService>((ref) {
  return TutorAiService(ref.watch(apiClientProvider));
});

final newsSummarizeServiceProvider = Provider<NewsSummarizeService>((ref) {
  return NewsSummarizeService(ref.watch(apiClientProvider));
});

final userPreferencesServiceProvider =
    Provider<UserPreferencesService>((ref) {
  return UserPreferencesService(ref.watch(apiClientProvider));
});

/// Singleton store for InsightAI saved searches. The store is `init()`ed
/// here so any consumer that touches it via this provider is guaranteed to
/// see a wired-up instance — no per-call `init` ceremony at the call site.
final savedSearchStoreProvider = Provider<SavedSearchStore>((ref) {
  final store = SavedSearchStore.instance;
  store.init(
    ref.watch(appDatabaseProvider),
    ref.watch(apiClientProvider),
  );
  return store;
});

/// Live stream of saved-search entries. Drift-backed so any change in the
/// underlying table propagates to every subscriber on the next tick.
final savedSearchesStreamProvider =
    StreamProvider<List<SavedSearchEntry>>((ref) {
  return ref.watch(savedSearchStoreProvider).watchAll();
});

/// Singleton store for InsightAI image (vision) searches. Mirrors the
/// retry / background-notification / cancel pattern of [OnlineSearchStore]
/// so the image upload path inherits all the lifecycle guarantees the
/// text path already provides.
final imageSearchStoreProvider = Provider<ImageSearchStore>((ref) {
  final store = ImageSearchStore.instance;
  store.init();
  return store;
});
