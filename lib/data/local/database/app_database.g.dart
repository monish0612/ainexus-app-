// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ExpensesTable extends Expenses with TableInfo<$ExpensesTable, Expense> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bankMeta = const VerificationMeta('bank');
  @override
  late final GeneratedColumn<String> bank = GeneratedColumn<String>(
      'bank', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardTypeMeta =
      const VerificationMeta('cardType');
  @override
  late final GeneratedColumn<String> cardType = GeneratedColumn<String>(
      'card_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
      'date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isManualCategoryMeta =
      const VerificationMeta('isManualCategory');
  @override
  late final GeneratedColumn<bool> isManualCategory = GeneratedColumn<bool>(
      'is_manual_category', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_manual_category" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        amount,
        description,
        category,
        bank,
        cardType,
        date,
        isManualCategory
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(Insertable<Expense> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('bank')) {
      context.handle(
          _bankMeta, bank.isAcceptableOrUnknown(data['bank']!, _bankMeta));
    } else if (isInserting) {
      context.missing(_bankMeta);
    }
    if (data.containsKey('card_type')) {
      context.handle(_cardTypeMeta,
          cardType.isAcceptableOrUnknown(data['card_type']!, _cardTypeMeta));
    } else if (isInserting) {
      context.missing(_cardTypeMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('is_manual_category')) {
      context.handle(
          _isManualCategoryMeta,
          isManualCategory.isAcceptableOrUnknown(
              data['is_manual_category']!, _isManualCategoryMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Expense map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Expense(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      bank: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bank'])!,
      cardType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_type'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date'])!,
      isManualCategory: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}is_manual_category'])!,
    );
  }

  @override
  $ExpensesTable createAlias(String alias) {
    return $ExpensesTable(attachedDatabase, alias);
  }
}

class Expense extends DataClass implements Insertable<Expense> {
  final String id;
  final double amount;
  final String description;
  final String category;
  final String bank;
  final String cardType;
  final String date;
  final bool isManualCategory;
  const Expense(
      {required this.id,
      required this.amount,
      required this.description,
      required this.category,
      required this.bank,
      required this.cardType,
      required this.date,
      required this.isManualCategory});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['amount'] = Variable<double>(amount);
    map['description'] = Variable<String>(description);
    map['category'] = Variable<String>(category);
    map['bank'] = Variable<String>(bank);
    map['card_type'] = Variable<String>(cardType);
    map['date'] = Variable<String>(date);
    map['is_manual_category'] = Variable<bool>(isManualCategory);
    return map;
  }

  ExpensesCompanion toCompanion(bool nullToAbsent) {
    return ExpensesCompanion(
      id: Value(id),
      amount: Value(amount),
      description: Value(description),
      category: Value(category),
      bank: Value(bank),
      cardType: Value(cardType),
      date: Value(date),
      isManualCategory: Value(isManualCategory),
    );
  }

  factory Expense.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Expense(
      id: serializer.fromJson<String>(json['id']),
      amount: serializer.fromJson<double>(json['amount']),
      description: serializer.fromJson<String>(json['description']),
      category: serializer.fromJson<String>(json['category']),
      bank: serializer.fromJson<String>(json['bank']),
      cardType: serializer.fromJson<String>(json['cardType']),
      date: serializer.fromJson<String>(json['date']),
      isManualCategory: serializer.fromJson<bool>(json['isManualCategory']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'amount': serializer.toJson<double>(amount),
      'description': serializer.toJson<String>(description),
      'category': serializer.toJson<String>(category),
      'bank': serializer.toJson<String>(bank),
      'cardType': serializer.toJson<String>(cardType),
      'date': serializer.toJson<String>(date),
      'isManualCategory': serializer.toJson<bool>(isManualCategory),
    };
  }

  Expense copyWith(
          {String? id,
          double? amount,
          String? description,
          String? category,
          String? bank,
          String? cardType,
          String? date,
          bool? isManualCategory}) =>
      Expense(
        id: id ?? this.id,
        amount: amount ?? this.amount,
        description: description ?? this.description,
        category: category ?? this.category,
        bank: bank ?? this.bank,
        cardType: cardType ?? this.cardType,
        date: date ?? this.date,
        isManualCategory: isManualCategory ?? this.isManualCategory,
      );
  Expense copyWithCompanion(ExpensesCompanion data) {
    return Expense(
      id: data.id.present ? data.id.value : this.id,
      amount: data.amount.present ? data.amount.value : this.amount,
      description:
          data.description.present ? data.description.value : this.description,
      category: data.category.present ? data.category.value : this.category,
      bank: data.bank.present ? data.bank.value : this.bank,
      cardType: data.cardType.present ? data.cardType.value : this.cardType,
      date: data.date.present ? data.date.value : this.date,
      isManualCategory: data.isManualCategory.present
          ? data.isManualCategory.value
          : this.isManualCategory,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Expense(')
          ..write('id: $id, ')
          ..write('amount: $amount, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('bank: $bank, ')
          ..write('cardType: $cardType, ')
          ..write('date: $date, ')
          ..write('isManualCategory: $isManualCategory')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, amount, description, category, bank,
      cardType, date, isManualCategory);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Expense &&
          other.id == this.id &&
          other.amount == this.amount &&
          other.description == this.description &&
          other.category == this.category &&
          other.bank == this.bank &&
          other.cardType == this.cardType &&
          other.date == this.date &&
          other.isManualCategory == this.isManualCategory);
}

class ExpensesCompanion extends UpdateCompanion<Expense> {
  final Value<String> id;
  final Value<double> amount;
  final Value<String> description;
  final Value<String> category;
  final Value<String> bank;
  final Value<String> cardType;
  final Value<String> date;
  final Value<bool> isManualCategory;
  final Value<int> rowid;
  const ExpensesCompanion({
    this.id = const Value.absent(),
    this.amount = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.bank = const Value.absent(),
    this.cardType = const Value.absent(),
    this.date = const Value.absent(),
    this.isManualCategory = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpensesCompanion.insert({
    required String id,
    required double amount,
    required String description,
    required String category,
    required String bank,
    required String cardType,
    required String date,
    this.isManualCategory = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        amount = Value(amount),
        description = Value(description),
        category = Value(category),
        bank = Value(bank),
        cardType = Value(cardType),
        date = Value(date);
  static Insertable<Expense> custom({
    Expression<String>? id,
    Expression<double>? amount,
    Expression<String>? description,
    Expression<String>? category,
    Expression<String>? bank,
    Expression<String>? cardType,
    Expression<String>? date,
    Expression<bool>? isManualCategory,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (amount != null) 'amount': amount,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (bank != null) 'bank': bank,
      if (cardType != null) 'card_type': cardType,
      if (date != null) 'date': date,
      if (isManualCategory != null) 'is_manual_category': isManualCategory,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpensesCompanion copyWith(
      {Value<String>? id,
      Value<double>? amount,
      Value<String>? description,
      Value<String>? category,
      Value<String>? bank,
      Value<String>? cardType,
      Value<String>? date,
      Value<bool>? isManualCategory,
      Value<int>? rowid}) {
    return ExpensesCompanion(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      category: category ?? this.category,
      bank: bank ?? this.bank,
      cardType: cardType ?? this.cardType,
      date: date ?? this.date,
      isManualCategory: isManualCategory ?? this.isManualCategory,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (bank.present) {
      map['bank'] = Variable<String>(bank.value);
    }
    if (cardType.present) {
      map['card_type'] = Variable<String>(cardType.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (isManualCategory.present) {
      map['is_manual_category'] = Variable<bool>(isManualCategory.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpensesCompanion(')
          ..write('id: $id, ')
          ..write('amount: $amount, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('bank: $bank, ')
          ..write('cardType: $cardType, ')
          ..write('date: $date, ')
          ..write('isManualCategory: $isManualCategory, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetEntriesTable extends BudgetEntries
    with TableInfo<$BudgetEntriesTable, BudgetEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _setAtMeta = const VerificationMeta('setAt');
  @override
  late final GeneratedColumn<String> setAt = GeneratedColumn<String>(
      'set_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, amount, setAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budget_entries';
  @override
  VerificationContext validateIntegrity(Insertable<BudgetEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('set_at')) {
      context.handle(
          _setAtMeta, setAt.isAcceptableOrUnknown(data['set_at']!, _setAtMeta));
    } else if (isInserting) {
      context.missing(_setAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BudgetEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BudgetEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      setAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}set_at'])!,
    );
  }

  @override
  $BudgetEntriesTable createAlias(String alias) {
    return $BudgetEntriesTable(attachedDatabase, alias);
  }
}

class BudgetEntry extends DataClass implements Insertable<BudgetEntry> {
  final String id;
  final double amount;
  final String setAt;
  const BudgetEntry(
      {required this.id, required this.amount, required this.setAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['amount'] = Variable<double>(amount);
    map['set_at'] = Variable<String>(setAt);
    return map;
  }

  BudgetEntriesCompanion toCompanion(bool nullToAbsent) {
    return BudgetEntriesCompanion(
      id: Value(id),
      amount: Value(amount),
      setAt: Value(setAt),
    );
  }

  factory BudgetEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BudgetEntry(
      id: serializer.fromJson<String>(json['id']),
      amount: serializer.fromJson<double>(json['amount']),
      setAt: serializer.fromJson<String>(json['setAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'amount': serializer.toJson<double>(amount),
      'setAt': serializer.toJson<String>(setAt),
    };
  }

  BudgetEntry copyWith({String? id, double? amount, String? setAt}) =>
      BudgetEntry(
        id: id ?? this.id,
        amount: amount ?? this.amount,
        setAt: setAt ?? this.setAt,
      );
  BudgetEntry copyWithCompanion(BudgetEntriesCompanion data) {
    return BudgetEntry(
      id: data.id.present ? data.id.value : this.id,
      amount: data.amount.present ? data.amount.value : this.amount,
      setAt: data.setAt.present ? data.setAt.value : this.setAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BudgetEntry(')
          ..write('id: $id, ')
          ..write('amount: $amount, ')
          ..write('setAt: $setAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, amount, setAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BudgetEntry &&
          other.id == this.id &&
          other.amount == this.amount &&
          other.setAt == this.setAt);
}

class BudgetEntriesCompanion extends UpdateCompanion<BudgetEntry> {
  final Value<String> id;
  final Value<double> amount;
  final Value<String> setAt;
  final Value<int> rowid;
  const BudgetEntriesCompanion({
    this.id = const Value.absent(),
    this.amount = const Value.absent(),
    this.setAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetEntriesCompanion.insert({
    required String id,
    required double amount,
    required String setAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        amount = Value(amount),
        setAt = Value(setAt);
  static Insertable<BudgetEntry> custom({
    Expression<String>? id,
    Expression<double>? amount,
    Expression<String>? setAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (amount != null) 'amount': amount,
      if (setAt != null) 'set_at': setAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetEntriesCompanion copyWith(
      {Value<String>? id,
      Value<double>? amount,
      Value<String>? setAt,
      Value<int>? rowid}) {
    return BudgetEntriesCompanion(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      setAt: setAt ?? this.setAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (setAt.present) {
      map['set_at'] = Variable<String>(setAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetEntriesCompanion(')
          ..write('id: $id, ')
          ..write('amount: $amount, ')
          ..write('setAt: $setAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NewsArticlesTable extends NewsArticles
    with TableInfo<$NewsArticlesTable, NewsArticle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NewsArticlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _excerptMeta =
      const VerificationMeta('excerpt');
  @override
  late final GeneratedColumn<String> excerpt = GeneratedColumn<String>(
      'excerpt', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _readTimeMeta =
      const VerificationMeta('readTime');
  @override
  late final GeneratedColumn<int> readTime = GeneratedColumn<int>(
      'read_time', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
      'date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _blocksJsonMeta =
      const VerificationMeta('blocksJson');
  @override
  late final GeneratedColumn<String> blocksJson = GeneratedColumn<String>(
      'blocks_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isSavedMeta =
      const VerificationMeta('isSaved');
  @override
  late final GeneratedColumn<bool> isSaved = GeneratedColumn<bool>(
      'is_saved', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_saved" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
      'is_read', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _summaryShortMeta =
      const VerificationMeta('summaryShort');
  @override
  late final GeneratedColumn<String> summaryShort = GeneratedColumn<String>(
      'summary_short', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        excerpt,
        source,
        category,
        imageUrl,
        readTime,
        date,
        blocksJson,
        isSaved,
        isRead,
        summaryShort
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'news_articles';
  @override
  VerificationContext validateIntegrity(Insertable<NewsArticle> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('excerpt')) {
      context.handle(_excerptMeta,
          excerpt.isAcceptableOrUnknown(data['excerpt']!, _excerptMeta));
    } else if (isInserting) {
      context.missing(_excerptMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    } else if (isInserting) {
      context.missing(_imageUrlMeta);
    }
    if (data.containsKey('read_time')) {
      context.handle(_readTimeMeta,
          readTime.isAcceptableOrUnknown(data['read_time']!, _readTimeMeta));
    } else if (isInserting) {
      context.missing(_readTimeMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('blocks_json')) {
      context.handle(
          _blocksJsonMeta,
          blocksJson.isAcceptableOrUnknown(
              data['blocks_json']!, _blocksJsonMeta));
    } else if (isInserting) {
      context.missing(_blocksJsonMeta);
    }
    if (data.containsKey('is_saved')) {
      context.handle(_isSavedMeta,
          isSaved.isAcceptableOrUnknown(data['is_saved']!, _isSavedMeta));
    }
    if (data.containsKey('is_read')) {
      context.handle(_isReadMeta,
          isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));
    }
    if (data.containsKey('summary_short')) {
      context.handle(
          _summaryShortMeta,
          summaryShort.isAcceptableOrUnknown(
              data['summary_short']!, _summaryShortMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NewsArticle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NewsArticle(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      excerpt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}excerpt'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url'])!,
      readTime: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}read_time'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date'])!,
      blocksJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}blocks_json'])!,
      isSaved: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_saved'])!,
      isRead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!,
      summaryShort: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary_short']),
    );
  }

  @override
  $NewsArticlesTable createAlias(String alias) {
    return $NewsArticlesTable(attachedDatabase, alias);
  }
}

class NewsArticle extends DataClass implements Insertable<NewsArticle> {
  final String id;
  final String title;
  final String excerpt;
  final String source;
  final String category;
  final String imageUrl;
  final int readTime;
  final String date;
  final String blocksJson;
  final bool isSaved;
  final bool isRead;

  /// AI-generated 1-2 sentence quick summary used by the For You "Summarize"
  /// action. NULL = not yet summarized. Cached forever per article so re-opening
  /// the summary reader is instant for already-processed items.
  final String? summaryShort;
  const NewsArticle(
      {required this.id,
      required this.title,
      required this.excerpt,
      required this.source,
      required this.category,
      required this.imageUrl,
      required this.readTime,
      required this.date,
      required this.blocksJson,
      required this.isSaved,
      required this.isRead,
      this.summaryShort});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['excerpt'] = Variable<String>(excerpt);
    map['source'] = Variable<String>(source);
    map['category'] = Variable<String>(category);
    map['image_url'] = Variable<String>(imageUrl);
    map['read_time'] = Variable<int>(readTime);
    map['date'] = Variable<String>(date);
    map['blocks_json'] = Variable<String>(blocksJson);
    map['is_saved'] = Variable<bool>(isSaved);
    map['is_read'] = Variable<bool>(isRead);
    if (!nullToAbsent || summaryShort != null) {
      map['summary_short'] = Variable<String>(summaryShort);
    }
    return map;
  }

  NewsArticlesCompanion toCompanion(bool nullToAbsent) {
    return NewsArticlesCompanion(
      id: Value(id),
      title: Value(title),
      excerpt: Value(excerpt),
      source: Value(source),
      category: Value(category),
      imageUrl: Value(imageUrl),
      readTime: Value(readTime),
      date: Value(date),
      blocksJson: Value(blocksJson),
      isSaved: Value(isSaved),
      isRead: Value(isRead),
      summaryShort: summaryShort == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryShort),
    );
  }

  factory NewsArticle.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NewsArticle(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      excerpt: serializer.fromJson<String>(json['excerpt']),
      source: serializer.fromJson<String>(json['source']),
      category: serializer.fromJson<String>(json['category']),
      imageUrl: serializer.fromJson<String>(json['imageUrl']),
      readTime: serializer.fromJson<int>(json['readTime']),
      date: serializer.fromJson<String>(json['date']),
      blocksJson: serializer.fromJson<String>(json['blocksJson']),
      isSaved: serializer.fromJson<bool>(json['isSaved']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      summaryShort: serializer.fromJson<String?>(json['summaryShort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'excerpt': serializer.toJson<String>(excerpt),
      'source': serializer.toJson<String>(source),
      'category': serializer.toJson<String>(category),
      'imageUrl': serializer.toJson<String>(imageUrl),
      'readTime': serializer.toJson<int>(readTime),
      'date': serializer.toJson<String>(date),
      'blocksJson': serializer.toJson<String>(blocksJson),
      'isSaved': serializer.toJson<bool>(isSaved),
      'isRead': serializer.toJson<bool>(isRead),
      'summaryShort': serializer.toJson<String?>(summaryShort),
    };
  }

  NewsArticle copyWith(
          {String? id,
          String? title,
          String? excerpt,
          String? source,
          String? category,
          String? imageUrl,
          int? readTime,
          String? date,
          String? blocksJson,
          bool? isSaved,
          bool? isRead,
          Value<String?> summaryShort = const Value.absent()}) =>
      NewsArticle(
        id: id ?? this.id,
        title: title ?? this.title,
        excerpt: excerpt ?? this.excerpt,
        source: source ?? this.source,
        category: category ?? this.category,
        imageUrl: imageUrl ?? this.imageUrl,
        readTime: readTime ?? this.readTime,
        date: date ?? this.date,
        blocksJson: blocksJson ?? this.blocksJson,
        isSaved: isSaved ?? this.isSaved,
        isRead: isRead ?? this.isRead,
        summaryShort:
            summaryShort.present ? summaryShort.value : this.summaryShort,
      );
  NewsArticle copyWithCompanion(NewsArticlesCompanion data) {
    return NewsArticle(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      excerpt: data.excerpt.present ? data.excerpt.value : this.excerpt,
      source: data.source.present ? data.source.value : this.source,
      category: data.category.present ? data.category.value : this.category,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      readTime: data.readTime.present ? data.readTime.value : this.readTime,
      date: data.date.present ? data.date.value : this.date,
      blocksJson:
          data.blocksJson.present ? data.blocksJson.value : this.blocksJson,
      isSaved: data.isSaved.present ? data.isSaved.value : this.isSaved,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      summaryShort: data.summaryShort.present
          ? data.summaryShort.value
          : this.summaryShort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NewsArticle(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('excerpt: $excerpt, ')
          ..write('source: $source, ')
          ..write('category: $category, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('readTime: $readTime, ')
          ..write('date: $date, ')
          ..write('blocksJson: $blocksJson, ')
          ..write('isSaved: $isSaved, ')
          ..write('isRead: $isRead, ')
          ..write('summaryShort: $summaryShort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, excerpt, source, category,
      imageUrl, readTime, date, blocksJson, isSaved, isRead, summaryShort);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NewsArticle &&
          other.id == this.id &&
          other.title == this.title &&
          other.excerpt == this.excerpt &&
          other.source == this.source &&
          other.category == this.category &&
          other.imageUrl == this.imageUrl &&
          other.readTime == this.readTime &&
          other.date == this.date &&
          other.blocksJson == this.blocksJson &&
          other.isSaved == this.isSaved &&
          other.isRead == this.isRead &&
          other.summaryShort == this.summaryShort);
}

class NewsArticlesCompanion extends UpdateCompanion<NewsArticle> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> excerpt;
  final Value<String> source;
  final Value<String> category;
  final Value<String> imageUrl;
  final Value<int> readTime;
  final Value<String> date;
  final Value<String> blocksJson;
  final Value<bool> isSaved;
  final Value<bool> isRead;
  final Value<String?> summaryShort;
  final Value<int> rowid;
  const NewsArticlesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.excerpt = const Value.absent(),
    this.source = const Value.absent(),
    this.category = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.readTime = const Value.absent(),
    this.date = const Value.absent(),
    this.blocksJson = const Value.absent(),
    this.isSaved = const Value.absent(),
    this.isRead = const Value.absent(),
    this.summaryShort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NewsArticlesCompanion.insert({
    required String id,
    required String title,
    required String excerpt,
    required String source,
    required String category,
    required String imageUrl,
    required int readTime,
    required String date,
    required String blocksJson,
    this.isSaved = const Value.absent(),
    this.isRead = const Value.absent(),
    this.summaryShort = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        excerpt = Value(excerpt),
        source = Value(source),
        category = Value(category),
        imageUrl = Value(imageUrl),
        readTime = Value(readTime),
        date = Value(date),
        blocksJson = Value(blocksJson);
  static Insertable<NewsArticle> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? excerpt,
    Expression<String>? source,
    Expression<String>? category,
    Expression<String>? imageUrl,
    Expression<int>? readTime,
    Expression<String>? date,
    Expression<String>? blocksJson,
    Expression<bool>? isSaved,
    Expression<bool>? isRead,
    Expression<String>? summaryShort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (excerpt != null) 'excerpt': excerpt,
      if (source != null) 'source': source,
      if (category != null) 'category': category,
      if (imageUrl != null) 'image_url': imageUrl,
      if (readTime != null) 'read_time': readTime,
      if (date != null) 'date': date,
      if (blocksJson != null) 'blocks_json': blocksJson,
      if (isSaved != null) 'is_saved': isSaved,
      if (isRead != null) 'is_read': isRead,
      if (summaryShort != null) 'summary_short': summaryShort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NewsArticlesCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? excerpt,
      Value<String>? source,
      Value<String>? category,
      Value<String>? imageUrl,
      Value<int>? readTime,
      Value<String>? date,
      Value<String>? blocksJson,
      Value<bool>? isSaved,
      Value<bool>? isRead,
      Value<String?>? summaryShort,
      Value<int>? rowid}) {
    return NewsArticlesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      excerpt: excerpt ?? this.excerpt,
      source: source ?? this.source,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      readTime: readTime ?? this.readTime,
      date: date ?? this.date,
      blocksJson: blocksJson ?? this.blocksJson,
      isSaved: isSaved ?? this.isSaved,
      isRead: isRead ?? this.isRead,
      summaryShort: summaryShort ?? this.summaryShort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (excerpt.present) {
      map['excerpt'] = Variable<String>(excerpt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (readTime.present) {
      map['read_time'] = Variable<int>(readTime.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (blocksJson.present) {
      map['blocks_json'] = Variable<String>(blocksJson.value);
    }
    if (isSaved.present) {
      map['is_saved'] = Variable<bool>(isSaved.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (summaryShort.present) {
      map['summary_short'] = Variable<String>(summaryShort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NewsArticlesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('excerpt: $excerpt, ')
          ..write('source: $source, ')
          ..write('category: $category, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('readTime: $readTime, ')
          ..write('date: $date, ')
          ..write('blocksJson: $blocksJson, ')
          ..write('isSaved: $isSaved, ')
          ..write('isRead: $isRead, ')
          ..write('summaryShort: $summaryShort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CloudFilesTable extends CloudFiles
    with TableInfo<$CloudFilesTable, CloudFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CloudFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sizeBytesMeta =
      const VerificationMeta('sizeBytes');
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
      'size_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _uploadDateMeta =
      const VerificationMeta('uploadDate');
  @override
  late final GeneratedColumn<String> uploadDate = GeneratedColumn<String>(
      'upload_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isStarredMeta =
      const VerificationMeta('isStarred');
  @override
  late final GeneratedColumn<bool> isStarred = GeneratedColumn<bool>(
      'is_starred', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_starred" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, type, sizeBytes, uploadDate, isStarred];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cloud_files';
  @override
  VerificationContext validateIntegrity(Insertable<CloudFile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(_sizeBytesMeta,
          sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta));
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('upload_date')) {
      context.handle(
          _uploadDateMeta,
          uploadDate.isAcceptableOrUnknown(
              data['upload_date']!, _uploadDateMeta));
    } else if (isInserting) {
      context.missing(_uploadDateMeta);
    }
    if (data.containsKey('is_starred')) {
      context.handle(_isStarredMeta,
          isStarred.isAcceptableOrUnknown(data['is_starred']!, _isStarredMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CloudFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CloudFile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      sizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size_bytes'])!,
      uploadDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}upload_date'])!,
      isStarred: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_starred'])!,
    );
  }

  @override
  $CloudFilesTable createAlias(String alias) {
    return $CloudFilesTable(attachedDatabase, alias);
  }
}

class CloudFile extends DataClass implements Insertable<CloudFile> {
  final String id;
  final String name;
  final String type;
  final int sizeBytes;
  final String uploadDate;
  final bool isStarred;
  const CloudFile(
      {required this.id,
      required this.name,
      required this.type,
      required this.sizeBytes,
      required this.uploadDate,
      required this.isStarred});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['upload_date'] = Variable<String>(uploadDate);
    map['is_starred'] = Variable<bool>(isStarred);
    return map;
  }

  CloudFilesCompanion toCompanion(bool nullToAbsent) {
    return CloudFilesCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      sizeBytes: Value(sizeBytes),
      uploadDate: Value(uploadDate),
      isStarred: Value(isStarred),
    );
  }

  factory CloudFile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CloudFile(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      uploadDate: serializer.fromJson<String>(json['uploadDate']),
      isStarred: serializer.fromJson<bool>(json['isStarred']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'uploadDate': serializer.toJson<String>(uploadDate),
      'isStarred': serializer.toJson<bool>(isStarred),
    };
  }

  CloudFile copyWith(
          {String? id,
          String? name,
          String? type,
          int? sizeBytes,
          String? uploadDate,
          bool? isStarred}) =>
      CloudFile(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        uploadDate: uploadDate ?? this.uploadDate,
        isStarred: isStarred ?? this.isStarred,
      );
  CloudFile copyWithCompanion(CloudFilesCompanion data) {
    return CloudFile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      uploadDate:
          data.uploadDate.present ? data.uploadDate.value : this.uploadDate,
      isStarred: data.isStarred.present ? data.isStarred.value : this.isStarred,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CloudFile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('uploadDate: $uploadDate, ')
          ..write('isStarred: $isStarred')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, type, sizeBytes, uploadDate, isStarred);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CloudFile &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.sizeBytes == this.sizeBytes &&
          other.uploadDate == this.uploadDate &&
          other.isStarred == this.isStarred);
}

class CloudFilesCompanion extends UpdateCompanion<CloudFile> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> type;
  final Value<int> sizeBytes;
  final Value<String> uploadDate;
  final Value<bool> isStarred;
  final Value<int> rowid;
  const CloudFilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.uploadDate = const Value.absent(),
    this.isStarred = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CloudFilesCompanion.insert({
    required String id,
    required String name,
    required String type,
    required int sizeBytes,
    required String uploadDate,
    this.isStarred = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        type = Value(type),
        sizeBytes = Value(sizeBytes),
        uploadDate = Value(uploadDate);
  static Insertable<CloudFile> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<int>? sizeBytes,
    Expression<String>? uploadDate,
    Expression<bool>? isStarred,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (uploadDate != null) 'upload_date': uploadDate,
      if (isStarred != null) 'is_starred': isStarred,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CloudFilesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? type,
      Value<int>? sizeBytes,
      Value<String>? uploadDate,
      Value<bool>? isStarred,
      Value<int>? rowid}) {
    return CloudFilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      uploadDate: uploadDate ?? this.uploadDate,
      isStarred: isStarred ?? this.isStarred,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (uploadDate.present) {
      map['upload_date'] = Variable<String>(uploadDate.value);
    }
    if (isStarred.present) {
      map['is_starred'] = Variable<bool>(isStarred.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CloudFilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('uploadDate: $uploadDate, ')
          ..write('isStarred: $isStarred, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedWordsTable extends SavedWords
    with TableInfo<$SavedWordsTable, SavedWord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedWordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _wordMeta = const VerificationMeta('word');
  @override
  late final GeneratedColumn<String> word = GeneratedColumn<String>(
      'word', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _definitionMeta =
      const VerificationMeta('definition');
  @override
  late final GeneratedColumn<String> definition = GeneratedColumn<String>(
      'definition', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pronunciationMeta =
      const VerificationMeta('pronunciation');
  @override
  late final GeneratedColumn<String> pronunciation = GeneratedColumn<String>(
      'pronunciation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _partOfSpeechMeta =
      const VerificationMeta('partOfSpeech');
  @override
  late final GeneratedColumn<String> partOfSpeech = GeneratedColumn<String>(
      'part_of_speech', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _savedAtMeta =
      const VerificationMeta('savedAt');
  @override
  late final GeneratedColumn<String> savedAt = GeneratedColumn<String>(
      'saved_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responseJsonMeta =
      const VerificationMeta('responseJson');
  @override
  late final GeneratedColumn<String> responseJson = GeneratedColumn<String>(
      'response_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        word,
        definition,
        pronunciation,
        partOfSpeech,
        savedAt,
        responseJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_words';
  @override
  VerificationContext validateIntegrity(Insertable<SavedWord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('word')) {
      context.handle(
          _wordMeta, word.isAcceptableOrUnknown(data['word']!, _wordMeta));
    } else if (isInserting) {
      context.missing(_wordMeta);
    }
    if (data.containsKey('definition')) {
      context.handle(
          _definitionMeta,
          definition.isAcceptableOrUnknown(
              data['definition']!, _definitionMeta));
    } else if (isInserting) {
      context.missing(_definitionMeta);
    }
    if (data.containsKey('pronunciation')) {
      context.handle(
          _pronunciationMeta,
          pronunciation.isAcceptableOrUnknown(
              data['pronunciation']!, _pronunciationMeta));
    } else if (isInserting) {
      context.missing(_pronunciationMeta);
    }
    if (data.containsKey('part_of_speech')) {
      context.handle(
          _partOfSpeechMeta,
          partOfSpeech.isAcceptableOrUnknown(
              data['part_of_speech']!, _partOfSpeechMeta));
    } else if (isInserting) {
      context.missing(_partOfSpeechMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(_savedAtMeta,
          savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta));
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('response_json')) {
      context.handle(
          _responseJsonMeta,
          responseJson.isAcceptableOrUnknown(
              data['response_json']!, _responseJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedWord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedWord(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      word: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}word'])!,
      definition: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}definition'])!,
      pronunciation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pronunciation'])!,
      partOfSpeech: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}part_of_speech'])!,
      savedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}saved_at'])!,
      responseJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}response_json'])!,
    );
  }

  @override
  $SavedWordsTable createAlias(String alias) {
    return $SavedWordsTable(attachedDatabase, alias);
  }
}

class SavedWord extends DataClass implements Insertable<SavedWord> {
  final String id;
  final String word;
  final String definition;
  final String pronunciation;
  final String partOfSpeech;
  final String savedAt;
  final String responseJson;
  const SavedWord(
      {required this.id,
      required this.word,
      required this.definition,
      required this.pronunciation,
      required this.partOfSpeech,
      required this.savedAt,
      required this.responseJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['word'] = Variable<String>(word);
    map['definition'] = Variable<String>(definition);
    map['pronunciation'] = Variable<String>(pronunciation);
    map['part_of_speech'] = Variable<String>(partOfSpeech);
    map['saved_at'] = Variable<String>(savedAt);
    map['response_json'] = Variable<String>(responseJson);
    return map;
  }

  SavedWordsCompanion toCompanion(bool nullToAbsent) {
    return SavedWordsCompanion(
      id: Value(id),
      word: Value(word),
      definition: Value(definition),
      pronunciation: Value(pronunciation),
      partOfSpeech: Value(partOfSpeech),
      savedAt: Value(savedAt),
      responseJson: Value(responseJson),
    );
  }

  factory SavedWord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedWord(
      id: serializer.fromJson<String>(json['id']),
      word: serializer.fromJson<String>(json['word']),
      definition: serializer.fromJson<String>(json['definition']),
      pronunciation: serializer.fromJson<String>(json['pronunciation']),
      partOfSpeech: serializer.fromJson<String>(json['partOfSpeech']),
      savedAt: serializer.fromJson<String>(json['savedAt']),
      responseJson: serializer.fromJson<String>(json['responseJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'word': serializer.toJson<String>(word),
      'definition': serializer.toJson<String>(definition),
      'pronunciation': serializer.toJson<String>(pronunciation),
      'partOfSpeech': serializer.toJson<String>(partOfSpeech),
      'savedAt': serializer.toJson<String>(savedAt),
      'responseJson': serializer.toJson<String>(responseJson),
    };
  }

  SavedWord copyWith(
          {String? id,
          String? word,
          String? definition,
          String? pronunciation,
          String? partOfSpeech,
          String? savedAt,
          String? responseJson}) =>
      SavedWord(
        id: id ?? this.id,
        word: word ?? this.word,
        definition: definition ?? this.definition,
        pronunciation: pronunciation ?? this.pronunciation,
        partOfSpeech: partOfSpeech ?? this.partOfSpeech,
        savedAt: savedAt ?? this.savedAt,
        responseJson: responseJson ?? this.responseJson,
      );
  SavedWord copyWithCompanion(SavedWordsCompanion data) {
    return SavedWord(
      id: data.id.present ? data.id.value : this.id,
      word: data.word.present ? data.word.value : this.word,
      definition:
          data.definition.present ? data.definition.value : this.definition,
      pronunciation: data.pronunciation.present
          ? data.pronunciation.value
          : this.pronunciation,
      partOfSpeech: data.partOfSpeech.present
          ? data.partOfSpeech.value
          : this.partOfSpeech,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      responseJson: data.responseJson.present
          ? data.responseJson.value
          : this.responseJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedWord(')
          ..write('id: $id, ')
          ..write('word: $word, ')
          ..write('definition: $definition, ')
          ..write('pronunciation: $pronunciation, ')
          ..write('partOfSpeech: $partOfSpeech, ')
          ..write('savedAt: $savedAt, ')
          ..write('responseJson: $responseJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, word, definition, pronunciation, partOfSpeech, savedAt, responseJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedWord &&
          other.id == this.id &&
          other.word == this.word &&
          other.definition == this.definition &&
          other.pronunciation == this.pronunciation &&
          other.partOfSpeech == this.partOfSpeech &&
          other.savedAt == this.savedAt &&
          other.responseJson == this.responseJson);
}

class SavedWordsCompanion extends UpdateCompanion<SavedWord> {
  final Value<String> id;
  final Value<String> word;
  final Value<String> definition;
  final Value<String> pronunciation;
  final Value<String> partOfSpeech;
  final Value<String> savedAt;
  final Value<String> responseJson;
  final Value<int> rowid;
  const SavedWordsCompanion({
    this.id = const Value.absent(),
    this.word = const Value.absent(),
    this.definition = const Value.absent(),
    this.pronunciation = const Value.absent(),
    this.partOfSpeech = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.responseJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedWordsCompanion.insert({
    required String id,
    required String word,
    required String definition,
    required String pronunciation,
    required String partOfSpeech,
    required String savedAt,
    this.responseJson = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        word = Value(word),
        definition = Value(definition),
        pronunciation = Value(pronunciation),
        partOfSpeech = Value(partOfSpeech),
        savedAt = Value(savedAt);
  static Insertable<SavedWord> custom({
    Expression<String>? id,
    Expression<String>? word,
    Expression<String>? definition,
    Expression<String>? pronunciation,
    Expression<String>? partOfSpeech,
    Expression<String>? savedAt,
    Expression<String>? responseJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (word != null) 'word': word,
      if (definition != null) 'definition': definition,
      if (pronunciation != null) 'pronunciation': pronunciation,
      if (partOfSpeech != null) 'part_of_speech': partOfSpeech,
      if (savedAt != null) 'saved_at': savedAt,
      if (responseJson != null) 'response_json': responseJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedWordsCompanion copyWith(
      {Value<String>? id,
      Value<String>? word,
      Value<String>? definition,
      Value<String>? pronunciation,
      Value<String>? partOfSpeech,
      Value<String>? savedAt,
      Value<String>? responseJson,
      Value<int>? rowid}) {
    return SavedWordsCompanion(
      id: id ?? this.id,
      word: word ?? this.word,
      definition: definition ?? this.definition,
      pronunciation: pronunciation ?? this.pronunciation,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      savedAt: savedAt ?? this.savedAt,
      responseJson: responseJson ?? this.responseJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (word.present) {
      map['word'] = Variable<String>(word.value);
    }
    if (definition.present) {
      map['definition'] = Variable<String>(definition.value);
    }
    if (pronunciation.present) {
      map['pronunciation'] = Variable<String>(pronunciation.value);
    }
    if (partOfSpeech.present) {
      map['part_of_speech'] = Variable<String>(partOfSpeech.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<String>(savedAt.value);
    }
    if (responseJson.present) {
      map['response_json'] = Variable<String>(responseJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedWordsCompanion(')
          ..write('id: $id, ')
          ..write('word: $word, ')
          ..write('definition: $definition, ')
          ..write('pronunciation: $pronunciation, ')
          ..write('partOfSpeech: $partOfSpeech, ')
          ..write('savedAt: $savedAt, ')
          ..write('responseJson: $responseJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, SyncQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityIdMeta =
      const VerificationMeta('entityId');
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
      'entity_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
      'synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, entityType, entityId, action, payload, createdAt, synced];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(Insertable<SyncQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(_entityIdMeta,
          entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta));
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(_syncedMeta,
          synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      entityId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_id'])!,
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at'])!,
      synced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}synced'])!,
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class SyncQueueData extends DataClass implements Insertable<SyncQueueData> {
  final int id;
  final String entityType;
  final String entityId;
  final String action;
  final String payload;
  final String createdAt;
  final bool synced;
  const SyncQueueData(
      {required this.id,
      required this.entityType,
      required this.entityId,
      required this.action,
      required this.payload,
      required this.createdAt,
      required this.synced});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['action'] = Variable<String>(action);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<String>(createdAt);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      action: Value(action),
      payload: Value(payload),
      createdAt: Value(createdAt),
      synced: Value(synced),
    );
  }

  factory SyncQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueData(
      id: serializer.fromJson<int>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      action: serializer.fromJson<String>(json['action']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'action': serializer.toJson<String>(action),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<String>(createdAt),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  SyncQueueData copyWith(
          {int? id,
          String? entityType,
          String? entityId,
          String? action,
          String? payload,
          String? createdAt,
          bool? synced}) =>
      SyncQueueData(
        id: id ?? this.id,
        entityType: entityType ?? this.entityType,
        entityId: entityId ?? this.entityId,
        action: action ?? this.action,
        payload: payload ?? this.payload,
        createdAt: createdAt ?? this.createdAt,
        synced: synced ?? this.synced,
      );
  SyncQueueData copyWithCompanion(SyncQueueCompanion data) {
    return SyncQueueData(
      id: data.id.present ? data.id.value : this.id,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      action: data.action.present ? data.action.value : this.action,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueData(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, entityType, entityId, action, payload, createdAt, synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueData &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.action == this.action &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.synced == this.synced);
}

class SyncQueueCompanion extends UpdateCompanion<SyncQueueData> {
  final Value<int> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> action;
  final Value<String> payload;
  final Value<String> createdAt;
  final Value<bool> synced;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.action = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.synced = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required String action,
    required String payload,
    required String createdAt,
    this.synced = const Value.absent(),
  })  : entityType = Value(entityType),
        entityId = Value(entityId),
        action = Value(action),
        payload = Value(payload),
        createdAt = Value(createdAt);
  static Insertable<SyncQueueData> custom({
    Expression<int>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? action,
    Expression<String>? payload,
    Expression<String>? createdAt,
    Expression<bool>? synced,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (action != null) 'action': action,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (synced != null) 'synced': synced,
    });
  }

  SyncQueueCompanion copyWith(
      {Value<int>? id,
      Value<String>? entityType,
      Value<String>? entityId,
      Value<String>? action,
      Value<String>? payload,
      Value<String>? createdAt,
      Value<bool>? synced}) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      synced: synced ?? this.synced,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }
}

class $CategoryLearningsTable extends CategoryLearnings
    with TableInfo<$CategoryLearningsTable, CategoryLearning> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoryLearningsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keywordMeta =
      const VerificationMeta('keyword');
  @override
  late final GeneratedColumn<String> keyword = GeneratedColumn<String>(
      'keyword', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [keyword, category];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'category_learnings';
  @override
  VerificationContext validateIntegrity(Insertable<CategoryLearning> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('keyword')) {
      context.handle(_keywordMeta,
          keyword.isAcceptableOrUnknown(data['keyword']!, _keywordMeta));
    } else if (isInserting) {
      context.missing(_keywordMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyword};
  @override
  CategoryLearning map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryLearning(
      keyword: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}keyword'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
    );
  }

  @override
  $CategoryLearningsTable createAlias(String alias) {
    return $CategoryLearningsTable(attachedDatabase, alias);
  }
}

class CategoryLearning extends DataClass
    implements Insertable<CategoryLearning> {
  final String keyword;
  final String category;
  const CategoryLearning({required this.keyword, required this.category});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['keyword'] = Variable<String>(keyword);
    map['category'] = Variable<String>(category);
    return map;
  }

  CategoryLearningsCompanion toCompanion(bool nullToAbsent) {
    return CategoryLearningsCompanion(
      keyword: Value(keyword),
      category: Value(category),
    );
  }

  factory CategoryLearning.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryLearning(
      keyword: serializer.fromJson<String>(json['keyword']),
      category: serializer.fromJson<String>(json['category']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyword': serializer.toJson<String>(keyword),
      'category': serializer.toJson<String>(category),
    };
  }

  CategoryLearning copyWith({String? keyword, String? category}) =>
      CategoryLearning(
        keyword: keyword ?? this.keyword,
        category: category ?? this.category,
      );
  CategoryLearning copyWithCompanion(CategoryLearningsCompanion data) {
    return CategoryLearning(
      keyword: data.keyword.present ? data.keyword.value : this.keyword,
      category: data.category.present ? data.category.value : this.category,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryLearning(')
          ..write('keyword: $keyword, ')
          ..write('category: $category')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(keyword, category);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryLearning &&
          other.keyword == this.keyword &&
          other.category == this.category);
}

class CategoryLearningsCompanion extends UpdateCompanion<CategoryLearning> {
  final Value<String> keyword;
  final Value<String> category;
  final Value<int> rowid;
  const CategoryLearningsCompanion({
    this.keyword = const Value.absent(),
    this.category = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoryLearningsCompanion.insert({
    required String keyword,
    required String category,
    this.rowid = const Value.absent(),
  })  : keyword = Value(keyword),
        category = Value(category);
  static Insertable<CategoryLearning> custom({
    Expression<String>? keyword,
    Expression<String>? category,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyword != null) 'keyword': keyword,
      if (category != null) 'category': category,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoryLearningsCompanion copyWith(
      {Value<String>? keyword, Value<String>? category, Value<int>? rowid}) {
    return CategoryLearningsCompanion(
      keyword: keyword ?? this.keyword,
      category: category ?? this.category,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyword.present) {
      map['keyword'] = Variable<String>(keyword.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoryLearningsCompanion(')
          ..write('keyword: $keyword, ')
          ..write('category: $category, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ArticleChatMessagesTable extends ArticleChatMessages
    with TableInfo<$ArticleChatMessagesTable, ArticleChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticleChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _articleIdMeta =
      const VerificationMeta('articleId');
  @override
  late final GeneratedColumn<String> articleId = GeneratedColumn<String>(
      'article_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _msgTextMeta =
      const VerificationMeta('msgText');
  @override
  late final GeneratedColumn<String> msgText = GeneratedColumn<String>(
      'msg_text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
      'model', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _sourcesJsonMeta =
      const VerificationMeta('sourcesJson');
  @override
  late final GeneratedColumn<String> sourcesJson = GeneratedColumn<String>(
      'sources_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, articleId, role, msgText, model, sourcesJson, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'article_chat_messages';
  @override
  VerificationContext validateIntegrity(Insertable<ArticleChatMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('article_id')) {
      context.handle(_articleIdMeta,
          articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta));
    } else if (isInserting) {
      context.missing(_articleIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('msg_text')) {
      context.handle(_msgTextMeta,
          msgText.isAcceptableOrUnknown(data['msg_text']!, _msgTextMeta));
    } else if (isInserting) {
      context.missing(_msgTextMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
          _modelMeta, model.isAcceptableOrUnknown(data['model']!, _modelMeta));
    }
    if (data.containsKey('sources_json')) {
      context.handle(
          _sourcesJsonMeta,
          sourcesJson.isAcceptableOrUnknown(
              data['sources_json']!, _sourcesJsonMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ArticleChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArticleChatMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      articleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}article_id'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      msgText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}msg_text'])!,
      model: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model'])!,
      sourcesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sources_json'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ArticleChatMessagesTable createAlias(String alias) {
    return $ArticleChatMessagesTable(attachedDatabase, alias);
  }
}

class ArticleChatMessage extends DataClass
    implements Insertable<ArticleChatMessage> {
  final String id;
  final String articleId;
  final String role;
  final String msgText;
  final String model;
  final String sourcesJson;
  final String createdAt;
  const ArticleChatMessage(
      {required this.id,
      required this.articleId,
      required this.role,
      required this.msgText,
      required this.model,
      required this.sourcesJson,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['article_id'] = Variable<String>(articleId);
    map['role'] = Variable<String>(role);
    map['msg_text'] = Variable<String>(msgText);
    map['model'] = Variable<String>(model);
    map['sources_json'] = Variable<String>(sourcesJson);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  ArticleChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ArticleChatMessagesCompanion(
      id: Value(id),
      articleId: Value(articleId),
      role: Value(role),
      msgText: Value(msgText),
      model: Value(model),
      sourcesJson: Value(sourcesJson),
      createdAt: Value(createdAt),
    );
  }

  factory ArticleChatMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArticleChatMessage(
      id: serializer.fromJson<String>(json['id']),
      articleId: serializer.fromJson<String>(json['articleId']),
      role: serializer.fromJson<String>(json['role']),
      msgText: serializer.fromJson<String>(json['msgText']),
      model: serializer.fromJson<String>(json['model']),
      sourcesJson: serializer.fromJson<String>(json['sourcesJson']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'articleId': serializer.toJson<String>(articleId),
      'role': serializer.toJson<String>(role),
      'msgText': serializer.toJson<String>(msgText),
      'model': serializer.toJson<String>(model),
      'sourcesJson': serializer.toJson<String>(sourcesJson),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  ArticleChatMessage copyWith(
          {String? id,
          String? articleId,
          String? role,
          String? msgText,
          String? model,
          String? sourcesJson,
          String? createdAt}) =>
      ArticleChatMessage(
        id: id ?? this.id,
        articleId: articleId ?? this.articleId,
        role: role ?? this.role,
        msgText: msgText ?? this.msgText,
        model: model ?? this.model,
        sourcesJson: sourcesJson ?? this.sourcesJson,
        createdAt: createdAt ?? this.createdAt,
      );
  ArticleChatMessage copyWithCompanion(ArticleChatMessagesCompanion data) {
    return ArticleChatMessage(
      id: data.id.present ? data.id.value : this.id,
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
      role: data.role.present ? data.role.value : this.role,
      msgText: data.msgText.present ? data.msgText.value : this.msgText,
      model: data.model.present ? data.model.value : this.model,
      sourcesJson:
          data.sourcesJson.present ? data.sourcesJson.value : this.sourcesJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArticleChatMessage(')
          ..write('id: $id, ')
          ..write('articleId: $articleId, ')
          ..write('role: $role, ')
          ..write('msgText: $msgText, ')
          ..write('model: $model, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, articleId, role, msgText, model, sourcesJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArticleChatMessage &&
          other.id == this.id &&
          other.articleId == this.articleId &&
          other.role == this.role &&
          other.msgText == this.msgText &&
          other.model == this.model &&
          other.sourcesJson == this.sourcesJson &&
          other.createdAt == this.createdAt);
}

class ArticleChatMessagesCompanion extends UpdateCompanion<ArticleChatMessage> {
  final Value<String> id;
  final Value<String> articleId;
  final Value<String> role;
  final Value<String> msgText;
  final Value<String> model;
  final Value<String> sourcesJson;
  final Value<String> createdAt;
  final Value<int> rowid;
  const ArticleChatMessagesCompanion({
    this.id = const Value.absent(),
    this.articleId = const Value.absent(),
    this.role = const Value.absent(),
    this.msgText = const Value.absent(),
    this.model = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArticleChatMessagesCompanion.insert({
    required String id,
    required String articleId,
    required String role,
    required String msgText,
    this.model = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    required String createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        articleId = Value(articleId),
        role = Value(role),
        msgText = Value(msgText),
        createdAt = Value(createdAt);
  static Insertable<ArticleChatMessage> custom({
    Expression<String>? id,
    Expression<String>? articleId,
    Expression<String>? role,
    Expression<String>? msgText,
    Expression<String>? model,
    Expression<String>? sourcesJson,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (articleId != null) 'article_id': articleId,
      if (role != null) 'role': role,
      if (msgText != null) 'msg_text': msgText,
      if (model != null) 'model': model,
      if (sourcesJson != null) 'sources_json': sourcesJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArticleChatMessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? articleId,
      Value<String>? role,
      Value<String>? msgText,
      Value<String>? model,
      Value<String>? sourcesJson,
      Value<String>? createdAt,
      Value<int>? rowid}) {
    return ArticleChatMessagesCompanion(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      role: role ?? this.role,
      msgText: msgText ?? this.msgText,
      model: model ?? this.model,
      sourcesJson: sourcesJson ?? this.sourcesJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (articleId.present) {
      map['article_id'] = Variable<String>(articleId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (msgText.present) {
      map['msg_text'] = Variable<String>(msgText.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (sourcesJson.present) {
      map['sources_json'] = Variable<String>(sourcesJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticleChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('articleId: $articleId, ')
          ..write('role: $role, ')
          ..write('msgText: $msgText, ')
          ..write('model: $model, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ArticleChatSummariesTable extends ArticleChatSummaries
    with TableInfo<$ArticleChatSummariesTable, ArticleChatSummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticleChatSummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _articleIdMeta =
      const VerificationMeta('articleId');
  @override
  late final GeneratedColumn<String> articleId = GeneratedColumn<String>(
      'article_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _summaryTextMeta =
      const VerificationMeta('summaryText');
  @override
  late final GeneratedColumn<String> summaryText = GeneratedColumn<String>(
      'summary_text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pairsCoveredMeta =
      const VerificationMeta('pairsCovered');
  @override
  late final GeneratedColumn<int> pairsCovered = GeneratedColumn<int>(
      'pairs_covered', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [articleId, summaryText, pairsCovered, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'article_chat_summaries';
  @override
  VerificationContext validateIntegrity(Insertable<ArticleChatSummary> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('article_id')) {
      context.handle(_articleIdMeta,
          articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta));
    } else if (isInserting) {
      context.missing(_articleIdMeta);
    }
    if (data.containsKey('summary_text')) {
      context.handle(
          _summaryTextMeta,
          summaryText.isAcceptableOrUnknown(
              data['summary_text']!, _summaryTextMeta));
    } else if (isInserting) {
      context.missing(_summaryTextMeta);
    }
    if (data.containsKey('pairs_covered')) {
      context.handle(
          _pairsCoveredMeta,
          pairsCovered.isAcceptableOrUnknown(
              data['pairs_covered']!, _pairsCoveredMeta));
    } else if (isInserting) {
      context.missing(_pairsCoveredMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {articleId};
  @override
  ArticleChatSummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArticleChatSummary(
      articleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}article_id'])!,
      summaryText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary_text'])!,
      pairsCovered: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}pairs_covered'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ArticleChatSummariesTable createAlias(String alias) {
    return $ArticleChatSummariesTable(attachedDatabase, alias);
  }
}

class ArticleChatSummary extends DataClass
    implements Insertable<ArticleChatSummary> {
  final String articleId;
  final String summaryText;
  final int pairsCovered;
  final String updatedAt;
  const ArticleChatSummary(
      {required this.articleId,
      required this.summaryText,
      required this.pairsCovered,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['article_id'] = Variable<String>(articleId);
    map['summary_text'] = Variable<String>(summaryText);
    map['pairs_covered'] = Variable<int>(pairsCovered);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ArticleChatSummariesCompanion toCompanion(bool nullToAbsent) {
    return ArticleChatSummariesCompanion(
      articleId: Value(articleId),
      summaryText: Value(summaryText),
      pairsCovered: Value(pairsCovered),
      updatedAt: Value(updatedAt),
    );
  }

  factory ArticleChatSummary.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArticleChatSummary(
      articleId: serializer.fromJson<String>(json['articleId']),
      summaryText: serializer.fromJson<String>(json['summaryText']),
      pairsCovered: serializer.fromJson<int>(json['pairsCovered']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'articleId': serializer.toJson<String>(articleId),
      'summaryText': serializer.toJson<String>(summaryText),
      'pairsCovered': serializer.toJson<int>(pairsCovered),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ArticleChatSummary copyWith(
          {String? articleId,
          String? summaryText,
          int? pairsCovered,
          String? updatedAt}) =>
      ArticleChatSummary(
        articleId: articleId ?? this.articleId,
        summaryText: summaryText ?? this.summaryText,
        pairsCovered: pairsCovered ?? this.pairsCovered,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ArticleChatSummary copyWithCompanion(ArticleChatSummariesCompanion data) {
    return ArticleChatSummary(
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
      summaryText:
          data.summaryText.present ? data.summaryText.value : this.summaryText,
      pairsCovered: data.pairsCovered.present
          ? data.pairsCovered.value
          : this.pairsCovered,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArticleChatSummary(')
          ..write('articleId: $articleId, ')
          ..write('summaryText: $summaryText, ')
          ..write('pairsCovered: $pairsCovered, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(articleId, summaryText, pairsCovered, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArticleChatSummary &&
          other.articleId == this.articleId &&
          other.summaryText == this.summaryText &&
          other.pairsCovered == this.pairsCovered &&
          other.updatedAt == this.updatedAt);
}

class ArticleChatSummariesCompanion
    extends UpdateCompanion<ArticleChatSummary> {
  final Value<String> articleId;
  final Value<String> summaryText;
  final Value<int> pairsCovered;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ArticleChatSummariesCompanion({
    this.articleId = const Value.absent(),
    this.summaryText = const Value.absent(),
    this.pairsCovered = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArticleChatSummariesCompanion.insert({
    required String articleId,
    required String summaryText,
    required int pairsCovered,
    required String updatedAt,
    this.rowid = const Value.absent(),
  })  : articleId = Value(articleId),
        summaryText = Value(summaryText),
        pairsCovered = Value(pairsCovered),
        updatedAt = Value(updatedAt);
  static Insertable<ArticleChatSummary> custom({
    Expression<String>? articleId,
    Expression<String>? summaryText,
    Expression<int>? pairsCovered,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (articleId != null) 'article_id': articleId,
      if (summaryText != null) 'summary_text': summaryText,
      if (pairsCovered != null) 'pairs_covered': pairsCovered,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArticleChatSummariesCompanion copyWith(
      {Value<String>? articleId,
      Value<String>? summaryText,
      Value<int>? pairsCovered,
      Value<String>? updatedAt,
      Value<int>? rowid}) {
    return ArticleChatSummariesCompanion(
      articleId: articleId ?? this.articleId,
      summaryText: summaryText ?? this.summaryText,
      pairsCovered: pairsCovered ?? this.pairsCovered,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (articleId.present) {
      map['article_id'] = Variable<String>(articleId.value);
    }
    if (summaryText.present) {
      map['summary_text'] = Variable<String>(summaryText.value);
    }
    if (pairsCovered.present) {
      map['pairs_covered'] = Variable<int>(pairsCovered.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticleChatSummariesCompanion(')
          ..write('articleId: $articleId, ')
          ..write('summaryText: $summaryText, ')
          ..write('pairsCovered: $pairsCovered, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ExpensesTable expenses = $ExpensesTable(this);
  late final $BudgetEntriesTable budgetEntries = $BudgetEntriesTable(this);
  late final $NewsArticlesTable newsArticles = $NewsArticlesTable(this);
  late final $CloudFilesTable cloudFiles = $CloudFilesTable(this);
  late final $SavedWordsTable savedWords = $SavedWordsTable(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $CategoryLearningsTable categoryLearnings =
      $CategoryLearningsTable(this);
  late final $ArticleChatMessagesTable articleChatMessages =
      $ArticleChatMessagesTable(this);
  late final $ArticleChatSummariesTable articleChatSummaries =
      $ArticleChatSummariesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        expenses,
        budgetEntries,
        newsArticles,
        cloudFiles,
        savedWords,
        syncQueue,
        categoryLearnings,
        articleChatMessages,
        articleChatSummaries
      ];
}

typedef $$ExpensesTableCreateCompanionBuilder = ExpensesCompanion Function({
  required String id,
  required double amount,
  required String description,
  required String category,
  required String bank,
  required String cardType,
  required String date,
  Value<bool> isManualCategory,
  Value<int> rowid,
});
typedef $$ExpensesTableUpdateCompanionBuilder = ExpensesCompanion Function({
  Value<String> id,
  Value<double> amount,
  Value<String> description,
  Value<String> category,
  Value<String> bank,
  Value<String> cardType,
  Value<String> date,
  Value<bool> isManualCategory,
  Value<int> rowid,
});

class $$ExpensesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bank => $composableBuilder(
      column: $table.bank, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardType => $composableBuilder(
      column: $table.cardType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isManualCategory => $composableBuilder(
      column: $table.isManualCategory,
      builder: (column) => ColumnFilters(column));
}

class $$ExpensesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bank => $composableBuilder(
      column: $table.bank, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardType => $composableBuilder(
      column: $table.cardType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isManualCategory => $composableBuilder(
      column: $table.isManualCategory,
      builder: (column) => ColumnOrderings(column));
}

class $$ExpensesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get bank =>
      $composableBuilder(column: $table.bank, builder: (column) => column);

  GeneratedColumn<String> get cardType =>
      $composableBuilder(column: $table.cardType, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<bool> get isManualCategory => $composableBuilder(
      column: $table.isManualCategory, builder: (column) => column);
}

class $$ExpensesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ExpensesTable,
    Expense,
    $$ExpensesTableFilterComposer,
    $$ExpensesTableOrderingComposer,
    $$ExpensesTableAnnotationComposer,
    $$ExpensesTableCreateCompanionBuilder,
    $$ExpensesTableUpdateCompanionBuilder,
    (Expense, BaseReferences<_$AppDatabase, $ExpensesTable, Expense>),
    Expense,
    PrefetchHooks Function()> {
  $$ExpensesTableTableManager(_$AppDatabase db, $ExpensesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String> bank = const Value.absent(),
            Value<String> cardType = const Value.absent(),
            Value<String> date = const Value.absent(),
            Value<bool> isManualCategory = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExpensesCompanion(
            id: id,
            amount: amount,
            description: description,
            category: category,
            bank: bank,
            cardType: cardType,
            date: date,
            isManualCategory: isManualCategory,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required double amount,
            required String description,
            required String category,
            required String bank,
            required String cardType,
            required String date,
            Value<bool> isManualCategory = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExpensesCompanion.insert(
            id: id,
            amount: amount,
            description: description,
            category: category,
            bank: bank,
            cardType: cardType,
            date: date,
            isManualCategory: isManualCategory,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExpensesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ExpensesTable,
    Expense,
    $$ExpensesTableFilterComposer,
    $$ExpensesTableOrderingComposer,
    $$ExpensesTableAnnotationComposer,
    $$ExpensesTableCreateCompanionBuilder,
    $$ExpensesTableUpdateCompanionBuilder,
    (Expense, BaseReferences<_$AppDatabase, $ExpensesTable, Expense>),
    Expense,
    PrefetchHooks Function()>;
typedef $$BudgetEntriesTableCreateCompanionBuilder = BudgetEntriesCompanion
    Function({
  required String id,
  required double amount,
  required String setAt,
  Value<int> rowid,
});
typedef $$BudgetEntriesTableUpdateCompanionBuilder = BudgetEntriesCompanion
    Function({
  Value<String> id,
  Value<double> amount,
  Value<String> setAt,
  Value<int> rowid,
});

class $$BudgetEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetEntriesTable> {
  $$BudgetEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get setAt => $composableBuilder(
      column: $table.setAt, builder: (column) => ColumnFilters(column));
}

class $$BudgetEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetEntriesTable> {
  $$BudgetEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get setAt => $composableBuilder(
      column: $table.setAt, builder: (column) => ColumnOrderings(column));
}

class $$BudgetEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetEntriesTable> {
  $$BudgetEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get setAt =>
      $composableBuilder(column: $table.setAt, builder: (column) => column);
}

class $$BudgetEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BudgetEntriesTable,
    BudgetEntry,
    $$BudgetEntriesTableFilterComposer,
    $$BudgetEntriesTableOrderingComposer,
    $$BudgetEntriesTableAnnotationComposer,
    $$BudgetEntriesTableCreateCompanionBuilder,
    $$BudgetEntriesTableUpdateCompanionBuilder,
    (
      BudgetEntry,
      BaseReferences<_$AppDatabase, $BudgetEntriesTable, BudgetEntry>
    ),
    BudgetEntry,
    PrefetchHooks Function()> {
  $$BudgetEntriesTableTableManager(_$AppDatabase db, $BudgetEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BudgetEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BudgetEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> setAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BudgetEntriesCompanion(
            id: id,
            amount: amount,
            setAt: setAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required double amount,
            required String setAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              BudgetEntriesCompanion.insert(
            id: id,
            amount: amount,
            setAt: setAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BudgetEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BudgetEntriesTable,
    BudgetEntry,
    $$BudgetEntriesTableFilterComposer,
    $$BudgetEntriesTableOrderingComposer,
    $$BudgetEntriesTableAnnotationComposer,
    $$BudgetEntriesTableCreateCompanionBuilder,
    $$BudgetEntriesTableUpdateCompanionBuilder,
    (
      BudgetEntry,
      BaseReferences<_$AppDatabase, $BudgetEntriesTable, BudgetEntry>
    ),
    BudgetEntry,
    PrefetchHooks Function()>;
typedef $$NewsArticlesTableCreateCompanionBuilder = NewsArticlesCompanion
    Function({
  required String id,
  required String title,
  required String excerpt,
  required String source,
  required String category,
  required String imageUrl,
  required int readTime,
  required String date,
  required String blocksJson,
  Value<bool> isSaved,
  Value<bool> isRead,
  Value<String?> summaryShort,
  Value<int> rowid,
});
typedef $$NewsArticlesTableUpdateCompanionBuilder = NewsArticlesCompanion
    Function({
  Value<String> id,
  Value<String> title,
  Value<String> excerpt,
  Value<String> source,
  Value<String> category,
  Value<String> imageUrl,
  Value<int> readTime,
  Value<String> date,
  Value<String> blocksJson,
  Value<bool> isSaved,
  Value<bool> isRead,
  Value<String?> summaryShort,
  Value<int> rowid,
});

class $$NewsArticlesTableFilterComposer
    extends Composer<_$AppDatabase, $NewsArticlesTable> {
  $$NewsArticlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get excerpt => $composableBuilder(
      column: $table.excerpt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get readTime => $composableBuilder(
      column: $table.readTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get blocksJson => $composableBuilder(
      column: $table.blocksJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSaved => $composableBuilder(
      column: $table.isSaved, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summaryShort => $composableBuilder(
      column: $table.summaryShort, builder: (column) => ColumnFilters(column));
}

class $$NewsArticlesTableOrderingComposer
    extends Composer<_$AppDatabase, $NewsArticlesTable> {
  $$NewsArticlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get excerpt => $composableBuilder(
      column: $table.excerpt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get readTime => $composableBuilder(
      column: $table.readTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get blocksJson => $composableBuilder(
      column: $table.blocksJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSaved => $composableBuilder(
      column: $table.isSaved, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summaryShort => $composableBuilder(
      column: $table.summaryShort,
      builder: (column) => ColumnOrderings(column));
}

class $$NewsArticlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NewsArticlesTable> {
  $$NewsArticlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get excerpt =>
      $composableBuilder(column: $table.excerpt, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<int> get readTime =>
      $composableBuilder(column: $table.readTime, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get blocksJson => $composableBuilder(
      column: $table.blocksJson, builder: (column) => column);

  GeneratedColumn<bool> get isSaved =>
      $composableBuilder(column: $table.isSaved, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<String> get summaryShort => $composableBuilder(
      column: $table.summaryShort, builder: (column) => column);
}

class $$NewsArticlesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $NewsArticlesTable,
    NewsArticle,
    $$NewsArticlesTableFilterComposer,
    $$NewsArticlesTableOrderingComposer,
    $$NewsArticlesTableAnnotationComposer,
    $$NewsArticlesTableCreateCompanionBuilder,
    $$NewsArticlesTableUpdateCompanionBuilder,
    (
      NewsArticle,
      BaseReferences<_$AppDatabase, $NewsArticlesTable, NewsArticle>
    ),
    NewsArticle,
    PrefetchHooks Function()> {
  $$NewsArticlesTableTableManager(_$AppDatabase db, $NewsArticlesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NewsArticlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NewsArticlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NewsArticlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> excerpt = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String> imageUrl = const Value.absent(),
            Value<int> readTime = const Value.absent(),
            Value<String> date = const Value.absent(),
            Value<String> blocksJson = const Value.absent(),
            Value<bool> isSaved = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<String?> summaryShort = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              NewsArticlesCompanion(
            id: id,
            title: title,
            excerpt: excerpt,
            source: source,
            category: category,
            imageUrl: imageUrl,
            readTime: readTime,
            date: date,
            blocksJson: blocksJson,
            isSaved: isSaved,
            isRead: isRead,
            summaryShort: summaryShort,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required String excerpt,
            required String source,
            required String category,
            required String imageUrl,
            required int readTime,
            required String date,
            required String blocksJson,
            Value<bool> isSaved = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<String?> summaryShort = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              NewsArticlesCompanion.insert(
            id: id,
            title: title,
            excerpt: excerpt,
            source: source,
            category: category,
            imageUrl: imageUrl,
            readTime: readTime,
            date: date,
            blocksJson: blocksJson,
            isSaved: isSaved,
            isRead: isRead,
            summaryShort: summaryShort,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$NewsArticlesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $NewsArticlesTable,
    NewsArticle,
    $$NewsArticlesTableFilterComposer,
    $$NewsArticlesTableOrderingComposer,
    $$NewsArticlesTableAnnotationComposer,
    $$NewsArticlesTableCreateCompanionBuilder,
    $$NewsArticlesTableUpdateCompanionBuilder,
    (
      NewsArticle,
      BaseReferences<_$AppDatabase, $NewsArticlesTable, NewsArticle>
    ),
    NewsArticle,
    PrefetchHooks Function()>;
typedef $$CloudFilesTableCreateCompanionBuilder = CloudFilesCompanion Function({
  required String id,
  required String name,
  required String type,
  required int sizeBytes,
  required String uploadDate,
  Value<bool> isStarred,
  Value<int> rowid,
});
typedef $$CloudFilesTableUpdateCompanionBuilder = CloudFilesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> type,
  Value<int> sizeBytes,
  Value<String> uploadDate,
  Value<bool> isStarred,
  Value<int> rowid,
});

class $$CloudFilesTableFilterComposer
    extends Composer<_$AppDatabase, $CloudFilesTable> {
  $$CloudFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uploadDate => $composableBuilder(
      column: $table.uploadDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isStarred => $composableBuilder(
      column: $table.isStarred, builder: (column) => ColumnFilters(column));
}

class $$CloudFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $CloudFilesTable> {
  $$CloudFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uploadDate => $composableBuilder(
      column: $table.uploadDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isStarred => $composableBuilder(
      column: $table.isStarred, builder: (column) => ColumnOrderings(column));
}

class $$CloudFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CloudFilesTable> {
  $$CloudFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get uploadDate => $composableBuilder(
      column: $table.uploadDate, builder: (column) => column);

  GeneratedColumn<bool> get isStarred =>
      $composableBuilder(column: $table.isStarred, builder: (column) => column);
}

class $$CloudFilesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CloudFilesTable,
    CloudFile,
    $$CloudFilesTableFilterComposer,
    $$CloudFilesTableOrderingComposer,
    $$CloudFilesTableAnnotationComposer,
    $$CloudFilesTableCreateCompanionBuilder,
    $$CloudFilesTableUpdateCompanionBuilder,
    (CloudFile, BaseReferences<_$AppDatabase, $CloudFilesTable, CloudFile>),
    CloudFile,
    PrefetchHooks Function()> {
  $$CloudFilesTableTableManager(_$AppDatabase db, $CloudFilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CloudFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CloudFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CloudFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int> sizeBytes = const Value.absent(),
            Value<String> uploadDate = const Value.absent(),
            Value<bool> isStarred = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CloudFilesCompanion(
            id: id,
            name: name,
            type: type,
            sizeBytes: sizeBytes,
            uploadDate: uploadDate,
            isStarred: isStarred,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String type,
            required int sizeBytes,
            required String uploadDate,
            Value<bool> isStarred = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CloudFilesCompanion.insert(
            id: id,
            name: name,
            type: type,
            sizeBytes: sizeBytes,
            uploadDate: uploadDate,
            isStarred: isStarred,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CloudFilesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CloudFilesTable,
    CloudFile,
    $$CloudFilesTableFilterComposer,
    $$CloudFilesTableOrderingComposer,
    $$CloudFilesTableAnnotationComposer,
    $$CloudFilesTableCreateCompanionBuilder,
    $$CloudFilesTableUpdateCompanionBuilder,
    (CloudFile, BaseReferences<_$AppDatabase, $CloudFilesTable, CloudFile>),
    CloudFile,
    PrefetchHooks Function()>;
typedef $$SavedWordsTableCreateCompanionBuilder = SavedWordsCompanion Function({
  required String id,
  required String word,
  required String definition,
  required String pronunciation,
  required String partOfSpeech,
  required String savedAt,
  Value<String> responseJson,
  Value<int> rowid,
});
typedef $$SavedWordsTableUpdateCompanionBuilder = SavedWordsCompanion Function({
  Value<String> id,
  Value<String> word,
  Value<String> definition,
  Value<String> pronunciation,
  Value<String> partOfSpeech,
  Value<String> savedAt,
  Value<String> responseJson,
  Value<int> rowid,
});

class $$SavedWordsTableFilterComposer
    extends Composer<_$AppDatabase, $SavedWordsTable> {
  $$SavedWordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get word => $composableBuilder(
      column: $table.word, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get definition => $composableBuilder(
      column: $table.definition, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get partOfSpeech => $composableBuilder(
      column: $table.partOfSpeech, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responseJson => $composableBuilder(
      column: $table.responseJson, builder: (column) => ColumnFilters(column));
}

class $$SavedWordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedWordsTable> {
  $$SavedWordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get word => $composableBuilder(
      column: $table.word, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get definition => $composableBuilder(
      column: $table.definition, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get partOfSpeech => $composableBuilder(
      column: $table.partOfSpeech,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responseJson => $composableBuilder(
      column: $table.responseJson,
      builder: (column) => ColumnOrderings(column));
}

class $$SavedWordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedWordsTable> {
  $$SavedWordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get word =>
      $composableBuilder(column: $table.word, builder: (column) => column);

  GeneratedColumn<String> get definition => $composableBuilder(
      column: $table.definition, builder: (column) => column);

  GeneratedColumn<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation, builder: (column) => column);

  GeneratedColumn<String> get partOfSpeech => $composableBuilder(
      column: $table.partOfSpeech, builder: (column) => column);

  GeneratedColumn<String> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<String> get responseJson => $composableBuilder(
      column: $table.responseJson, builder: (column) => column);
}

class $$SavedWordsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SavedWordsTable,
    SavedWord,
    $$SavedWordsTableFilterComposer,
    $$SavedWordsTableOrderingComposer,
    $$SavedWordsTableAnnotationComposer,
    $$SavedWordsTableCreateCompanionBuilder,
    $$SavedWordsTableUpdateCompanionBuilder,
    (SavedWord, BaseReferences<_$AppDatabase, $SavedWordsTable, SavedWord>),
    SavedWord,
    PrefetchHooks Function()> {
  $$SavedWordsTableTableManager(_$AppDatabase db, $SavedWordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedWordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedWordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedWordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> word = const Value.absent(),
            Value<String> definition = const Value.absent(),
            Value<String> pronunciation = const Value.absent(),
            Value<String> partOfSpeech = const Value.absent(),
            Value<String> savedAt = const Value.absent(),
            Value<String> responseJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedWordsCompanion(
            id: id,
            word: word,
            definition: definition,
            pronunciation: pronunciation,
            partOfSpeech: partOfSpeech,
            savedAt: savedAt,
            responseJson: responseJson,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String word,
            required String definition,
            required String pronunciation,
            required String partOfSpeech,
            required String savedAt,
            Value<String> responseJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedWordsCompanion.insert(
            id: id,
            word: word,
            definition: definition,
            pronunciation: pronunciation,
            partOfSpeech: partOfSpeech,
            savedAt: savedAt,
            responseJson: responseJson,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SavedWordsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SavedWordsTable,
    SavedWord,
    $$SavedWordsTableFilterComposer,
    $$SavedWordsTableOrderingComposer,
    $$SavedWordsTableAnnotationComposer,
    $$SavedWordsTableCreateCompanionBuilder,
    $$SavedWordsTableUpdateCompanionBuilder,
    (SavedWord, BaseReferences<_$AppDatabase, $SavedWordsTable, SavedWord>),
    SavedWord,
    PrefetchHooks Function()>;
typedef $$SyncQueueTableCreateCompanionBuilder = SyncQueueCompanion Function({
  Value<int> id,
  required String entityType,
  required String entityId,
  required String action,
  required String payload,
  required String createdAt,
  Value<bool> synced,
});
typedef $$SyncQueueTableUpdateCompanionBuilder = SyncQueueCompanion Function({
  Value<int> id,
  Value<String> entityType,
  Value<String> entityId,
  Value<String> action,
  Value<String> payload,
  Value<String> createdAt,
  Value<bool> synced,
});

class $$SyncQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnFilters(column));
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnOrderings(column));
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$SyncQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncQueueTable,
    SyncQueueData,
    $$SyncQueueTableFilterComposer,
    $$SyncQueueTableOrderingComposer,
    $$SyncQueueTableAnnotationComposer,
    $$SyncQueueTableCreateCompanionBuilder,
    $$SyncQueueTableUpdateCompanionBuilder,
    (
      SyncQueueData,
      BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>
    ),
    SyncQueueData,
    PrefetchHooks Function()> {
  $$SyncQueueTableTableManager(_$AppDatabase db, $SyncQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<String> entityId = const Value.absent(),
            Value<String> action = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
            Value<bool> synced = const Value.absent(),
          }) =>
              SyncQueueCompanion(
            id: id,
            entityType: entityType,
            entityId: entityId,
            action: action,
            payload: payload,
            createdAt: createdAt,
            synced: synced,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String entityType,
            required String entityId,
            required String action,
            required String payload,
            required String createdAt,
            Value<bool> synced = const Value.absent(),
          }) =>
              SyncQueueCompanion.insert(
            id: id,
            entityType: entityType,
            entityId: entityId,
            action: action,
            payload: payload,
            createdAt: createdAt,
            synced: synced,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncQueueTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncQueueTable,
    SyncQueueData,
    $$SyncQueueTableFilterComposer,
    $$SyncQueueTableOrderingComposer,
    $$SyncQueueTableAnnotationComposer,
    $$SyncQueueTableCreateCompanionBuilder,
    $$SyncQueueTableUpdateCompanionBuilder,
    (
      SyncQueueData,
      BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>
    ),
    SyncQueueData,
    PrefetchHooks Function()>;
typedef $$CategoryLearningsTableCreateCompanionBuilder
    = CategoryLearningsCompanion Function({
  required String keyword,
  required String category,
  Value<int> rowid,
});
typedef $$CategoryLearningsTableUpdateCompanionBuilder
    = CategoryLearningsCompanion Function({
  Value<String> keyword,
  Value<String> category,
  Value<int> rowid,
});

class $$CategoryLearningsTableFilterComposer
    extends Composer<_$AppDatabase, $CategoryLearningsTable> {
  $$CategoryLearningsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyword => $composableBuilder(
      column: $table.keyword, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));
}

class $$CategoryLearningsTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoryLearningsTable> {
  $$CategoryLearningsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyword => $composableBuilder(
      column: $table.keyword, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));
}

class $$CategoryLearningsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoryLearningsTable> {
  $$CategoryLearningsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyword =>
      $composableBuilder(column: $table.keyword, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);
}

class $$CategoryLearningsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CategoryLearningsTable,
    CategoryLearning,
    $$CategoryLearningsTableFilterComposer,
    $$CategoryLearningsTableOrderingComposer,
    $$CategoryLearningsTableAnnotationComposer,
    $$CategoryLearningsTableCreateCompanionBuilder,
    $$CategoryLearningsTableUpdateCompanionBuilder,
    (
      CategoryLearning,
      BaseReferences<_$AppDatabase, $CategoryLearningsTable, CategoryLearning>
    ),
    CategoryLearning,
    PrefetchHooks Function()> {
  $$CategoryLearningsTableTableManager(
      _$AppDatabase db, $CategoryLearningsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoryLearningsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoryLearningsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoryLearningsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> keyword = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoryLearningsCompanion(
            keyword: keyword,
            category: category,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String keyword,
            required String category,
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoryLearningsCompanion.insert(
            keyword: keyword,
            category: category,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CategoryLearningsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CategoryLearningsTable,
    CategoryLearning,
    $$CategoryLearningsTableFilterComposer,
    $$CategoryLearningsTableOrderingComposer,
    $$CategoryLearningsTableAnnotationComposer,
    $$CategoryLearningsTableCreateCompanionBuilder,
    $$CategoryLearningsTableUpdateCompanionBuilder,
    (
      CategoryLearning,
      BaseReferences<_$AppDatabase, $CategoryLearningsTable, CategoryLearning>
    ),
    CategoryLearning,
    PrefetchHooks Function()>;
typedef $$ArticleChatMessagesTableCreateCompanionBuilder
    = ArticleChatMessagesCompanion Function({
  required String id,
  required String articleId,
  required String role,
  required String msgText,
  Value<String> model,
  Value<String> sourcesJson,
  required String createdAt,
  Value<int> rowid,
});
typedef $$ArticleChatMessagesTableUpdateCompanionBuilder
    = ArticleChatMessagesCompanion Function({
  Value<String> id,
  Value<String> articleId,
  Value<String> role,
  Value<String> msgText,
  Value<String> model,
  Value<String> sourcesJson,
  Value<String> createdAt,
  Value<int> rowid,
});

class $$ArticleChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ArticleChatMessagesTable> {
  $$ArticleChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get msgText => $composableBuilder(
      column: $table.msgText, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourcesJson => $composableBuilder(
      column: $table.sourcesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ArticleChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticleChatMessagesTable> {
  $$ArticleChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get msgText => $composableBuilder(
      column: $table.msgText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourcesJson => $composableBuilder(
      column: $table.sourcesJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ArticleChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticleChatMessagesTable> {
  $$ArticleChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get articleId =>
      $composableBuilder(column: $table.articleId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get msgText =>
      $composableBuilder(column: $table.msgText, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get sourcesJson => $composableBuilder(
      column: $table.sourcesJson, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ArticleChatMessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ArticleChatMessagesTable,
    ArticleChatMessage,
    $$ArticleChatMessagesTableFilterComposer,
    $$ArticleChatMessagesTableOrderingComposer,
    $$ArticleChatMessagesTableAnnotationComposer,
    $$ArticleChatMessagesTableCreateCompanionBuilder,
    $$ArticleChatMessagesTableUpdateCompanionBuilder,
    (
      ArticleChatMessage,
      BaseReferences<_$AppDatabase, $ArticleChatMessagesTable,
          ArticleChatMessage>
    ),
    ArticleChatMessage,
    PrefetchHooks Function()> {
  $$ArticleChatMessagesTableTableManager(
      _$AppDatabase db, $ArticleChatMessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticleChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticleChatMessagesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticleChatMessagesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> articleId = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> msgText = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<String> sourcesJson = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ArticleChatMessagesCompanion(
            id: id,
            articleId: articleId,
            role: role,
            msgText: msgText,
            model: model,
            sourcesJson: sourcesJson,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String articleId,
            required String role,
            required String msgText,
            Value<String> model = const Value.absent(),
            Value<String> sourcesJson = const Value.absent(),
            required String createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ArticleChatMessagesCompanion.insert(
            id: id,
            articleId: articleId,
            role: role,
            msgText: msgText,
            model: model,
            sourcesJson: sourcesJson,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ArticleChatMessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ArticleChatMessagesTable,
    ArticleChatMessage,
    $$ArticleChatMessagesTableFilterComposer,
    $$ArticleChatMessagesTableOrderingComposer,
    $$ArticleChatMessagesTableAnnotationComposer,
    $$ArticleChatMessagesTableCreateCompanionBuilder,
    $$ArticleChatMessagesTableUpdateCompanionBuilder,
    (
      ArticleChatMessage,
      BaseReferences<_$AppDatabase, $ArticleChatMessagesTable,
          ArticleChatMessage>
    ),
    ArticleChatMessage,
    PrefetchHooks Function()>;
typedef $$ArticleChatSummariesTableCreateCompanionBuilder
    = ArticleChatSummariesCompanion Function({
  required String articleId,
  required String summaryText,
  required int pairsCovered,
  required String updatedAt,
  Value<int> rowid,
});
typedef $$ArticleChatSummariesTableUpdateCompanionBuilder
    = ArticleChatSummariesCompanion Function({
  Value<String> articleId,
  Value<String> summaryText,
  Value<int> pairsCovered,
  Value<String> updatedAt,
  Value<int> rowid,
});

class $$ArticleChatSummariesTableFilterComposer
    extends Composer<_$AppDatabase, $ArticleChatSummariesTable> {
  $$ArticleChatSummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pairsCovered => $composableBuilder(
      column: $table.pairsCovered, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ArticleChatSummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticleChatSummariesTable> {
  $$ArticleChatSummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get articleId => $composableBuilder(
      column: $table.articleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pairsCovered => $composableBuilder(
      column: $table.pairsCovered,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ArticleChatSummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticleChatSummariesTable> {
  $$ArticleChatSummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get articleId =>
      $composableBuilder(column: $table.articleId, builder: (column) => column);

  GeneratedColumn<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => column);

  GeneratedColumn<int> get pairsCovered => $composableBuilder(
      column: $table.pairsCovered, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ArticleChatSummariesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ArticleChatSummariesTable,
    ArticleChatSummary,
    $$ArticleChatSummariesTableFilterComposer,
    $$ArticleChatSummariesTableOrderingComposer,
    $$ArticleChatSummariesTableAnnotationComposer,
    $$ArticleChatSummariesTableCreateCompanionBuilder,
    $$ArticleChatSummariesTableUpdateCompanionBuilder,
    (
      ArticleChatSummary,
      BaseReferences<_$AppDatabase, $ArticleChatSummariesTable,
          ArticleChatSummary>
    ),
    ArticleChatSummary,
    PrefetchHooks Function()> {
  $$ArticleChatSummariesTableTableManager(
      _$AppDatabase db, $ArticleChatSummariesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticleChatSummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticleChatSummariesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticleChatSummariesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> articleId = const Value.absent(),
            Value<String> summaryText = const Value.absent(),
            Value<int> pairsCovered = const Value.absent(),
            Value<String> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ArticleChatSummariesCompanion(
            articleId: articleId,
            summaryText: summaryText,
            pairsCovered: pairsCovered,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String articleId,
            required String summaryText,
            required int pairsCovered,
            required String updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ArticleChatSummariesCompanion.insert(
            articleId: articleId,
            summaryText: summaryText,
            pairsCovered: pairsCovered,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ArticleChatSummariesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $ArticleChatSummariesTable,
        ArticleChatSummary,
        $$ArticleChatSummariesTableFilterComposer,
        $$ArticleChatSummariesTableOrderingComposer,
        $$ArticleChatSummariesTableAnnotationComposer,
        $$ArticleChatSummariesTableCreateCompanionBuilder,
        $$ArticleChatSummariesTableUpdateCompanionBuilder,
        (
          ArticleChatSummary,
          BaseReferences<_$AppDatabase, $ArticleChatSummariesTable,
              ArticleChatSummary>
        ),
        ArticleChatSummary,
        PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$BudgetEntriesTableTableManager get budgetEntries =>
      $$BudgetEntriesTableTableManager(_db, _db.budgetEntries);
  $$NewsArticlesTableTableManager get newsArticles =>
      $$NewsArticlesTableTableManager(_db, _db.newsArticles);
  $$CloudFilesTableTableManager get cloudFiles =>
      $$CloudFilesTableTableManager(_db, _db.cloudFiles);
  $$SavedWordsTableTableManager get savedWords =>
      $$SavedWordsTableTableManager(_db, _db.savedWords);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$CategoryLearningsTableTableManager get categoryLearnings =>
      $$CategoryLearningsTableTableManager(_db, _db.categoryLearnings);
  $$ArticleChatMessagesTableTableManager get articleChatMessages =>
      $$ArticleChatMessagesTableTableManager(_db, _db.articleChatMessages);
  $$ArticleChatSummariesTableTableManager get articleChatSummaries =>
      $$ArticleChatSummariesTableTableManager(_db, _db.articleChatSummaries);
}
