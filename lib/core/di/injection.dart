import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/database/app_database.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/news_repository.dart';
import '../../data/services/ai_categorize_service.dart';
import '../../data/services/tutor_ai_service.dart';
import '../../data/services/user_preferences_service.dart';
import '../network/api_client.dart';

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

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(apiClientProvider),
  );
});

final aiCategorizeServiceProvider = Provider<AICategorizeService>((ref) {
  return AICategorizeService(ref.watch(apiClientProvider));
});

final tutorAiServiceProvider = Provider<TutorAiService>((ref) {
  return TutorAiService(ref.watch(apiClientProvider));
});

final userPreferencesServiceProvider =
    Provider<UserPreferencesService>((ref) {
  return UserPreferencesService(ref.watch(apiClientProvider));
});
