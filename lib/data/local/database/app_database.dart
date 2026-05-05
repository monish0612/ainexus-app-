import 'package:drift/drift.dart';

import 'connection/connection.dart' as connection;

part 'app_database.g.dart';

class Expenses extends Table {
  TextColumn get id => text()();
  RealColumn get amount => real()();
  TextColumn get description => text()();
  TextColumn get category => text()();
  TextColumn get bank => text()();
  TextColumn get cardType => text()();
  TextColumn get date => text()();
  BoolColumn get isManualCategory =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class BudgetEntries extends Table {
  TextColumn get id => text()();
  RealColumn get amount => real()();
  TextColumn get setAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class NewsArticles extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get excerpt => text()();
  TextColumn get source => text()();
  TextColumn get category => text()();
  TextColumn get imageUrl => text()();
  IntColumn get readTime => integer()();
  TextColumn get date => text()();
  TextColumn get blocksJson => text()();
  BoolColumn get isSaved => boolean().withDefault(const Constant(false))();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class CloudFiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get uploadDate => text()();
  BoolColumn get isStarred => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SavedWords extends Table {
  TextColumn get id => text()();
  TextColumn get word => text()();
  TextColumn get definition => text()();
  TextColumn get pronunciation => text()();
  TextColumn get partOfSpeech => text()();
  TextColumn get savedAt => text()();
  TextColumn get responseJson => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payload => text()();
  TextColumn get createdAt => text()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

class ArticleChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get articleId => text()();
  TextColumn get role => text()();
  TextColumn get msgText => text()();
  TextColumn get model => text().withDefault(const Constant(''))();
  TextColumn get sourcesJson => text().withDefault(const Constant('[]'))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class ArticleChatSummaries extends Table {
  TextColumn get articleId => text()();
  TextColumn get summaryText => text()();
  IntColumn get pairsCovered => integer()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {articleId};
}

class CategoryLearnings extends Table {
  TextColumn get keyword => text()();
  TextColumn get category => text()();

  @override
  Set<Column> get primaryKey => {keyword};
}

@DriftDatabase(
  tables: [
    Expenses,
    BudgetEntries,
    NewsArticles,
    CloudFiles,
    SavedWords,
    SyncQueue,
    CategoryLearnings,
    ArticleChatMessages,
    ArticleChatSummaries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(connection.openAppConnection());

  AppDatabase.background() : super(connection.openBackgroundConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(savedWords, savedWords.responseJson);
      }
      if (from < 3) {
        await migrator.createTable(articleChatMessages);
      }
      if (from < 4) {
        await migrator.createTable(articleChatSummaries);
      }
    },
  );
}
