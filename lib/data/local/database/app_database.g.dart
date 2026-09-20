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
  static const VerificationMeta _commentsMeta =
      const VerificationMeta('comments');
  @override
  late final GeneratedColumn<String> comments = GeneratedColumn<String>(
      'comments', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        amount,
        description,
        category,
        bank,
        cardType,
        date,
        isManualCategory,
        comments,
        updatedAt
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
    if (data.containsKey('comments')) {
      context.handle(_commentsMeta,
          comments.isAcceptableOrUnknown(data['comments']!, _commentsMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
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
      comments: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}comments'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at']),
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

  /// Optional free-form note/reminder attached at log time (manual, voice, or
  /// PDF/scan flows). NULL/'' = no comment. Local-only-friendly: synced when the
  /// backend supports it, otherwise preserved locally.
  final String comments;

  /// ISO-8601 UTC timestamp of the last local OR remote write to this row. Used
  /// for last-write-wins cross-device merge in [ExpenseRepository.syncFromServer]
  /// — a server row only overwrites the local copy when its [updatedAt] is newer.
  /// NULL on rows created before the v10 migration (treated as "oldest").
  final String? updatedAt;
  const Expense(
      {required this.id,
      required this.amount,
      required this.description,
      required this.category,
      required this.bank,
      required this.cardType,
      required this.date,
      required this.isManualCategory,
      required this.comments,
      this.updatedAt});
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
    map['comments'] = Variable<String>(comments);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
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
      comments: Value(comments),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
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
      comments: serializer.fromJson<String>(json['comments']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
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
      'comments': serializer.toJson<String>(comments),
      'updatedAt': serializer.toJson<String?>(updatedAt),
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
          bool? isManualCategory,
          String? comments,
          Value<String?> updatedAt = const Value.absent()}) =>
      Expense(
        id: id ?? this.id,
        amount: amount ?? this.amount,
        description: description ?? this.description,
        category: category ?? this.category,
        bank: bank ?? this.bank,
        cardType: cardType ?? this.cardType,
        date: date ?? this.date,
        isManualCategory: isManualCategory ?? this.isManualCategory,
        comments: comments ?? this.comments,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
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
      comments: data.comments.present ? data.comments.value : this.comments,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
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
          ..write('isManualCategory: $isManualCategory, ')
          ..write('comments: $comments, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, amount, description, category, bank,
      cardType, date, isManualCategory, comments, updatedAt);
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
          other.isManualCategory == this.isManualCategory &&
          other.comments == this.comments &&
          other.updatedAt == this.updatedAt);
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
  final Value<String> comments;
  final Value<String?> updatedAt;
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
    this.comments = const Value.absent(),
    this.updatedAt = const Value.absent(),
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
    this.comments = const Value.absent(),
    this.updatedAt = const Value.absent(),
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
    Expression<String>? comments,
    Expression<String>? updatedAt,
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
      if (comments != null) 'comments': comments,
      if (updatedAt != null) 'updated_at': updatedAt,
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
      Value<String>? comments,
      Value<String?>? updatedAt,
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
      comments: comments ?? this.comments,
      updatedAt: updatedAt ?? this.updatedAt,
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
    if (comments.present) {
      map['comments'] = Variable<String>(comments.value);
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
    return (StringBuffer('ExpensesCompanion(')
          ..write('id: $id, ')
          ..write('amount: $amount, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('bank: $bank, ')
          ..write('cardType: $cardType, ')
          ..write('date: $date, ')
          ..write('isManualCategory: $isManualCategory, ')
          ..write('comments: $comments, ')
          ..write('updatedAt: $updatedAt, ')
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

class $SalaryEntriesTable extends SalaryEntries
    with TableInfo<$SalaryEntriesTable, SalaryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SalaryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<String> month = GeneratedColumn<String>(
      'month', aliasedName, false,
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
  List<GeneratedColumn> get $columns => [id, month, amount, setAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'salary_entries';
  @override
  VerificationContext validateIntegrity(Insertable<SalaryEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('month')) {
      context.handle(
          _monthMeta, month.isAcceptableOrUnknown(data['month']!, _monthMeta));
    } else if (isInserting) {
      context.missing(_monthMeta);
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
  Set<GeneratedColumn> get $primaryKey => {month};
  @override
  SalaryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SalaryEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      month: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}month'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      setAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}set_at'])!,
    );
  }

  @override
  $SalaryEntriesTable createAlias(String alias) {
    return $SalaryEntriesTable(attachedDatabase, alias);
  }
}

class SalaryEntry extends DataClass implements Insertable<SalaryEntry> {
  final String id;
  final String month;
  final double amount;
  final String setAt;
  const SalaryEntry(
      {required this.id,
      required this.month,
      required this.amount,
      required this.setAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['month'] = Variable<String>(month);
    map['amount'] = Variable<double>(amount);
    map['set_at'] = Variable<String>(setAt);
    return map;
  }

  SalaryEntriesCompanion toCompanion(bool nullToAbsent) {
    return SalaryEntriesCompanion(
      id: Value(id),
      month: Value(month),
      amount: Value(amount),
      setAt: Value(setAt),
    );
  }

  factory SalaryEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SalaryEntry(
      id: serializer.fromJson<String>(json['id']),
      month: serializer.fromJson<String>(json['month']),
      amount: serializer.fromJson<double>(json['amount']),
      setAt: serializer.fromJson<String>(json['setAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'month': serializer.toJson<String>(month),
      'amount': serializer.toJson<double>(amount),
      'setAt': serializer.toJson<String>(setAt),
    };
  }

  SalaryEntry copyWith(
          {String? id, String? month, double? amount, String? setAt}) =>
      SalaryEntry(
        id: id ?? this.id,
        month: month ?? this.month,
        amount: amount ?? this.amount,
        setAt: setAt ?? this.setAt,
      );
  SalaryEntry copyWithCompanion(SalaryEntriesCompanion data) {
    return SalaryEntry(
      id: data.id.present ? data.id.value : this.id,
      month: data.month.present ? data.month.value : this.month,
      amount: data.amount.present ? data.amount.value : this.amount,
      setAt: data.setAt.present ? data.setAt.value : this.setAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SalaryEntry(')
          ..write('id: $id, ')
          ..write('month: $month, ')
          ..write('amount: $amount, ')
          ..write('setAt: $setAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, month, amount, setAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SalaryEntry &&
          other.id == this.id &&
          other.month == this.month &&
          other.amount == this.amount &&
          other.setAt == this.setAt);
}

class SalaryEntriesCompanion extends UpdateCompanion<SalaryEntry> {
  final Value<String> id;
  final Value<String> month;
  final Value<double> amount;
  final Value<String> setAt;
  final Value<int> rowid;
  const SalaryEntriesCompanion({
    this.id = const Value.absent(),
    this.month = const Value.absent(),
    this.amount = const Value.absent(),
    this.setAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SalaryEntriesCompanion.insert({
    required String id,
    required String month,
    required double amount,
    required String setAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        month = Value(month),
        amount = Value(amount),
        setAt = Value(setAt);
  static Insertable<SalaryEntry> custom({
    Expression<String>? id,
    Expression<String>? month,
    Expression<double>? amount,
    Expression<String>? setAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (month != null) 'month': month,
      if (amount != null) 'amount': amount,
      if (setAt != null) 'set_at': setAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SalaryEntriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? month,
      Value<double>? amount,
      Value<String>? setAt,
      Value<int>? rowid}) {
    return SalaryEntriesCompanion(
      id: id ?? this.id,
      month: month ?? this.month,
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
    if (month.present) {
      map['month'] = Variable<String>(month.value);
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
    return (StringBuffer('SalaryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('month: $month, ')
          ..write('amount: $amount, ')
          ..write('setAt: $setAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpenseMonthlyCategoryTable extends ExpenseMonthlyCategory
    with TableInfo<$ExpenseMonthlyCategoryTable, ExpenseMonthlyCategoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpenseMonthlyCategoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<String> month = GeneratedColumn<String>(
      'month', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<double> total = GeneratedColumn<double>(
      'total', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
      'count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [month, category, total, count];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expense_monthly_category';
  @override
  VerificationContext validateIntegrity(
      Insertable<ExpenseMonthlyCategoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('month')) {
      context.handle(
          _monthMeta, month.isAcceptableOrUnknown(data['month']!, _monthMeta));
    } else if (isInserting) {
      context.missing(_monthMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('total')) {
      context.handle(
          _totalMeta, total.isAcceptableOrUnknown(data['total']!, _totalMeta));
    }
    if (data.containsKey('count')) {
      context.handle(
          _countMeta, count.isAcceptableOrUnknown(data['count']!, _countMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {month, category};
  @override
  ExpenseMonthlyCategoryData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseMonthlyCategoryData(
      month: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}month'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      total: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}total'])!,
      count: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}count'])!,
    );
  }

  @override
  $ExpenseMonthlyCategoryTable createAlias(String alias) {
    return $ExpenseMonthlyCategoryTable(attachedDatabase, alias);
  }
}

class ExpenseMonthlyCategoryData extends DataClass
    implements Insertable<ExpenseMonthlyCategoryData> {
  final String month;
  final String category;
  final double total;
  final int count;
  const ExpenseMonthlyCategoryData(
      {required this.month,
      required this.category,
      required this.total,
      required this.count});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['month'] = Variable<String>(month);
    map['category'] = Variable<String>(category);
    map['total'] = Variable<double>(total);
    map['count'] = Variable<int>(count);
    return map;
  }

  ExpenseMonthlyCategoryCompanion toCompanion(bool nullToAbsent) {
    return ExpenseMonthlyCategoryCompanion(
      month: Value(month),
      category: Value(category),
      total: Value(total),
      count: Value(count),
    );
  }

  factory ExpenseMonthlyCategoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseMonthlyCategoryData(
      month: serializer.fromJson<String>(json['month']),
      category: serializer.fromJson<String>(json['category']),
      total: serializer.fromJson<double>(json['total']),
      count: serializer.fromJson<int>(json['count']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'month': serializer.toJson<String>(month),
      'category': serializer.toJson<String>(category),
      'total': serializer.toJson<double>(total),
      'count': serializer.toJson<int>(count),
    };
  }

  ExpenseMonthlyCategoryData copyWith(
          {String? month, String? category, double? total, int? count}) =>
      ExpenseMonthlyCategoryData(
        month: month ?? this.month,
        category: category ?? this.category,
        total: total ?? this.total,
        count: count ?? this.count,
      );
  ExpenseMonthlyCategoryData copyWithCompanion(
      ExpenseMonthlyCategoryCompanion data) {
    return ExpenseMonthlyCategoryData(
      month: data.month.present ? data.month.value : this.month,
      category: data.category.present ? data.category.value : this.category,
      total: data.total.present ? data.total.value : this.total,
      count: data.count.present ? data.count.value : this.count,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseMonthlyCategoryData(')
          ..write('month: $month, ')
          ..write('category: $category, ')
          ..write('total: $total, ')
          ..write('count: $count')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(month, category, total, count);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseMonthlyCategoryData &&
          other.month == this.month &&
          other.category == this.category &&
          other.total == this.total &&
          other.count == this.count);
}

class ExpenseMonthlyCategoryCompanion
    extends UpdateCompanion<ExpenseMonthlyCategoryData> {
  final Value<String> month;
  final Value<String> category;
  final Value<double> total;
  final Value<int> count;
  final Value<int> rowid;
  const ExpenseMonthlyCategoryCompanion({
    this.month = const Value.absent(),
    this.category = const Value.absent(),
    this.total = const Value.absent(),
    this.count = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpenseMonthlyCategoryCompanion.insert({
    required String month,
    required String category,
    this.total = const Value.absent(),
    this.count = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : month = Value(month),
        category = Value(category);
  static Insertable<ExpenseMonthlyCategoryData> custom({
    Expression<String>? month,
    Expression<String>? category,
    Expression<double>? total,
    Expression<int>? count,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (month != null) 'month': month,
      if (category != null) 'category': category,
      if (total != null) 'total': total,
      if (count != null) 'count': count,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpenseMonthlyCategoryCompanion copyWith(
      {Value<String>? month,
      Value<String>? category,
      Value<double>? total,
      Value<int>? count,
      Value<int>? rowid}) {
    return ExpenseMonthlyCategoryCompanion(
      month: month ?? this.month,
      category: category ?? this.category,
      total: total ?? this.total,
      count: count ?? this.count,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (month.present) {
      map['month'] = Variable<String>(month.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (total.present) {
      map['total'] = Variable<double>(total.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseMonthlyCategoryCompanion(')
          ..write('month: $month, ')
          ..write('category: $category, ')
          ..write('total: $total, ')
          ..write('count: $count, ')
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

class $SavedSearchesTable extends SavedSearches
    with TableInfo<$SavedSearchesTable, SavedSearche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedSearchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
      'query', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responseTypeMeta =
      const VerificationMeta('responseType');
  @override
  late final GeneratedColumn<String> responseType = GeneratedColumn<String>(
      'response_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responseJsonMeta =
      const VerificationMeta('responseJson');
  @override
  late final GeneratedColumn<String> responseJson = GeneratedColumn<String>(
      'response_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
      'model', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _providerMeta =
      const VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
      'provider', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
      'mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _savedAtMeta =
      const VerificationMeta('savedAt');
  @override
  late final GeneratedColumn<String> savedAt = GeneratedColumn<String>(
      'saved_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
      'pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("pinned" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        kind,
        query,
        title,
        responseType,
        responseJson,
        model,
        provider,
        mode,
        savedAt,
        updatedAt,
        pinned,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_searches';
  @override
  VerificationContext validateIntegrity(Insertable<SavedSearche> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('query')) {
      context.handle(
          _queryMeta, query.isAcceptableOrUnknown(data['query']!, _queryMeta));
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('response_type')) {
      context.handle(
          _responseTypeMeta,
          responseType.isAcceptableOrUnknown(
              data['response_type']!, _responseTypeMeta));
    } else if (isInserting) {
      context.missing(_responseTypeMeta);
    }
    if (data.containsKey('response_json')) {
      context.handle(
          _responseJsonMeta,
          responseJson.isAcceptableOrUnknown(
              data['response_json']!, _responseJsonMeta));
    } else if (isInserting) {
      context.missing(_responseJsonMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
          _modelMeta, model.isAcceptableOrUnknown(data['model']!, _modelMeta));
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta,
          provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    }
    if (data.containsKey('mode')) {
      context.handle(
          _modeMeta, mode.isAcceptableOrUnknown(data['mode']!, _modeMeta));
    }
    if (data.containsKey('saved_at')) {
      context.handle(_savedAtMeta,
          savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta));
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('pinned')) {
      context.handle(_pinnedMeta,
          pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedSearche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedSearche(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      query: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}query'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      responseType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}response_type'])!,
      responseJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}response_json'])!,
      model: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}model'])!,
      provider: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}provider'])!,
      mode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mode'])!,
      savedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}saved_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at'])!,
      pinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}pinned'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $SavedSearchesTable createAlias(String alias) {
    return $SavedSearchesTable(attachedDatabase, alias);
  }
}

class SavedSearche extends DataClass implements Insertable<SavedSearche> {
  final String id;

  /// 'url' for URL-summarize entries, 'query' for text search entries.
  final String kind;

  /// The original input text (URL or query).
  final String query;

  /// Display title derived at save time (URL hostname or first 80 chars).
  final String title;

  /// Discriminator for [responseJson]: 'summarizer' | 'grounded' | 'tavily'.
  final String responseType;

  /// Full serialized response DTO. Kept opaque at the DB layer so result
  /// shape evolution doesn't require migrations.
  final String responseJson;
  final String model;
  final String provider;
  final String mode;

  /// ISO-8601 UTC timestamp.
  final String savedAt;

  /// ISO-8601 UTC timestamp; bumped whenever a follow-up message is appended
  /// so the History list can sort by activity.
  final String updatedAt;

  /// Reserved for future filter / cleanup logic. Defaults to true on save.
  final bool pinned;

  /// Soft-delete tombstone — set when the user deletes locally; the row is
  /// hard-deleted only after the remote DELETE is acknowledged. Lets sync
  /// be eventual-consistent without losing remote rows on transient errors.
  final String? deletedAt;
  const SavedSearche(
      {required this.id,
      required this.kind,
      required this.query,
      required this.title,
      required this.responseType,
      required this.responseJson,
      required this.model,
      required this.provider,
      required this.mode,
      required this.savedAt,
      required this.updatedAt,
      required this.pinned,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['query'] = Variable<String>(query);
    map['title'] = Variable<String>(title);
    map['response_type'] = Variable<String>(responseType);
    map['response_json'] = Variable<String>(responseJson);
    map['model'] = Variable<String>(model);
    map['provider'] = Variable<String>(provider);
    map['mode'] = Variable<String>(mode);
    map['saved_at'] = Variable<String>(savedAt);
    map['updated_at'] = Variable<String>(updatedAt);
    map['pinned'] = Variable<bool>(pinned);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  SavedSearchesCompanion toCompanion(bool nullToAbsent) {
    return SavedSearchesCompanion(
      id: Value(id),
      kind: Value(kind),
      query: Value(query),
      title: Value(title),
      responseType: Value(responseType),
      responseJson: Value(responseJson),
      model: Value(model),
      provider: Value(provider),
      mode: Value(mode),
      savedAt: Value(savedAt),
      updatedAt: Value(updatedAt),
      pinned: Value(pinned),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory SavedSearche.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedSearche(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      query: serializer.fromJson<String>(json['query']),
      title: serializer.fromJson<String>(json['title']),
      responseType: serializer.fromJson<String>(json['responseType']),
      responseJson: serializer.fromJson<String>(json['responseJson']),
      model: serializer.fromJson<String>(json['model']),
      provider: serializer.fromJson<String>(json['provider']),
      mode: serializer.fromJson<String>(json['mode']),
      savedAt: serializer.fromJson<String>(json['savedAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'query': serializer.toJson<String>(query),
      'title': serializer.toJson<String>(title),
      'responseType': serializer.toJson<String>(responseType),
      'responseJson': serializer.toJson<String>(responseJson),
      'model': serializer.toJson<String>(model),
      'provider': serializer.toJson<String>(provider),
      'mode': serializer.toJson<String>(mode),
      'savedAt': serializer.toJson<String>(savedAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'pinned': serializer.toJson<bool>(pinned),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  SavedSearche copyWith(
          {String? id,
          String? kind,
          String? query,
          String? title,
          String? responseType,
          String? responseJson,
          String? model,
          String? provider,
          String? mode,
          String? savedAt,
          String? updatedAt,
          bool? pinned,
          Value<String?> deletedAt = const Value.absent()}) =>
      SavedSearche(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        query: query ?? this.query,
        title: title ?? this.title,
        responseType: responseType ?? this.responseType,
        responseJson: responseJson ?? this.responseJson,
        model: model ?? this.model,
        provider: provider ?? this.provider,
        mode: mode ?? this.mode,
        savedAt: savedAt ?? this.savedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pinned: pinned ?? this.pinned,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  SavedSearche copyWithCompanion(SavedSearchesCompanion data) {
    return SavedSearche(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      query: data.query.present ? data.query.value : this.query,
      title: data.title.present ? data.title.value : this.title,
      responseType: data.responseType.present
          ? data.responseType.value
          : this.responseType,
      responseJson: data.responseJson.present
          ? data.responseJson.value
          : this.responseJson,
      model: data.model.present ? data.model.value : this.model,
      provider: data.provider.present ? data.provider.value : this.provider,
      mode: data.mode.present ? data.mode.value : this.mode,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedSearche(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('query: $query, ')
          ..write('title: $title, ')
          ..write('responseType: $responseType, ')
          ..write('responseJson: $responseJson, ')
          ..write('model: $model, ')
          ..write('provider: $provider, ')
          ..write('mode: $mode, ')
          ..write('savedAt: $savedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pinned: $pinned, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      kind,
      query,
      title,
      responseType,
      responseJson,
      model,
      provider,
      mode,
      savedAt,
      updatedAt,
      pinned,
      deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedSearche &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.query == this.query &&
          other.title == this.title &&
          other.responseType == this.responseType &&
          other.responseJson == this.responseJson &&
          other.model == this.model &&
          other.provider == this.provider &&
          other.mode == this.mode &&
          other.savedAt == this.savedAt &&
          other.updatedAt == this.updatedAt &&
          other.pinned == this.pinned &&
          other.deletedAt == this.deletedAt);
}

class SavedSearchesCompanion extends UpdateCompanion<SavedSearche> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> query;
  final Value<String> title;
  final Value<String> responseType;
  final Value<String> responseJson;
  final Value<String> model;
  final Value<String> provider;
  final Value<String> mode;
  final Value<String> savedAt;
  final Value<String> updatedAt;
  final Value<bool> pinned;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const SavedSearchesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.query = const Value.absent(),
    this.title = const Value.absent(),
    this.responseType = const Value.absent(),
    this.responseJson = const Value.absent(),
    this.model = const Value.absent(),
    this.provider = const Value.absent(),
    this.mode = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.pinned = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedSearchesCompanion.insert({
    required String id,
    required String kind,
    required String query,
    required String title,
    required String responseType,
    required String responseJson,
    this.model = const Value.absent(),
    this.provider = const Value.absent(),
    this.mode = const Value.absent(),
    required String savedAt,
    required String updatedAt,
    this.pinned = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        kind = Value(kind),
        query = Value(query),
        title = Value(title),
        responseType = Value(responseType),
        responseJson = Value(responseJson),
        savedAt = Value(savedAt),
        updatedAt = Value(updatedAt);
  static Insertable<SavedSearche> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? query,
    Expression<String>? title,
    Expression<String>? responseType,
    Expression<String>? responseJson,
    Expression<String>? model,
    Expression<String>? provider,
    Expression<String>? mode,
    Expression<String>? savedAt,
    Expression<String>? updatedAt,
    Expression<bool>? pinned,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (query != null) 'query': query,
      if (title != null) 'title': title,
      if (responseType != null) 'response_type': responseType,
      if (responseJson != null) 'response_json': responseJson,
      if (model != null) 'model': model,
      if (provider != null) 'provider': provider,
      if (mode != null) 'mode': mode,
      if (savedAt != null) 'saved_at': savedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (pinned != null) 'pinned': pinned,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedSearchesCompanion copyWith(
      {Value<String>? id,
      Value<String>? kind,
      Value<String>? query,
      Value<String>? title,
      Value<String>? responseType,
      Value<String>? responseJson,
      Value<String>? model,
      Value<String>? provider,
      Value<String>? mode,
      Value<String>? savedAt,
      Value<String>? updatedAt,
      Value<bool>? pinned,
      Value<String?>? deletedAt,
      Value<int>? rowid}) {
    return SavedSearchesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      query: query ?? this.query,
      title: title ?? this.title,
      responseType: responseType ?? this.responseType,
      responseJson: responseJson ?? this.responseJson,
      model: model ?? this.model,
      provider: provider ?? this.provider,
      mode: mode ?? this.mode,
      savedAt: savedAt ?? this.savedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (responseType.present) {
      map['response_type'] = Variable<String>(responseType.value);
    }
    if (responseJson.present) {
      map['response_json'] = Variable<String>(responseJson.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<String>(savedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedSearchesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('query: $query, ')
          ..write('title: $title, ')
          ..write('responseType: $responseType, ')
          ..write('responseJson: $responseJson, ')
          ..write('model: $model, ')
          ..write('provider: $provider, ')
          ..write('mode: $mode, ')
          ..write('savedAt: $savedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pinned: $pinned, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedSearchChatMessagesTable extends SavedSearchChatMessages
    with TableInfo<$SavedSearchChatMessagesTable, SavedSearchChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedSearchChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _searchIdMeta =
      const VerificationMeta('searchId');
  @override
  late final GeneratedColumn<String> searchId = GeneratedColumn<String>(
      'search_id', aliasedName, false,
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
      [id, searchId, role, msgText, model, sourcesJson, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_search_chat_messages';
  @override
  VerificationContext validateIntegrity(
      Insertable<SavedSearchChatMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('search_id')) {
      context.handle(_searchIdMeta,
          searchId.isAcceptableOrUnknown(data['search_id']!, _searchIdMeta));
    } else if (isInserting) {
      context.missing(_searchIdMeta);
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
  SavedSearchChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedSearchChatMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      searchId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}search_id'])!,
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
  $SavedSearchChatMessagesTable createAlias(String alias) {
    return $SavedSearchChatMessagesTable(attachedDatabase, alias);
  }
}

class SavedSearchChatMessage extends DataClass
    implements Insertable<SavedSearchChatMessage> {
  final String id;
  final String searchId;
  final String role;
  final String msgText;
  final String model;
  final String sourcesJson;
  final String createdAt;
  const SavedSearchChatMessage(
      {required this.id,
      required this.searchId,
      required this.role,
      required this.msgText,
      required this.model,
      required this.sourcesJson,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['search_id'] = Variable<String>(searchId);
    map['role'] = Variable<String>(role);
    map['msg_text'] = Variable<String>(msgText);
    map['model'] = Variable<String>(model);
    map['sources_json'] = Variable<String>(sourcesJson);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  SavedSearchChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return SavedSearchChatMessagesCompanion(
      id: Value(id),
      searchId: Value(searchId),
      role: Value(role),
      msgText: Value(msgText),
      model: Value(model),
      sourcesJson: Value(sourcesJson),
      createdAt: Value(createdAt),
    );
  }

  factory SavedSearchChatMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedSearchChatMessage(
      id: serializer.fromJson<String>(json['id']),
      searchId: serializer.fromJson<String>(json['searchId']),
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
      'searchId': serializer.toJson<String>(searchId),
      'role': serializer.toJson<String>(role),
      'msgText': serializer.toJson<String>(msgText),
      'model': serializer.toJson<String>(model),
      'sourcesJson': serializer.toJson<String>(sourcesJson),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  SavedSearchChatMessage copyWith(
          {String? id,
          String? searchId,
          String? role,
          String? msgText,
          String? model,
          String? sourcesJson,
          String? createdAt}) =>
      SavedSearchChatMessage(
        id: id ?? this.id,
        searchId: searchId ?? this.searchId,
        role: role ?? this.role,
        msgText: msgText ?? this.msgText,
        model: model ?? this.model,
        sourcesJson: sourcesJson ?? this.sourcesJson,
        createdAt: createdAt ?? this.createdAt,
      );
  SavedSearchChatMessage copyWithCompanion(
      SavedSearchChatMessagesCompanion data) {
    return SavedSearchChatMessage(
      id: data.id.present ? data.id.value : this.id,
      searchId: data.searchId.present ? data.searchId.value : this.searchId,
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
    return (StringBuffer('SavedSearchChatMessage(')
          ..write('id: $id, ')
          ..write('searchId: $searchId, ')
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
      Object.hash(id, searchId, role, msgText, model, sourcesJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedSearchChatMessage &&
          other.id == this.id &&
          other.searchId == this.searchId &&
          other.role == this.role &&
          other.msgText == this.msgText &&
          other.model == this.model &&
          other.sourcesJson == this.sourcesJson &&
          other.createdAt == this.createdAt);
}

class SavedSearchChatMessagesCompanion
    extends UpdateCompanion<SavedSearchChatMessage> {
  final Value<String> id;
  final Value<String> searchId;
  final Value<String> role;
  final Value<String> msgText;
  final Value<String> model;
  final Value<String> sourcesJson;
  final Value<String> createdAt;
  final Value<int> rowid;
  const SavedSearchChatMessagesCompanion({
    this.id = const Value.absent(),
    this.searchId = const Value.absent(),
    this.role = const Value.absent(),
    this.msgText = const Value.absent(),
    this.model = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedSearchChatMessagesCompanion.insert({
    required String id,
    required String searchId,
    required String role,
    required String msgText,
    this.model = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    required String createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        searchId = Value(searchId),
        role = Value(role),
        msgText = Value(msgText),
        createdAt = Value(createdAt);
  static Insertable<SavedSearchChatMessage> custom({
    Expression<String>? id,
    Expression<String>? searchId,
    Expression<String>? role,
    Expression<String>? msgText,
    Expression<String>? model,
    Expression<String>? sourcesJson,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (searchId != null) 'search_id': searchId,
      if (role != null) 'role': role,
      if (msgText != null) 'msg_text': msgText,
      if (model != null) 'model': model,
      if (sourcesJson != null) 'sources_json': sourcesJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedSearchChatMessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? searchId,
      Value<String>? role,
      Value<String>? msgText,
      Value<String>? model,
      Value<String>? sourcesJson,
      Value<String>? createdAt,
      Value<int>? rowid}) {
    return SavedSearchChatMessagesCompanion(
      id: id ?? this.id,
      searchId: searchId ?? this.searchId,
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
    if (searchId.present) {
      map['search_id'] = Variable<String>(searchId.value);
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
    return (StringBuffer('SavedSearchChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('searchId: $searchId, ')
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

class $SavedSearchChatSummariesTable extends SavedSearchChatSummaries
    with TableInfo<$SavedSearchChatSummariesTable, SavedSearchChatSummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedSearchChatSummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _searchIdMeta =
      const VerificationMeta('searchId');
  @override
  late final GeneratedColumn<String> searchId = GeneratedColumn<String>(
      'search_id', aliasedName, false,
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
      [searchId, summaryText, pairsCovered, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_search_chat_summaries';
  @override
  VerificationContext validateIntegrity(
      Insertable<SavedSearchChatSummary> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('search_id')) {
      context.handle(_searchIdMeta,
          searchId.isAcceptableOrUnknown(data['search_id']!, _searchIdMeta));
    } else if (isInserting) {
      context.missing(_searchIdMeta);
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
  Set<GeneratedColumn> get $primaryKey => {searchId};
  @override
  SavedSearchChatSummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedSearchChatSummary(
      searchId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}search_id'])!,
      summaryText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary_text'])!,
      pairsCovered: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}pairs_covered'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SavedSearchChatSummariesTable createAlias(String alias) {
    return $SavedSearchChatSummariesTable(attachedDatabase, alias);
  }
}

class SavedSearchChatSummary extends DataClass
    implements Insertable<SavedSearchChatSummary> {
  final String searchId;
  final String summaryText;
  final int pairsCovered;
  final String updatedAt;
  const SavedSearchChatSummary(
      {required this.searchId,
      required this.summaryText,
      required this.pairsCovered,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['search_id'] = Variable<String>(searchId);
    map['summary_text'] = Variable<String>(summaryText);
    map['pairs_covered'] = Variable<int>(pairsCovered);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  SavedSearchChatSummariesCompanion toCompanion(bool nullToAbsent) {
    return SavedSearchChatSummariesCompanion(
      searchId: Value(searchId),
      summaryText: Value(summaryText),
      pairsCovered: Value(pairsCovered),
      updatedAt: Value(updatedAt),
    );
  }

  factory SavedSearchChatSummary.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedSearchChatSummary(
      searchId: serializer.fromJson<String>(json['searchId']),
      summaryText: serializer.fromJson<String>(json['summaryText']),
      pairsCovered: serializer.fromJson<int>(json['pairsCovered']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'searchId': serializer.toJson<String>(searchId),
      'summaryText': serializer.toJson<String>(summaryText),
      'pairsCovered': serializer.toJson<int>(pairsCovered),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  SavedSearchChatSummary copyWith(
          {String? searchId,
          String? summaryText,
          int? pairsCovered,
          String? updatedAt}) =>
      SavedSearchChatSummary(
        searchId: searchId ?? this.searchId,
        summaryText: summaryText ?? this.summaryText,
        pairsCovered: pairsCovered ?? this.pairsCovered,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SavedSearchChatSummary copyWithCompanion(
      SavedSearchChatSummariesCompanion data) {
    return SavedSearchChatSummary(
      searchId: data.searchId.present ? data.searchId.value : this.searchId,
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
    return (StringBuffer('SavedSearchChatSummary(')
          ..write('searchId: $searchId, ')
          ..write('summaryText: $summaryText, ')
          ..write('pairsCovered: $pairsCovered, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(searchId, summaryText, pairsCovered, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedSearchChatSummary &&
          other.searchId == this.searchId &&
          other.summaryText == this.summaryText &&
          other.pairsCovered == this.pairsCovered &&
          other.updatedAt == this.updatedAt);
}

class SavedSearchChatSummariesCompanion
    extends UpdateCompanion<SavedSearchChatSummary> {
  final Value<String> searchId;
  final Value<String> summaryText;
  final Value<int> pairsCovered;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const SavedSearchChatSummariesCompanion({
    this.searchId = const Value.absent(),
    this.summaryText = const Value.absent(),
    this.pairsCovered = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedSearchChatSummariesCompanion.insert({
    required String searchId,
    required String summaryText,
    required int pairsCovered,
    required String updatedAt,
    this.rowid = const Value.absent(),
  })  : searchId = Value(searchId),
        summaryText = Value(summaryText),
        pairsCovered = Value(pairsCovered),
        updatedAt = Value(updatedAt);
  static Insertable<SavedSearchChatSummary> custom({
    Expression<String>? searchId,
    Expression<String>? summaryText,
    Expression<int>? pairsCovered,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (searchId != null) 'search_id': searchId,
      if (summaryText != null) 'summary_text': summaryText,
      if (pairsCovered != null) 'pairs_covered': pairsCovered,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedSearchChatSummariesCompanion copyWith(
      {Value<String>? searchId,
      Value<String>? summaryText,
      Value<int>? pairsCovered,
      Value<String>? updatedAt,
      Value<int>? rowid}) {
    return SavedSearchChatSummariesCompanion(
      searchId: searchId ?? this.searchId,
      summaryText: summaryText ?? this.summaryText,
      pairsCovered: pairsCovered ?? this.pairsCovered,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (searchId.present) {
      map['search_id'] = Variable<String>(searchId.value);
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
    return (StringBuffer('SavedSearchChatSummariesCompanion(')
          ..write('searchId: $searchId, ')
          ..write('summaryText: $summaryText, ')
          ..write('pairsCovered: $pairsCovered, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchProductsTable extends WatchProducts
    with TableInfo<$WatchProductsTable, WatchProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchProductsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
      'url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _canonicalUrlMeta =
      const VerificationMeta('canonicalUrl');
  @override
  late final GeneratedColumn<String> canonicalUrl = GeneratedColumn<String>(
      'canonical_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _storeMeta = const VerificationMeta('store');
  @override
  late final GeneratedColumn<String> store = GeneratedColumn<String>(
      'store', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _currentPriceMeta =
      const VerificationMeta('currentPrice');
  @override
  late final GeneratedColumn<double> currentPrice = GeneratedColumn<double>(
      'current_price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _basePriceMeta =
      const VerificationMeta('basePrice');
  @override
  late final GeneratedColumn<double> basePrice = GeneratedColumn<double>(
      'base_price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _lastCheckedMeta =
      const VerificationMeta('lastChecked');
  @override
  late final GeneratedColumn<String> lastChecked = GeneratedColumn<String>(
      'last_checked', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _targetPriceMeta =
      const VerificationMeta('targetPrice');
  @override
  late final GeneratedColumn<double> targetPrice = GeneratedColumn<double>(
      'target_price', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _notifyOnDecreaseMeta =
      const VerificationMeta('notifyOnDecrease');
  @override
  late final GeneratedColumn<bool> notifyOnDecrease = GeneratedColumn<bool>(
      'notify_on_decrease', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("notify_on_decrease" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _notifyOnIncreaseMeta =
      const VerificationMeta('notifyOnIncrease');
  @override
  late final GeneratedColumn<bool> notifyOnIncrease = GeneratedColumn<bool>(
      'notify_on_increase', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("notify_on_increase" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _notifyOnTargetMeta =
      const VerificationMeta('notifyOnTarget');
  @override
  late final GeneratedColumn<bool> notifyOnTarget = GeneratedColumn<bool>(
      'notify_on_target', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("notify_on_target" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _checkIntervalMinutesMeta =
      const VerificationMeta('checkIntervalMinutes');
  @override
  late final GeneratedColumn<int> checkIntervalMinutes = GeneratedColumn<int>(
      'check_interval_minutes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(60));
  static const VerificationMeta _isPausedMeta =
      const VerificationMeta('isPaused');
  @override
  late final GeneratedColumn<bool> isPaused = GeneratedColumn<bool>(
      'is_paused', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_paused" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isPinnedMeta =
      const VerificationMeta('isPinned');
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
      'is_pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_pinned" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _manuallyPausedMeta =
      const VerificationMeta('manuallyPaused');
  @override
  late final GeneratedColumn<bool> manuallyPaused = GeneratedColumn<bool>(
      'manually_paused', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("manually_paused" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _pausedAtMeta =
      const VerificationMeta('pausedAt');
  @override
  late final GeneratedColumn<String> pausedAt = GeneratedColumn<String>(
      'paused_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pinnedAtMeta =
      const VerificationMeta('pinnedAt');
  @override
  late final GeneratedColumn<String> pinnedAt = GeneratedColumn<String>(
      'pinned_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pendingPriceMeta =
      const VerificationMeta('pendingPrice');
  @override
  late final GeneratedColumn<double> pendingPrice = GeneratedColumn<double>(
      'pending_price', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _pendingPriceAtMeta =
      const VerificationMeta('pendingPriceAt');
  @override
  late final GeneratedColumn<String> pendingPriceAt = GeneratedColumn<String>(
      'pending_price_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _consecutiveFailuresMeta =
      const VerificationMeta('consecutiveFailures');
  @override
  late final GeneratedColumn<int> consecutiveFailures = GeneratedColumn<int>(
      'consecutive_failures', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastCheckErrorMeta =
      const VerificationMeta('lastCheckError');
  @override
  late final GeneratedColumn<String> lastCheckError = GeneratedColumn<String>(
      'last_check_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _availabilityMeta =
      const VerificationMeta('availability');
  @override
  late final GeneratedColumn<String> availability = GeneratedColumn<String>(
      'availability', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _currencyCodeMeta =
      const VerificationMeta('currencyCode');
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
      'currency_code', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('INR'));
  static const VerificationMeta _lastSourceMeta =
      const VerificationMeta('lastSource');
  @override
  late final GeneratedColumn<String> lastSource = GeneratedColumn<String>(
      'last_source', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _lastScoreMeta =
      const VerificationMeta('lastScore');
  @override
  late final GeneratedColumn<int> lastScore = GeneratedColumn<int>(
      'last_score', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _identityKeyMeta =
      const VerificationMeta('identityKey');
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
      'identity_key', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
      'rev', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        url,
        canonicalUrl,
        store,
        productId,
        imageUrl,
        currentPrice,
        basePrice,
        lastChecked,
        createdAt,
        targetPrice,
        notifyOnDecrease,
        notifyOnIncrease,
        notifyOnTarget,
        checkIntervalMinutes,
        isPaused,
        isPinned,
        manuallyPaused,
        pausedAt,
        pinnedAt,
        pendingPrice,
        pendingPriceAt,
        consecutiveFailures,
        lastCheckError,
        availability,
        currencyCode,
        lastSource,
        lastScore,
        identityKey,
        updatedAt,
        rev
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_products';
  @override
  VerificationContext validateIntegrity(Insertable<WatchProduct> instance,
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
    if (data.containsKey('url')) {
      context.handle(
          _urlMeta, url.isAcceptableOrUnknown(data['url']!, _urlMeta));
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('canonical_url')) {
      context.handle(
          _canonicalUrlMeta,
          canonicalUrl.isAcceptableOrUnknown(
              data['canonical_url']!, _canonicalUrlMeta));
    } else if (isInserting) {
      context.missing(_canonicalUrlMeta);
    }
    if (data.containsKey('store')) {
      context.handle(
          _storeMeta, store.isAcceptableOrUnknown(data['store']!, _storeMeta));
    } else if (isInserting) {
      context.missing(_storeMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    if (data.containsKey('current_price')) {
      context.handle(
          _currentPriceMeta,
          currentPrice.isAcceptableOrUnknown(
              data['current_price']!, _currentPriceMeta));
    } else if (isInserting) {
      context.missing(_currentPriceMeta);
    }
    if (data.containsKey('base_price')) {
      context.handle(_basePriceMeta,
          basePrice.isAcceptableOrUnknown(data['base_price']!, _basePriceMeta));
    } else if (isInserting) {
      context.missing(_basePriceMeta);
    }
    if (data.containsKey('last_checked')) {
      context.handle(
          _lastCheckedMeta,
          lastChecked.isAcceptableOrUnknown(
              data['last_checked']!, _lastCheckedMeta));
    } else if (isInserting) {
      context.missing(_lastCheckedMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('target_price')) {
      context.handle(
          _targetPriceMeta,
          targetPrice.isAcceptableOrUnknown(
              data['target_price']!, _targetPriceMeta));
    }
    if (data.containsKey('notify_on_decrease')) {
      context.handle(
          _notifyOnDecreaseMeta,
          notifyOnDecrease.isAcceptableOrUnknown(
              data['notify_on_decrease']!, _notifyOnDecreaseMeta));
    }
    if (data.containsKey('notify_on_increase')) {
      context.handle(
          _notifyOnIncreaseMeta,
          notifyOnIncrease.isAcceptableOrUnknown(
              data['notify_on_increase']!, _notifyOnIncreaseMeta));
    }
    if (data.containsKey('notify_on_target')) {
      context.handle(
          _notifyOnTargetMeta,
          notifyOnTarget.isAcceptableOrUnknown(
              data['notify_on_target']!, _notifyOnTargetMeta));
    }
    if (data.containsKey('check_interval_minutes')) {
      context.handle(
          _checkIntervalMinutesMeta,
          checkIntervalMinutes.isAcceptableOrUnknown(
              data['check_interval_minutes']!, _checkIntervalMinutesMeta));
    }
    if (data.containsKey('is_paused')) {
      context.handle(_isPausedMeta,
          isPaused.isAcceptableOrUnknown(data['is_paused']!, _isPausedMeta));
    }
    if (data.containsKey('is_pinned')) {
      context.handle(_isPinnedMeta,
          isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta));
    }
    if (data.containsKey('manually_paused')) {
      context.handle(
          _manuallyPausedMeta,
          manuallyPaused.isAcceptableOrUnknown(
              data['manually_paused']!, _manuallyPausedMeta));
    }
    if (data.containsKey('paused_at')) {
      context.handle(_pausedAtMeta,
          pausedAt.isAcceptableOrUnknown(data['paused_at']!, _pausedAtMeta));
    }
    if (data.containsKey('pinned_at')) {
      context.handle(_pinnedAtMeta,
          pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta));
    }
    if (data.containsKey('pending_price')) {
      context.handle(
          _pendingPriceMeta,
          pendingPrice.isAcceptableOrUnknown(
              data['pending_price']!, _pendingPriceMeta));
    }
    if (data.containsKey('pending_price_at')) {
      context.handle(
          _pendingPriceAtMeta,
          pendingPriceAt.isAcceptableOrUnknown(
              data['pending_price_at']!, _pendingPriceAtMeta));
    }
    if (data.containsKey('consecutive_failures')) {
      context.handle(
          _consecutiveFailuresMeta,
          consecutiveFailures.isAcceptableOrUnknown(
              data['consecutive_failures']!, _consecutiveFailuresMeta));
    }
    if (data.containsKey('last_check_error')) {
      context.handle(
          _lastCheckErrorMeta,
          lastCheckError.isAcceptableOrUnknown(
              data['last_check_error']!, _lastCheckErrorMeta));
    }
    if (data.containsKey('availability')) {
      context.handle(
          _availabilityMeta,
          availability.isAcceptableOrUnknown(
              data['availability']!, _availabilityMeta));
    }
    if (data.containsKey('currency_code')) {
      context.handle(
          _currencyCodeMeta,
          currencyCode.isAcceptableOrUnknown(
              data['currency_code']!, _currencyCodeMeta));
    }
    if (data.containsKey('last_source')) {
      context.handle(
          _lastSourceMeta,
          lastSource.isAcceptableOrUnknown(
              data['last_source']!, _lastSourceMeta));
    }
    if (data.containsKey('last_score')) {
      context.handle(_lastScoreMeta,
          lastScore.isAcceptableOrUnknown(data['last_score']!, _lastScoreMeta));
    }
    if (data.containsKey('identity_key')) {
      context.handle(
          _identityKeyMeta,
          identityKey.isAcceptableOrUnknown(
              data['identity_key']!, _identityKeyMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('rev')) {
      context.handle(
          _revMeta, rev.isAcceptableOrUnknown(data['rev']!, _revMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {canonicalUrl},
      ];
  @override
  WatchProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchProduct(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      url: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}url'])!,
      canonicalUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}canonical_url'])!,
      store: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}store'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id']),
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url'])!,
      currentPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}current_price'])!,
      basePrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}base_price'])!,
      lastChecked: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_checked'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at'])!,
      targetPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}target_price']),
      notifyOnDecrease: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}notify_on_decrease'])!,
      notifyOnIncrease: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}notify_on_increase'])!,
      notifyOnTarget: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}notify_on_target'])!,
      checkIntervalMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}check_interval_minutes'])!,
      isPaused: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_paused'])!,
      isPinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_pinned'])!,
      manuallyPaused: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}manually_paused'])!,
      pausedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}paused_at']),
      pinnedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pinned_at']),
      pendingPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}pending_price']),
      pendingPriceAt: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}pending_price_at']),
      consecutiveFailures: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}consecutive_failures'])!,
      lastCheckError: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_check_error']),
      availability: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}availability']),
      currencyCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency_code'])!,
      lastSource: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_source'])!,
      lastScore: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_score'])!,
      identityKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}identity_key'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at']),
      rev: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rev'])!,
    );
  }

  @override
  $WatchProductsTable createAlias(String alias) {
    return $WatchProductsTable(attachedDatabase, alias);
  }
}

class WatchProduct extends DataClass implements Insertable<WatchProduct> {
  final String id;
  final String name;
  final String url;
  final String canonicalUrl;
  final String store;
  final String? productId;
  final String imageUrl;
  final double currentPrice;
  final double basePrice;
  final String lastChecked;
  final String createdAt;
  final double? targetPrice;
  final bool notifyOnDecrease;
  final bool notifyOnIncrease;
  final bool notifyOnTarget;
  final int checkIntervalMinutes;
  final bool isPaused;
  final bool isPinned;
  final bool manuallyPaused;
  final String? pausedAt;
  final String? pinnedAt;
  final double? pendingPrice;
  final String? pendingPriceAt;
  final int consecutiveFailures;
  final String? lastCheckError;
  final String? availability;
  final String currencyCode;
  final String lastSource;
  final int lastScore;

  /// `store:productId` (or `store:url:…` until the SKU is known). Same
  /// SKU on two phones merges on this key, not the local UUID.
  final String identityKey;

  /// ISO-8601 UTC of the last local write. Last-write-wins when a cloud
  /// catalog exists. NULL on rows created before the v12 migration.
  final String? updatedAt;

  /// Bumped on every local mutation so a later sync can collapse upserts.
  final int rev;
  const WatchProduct(
      {required this.id,
      required this.name,
      required this.url,
      required this.canonicalUrl,
      required this.store,
      this.productId,
      required this.imageUrl,
      required this.currentPrice,
      required this.basePrice,
      required this.lastChecked,
      required this.createdAt,
      this.targetPrice,
      required this.notifyOnDecrease,
      required this.notifyOnIncrease,
      required this.notifyOnTarget,
      required this.checkIntervalMinutes,
      required this.isPaused,
      required this.isPinned,
      required this.manuallyPaused,
      this.pausedAt,
      this.pinnedAt,
      this.pendingPrice,
      this.pendingPriceAt,
      required this.consecutiveFailures,
      this.lastCheckError,
      this.availability,
      required this.currencyCode,
      required this.lastSource,
      required this.lastScore,
      required this.identityKey,
      this.updatedAt,
      required this.rev});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['url'] = Variable<String>(url);
    map['canonical_url'] = Variable<String>(canonicalUrl);
    map['store'] = Variable<String>(store);
    if (!nullToAbsent || productId != null) {
      map['product_id'] = Variable<String>(productId);
    }
    map['image_url'] = Variable<String>(imageUrl);
    map['current_price'] = Variable<double>(currentPrice);
    map['base_price'] = Variable<double>(basePrice);
    map['last_checked'] = Variable<String>(lastChecked);
    map['created_at'] = Variable<String>(createdAt);
    if (!nullToAbsent || targetPrice != null) {
      map['target_price'] = Variable<double>(targetPrice);
    }
    map['notify_on_decrease'] = Variable<bool>(notifyOnDecrease);
    map['notify_on_increase'] = Variable<bool>(notifyOnIncrease);
    map['notify_on_target'] = Variable<bool>(notifyOnTarget);
    map['check_interval_minutes'] = Variable<int>(checkIntervalMinutes);
    map['is_paused'] = Variable<bool>(isPaused);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['manually_paused'] = Variable<bool>(manuallyPaused);
    if (!nullToAbsent || pausedAt != null) {
      map['paused_at'] = Variable<String>(pausedAt);
    }
    if (!nullToAbsent || pinnedAt != null) {
      map['pinned_at'] = Variable<String>(pinnedAt);
    }
    if (!nullToAbsent || pendingPrice != null) {
      map['pending_price'] = Variable<double>(pendingPrice);
    }
    if (!nullToAbsent || pendingPriceAt != null) {
      map['pending_price_at'] = Variable<String>(pendingPriceAt);
    }
    map['consecutive_failures'] = Variable<int>(consecutiveFailures);
    if (!nullToAbsent || lastCheckError != null) {
      map['last_check_error'] = Variable<String>(lastCheckError);
    }
    if (!nullToAbsent || availability != null) {
      map['availability'] = Variable<String>(availability);
    }
    map['currency_code'] = Variable<String>(currencyCode);
    map['last_source'] = Variable<String>(lastSource);
    map['last_score'] = Variable<int>(lastScore);
    map['identity_key'] = Variable<String>(identityKey);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    map['rev'] = Variable<int>(rev);
    return map;
  }

  WatchProductsCompanion toCompanion(bool nullToAbsent) {
    return WatchProductsCompanion(
      id: Value(id),
      name: Value(name),
      url: Value(url),
      canonicalUrl: Value(canonicalUrl),
      store: Value(store),
      productId: productId == null && nullToAbsent
          ? const Value.absent()
          : Value(productId),
      imageUrl: Value(imageUrl),
      currentPrice: Value(currentPrice),
      basePrice: Value(basePrice),
      lastChecked: Value(lastChecked),
      createdAt: Value(createdAt),
      targetPrice: targetPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(targetPrice),
      notifyOnDecrease: Value(notifyOnDecrease),
      notifyOnIncrease: Value(notifyOnIncrease),
      notifyOnTarget: Value(notifyOnTarget),
      checkIntervalMinutes: Value(checkIntervalMinutes),
      isPaused: Value(isPaused),
      isPinned: Value(isPinned),
      manuallyPaused: Value(manuallyPaused),
      pausedAt: pausedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pausedAt),
      pinnedAt: pinnedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pinnedAt),
      pendingPrice: pendingPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingPrice),
      pendingPriceAt: pendingPriceAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingPriceAt),
      consecutiveFailures: Value(consecutiveFailures),
      lastCheckError: lastCheckError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckError),
      availability: availability == null && nullToAbsent
          ? const Value.absent()
          : Value(availability),
      currencyCode: Value(currencyCode),
      lastSource: Value(lastSource),
      lastScore: Value(lastScore),
      identityKey: Value(identityKey),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      rev: Value(rev),
    );
  }

  factory WatchProduct.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchProduct(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      url: serializer.fromJson<String>(json['url']),
      canonicalUrl: serializer.fromJson<String>(json['canonicalUrl']),
      store: serializer.fromJson<String>(json['store']),
      productId: serializer.fromJson<String?>(json['productId']),
      imageUrl: serializer.fromJson<String>(json['imageUrl']),
      currentPrice: serializer.fromJson<double>(json['currentPrice']),
      basePrice: serializer.fromJson<double>(json['basePrice']),
      lastChecked: serializer.fromJson<String>(json['lastChecked']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      targetPrice: serializer.fromJson<double?>(json['targetPrice']),
      notifyOnDecrease: serializer.fromJson<bool>(json['notifyOnDecrease']),
      notifyOnIncrease: serializer.fromJson<bool>(json['notifyOnIncrease']),
      notifyOnTarget: serializer.fromJson<bool>(json['notifyOnTarget']),
      checkIntervalMinutes:
          serializer.fromJson<int>(json['checkIntervalMinutes']),
      isPaused: serializer.fromJson<bool>(json['isPaused']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      manuallyPaused: serializer.fromJson<bool>(json['manuallyPaused']),
      pausedAt: serializer.fromJson<String?>(json['pausedAt']),
      pinnedAt: serializer.fromJson<String?>(json['pinnedAt']),
      pendingPrice: serializer.fromJson<double?>(json['pendingPrice']),
      pendingPriceAt: serializer.fromJson<String?>(json['pendingPriceAt']),
      consecutiveFailures:
          serializer.fromJson<int>(json['consecutiveFailures']),
      lastCheckError: serializer.fromJson<String?>(json['lastCheckError']),
      availability: serializer.fromJson<String?>(json['availability']),
      currencyCode: serializer.fromJson<String>(json['currencyCode']),
      lastSource: serializer.fromJson<String>(json['lastSource']),
      lastScore: serializer.fromJson<int>(json['lastScore']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
      rev: serializer.fromJson<int>(json['rev']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'url': serializer.toJson<String>(url),
      'canonicalUrl': serializer.toJson<String>(canonicalUrl),
      'store': serializer.toJson<String>(store),
      'productId': serializer.toJson<String?>(productId),
      'imageUrl': serializer.toJson<String>(imageUrl),
      'currentPrice': serializer.toJson<double>(currentPrice),
      'basePrice': serializer.toJson<double>(basePrice),
      'lastChecked': serializer.toJson<String>(lastChecked),
      'createdAt': serializer.toJson<String>(createdAt),
      'targetPrice': serializer.toJson<double?>(targetPrice),
      'notifyOnDecrease': serializer.toJson<bool>(notifyOnDecrease),
      'notifyOnIncrease': serializer.toJson<bool>(notifyOnIncrease),
      'notifyOnTarget': serializer.toJson<bool>(notifyOnTarget),
      'checkIntervalMinutes': serializer.toJson<int>(checkIntervalMinutes),
      'isPaused': serializer.toJson<bool>(isPaused),
      'isPinned': serializer.toJson<bool>(isPinned),
      'manuallyPaused': serializer.toJson<bool>(manuallyPaused),
      'pausedAt': serializer.toJson<String?>(pausedAt),
      'pinnedAt': serializer.toJson<String?>(pinnedAt),
      'pendingPrice': serializer.toJson<double?>(pendingPrice),
      'pendingPriceAt': serializer.toJson<String?>(pendingPriceAt),
      'consecutiveFailures': serializer.toJson<int>(consecutiveFailures),
      'lastCheckError': serializer.toJson<String?>(lastCheckError),
      'availability': serializer.toJson<String?>(availability),
      'currencyCode': serializer.toJson<String>(currencyCode),
      'lastSource': serializer.toJson<String>(lastSource),
      'lastScore': serializer.toJson<int>(lastScore),
      'identityKey': serializer.toJson<String>(identityKey),
      'updatedAt': serializer.toJson<String?>(updatedAt),
      'rev': serializer.toJson<int>(rev),
    };
  }

  WatchProduct copyWith(
          {String? id,
          String? name,
          String? url,
          String? canonicalUrl,
          String? store,
          Value<String?> productId = const Value.absent(),
          String? imageUrl,
          double? currentPrice,
          double? basePrice,
          String? lastChecked,
          String? createdAt,
          Value<double?> targetPrice = const Value.absent(),
          bool? notifyOnDecrease,
          bool? notifyOnIncrease,
          bool? notifyOnTarget,
          int? checkIntervalMinutes,
          bool? isPaused,
          bool? isPinned,
          bool? manuallyPaused,
          Value<String?> pausedAt = const Value.absent(),
          Value<String?> pinnedAt = const Value.absent(),
          Value<double?> pendingPrice = const Value.absent(),
          Value<String?> pendingPriceAt = const Value.absent(),
          int? consecutiveFailures,
          Value<String?> lastCheckError = const Value.absent(),
          Value<String?> availability = const Value.absent(),
          String? currencyCode,
          String? lastSource,
          int? lastScore,
          String? identityKey,
          Value<String?> updatedAt = const Value.absent(),
          int? rev}) =>
      WatchProduct(
        id: id ?? this.id,
        name: name ?? this.name,
        url: url ?? this.url,
        canonicalUrl: canonicalUrl ?? this.canonicalUrl,
        store: store ?? this.store,
        productId: productId.present ? productId.value : this.productId,
        imageUrl: imageUrl ?? this.imageUrl,
        currentPrice: currentPrice ?? this.currentPrice,
        basePrice: basePrice ?? this.basePrice,
        lastChecked: lastChecked ?? this.lastChecked,
        createdAt: createdAt ?? this.createdAt,
        targetPrice: targetPrice.present ? targetPrice.value : this.targetPrice,
        notifyOnDecrease: notifyOnDecrease ?? this.notifyOnDecrease,
        notifyOnIncrease: notifyOnIncrease ?? this.notifyOnIncrease,
        notifyOnTarget: notifyOnTarget ?? this.notifyOnTarget,
        checkIntervalMinutes: checkIntervalMinutes ?? this.checkIntervalMinutes,
        isPaused: isPaused ?? this.isPaused,
        isPinned: isPinned ?? this.isPinned,
        manuallyPaused: manuallyPaused ?? this.manuallyPaused,
        pausedAt: pausedAt.present ? pausedAt.value : this.pausedAt,
        pinnedAt: pinnedAt.present ? pinnedAt.value : this.pinnedAt,
        pendingPrice:
            pendingPrice.present ? pendingPrice.value : this.pendingPrice,
        pendingPriceAt:
            pendingPriceAt.present ? pendingPriceAt.value : this.pendingPriceAt,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        lastCheckError:
            lastCheckError.present ? lastCheckError.value : this.lastCheckError,
        availability:
            availability.present ? availability.value : this.availability,
        currencyCode: currencyCode ?? this.currencyCode,
        lastSource: lastSource ?? this.lastSource,
        lastScore: lastScore ?? this.lastScore,
        identityKey: identityKey ?? this.identityKey,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
        rev: rev ?? this.rev,
      );
  WatchProduct copyWithCompanion(WatchProductsCompanion data) {
    return WatchProduct(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      url: data.url.present ? data.url.value : this.url,
      canonicalUrl: data.canonicalUrl.present
          ? data.canonicalUrl.value
          : this.canonicalUrl,
      store: data.store.present ? data.store.value : this.store,
      productId: data.productId.present ? data.productId.value : this.productId,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      currentPrice: data.currentPrice.present
          ? data.currentPrice.value
          : this.currentPrice,
      basePrice: data.basePrice.present ? data.basePrice.value : this.basePrice,
      lastChecked:
          data.lastChecked.present ? data.lastChecked.value : this.lastChecked,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      targetPrice:
          data.targetPrice.present ? data.targetPrice.value : this.targetPrice,
      notifyOnDecrease: data.notifyOnDecrease.present
          ? data.notifyOnDecrease.value
          : this.notifyOnDecrease,
      notifyOnIncrease: data.notifyOnIncrease.present
          ? data.notifyOnIncrease.value
          : this.notifyOnIncrease,
      notifyOnTarget: data.notifyOnTarget.present
          ? data.notifyOnTarget.value
          : this.notifyOnTarget,
      checkIntervalMinutes: data.checkIntervalMinutes.present
          ? data.checkIntervalMinutes.value
          : this.checkIntervalMinutes,
      isPaused: data.isPaused.present ? data.isPaused.value : this.isPaused,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      manuallyPaused: data.manuallyPaused.present
          ? data.manuallyPaused.value
          : this.manuallyPaused,
      pausedAt: data.pausedAt.present ? data.pausedAt.value : this.pausedAt,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
      pendingPrice: data.pendingPrice.present
          ? data.pendingPrice.value
          : this.pendingPrice,
      pendingPriceAt: data.pendingPriceAt.present
          ? data.pendingPriceAt.value
          : this.pendingPriceAt,
      consecutiveFailures: data.consecutiveFailures.present
          ? data.consecutiveFailures.value
          : this.consecutiveFailures,
      lastCheckError: data.lastCheckError.present
          ? data.lastCheckError.value
          : this.lastCheckError,
      availability: data.availability.present
          ? data.availability.value
          : this.availability,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      lastSource:
          data.lastSource.present ? data.lastSource.value : this.lastSource,
      lastScore: data.lastScore.present ? data.lastScore.value : this.lastScore,
      identityKey:
          data.identityKey.present ? data.identityKey.value : this.identityKey,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      rev: data.rev.present ? data.rev.value : this.rev,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchProduct(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('canonicalUrl: $canonicalUrl, ')
          ..write('store: $store, ')
          ..write('productId: $productId, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('currentPrice: $currentPrice, ')
          ..write('basePrice: $basePrice, ')
          ..write('lastChecked: $lastChecked, ')
          ..write('createdAt: $createdAt, ')
          ..write('targetPrice: $targetPrice, ')
          ..write('notifyOnDecrease: $notifyOnDecrease, ')
          ..write('notifyOnIncrease: $notifyOnIncrease, ')
          ..write('notifyOnTarget: $notifyOnTarget, ')
          ..write('checkIntervalMinutes: $checkIntervalMinutes, ')
          ..write('isPaused: $isPaused, ')
          ..write('isPinned: $isPinned, ')
          ..write('manuallyPaused: $manuallyPaused, ')
          ..write('pausedAt: $pausedAt, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('pendingPrice: $pendingPrice, ')
          ..write('pendingPriceAt: $pendingPriceAt, ')
          ..write('consecutiveFailures: $consecutiveFailures, ')
          ..write('lastCheckError: $lastCheckError, ')
          ..write('availability: $availability, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('lastSource: $lastSource, ')
          ..write('lastScore: $lastScore, ')
          ..write('identityKey: $identityKey, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rev: $rev')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        url,
        canonicalUrl,
        store,
        productId,
        imageUrl,
        currentPrice,
        basePrice,
        lastChecked,
        createdAt,
        targetPrice,
        notifyOnDecrease,
        notifyOnIncrease,
        notifyOnTarget,
        checkIntervalMinutes,
        isPaused,
        isPinned,
        manuallyPaused,
        pausedAt,
        pinnedAt,
        pendingPrice,
        pendingPriceAt,
        consecutiveFailures,
        lastCheckError,
        availability,
        currencyCode,
        lastSource,
        lastScore,
        identityKey,
        updatedAt,
        rev
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchProduct &&
          other.id == this.id &&
          other.name == this.name &&
          other.url == this.url &&
          other.canonicalUrl == this.canonicalUrl &&
          other.store == this.store &&
          other.productId == this.productId &&
          other.imageUrl == this.imageUrl &&
          other.currentPrice == this.currentPrice &&
          other.basePrice == this.basePrice &&
          other.lastChecked == this.lastChecked &&
          other.createdAt == this.createdAt &&
          other.targetPrice == this.targetPrice &&
          other.notifyOnDecrease == this.notifyOnDecrease &&
          other.notifyOnIncrease == this.notifyOnIncrease &&
          other.notifyOnTarget == this.notifyOnTarget &&
          other.checkIntervalMinutes == this.checkIntervalMinutes &&
          other.isPaused == this.isPaused &&
          other.isPinned == this.isPinned &&
          other.manuallyPaused == this.manuallyPaused &&
          other.pausedAt == this.pausedAt &&
          other.pinnedAt == this.pinnedAt &&
          other.pendingPrice == this.pendingPrice &&
          other.pendingPriceAt == this.pendingPriceAt &&
          other.consecutiveFailures == this.consecutiveFailures &&
          other.lastCheckError == this.lastCheckError &&
          other.availability == this.availability &&
          other.currencyCode == this.currencyCode &&
          other.lastSource == this.lastSource &&
          other.lastScore == this.lastScore &&
          other.identityKey == this.identityKey &&
          other.updatedAt == this.updatedAt &&
          other.rev == this.rev);
}

class WatchProductsCompanion extends UpdateCompanion<WatchProduct> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> url;
  final Value<String> canonicalUrl;
  final Value<String> store;
  final Value<String?> productId;
  final Value<String> imageUrl;
  final Value<double> currentPrice;
  final Value<double> basePrice;
  final Value<String> lastChecked;
  final Value<String> createdAt;
  final Value<double?> targetPrice;
  final Value<bool> notifyOnDecrease;
  final Value<bool> notifyOnIncrease;
  final Value<bool> notifyOnTarget;
  final Value<int> checkIntervalMinutes;
  final Value<bool> isPaused;
  final Value<bool> isPinned;
  final Value<bool> manuallyPaused;
  final Value<String?> pausedAt;
  final Value<String?> pinnedAt;
  final Value<double?> pendingPrice;
  final Value<String?> pendingPriceAt;
  final Value<int> consecutiveFailures;
  final Value<String?> lastCheckError;
  final Value<String?> availability;
  final Value<String> currencyCode;
  final Value<String> lastSource;
  final Value<int> lastScore;
  final Value<String> identityKey;
  final Value<String?> updatedAt;
  final Value<int> rev;
  final Value<int> rowid;
  const WatchProductsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.canonicalUrl = const Value.absent(),
    this.store = const Value.absent(),
    this.productId = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.currentPrice = const Value.absent(),
    this.basePrice = const Value.absent(),
    this.lastChecked = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.targetPrice = const Value.absent(),
    this.notifyOnDecrease = const Value.absent(),
    this.notifyOnIncrease = const Value.absent(),
    this.notifyOnTarget = const Value.absent(),
    this.checkIntervalMinutes = const Value.absent(),
    this.isPaused = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.manuallyPaused = const Value.absent(),
    this.pausedAt = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.pendingPrice = const Value.absent(),
    this.pendingPriceAt = const Value.absent(),
    this.consecutiveFailures = const Value.absent(),
    this.lastCheckError = const Value.absent(),
    this.availability = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.lastSource = const Value.absent(),
    this.lastScore = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rev = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchProductsCompanion.insert({
    required String id,
    required String name,
    required String url,
    required String canonicalUrl,
    required String store,
    this.productId = const Value.absent(),
    this.imageUrl = const Value.absent(),
    required double currentPrice,
    required double basePrice,
    required String lastChecked,
    required String createdAt,
    this.targetPrice = const Value.absent(),
    this.notifyOnDecrease = const Value.absent(),
    this.notifyOnIncrease = const Value.absent(),
    this.notifyOnTarget = const Value.absent(),
    this.checkIntervalMinutes = const Value.absent(),
    this.isPaused = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.manuallyPaused = const Value.absent(),
    this.pausedAt = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.pendingPrice = const Value.absent(),
    this.pendingPriceAt = const Value.absent(),
    this.consecutiveFailures = const Value.absent(),
    this.lastCheckError = const Value.absent(),
    this.availability = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.lastSource = const Value.absent(),
    this.lastScore = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rev = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        url = Value(url),
        canonicalUrl = Value(canonicalUrl),
        store = Value(store),
        currentPrice = Value(currentPrice),
        basePrice = Value(basePrice),
        lastChecked = Value(lastChecked),
        createdAt = Value(createdAt);
  static Insertable<WatchProduct> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? url,
    Expression<String>? canonicalUrl,
    Expression<String>? store,
    Expression<String>? productId,
    Expression<String>? imageUrl,
    Expression<double>? currentPrice,
    Expression<double>? basePrice,
    Expression<String>? lastChecked,
    Expression<String>? createdAt,
    Expression<double>? targetPrice,
    Expression<bool>? notifyOnDecrease,
    Expression<bool>? notifyOnIncrease,
    Expression<bool>? notifyOnTarget,
    Expression<int>? checkIntervalMinutes,
    Expression<bool>? isPaused,
    Expression<bool>? isPinned,
    Expression<bool>? manuallyPaused,
    Expression<String>? pausedAt,
    Expression<String>? pinnedAt,
    Expression<double>? pendingPrice,
    Expression<String>? pendingPriceAt,
    Expression<int>? consecutiveFailures,
    Expression<String>? lastCheckError,
    Expression<String>? availability,
    Expression<String>? currencyCode,
    Expression<String>? lastSource,
    Expression<int>? lastScore,
    Expression<String>? identityKey,
    Expression<String>? updatedAt,
    Expression<int>? rev,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (canonicalUrl != null) 'canonical_url': canonicalUrl,
      if (store != null) 'store': store,
      if (productId != null) 'product_id': productId,
      if (imageUrl != null) 'image_url': imageUrl,
      if (currentPrice != null) 'current_price': currentPrice,
      if (basePrice != null) 'base_price': basePrice,
      if (lastChecked != null) 'last_checked': lastChecked,
      if (createdAt != null) 'created_at': createdAt,
      if (targetPrice != null) 'target_price': targetPrice,
      if (notifyOnDecrease != null) 'notify_on_decrease': notifyOnDecrease,
      if (notifyOnIncrease != null) 'notify_on_increase': notifyOnIncrease,
      if (notifyOnTarget != null) 'notify_on_target': notifyOnTarget,
      if (checkIntervalMinutes != null)
        'check_interval_minutes': checkIntervalMinutes,
      if (isPaused != null) 'is_paused': isPaused,
      if (isPinned != null) 'is_pinned': isPinned,
      if (manuallyPaused != null) 'manually_paused': manuallyPaused,
      if (pausedAt != null) 'paused_at': pausedAt,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (pendingPrice != null) 'pending_price': pendingPrice,
      if (pendingPriceAt != null) 'pending_price_at': pendingPriceAt,
      if (consecutiveFailures != null)
        'consecutive_failures': consecutiveFailures,
      if (lastCheckError != null) 'last_check_error': lastCheckError,
      if (availability != null) 'availability': availability,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (lastSource != null) 'last_source': lastSource,
      if (lastScore != null) 'last_score': lastScore,
      if (identityKey != null) 'identity_key': identityKey,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rev != null) 'rev': rev,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchProductsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? url,
      Value<String>? canonicalUrl,
      Value<String>? store,
      Value<String?>? productId,
      Value<String>? imageUrl,
      Value<double>? currentPrice,
      Value<double>? basePrice,
      Value<String>? lastChecked,
      Value<String>? createdAt,
      Value<double?>? targetPrice,
      Value<bool>? notifyOnDecrease,
      Value<bool>? notifyOnIncrease,
      Value<bool>? notifyOnTarget,
      Value<int>? checkIntervalMinutes,
      Value<bool>? isPaused,
      Value<bool>? isPinned,
      Value<bool>? manuallyPaused,
      Value<String?>? pausedAt,
      Value<String?>? pinnedAt,
      Value<double?>? pendingPrice,
      Value<String?>? pendingPriceAt,
      Value<int>? consecutiveFailures,
      Value<String?>? lastCheckError,
      Value<String?>? availability,
      Value<String>? currencyCode,
      Value<String>? lastSource,
      Value<int>? lastScore,
      Value<String>? identityKey,
      Value<String?>? updatedAt,
      Value<int>? rev,
      Value<int>? rowid}) {
    return WatchProductsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      canonicalUrl: canonicalUrl ?? this.canonicalUrl,
      store: store ?? this.store,
      productId: productId ?? this.productId,
      imageUrl: imageUrl ?? this.imageUrl,
      currentPrice: currentPrice ?? this.currentPrice,
      basePrice: basePrice ?? this.basePrice,
      lastChecked: lastChecked ?? this.lastChecked,
      createdAt: createdAt ?? this.createdAt,
      targetPrice: targetPrice ?? this.targetPrice,
      notifyOnDecrease: notifyOnDecrease ?? this.notifyOnDecrease,
      notifyOnIncrease: notifyOnIncrease ?? this.notifyOnIncrease,
      notifyOnTarget: notifyOnTarget ?? this.notifyOnTarget,
      checkIntervalMinutes: checkIntervalMinutes ?? this.checkIntervalMinutes,
      isPaused: isPaused ?? this.isPaused,
      isPinned: isPinned ?? this.isPinned,
      manuallyPaused: manuallyPaused ?? this.manuallyPaused,
      pausedAt: pausedAt ?? this.pausedAt,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      pendingPrice: pendingPrice ?? this.pendingPrice,
      pendingPriceAt: pendingPriceAt ?? this.pendingPriceAt,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastCheckError: lastCheckError ?? this.lastCheckError,
      availability: availability ?? this.availability,
      currencyCode: currencyCode ?? this.currencyCode,
      lastSource: lastSource ?? this.lastSource,
      lastScore: lastScore ?? this.lastScore,
      identityKey: identityKey ?? this.identityKey,
      updatedAt: updatedAt ?? this.updatedAt,
      rev: rev ?? this.rev,
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
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (canonicalUrl.present) {
      map['canonical_url'] = Variable<String>(canonicalUrl.value);
    }
    if (store.present) {
      map['store'] = Variable<String>(store.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (currentPrice.present) {
      map['current_price'] = Variable<double>(currentPrice.value);
    }
    if (basePrice.present) {
      map['base_price'] = Variable<double>(basePrice.value);
    }
    if (lastChecked.present) {
      map['last_checked'] = Variable<String>(lastChecked.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (targetPrice.present) {
      map['target_price'] = Variable<double>(targetPrice.value);
    }
    if (notifyOnDecrease.present) {
      map['notify_on_decrease'] = Variable<bool>(notifyOnDecrease.value);
    }
    if (notifyOnIncrease.present) {
      map['notify_on_increase'] = Variable<bool>(notifyOnIncrease.value);
    }
    if (notifyOnTarget.present) {
      map['notify_on_target'] = Variable<bool>(notifyOnTarget.value);
    }
    if (checkIntervalMinutes.present) {
      map['check_interval_minutes'] = Variable<int>(checkIntervalMinutes.value);
    }
    if (isPaused.present) {
      map['is_paused'] = Variable<bool>(isPaused.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (manuallyPaused.present) {
      map['manually_paused'] = Variable<bool>(manuallyPaused.value);
    }
    if (pausedAt.present) {
      map['paused_at'] = Variable<String>(pausedAt.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<String>(pinnedAt.value);
    }
    if (pendingPrice.present) {
      map['pending_price'] = Variable<double>(pendingPrice.value);
    }
    if (pendingPriceAt.present) {
      map['pending_price_at'] = Variable<String>(pendingPriceAt.value);
    }
    if (consecutiveFailures.present) {
      map['consecutive_failures'] = Variable<int>(consecutiveFailures.value);
    }
    if (lastCheckError.present) {
      map['last_check_error'] = Variable<String>(lastCheckError.value);
    }
    if (availability.present) {
      map['availability'] = Variable<String>(availability.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (lastSource.present) {
      map['last_source'] = Variable<String>(lastSource.value);
    }
    if (lastScore.present) {
      map['last_score'] = Variable<int>(lastScore.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchProductsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('canonicalUrl: $canonicalUrl, ')
          ..write('store: $store, ')
          ..write('productId: $productId, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('currentPrice: $currentPrice, ')
          ..write('basePrice: $basePrice, ')
          ..write('lastChecked: $lastChecked, ')
          ..write('createdAt: $createdAt, ')
          ..write('targetPrice: $targetPrice, ')
          ..write('notifyOnDecrease: $notifyOnDecrease, ')
          ..write('notifyOnIncrease: $notifyOnIncrease, ')
          ..write('notifyOnTarget: $notifyOnTarget, ')
          ..write('checkIntervalMinutes: $checkIntervalMinutes, ')
          ..write('isPaused: $isPaused, ')
          ..write('isPinned: $isPinned, ')
          ..write('manuallyPaused: $manuallyPaused, ')
          ..write('pausedAt: $pausedAt, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('pendingPrice: $pendingPrice, ')
          ..write('pendingPriceAt: $pendingPriceAt, ')
          ..write('consecutiveFailures: $consecutiveFailures, ')
          ..write('lastCheckError: $lastCheckError, ')
          ..write('availability: $availability, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('lastSource: $lastSource, ')
          ..write('lastScore: $lastScore, ')
          ..write('identityKey: $identityKey, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rev: $rev, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchPriceHistoryTable extends WatchPriceHistory
    with TableInfo<$WatchPriceHistoryTable, WatchPriceHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchPriceHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
      'price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _checkedAtMeta =
      const VerificationMeta('checkedAt');
  @override
  late final GeneratedColumn<String> checkedAt = GeneratedColumn<String>(
      'checked_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  @override
  List<GeneratedColumn> get $columns =>
      [id, productId, price, checkedAt, source];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_price_history';
  @override
  VerificationContext validateIntegrity(
      Insertable<WatchPriceHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('checked_at')) {
      context.handle(_checkedAtMeta,
          checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta));
    } else if (isInserting) {
      context.missing(_checkedAtMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WatchPriceHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchPriceHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price'])!,
      checkedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}checked_at'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
    );
  }

  @override
  $WatchPriceHistoryTable createAlias(String alias) {
    return $WatchPriceHistoryTable(attachedDatabase, alias);
  }
}

class WatchPriceHistoryData extends DataClass
    implements Insertable<WatchPriceHistoryData> {
  final String id;
  final String productId;
  final double price;
  final String checkedAt;
  final String source;
  const WatchPriceHistoryData(
      {required this.id,
      required this.productId,
      required this.price,
      required this.checkedAt,
      required this.source});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['price'] = Variable<double>(price);
    map['checked_at'] = Variable<String>(checkedAt);
    map['source'] = Variable<String>(source);
    return map;
  }

  WatchPriceHistoryCompanion toCompanion(bool nullToAbsent) {
    return WatchPriceHistoryCompanion(
      id: Value(id),
      productId: Value(productId),
      price: Value(price),
      checkedAt: Value(checkedAt),
      source: Value(source),
    );
  }

  factory WatchPriceHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchPriceHistoryData(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      price: serializer.fromJson<double>(json['price']),
      checkedAt: serializer.fromJson<String>(json['checkedAt']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'price': serializer.toJson<double>(price),
      'checkedAt': serializer.toJson<String>(checkedAt),
      'source': serializer.toJson<String>(source),
    };
  }

  WatchPriceHistoryData copyWith(
          {String? id,
          String? productId,
          double? price,
          String? checkedAt,
          String? source}) =>
      WatchPriceHistoryData(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        price: price ?? this.price,
        checkedAt: checkedAt ?? this.checkedAt,
        source: source ?? this.source,
      );
  WatchPriceHistoryData copyWithCompanion(WatchPriceHistoryCompanion data) {
    return WatchPriceHistoryData(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      price: data.price.present ? data.price.value : this.price,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchPriceHistoryData(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('price: $price, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, productId, price, checkedAt, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchPriceHistoryData &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.price == this.price &&
          other.checkedAt == this.checkedAt &&
          other.source == this.source);
}

class WatchPriceHistoryCompanion
    extends UpdateCompanion<WatchPriceHistoryData> {
  final Value<String> id;
  final Value<String> productId;
  final Value<double> price;
  final Value<String> checkedAt;
  final Value<String> source;
  final Value<int> rowid;
  const WatchPriceHistoryCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.price = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchPriceHistoryCompanion.insert({
    required String id,
    required String productId,
    required double price,
    required String checkedAt,
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        price = Value(price),
        checkedAt = Value(checkedAt);
  static Insertable<WatchPriceHistoryData> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<double>? price,
    Expression<String>? checkedAt,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (price != null) 'price': price,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchPriceHistoryCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<double>? price,
      Value<String>? checkedAt,
      Value<String>? source,
      Value<int>? rowid}) {
    return WatchPriceHistoryCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      price: price ?? this.price,
      checkedAt: checkedAt ?? this.checkedAt,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<String>(checkedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchPriceHistoryCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('price: $price, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchAlertsTable extends WatchAlerts
    with TableInfo<$WatchAlertsTable, WatchAlert> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchAlertsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productNameMeta =
      const VerificationMeta('productName');
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
      'product_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _oldPriceMeta =
      const VerificationMeta('oldPrice');
  @override
  late final GeneratedColumn<double> oldPrice = GeneratedColumn<double>(
      'old_price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _newPriceMeta =
      const VerificationMeta('newPrice');
  @override
  late final GeneratedColumn<double> newPrice = GeneratedColumn<double>(
      'new_price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
      'reason', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
      'is_read', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productId,
        productName,
        imageUrl,
        oldPrice,
        newPrice,
        reason,
        createdAt,
        isRead
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_alerts';
  @override
  VerificationContext validateIntegrity(Insertable<WatchAlert> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('product_name')) {
      context.handle(
          _productNameMeta,
          productName.isAcceptableOrUnknown(
              data['product_name']!, _productNameMeta));
    } else if (isInserting) {
      context.missing(_productNameMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    if (data.containsKey('old_price')) {
      context.handle(_oldPriceMeta,
          oldPrice.isAcceptableOrUnknown(data['old_price']!, _oldPriceMeta));
    } else if (isInserting) {
      context.missing(_oldPriceMeta);
    }
    if (data.containsKey('new_price')) {
      context.handle(_newPriceMeta,
          newPrice.isAcceptableOrUnknown(data['new_price']!, _newPriceMeta));
    } else if (isInserting) {
      context.missing(_newPriceMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(_reasonMeta,
          reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta));
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('is_read')) {
      context.handle(_isReadMeta,
          isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WatchAlert map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchAlert(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      productName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_name'])!,
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url'])!,
      oldPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}old_price'])!,
      newPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}new_price'])!,
      reason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reason'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at'])!,
      isRead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!,
    );
  }

  @override
  $WatchAlertsTable createAlias(String alias) {
    return $WatchAlertsTable(attachedDatabase, alias);
  }
}

class WatchAlert extends DataClass implements Insertable<WatchAlert> {
  final String id;
  final String productId;
  final String productName;
  final String imageUrl;
  final double oldPrice;
  final double newPrice;
  final String reason;
  final String createdAt;
  final bool isRead;
  const WatchAlert(
      {required this.id,
      required this.productId,
      required this.productName,
      required this.imageUrl,
      required this.oldPrice,
      required this.newPrice,
      required this.reason,
      required this.createdAt,
      required this.isRead});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['product_name'] = Variable<String>(productName);
    map['image_url'] = Variable<String>(imageUrl);
    map['old_price'] = Variable<double>(oldPrice);
    map['new_price'] = Variable<double>(newPrice);
    map['reason'] = Variable<String>(reason);
    map['created_at'] = Variable<String>(createdAt);
    map['is_read'] = Variable<bool>(isRead);
    return map;
  }

  WatchAlertsCompanion toCompanion(bool nullToAbsent) {
    return WatchAlertsCompanion(
      id: Value(id),
      productId: Value(productId),
      productName: Value(productName),
      imageUrl: Value(imageUrl),
      oldPrice: Value(oldPrice),
      newPrice: Value(newPrice),
      reason: Value(reason),
      createdAt: Value(createdAt),
      isRead: Value(isRead),
    );
  }

  factory WatchAlert.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchAlert(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      productName: serializer.fromJson<String>(json['productName']),
      imageUrl: serializer.fromJson<String>(json['imageUrl']),
      oldPrice: serializer.fromJson<double>(json['oldPrice']),
      newPrice: serializer.fromJson<double>(json['newPrice']),
      reason: serializer.fromJson<String>(json['reason']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      isRead: serializer.fromJson<bool>(json['isRead']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'productName': serializer.toJson<String>(productName),
      'imageUrl': serializer.toJson<String>(imageUrl),
      'oldPrice': serializer.toJson<double>(oldPrice),
      'newPrice': serializer.toJson<double>(newPrice),
      'reason': serializer.toJson<String>(reason),
      'createdAt': serializer.toJson<String>(createdAt),
      'isRead': serializer.toJson<bool>(isRead),
    };
  }

  WatchAlert copyWith(
          {String? id,
          String? productId,
          String? productName,
          String? imageUrl,
          double? oldPrice,
          double? newPrice,
          String? reason,
          String? createdAt,
          bool? isRead}) =>
      WatchAlert(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        productName: productName ?? this.productName,
        imageUrl: imageUrl ?? this.imageUrl,
        oldPrice: oldPrice ?? this.oldPrice,
        newPrice: newPrice ?? this.newPrice,
        reason: reason ?? this.reason,
        createdAt: createdAt ?? this.createdAt,
        isRead: isRead ?? this.isRead,
      );
  WatchAlert copyWithCompanion(WatchAlertsCompanion data) {
    return WatchAlert(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      productName:
          data.productName.present ? data.productName.value : this.productName,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      oldPrice: data.oldPrice.present ? data.oldPrice.value : this.oldPrice,
      newPrice: data.newPrice.present ? data.newPrice.value : this.newPrice,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchAlert(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('productName: $productName, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('oldPrice: $oldPrice, ')
          ..write('newPrice: $newPrice, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt, ')
          ..write('isRead: $isRead')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, productId, productName, imageUrl,
      oldPrice, newPrice, reason, createdAt, isRead);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchAlert &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.productName == this.productName &&
          other.imageUrl == this.imageUrl &&
          other.oldPrice == this.oldPrice &&
          other.newPrice == this.newPrice &&
          other.reason == this.reason &&
          other.createdAt == this.createdAt &&
          other.isRead == this.isRead);
}

class WatchAlertsCompanion extends UpdateCompanion<WatchAlert> {
  final Value<String> id;
  final Value<String> productId;
  final Value<String> productName;
  final Value<String> imageUrl;
  final Value<double> oldPrice;
  final Value<double> newPrice;
  final Value<String> reason;
  final Value<String> createdAt;
  final Value<bool> isRead;
  final Value<int> rowid;
  const WatchAlertsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.productName = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.oldPrice = const Value.absent(),
    this.newPrice = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isRead = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchAlertsCompanion.insert({
    required String id,
    required String productId,
    required String productName,
    this.imageUrl = const Value.absent(),
    required double oldPrice,
    required double newPrice,
    required String reason,
    required String createdAt,
    this.isRead = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        productName = Value(productName),
        oldPrice = Value(oldPrice),
        newPrice = Value(newPrice),
        reason = Value(reason),
        createdAt = Value(createdAt);
  static Insertable<WatchAlert> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? productName,
    Expression<String>? imageUrl,
    Expression<double>? oldPrice,
    Expression<double>? newPrice,
    Expression<String>? reason,
    Expression<String>? createdAt,
    Expression<bool>? isRead,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (productName != null) 'product_name': productName,
      if (imageUrl != null) 'image_url': imageUrl,
      if (oldPrice != null) 'old_price': oldPrice,
      if (newPrice != null) 'new_price': newPrice,
      if (reason != null) 'reason': reason,
      if (createdAt != null) 'created_at': createdAt,
      if (isRead != null) 'is_read': isRead,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchAlertsCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<String>? productName,
      Value<String>? imageUrl,
      Value<double>? oldPrice,
      Value<double>? newPrice,
      Value<String>? reason,
      Value<String>? createdAt,
      Value<bool>? isRead,
      Value<int>? rowid}) {
    return WatchAlertsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      oldPrice: oldPrice ?? this.oldPrice,
      newPrice: newPrice ?? this.newPrice,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (oldPrice.present) {
      map['old_price'] = Variable<double>(oldPrice.value);
    }
    if (newPrice.present) {
      map['new_price'] = Variable<double>(newPrice.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchAlertsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('productName: $productName, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('oldPrice: $oldPrice, ')
          ..write('newPrice: $newPrice, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt, ')
          ..write('isRead: $isRead, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchTombstonesTable extends WatchTombstones
    with TableInfo<$WatchTombstonesTable, WatchTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _identityKeyMeta =
      const VerificationMeta('identityKey');
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
      'identity_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
      'deleted_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [identityKey, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_tombstones';
  @override
  VerificationContext validateIntegrity(Insertable<WatchTombstone> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('identity_key')) {
      context.handle(
          _identityKeyMeta,
          identityKey.isAcceptableOrUnknown(
              data['identity_key']!, _identityKeyMeta));
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {identityKey};
  @override
  WatchTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchTombstone(
      identityKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}identity_key'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}deleted_at'])!,
    );
  }

  @override
  $WatchTombstonesTable createAlias(String alias) {
    return $WatchTombstonesTable(attachedDatabase, alias);
  }
}

class WatchTombstone extends DataClass implements Insertable<WatchTombstone> {
  final String identityKey;
  final String deletedAt;
  const WatchTombstone({required this.identityKey, required this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['identity_key'] = Variable<String>(identityKey);
    map['deleted_at'] = Variable<String>(deletedAt);
    return map;
  }

  WatchTombstonesCompanion toCompanion(bool nullToAbsent) {
    return WatchTombstonesCompanion(
      identityKey: Value(identityKey),
      deletedAt: Value(deletedAt),
    );
  }

  factory WatchTombstone.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchTombstone(
      identityKey: serializer.fromJson<String>(json['identityKey']),
      deletedAt: serializer.fromJson<String>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'identityKey': serializer.toJson<String>(identityKey),
      'deletedAt': serializer.toJson<String>(deletedAt),
    };
  }

  WatchTombstone copyWith({String? identityKey, String? deletedAt}) =>
      WatchTombstone(
        identityKey: identityKey ?? this.identityKey,
        deletedAt: deletedAt ?? this.deletedAt,
      );
  WatchTombstone copyWithCompanion(WatchTombstonesCompanion data) {
    return WatchTombstone(
      identityKey:
          data.identityKey.present ? data.identityKey.value : this.identityKey,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchTombstone(')
          ..write('identityKey: $identityKey, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(identityKey, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchTombstone &&
          other.identityKey == this.identityKey &&
          other.deletedAt == this.deletedAt);
}

class WatchTombstonesCompanion extends UpdateCompanion<WatchTombstone> {
  final Value<String> identityKey;
  final Value<String> deletedAt;
  final Value<int> rowid;
  const WatchTombstonesCompanion({
    this.identityKey = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchTombstonesCompanion.insert({
    required String identityKey,
    required String deletedAt,
    this.rowid = const Value.absent(),
  })  : identityKey = Value(identityKey),
        deletedAt = Value(deletedAt);
  static Insertable<WatchTombstone> custom({
    Expression<String>? identityKey,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (identityKey != null) 'identity_key': identityKey,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchTombstonesCompanion copyWith(
      {Value<String>? identityKey,
      Value<String>? deletedAt,
      Value<int>? rowid}) {
    return WatchTombstonesCompanion(
      identityKey: identityKey ?? this.identityKey,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchTombstonesCompanion(')
          ..write('identityKey: $identityKey, ')
          ..write('deletedAt: $deletedAt, ')
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
  late final $SalaryEntriesTable salaryEntries = $SalaryEntriesTable(this);
  late final $ExpenseMonthlyCategoryTable expenseMonthlyCategory =
      $ExpenseMonthlyCategoryTable(this);
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
  late final $SavedSearchesTable savedSearches = $SavedSearchesTable(this);
  late final $SavedSearchChatMessagesTable savedSearchChatMessages =
      $SavedSearchChatMessagesTable(this);
  late final $SavedSearchChatSummariesTable savedSearchChatSummaries =
      $SavedSearchChatSummariesTable(this);
  late final $WatchProductsTable watchProducts = $WatchProductsTable(this);
  late final $WatchPriceHistoryTable watchPriceHistory =
      $WatchPriceHistoryTable(this);
  late final $WatchAlertsTable watchAlerts = $WatchAlertsTable(this);
  late final $WatchTombstonesTable watchTombstones =
      $WatchTombstonesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        expenses,
        budgetEntries,
        salaryEntries,
        expenseMonthlyCategory,
        newsArticles,
        cloudFiles,
        savedWords,
        syncQueue,
        categoryLearnings,
        articleChatMessages,
        articleChatSummaries,
        savedSearches,
        savedSearchChatMessages,
        savedSearchChatSummaries,
        watchProducts,
        watchPriceHistory,
        watchAlerts,
        watchTombstones
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
  Value<String> comments,
  Value<String?> updatedAt,
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
  Value<String> comments,
  Value<String?> updatedAt,
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

  ColumnFilters<String> get comments => $composableBuilder(
      column: $table.comments, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
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

  ColumnOrderings<String> get comments => $composableBuilder(
      column: $table.comments, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
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

  GeneratedColumn<String> get comments =>
      $composableBuilder(column: $table.comments, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
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
            Value<String> comments = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
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
            comments: comments,
            updatedAt: updatedAt,
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
            Value<String> comments = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
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
            comments: comments,
            updatedAt: updatedAt,
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
typedef $$SalaryEntriesTableCreateCompanionBuilder = SalaryEntriesCompanion
    Function({
  required String id,
  required String month,
  required double amount,
  required String setAt,
  Value<int> rowid,
});
typedef $$SalaryEntriesTableUpdateCompanionBuilder = SalaryEntriesCompanion
    Function({
  Value<String> id,
  Value<String> month,
  Value<double> amount,
  Value<String> setAt,
  Value<int> rowid,
});

class $$SalaryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SalaryEntriesTable> {
  $$SalaryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get month => $composableBuilder(
      column: $table.month, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get setAt => $composableBuilder(
      column: $table.setAt, builder: (column) => ColumnFilters(column));
}

class $$SalaryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SalaryEntriesTable> {
  $$SalaryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get month => $composableBuilder(
      column: $table.month, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get setAt => $composableBuilder(
      column: $table.setAt, builder: (column) => ColumnOrderings(column));
}

class $$SalaryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SalaryEntriesTable> {
  $$SalaryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get setAt =>
      $composableBuilder(column: $table.setAt, builder: (column) => column);
}

class $$SalaryEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SalaryEntriesTable,
    SalaryEntry,
    $$SalaryEntriesTableFilterComposer,
    $$SalaryEntriesTableOrderingComposer,
    $$SalaryEntriesTableAnnotationComposer,
    $$SalaryEntriesTableCreateCompanionBuilder,
    $$SalaryEntriesTableUpdateCompanionBuilder,
    (
      SalaryEntry,
      BaseReferences<_$AppDatabase, $SalaryEntriesTable, SalaryEntry>
    ),
    SalaryEntry,
    PrefetchHooks Function()> {
  $$SalaryEntriesTableTableManager(_$AppDatabase db, $SalaryEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SalaryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SalaryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SalaryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> month = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> setAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SalaryEntriesCompanion(
            id: id,
            month: month,
            amount: amount,
            setAt: setAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String month,
            required double amount,
            required String setAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SalaryEntriesCompanion.insert(
            id: id,
            month: month,
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

typedef $$SalaryEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SalaryEntriesTable,
    SalaryEntry,
    $$SalaryEntriesTableFilterComposer,
    $$SalaryEntriesTableOrderingComposer,
    $$SalaryEntriesTableAnnotationComposer,
    $$SalaryEntriesTableCreateCompanionBuilder,
    $$SalaryEntriesTableUpdateCompanionBuilder,
    (
      SalaryEntry,
      BaseReferences<_$AppDatabase, $SalaryEntriesTable, SalaryEntry>
    ),
    SalaryEntry,
    PrefetchHooks Function()>;
typedef $$ExpenseMonthlyCategoryTableCreateCompanionBuilder
    = ExpenseMonthlyCategoryCompanion Function({
  required String month,
  required String category,
  Value<double> total,
  Value<int> count,
  Value<int> rowid,
});
typedef $$ExpenseMonthlyCategoryTableUpdateCompanionBuilder
    = ExpenseMonthlyCategoryCompanion Function({
  Value<String> month,
  Value<String> category,
  Value<double> total,
  Value<int> count,
  Value<int> rowid,
});

class $$ExpenseMonthlyCategoryTableFilterComposer
    extends Composer<_$AppDatabase, $ExpenseMonthlyCategoryTable> {
  $$ExpenseMonthlyCategoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get month => $composableBuilder(
      column: $table.month, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get count => $composableBuilder(
      column: $table.count, builder: (column) => ColumnFilters(column));
}

class $$ExpenseMonthlyCategoryTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpenseMonthlyCategoryTable> {
  $$ExpenseMonthlyCategoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get month => $composableBuilder(
      column: $table.month, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get count => $composableBuilder(
      column: $table.count, builder: (column) => ColumnOrderings(column));
}

class $$ExpenseMonthlyCategoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpenseMonthlyCategoryTable> {
  $$ExpenseMonthlyCategoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<double> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);
}

class $$ExpenseMonthlyCategoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ExpenseMonthlyCategoryTable,
    ExpenseMonthlyCategoryData,
    $$ExpenseMonthlyCategoryTableFilterComposer,
    $$ExpenseMonthlyCategoryTableOrderingComposer,
    $$ExpenseMonthlyCategoryTableAnnotationComposer,
    $$ExpenseMonthlyCategoryTableCreateCompanionBuilder,
    $$ExpenseMonthlyCategoryTableUpdateCompanionBuilder,
    (
      ExpenseMonthlyCategoryData,
      BaseReferences<_$AppDatabase, $ExpenseMonthlyCategoryTable,
          ExpenseMonthlyCategoryData>
    ),
    ExpenseMonthlyCategoryData,
    PrefetchHooks Function()> {
  $$ExpenseMonthlyCategoryTableTableManager(
      _$AppDatabase db, $ExpenseMonthlyCategoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpenseMonthlyCategoryTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpenseMonthlyCategoryTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpenseMonthlyCategoryTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> month = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<double> total = const Value.absent(),
            Value<int> count = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExpenseMonthlyCategoryCompanion(
            month: month,
            category: category,
            total: total,
            count: count,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String month,
            required String category,
            Value<double> total = const Value.absent(),
            Value<int> count = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExpenseMonthlyCategoryCompanion.insert(
            month: month,
            category: category,
            total: total,
            count: count,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExpenseMonthlyCategoryTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $ExpenseMonthlyCategoryTable,
        ExpenseMonthlyCategoryData,
        $$ExpenseMonthlyCategoryTableFilterComposer,
        $$ExpenseMonthlyCategoryTableOrderingComposer,
        $$ExpenseMonthlyCategoryTableAnnotationComposer,
        $$ExpenseMonthlyCategoryTableCreateCompanionBuilder,
        $$ExpenseMonthlyCategoryTableUpdateCompanionBuilder,
        (
          ExpenseMonthlyCategoryData,
          BaseReferences<_$AppDatabase, $ExpenseMonthlyCategoryTable,
              ExpenseMonthlyCategoryData>
        ),
        ExpenseMonthlyCategoryData,
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
typedef $$SavedSearchesTableCreateCompanionBuilder = SavedSearchesCompanion
    Function({
  required String id,
  required String kind,
  required String query,
  required String title,
  required String responseType,
  required String responseJson,
  Value<String> model,
  Value<String> provider,
  Value<String> mode,
  required String savedAt,
  required String updatedAt,
  Value<bool> pinned,
  Value<String?> deletedAt,
  Value<int> rowid,
});
typedef $$SavedSearchesTableUpdateCompanionBuilder = SavedSearchesCompanion
    Function({
  Value<String> id,
  Value<String> kind,
  Value<String> query,
  Value<String> title,
  Value<String> responseType,
  Value<String> responseJson,
  Value<String> model,
  Value<String> provider,
  Value<String> mode,
  Value<String> savedAt,
  Value<String> updatedAt,
  Value<bool> pinned,
  Value<String?> deletedAt,
  Value<int> rowid,
});

class $$SavedSearchesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedSearchesTable> {
  $$SavedSearchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get query => $composableBuilder(
      column: $table.query, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responseType => $composableBuilder(
      column: $table.responseType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responseJson => $composableBuilder(
      column: $table.responseJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get pinned => $composableBuilder(
      column: $table.pinned, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));
}

class $$SavedSearchesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedSearchesTable> {
  $$SavedSearchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get query => $composableBuilder(
      column: $table.query, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responseType => $composableBuilder(
      column: $table.responseType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responseJson => $composableBuilder(
      column: $table.responseJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get model => $composableBuilder(
      column: $table.model, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get provider => $composableBuilder(
      column: $table.provider, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get pinned => $composableBuilder(
      column: $table.pinned, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));
}

class $$SavedSearchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedSearchesTable> {
  $$SavedSearchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get responseType => $composableBuilder(
      column: $table.responseType, builder: (column) => column);

  GeneratedColumn<String> get responseJson => $composableBuilder(
      column: $table.responseJson, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$SavedSearchesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SavedSearchesTable,
    SavedSearche,
    $$SavedSearchesTableFilterComposer,
    $$SavedSearchesTableOrderingComposer,
    $$SavedSearchesTableAnnotationComposer,
    $$SavedSearchesTableCreateCompanionBuilder,
    $$SavedSearchesTableUpdateCompanionBuilder,
    (
      SavedSearche,
      BaseReferences<_$AppDatabase, $SavedSearchesTable, SavedSearche>
    ),
    SavedSearche,
    PrefetchHooks Function()> {
  $$SavedSearchesTableTableManager(_$AppDatabase db, $SavedSearchesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedSearchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedSearchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedSearchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> query = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> responseType = const Value.absent(),
            Value<String> responseJson = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<String> provider = const Value.absent(),
            Value<String> mode = const Value.absent(),
            Value<String> savedAt = const Value.absent(),
            Value<String> updatedAt = const Value.absent(),
            Value<bool> pinned = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedSearchesCompanion(
            id: id,
            kind: kind,
            query: query,
            title: title,
            responseType: responseType,
            responseJson: responseJson,
            model: model,
            provider: provider,
            mode: mode,
            savedAt: savedAt,
            updatedAt: updatedAt,
            pinned: pinned,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String kind,
            required String query,
            required String title,
            required String responseType,
            required String responseJson,
            Value<String> model = const Value.absent(),
            Value<String> provider = const Value.absent(),
            Value<String> mode = const Value.absent(),
            required String savedAt,
            required String updatedAt,
            Value<bool> pinned = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedSearchesCompanion.insert(
            id: id,
            kind: kind,
            query: query,
            title: title,
            responseType: responseType,
            responseJson: responseJson,
            model: model,
            provider: provider,
            mode: mode,
            savedAt: savedAt,
            updatedAt: updatedAt,
            pinned: pinned,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SavedSearchesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SavedSearchesTable,
    SavedSearche,
    $$SavedSearchesTableFilterComposer,
    $$SavedSearchesTableOrderingComposer,
    $$SavedSearchesTableAnnotationComposer,
    $$SavedSearchesTableCreateCompanionBuilder,
    $$SavedSearchesTableUpdateCompanionBuilder,
    (
      SavedSearche,
      BaseReferences<_$AppDatabase, $SavedSearchesTable, SavedSearche>
    ),
    SavedSearche,
    PrefetchHooks Function()>;
typedef $$SavedSearchChatMessagesTableCreateCompanionBuilder
    = SavedSearchChatMessagesCompanion Function({
  required String id,
  required String searchId,
  required String role,
  required String msgText,
  Value<String> model,
  Value<String> sourcesJson,
  required String createdAt,
  Value<int> rowid,
});
typedef $$SavedSearchChatMessagesTableUpdateCompanionBuilder
    = SavedSearchChatMessagesCompanion Function({
  Value<String> id,
  Value<String> searchId,
  Value<String> role,
  Value<String> msgText,
  Value<String> model,
  Value<String> sourcesJson,
  Value<String> createdAt,
  Value<int> rowid,
});

class $$SavedSearchChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedSearchChatMessagesTable> {
  $$SavedSearchChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get searchId => $composableBuilder(
      column: $table.searchId, builder: (column) => ColumnFilters(column));

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

class $$SavedSearchChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedSearchChatMessagesTable> {
  $$SavedSearchChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get searchId => $composableBuilder(
      column: $table.searchId, builder: (column) => ColumnOrderings(column));

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

class $$SavedSearchChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedSearchChatMessagesTable> {
  $$SavedSearchChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get searchId =>
      $composableBuilder(column: $table.searchId, builder: (column) => column);

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

class $$SavedSearchChatMessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SavedSearchChatMessagesTable,
    SavedSearchChatMessage,
    $$SavedSearchChatMessagesTableFilterComposer,
    $$SavedSearchChatMessagesTableOrderingComposer,
    $$SavedSearchChatMessagesTableAnnotationComposer,
    $$SavedSearchChatMessagesTableCreateCompanionBuilder,
    $$SavedSearchChatMessagesTableUpdateCompanionBuilder,
    (
      SavedSearchChatMessage,
      BaseReferences<_$AppDatabase, $SavedSearchChatMessagesTable,
          SavedSearchChatMessage>
    ),
    SavedSearchChatMessage,
    PrefetchHooks Function()> {
  $$SavedSearchChatMessagesTableTableManager(
      _$AppDatabase db, $SavedSearchChatMessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedSearchChatMessagesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedSearchChatMessagesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedSearchChatMessagesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> searchId = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> msgText = const Value.absent(),
            Value<String> model = const Value.absent(),
            Value<String> sourcesJson = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedSearchChatMessagesCompanion(
            id: id,
            searchId: searchId,
            role: role,
            msgText: msgText,
            model: model,
            sourcesJson: sourcesJson,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String searchId,
            required String role,
            required String msgText,
            Value<String> model = const Value.absent(),
            Value<String> sourcesJson = const Value.absent(),
            required String createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedSearchChatMessagesCompanion.insert(
            id: id,
            searchId: searchId,
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

typedef $$SavedSearchChatMessagesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $SavedSearchChatMessagesTable,
        SavedSearchChatMessage,
        $$SavedSearchChatMessagesTableFilterComposer,
        $$SavedSearchChatMessagesTableOrderingComposer,
        $$SavedSearchChatMessagesTableAnnotationComposer,
        $$SavedSearchChatMessagesTableCreateCompanionBuilder,
        $$SavedSearchChatMessagesTableUpdateCompanionBuilder,
        (
          SavedSearchChatMessage,
          BaseReferences<_$AppDatabase, $SavedSearchChatMessagesTable,
              SavedSearchChatMessage>
        ),
        SavedSearchChatMessage,
        PrefetchHooks Function()>;
typedef $$SavedSearchChatSummariesTableCreateCompanionBuilder
    = SavedSearchChatSummariesCompanion Function({
  required String searchId,
  required String summaryText,
  required int pairsCovered,
  required String updatedAt,
  Value<int> rowid,
});
typedef $$SavedSearchChatSummariesTableUpdateCompanionBuilder
    = SavedSearchChatSummariesCompanion Function({
  Value<String> searchId,
  Value<String> summaryText,
  Value<int> pairsCovered,
  Value<String> updatedAt,
  Value<int> rowid,
});

class $$SavedSearchChatSummariesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedSearchChatSummariesTable> {
  $$SavedSearchChatSummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get searchId => $composableBuilder(
      column: $table.searchId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pairsCovered => $composableBuilder(
      column: $table.pairsCovered, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SavedSearchChatSummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedSearchChatSummariesTable> {
  $$SavedSearchChatSummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get searchId => $composableBuilder(
      column: $table.searchId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pairsCovered => $composableBuilder(
      column: $table.pairsCovered,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SavedSearchChatSummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedSearchChatSummariesTable> {
  $$SavedSearchChatSummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get searchId =>
      $composableBuilder(column: $table.searchId, builder: (column) => column);

  GeneratedColumn<String> get summaryText => $composableBuilder(
      column: $table.summaryText, builder: (column) => column);

  GeneratedColumn<int> get pairsCovered => $composableBuilder(
      column: $table.pairsCovered, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SavedSearchChatSummariesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SavedSearchChatSummariesTable,
    SavedSearchChatSummary,
    $$SavedSearchChatSummariesTableFilterComposer,
    $$SavedSearchChatSummariesTableOrderingComposer,
    $$SavedSearchChatSummariesTableAnnotationComposer,
    $$SavedSearchChatSummariesTableCreateCompanionBuilder,
    $$SavedSearchChatSummariesTableUpdateCompanionBuilder,
    (
      SavedSearchChatSummary,
      BaseReferences<_$AppDatabase, $SavedSearchChatSummariesTable,
          SavedSearchChatSummary>
    ),
    SavedSearchChatSummary,
    PrefetchHooks Function()> {
  $$SavedSearchChatSummariesTableTableManager(
      _$AppDatabase db, $SavedSearchChatSummariesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedSearchChatSummariesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedSearchChatSummariesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedSearchChatSummariesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> searchId = const Value.absent(),
            Value<String> summaryText = const Value.absent(),
            Value<int> pairsCovered = const Value.absent(),
            Value<String> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedSearchChatSummariesCompanion(
            searchId: searchId,
            summaryText: summaryText,
            pairsCovered: pairsCovered,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String searchId,
            required String summaryText,
            required int pairsCovered,
            required String updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SavedSearchChatSummariesCompanion.insert(
            searchId: searchId,
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

typedef $$SavedSearchChatSummariesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $SavedSearchChatSummariesTable,
        SavedSearchChatSummary,
        $$SavedSearchChatSummariesTableFilterComposer,
        $$SavedSearchChatSummariesTableOrderingComposer,
        $$SavedSearchChatSummariesTableAnnotationComposer,
        $$SavedSearchChatSummariesTableCreateCompanionBuilder,
        $$SavedSearchChatSummariesTableUpdateCompanionBuilder,
        (
          SavedSearchChatSummary,
          BaseReferences<_$AppDatabase, $SavedSearchChatSummariesTable,
              SavedSearchChatSummary>
        ),
        SavedSearchChatSummary,
        PrefetchHooks Function()>;
typedef $$WatchProductsTableCreateCompanionBuilder = WatchProductsCompanion
    Function({
  required String id,
  required String name,
  required String url,
  required String canonicalUrl,
  required String store,
  Value<String?> productId,
  Value<String> imageUrl,
  required double currentPrice,
  required double basePrice,
  required String lastChecked,
  required String createdAt,
  Value<double?> targetPrice,
  Value<bool> notifyOnDecrease,
  Value<bool> notifyOnIncrease,
  Value<bool> notifyOnTarget,
  Value<int> checkIntervalMinutes,
  Value<bool> isPaused,
  Value<bool> isPinned,
  Value<bool> manuallyPaused,
  Value<String?> pausedAt,
  Value<String?> pinnedAt,
  Value<double?> pendingPrice,
  Value<String?> pendingPriceAt,
  Value<int> consecutiveFailures,
  Value<String?> lastCheckError,
  Value<String?> availability,
  Value<String> currencyCode,
  Value<String> lastSource,
  Value<int> lastScore,
  Value<String> identityKey,
  Value<String?> updatedAt,
  Value<int> rev,
  Value<int> rowid,
});
typedef $$WatchProductsTableUpdateCompanionBuilder = WatchProductsCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> url,
  Value<String> canonicalUrl,
  Value<String> store,
  Value<String?> productId,
  Value<String> imageUrl,
  Value<double> currentPrice,
  Value<double> basePrice,
  Value<String> lastChecked,
  Value<String> createdAt,
  Value<double?> targetPrice,
  Value<bool> notifyOnDecrease,
  Value<bool> notifyOnIncrease,
  Value<bool> notifyOnTarget,
  Value<int> checkIntervalMinutes,
  Value<bool> isPaused,
  Value<bool> isPinned,
  Value<bool> manuallyPaused,
  Value<String?> pausedAt,
  Value<String?> pinnedAt,
  Value<double?> pendingPrice,
  Value<String?> pendingPriceAt,
  Value<int> consecutiveFailures,
  Value<String?> lastCheckError,
  Value<String?> availability,
  Value<String> currencyCode,
  Value<String> lastSource,
  Value<int> lastScore,
  Value<String> identityKey,
  Value<String?> updatedAt,
  Value<int> rev,
  Value<int> rowid,
});

class $$WatchProductsTableFilterComposer
    extends Composer<_$AppDatabase, $WatchProductsTable> {
  $$WatchProductsTableFilterComposer({
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

  ColumnFilters<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get canonicalUrl => $composableBuilder(
      column: $table.canonicalUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get store => $composableBuilder(
      column: $table.store, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get currentPrice => $composableBuilder(
      column: $table.currentPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get basePrice => $composableBuilder(
      column: $table.basePrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastChecked => $composableBuilder(
      column: $table.lastChecked, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get targetPrice => $composableBuilder(
      column: $table.targetPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get notifyOnDecrease => $composableBuilder(
      column: $table.notifyOnDecrease,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get notifyOnIncrease => $composableBuilder(
      column: $table.notifyOnIncrease,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get notifyOnTarget => $composableBuilder(
      column: $table.notifyOnTarget,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get checkIntervalMinutes => $composableBuilder(
      column: $table.checkIntervalMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPaused => $composableBuilder(
      column: $table.isPaused, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get manuallyPaused => $composableBuilder(
      column: $table.manuallyPaused,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pausedAt => $composableBuilder(
      column: $table.pausedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pinnedAt => $composableBuilder(
      column: $table.pinnedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pendingPrice => $composableBuilder(
      column: $table.pendingPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pendingPriceAt => $composableBuilder(
      column: $table.pendingPriceAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get consecutiveFailures => $composableBuilder(
      column: $table.consecutiveFailures,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastCheckError => $composableBuilder(
      column: $table.lastCheckError,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get availability => $composableBuilder(
      column: $table.availability, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currencyCode => $composableBuilder(
      column: $table.currencyCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastSource => $composableBuilder(
      column: $table.lastSource, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastScore => $composableBuilder(
      column: $table.lastScore, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get identityKey => $composableBuilder(
      column: $table.identityKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rev => $composableBuilder(
      column: $table.rev, builder: (column) => ColumnFilters(column));
}

class $$WatchProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchProductsTable> {
  $$WatchProductsTableOrderingComposer({
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

  ColumnOrderings<String> get url => $composableBuilder(
      column: $table.url, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get canonicalUrl => $composableBuilder(
      column: $table.canonicalUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get store => $composableBuilder(
      column: $table.store, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get currentPrice => $composableBuilder(
      column: $table.currentPrice,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get basePrice => $composableBuilder(
      column: $table.basePrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastChecked => $composableBuilder(
      column: $table.lastChecked, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get targetPrice => $composableBuilder(
      column: $table.targetPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get notifyOnDecrease => $composableBuilder(
      column: $table.notifyOnDecrease,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get notifyOnIncrease => $composableBuilder(
      column: $table.notifyOnIncrease,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get notifyOnTarget => $composableBuilder(
      column: $table.notifyOnTarget,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get checkIntervalMinutes => $composableBuilder(
      column: $table.checkIntervalMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPaused => $composableBuilder(
      column: $table.isPaused, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get manuallyPaused => $composableBuilder(
      column: $table.manuallyPaused,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pausedAt => $composableBuilder(
      column: $table.pausedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pinnedAt => $composableBuilder(
      column: $table.pinnedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pendingPrice => $composableBuilder(
      column: $table.pendingPrice,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pendingPriceAt => $composableBuilder(
      column: $table.pendingPriceAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get consecutiveFailures => $composableBuilder(
      column: $table.consecutiveFailures,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastCheckError => $composableBuilder(
      column: $table.lastCheckError,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get availability => $composableBuilder(
      column: $table.availability,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currencyCode => $composableBuilder(
      column: $table.currencyCode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastSource => $composableBuilder(
      column: $table.lastSource, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastScore => $composableBuilder(
      column: $table.lastScore, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get identityKey => $composableBuilder(
      column: $table.identityKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rev => $composableBuilder(
      column: $table.rev, builder: (column) => ColumnOrderings(column));
}

class $$WatchProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchProductsTable> {
  $$WatchProductsTableAnnotationComposer({
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

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get canonicalUrl => $composableBuilder(
      column: $table.canonicalUrl, builder: (column) => column);

  GeneratedColumn<String> get store =>
      $composableBuilder(column: $table.store, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<double> get currentPrice => $composableBuilder(
      column: $table.currentPrice, builder: (column) => column);

  GeneratedColumn<double> get basePrice =>
      $composableBuilder(column: $table.basePrice, builder: (column) => column);

  GeneratedColumn<String> get lastChecked => $composableBuilder(
      column: $table.lastChecked, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<double> get targetPrice => $composableBuilder(
      column: $table.targetPrice, builder: (column) => column);

  GeneratedColumn<bool> get notifyOnDecrease => $composableBuilder(
      column: $table.notifyOnDecrease, builder: (column) => column);

  GeneratedColumn<bool> get notifyOnIncrease => $composableBuilder(
      column: $table.notifyOnIncrease, builder: (column) => column);

  GeneratedColumn<bool> get notifyOnTarget => $composableBuilder(
      column: $table.notifyOnTarget, builder: (column) => column);

  GeneratedColumn<int> get checkIntervalMinutes => $composableBuilder(
      column: $table.checkIntervalMinutes, builder: (column) => column);

  GeneratedColumn<bool> get isPaused =>
      $composableBuilder(column: $table.isPaused, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get manuallyPaused => $composableBuilder(
      column: $table.manuallyPaused, builder: (column) => column);

  GeneratedColumn<String> get pausedAt =>
      $composableBuilder(column: $table.pausedAt, builder: (column) => column);

  GeneratedColumn<String> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);

  GeneratedColumn<double> get pendingPrice => $composableBuilder(
      column: $table.pendingPrice, builder: (column) => column);

  GeneratedColumn<String> get pendingPriceAt => $composableBuilder(
      column: $table.pendingPriceAt, builder: (column) => column);

  GeneratedColumn<int> get consecutiveFailures => $composableBuilder(
      column: $table.consecutiveFailures, builder: (column) => column);

  GeneratedColumn<String> get lastCheckError => $composableBuilder(
      column: $table.lastCheckError, builder: (column) => column);

  GeneratedColumn<String> get availability => $composableBuilder(
      column: $table.availability, builder: (column) => column);

  GeneratedColumn<String> get currencyCode => $composableBuilder(
      column: $table.currencyCode, builder: (column) => column);

  GeneratedColumn<String> get lastSource => $composableBuilder(
      column: $table.lastSource, builder: (column) => column);

  GeneratedColumn<int> get lastScore =>
      $composableBuilder(column: $table.lastScore, builder: (column) => column);

  GeneratedColumn<String> get identityKey => $composableBuilder(
      column: $table.identityKey, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);
}

class $$WatchProductsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $WatchProductsTable,
    WatchProduct,
    $$WatchProductsTableFilterComposer,
    $$WatchProductsTableOrderingComposer,
    $$WatchProductsTableAnnotationComposer,
    $$WatchProductsTableCreateCompanionBuilder,
    $$WatchProductsTableUpdateCompanionBuilder,
    (
      WatchProduct,
      BaseReferences<_$AppDatabase, $WatchProductsTable, WatchProduct>
    ),
    WatchProduct,
    PrefetchHooks Function()> {
  $$WatchProductsTableTableManager(_$AppDatabase db, $WatchProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> url = const Value.absent(),
            Value<String> canonicalUrl = const Value.absent(),
            Value<String> store = const Value.absent(),
            Value<String?> productId = const Value.absent(),
            Value<String> imageUrl = const Value.absent(),
            Value<double> currentPrice = const Value.absent(),
            Value<double> basePrice = const Value.absent(),
            Value<String> lastChecked = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
            Value<double?> targetPrice = const Value.absent(),
            Value<bool> notifyOnDecrease = const Value.absent(),
            Value<bool> notifyOnIncrease = const Value.absent(),
            Value<bool> notifyOnTarget = const Value.absent(),
            Value<int> checkIntervalMinutes = const Value.absent(),
            Value<bool> isPaused = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> manuallyPaused = const Value.absent(),
            Value<String?> pausedAt = const Value.absent(),
            Value<String?> pinnedAt = const Value.absent(),
            Value<double?> pendingPrice = const Value.absent(),
            Value<String?> pendingPriceAt = const Value.absent(),
            Value<int> consecutiveFailures = const Value.absent(),
            Value<String?> lastCheckError = const Value.absent(),
            Value<String?> availability = const Value.absent(),
            Value<String> currencyCode = const Value.absent(),
            Value<String> lastSource = const Value.absent(),
            Value<int> lastScore = const Value.absent(),
            Value<String> identityKey = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
            Value<int> rev = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchProductsCompanion(
            id: id,
            name: name,
            url: url,
            canonicalUrl: canonicalUrl,
            store: store,
            productId: productId,
            imageUrl: imageUrl,
            currentPrice: currentPrice,
            basePrice: basePrice,
            lastChecked: lastChecked,
            createdAt: createdAt,
            targetPrice: targetPrice,
            notifyOnDecrease: notifyOnDecrease,
            notifyOnIncrease: notifyOnIncrease,
            notifyOnTarget: notifyOnTarget,
            checkIntervalMinutes: checkIntervalMinutes,
            isPaused: isPaused,
            isPinned: isPinned,
            manuallyPaused: manuallyPaused,
            pausedAt: pausedAt,
            pinnedAt: pinnedAt,
            pendingPrice: pendingPrice,
            pendingPriceAt: pendingPriceAt,
            consecutiveFailures: consecutiveFailures,
            lastCheckError: lastCheckError,
            availability: availability,
            currencyCode: currencyCode,
            lastSource: lastSource,
            lastScore: lastScore,
            identityKey: identityKey,
            updatedAt: updatedAt,
            rev: rev,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String url,
            required String canonicalUrl,
            required String store,
            Value<String?> productId = const Value.absent(),
            Value<String> imageUrl = const Value.absent(),
            required double currentPrice,
            required double basePrice,
            required String lastChecked,
            required String createdAt,
            Value<double?> targetPrice = const Value.absent(),
            Value<bool> notifyOnDecrease = const Value.absent(),
            Value<bool> notifyOnIncrease = const Value.absent(),
            Value<bool> notifyOnTarget = const Value.absent(),
            Value<int> checkIntervalMinutes = const Value.absent(),
            Value<bool> isPaused = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> manuallyPaused = const Value.absent(),
            Value<String?> pausedAt = const Value.absent(),
            Value<String?> pinnedAt = const Value.absent(),
            Value<double?> pendingPrice = const Value.absent(),
            Value<String?> pendingPriceAt = const Value.absent(),
            Value<int> consecutiveFailures = const Value.absent(),
            Value<String?> lastCheckError = const Value.absent(),
            Value<String?> availability = const Value.absent(),
            Value<String> currencyCode = const Value.absent(),
            Value<String> lastSource = const Value.absent(),
            Value<int> lastScore = const Value.absent(),
            Value<String> identityKey = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
            Value<int> rev = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchProductsCompanion.insert(
            id: id,
            name: name,
            url: url,
            canonicalUrl: canonicalUrl,
            store: store,
            productId: productId,
            imageUrl: imageUrl,
            currentPrice: currentPrice,
            basePrice: basePrice,
            lastChecked: lastChecked,
            createdAt: createdAt,
            targetPrice: targetPrice,
            notifyOnDecrease: notifyOnDecrease,
            notifyOnIncrease: notifyOnIncrease,
            notifyOnTarget: notifyOnTarget,
            checkIntervalMinutes: checkIntervalMinutes,
            isPaused: isPaused,
            isPinned: isPinned,
            manuallyPaused: manuallyPaused,
            pausedAt: pausedAt,
            pinnedAt: pinnedAt,
            pendingPrice: pendingPrice,
            pendingPriceAt: pendingPriceAt,
            consecutiveFailures: consecutiveFailures,
            lastCheckError: lastCheckError,
            availability: availability,
            currencyCode: currencyCode,
            lastSource: lastSource,
            lastScore: lastScore,
            identityKey: identityKey,
            updatedAt: updatedAt,
            rev: rev,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WatchProductsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $WatchProductsTable,
    WatchProduct,
    $$WatchProductsTableFilterComposer,
    $$WatchProductsTableOrderingComposer,
    $$WatchProductsTableAnnotationComposer,
    $$WatchProductsTableCreateCompanionBuilder,
    $$WatchProductsTableUpdateCompanionBuilder,
    (
      WatchProduct,
      BaseReferences<_$AppDatabase, $WatchProductsTable, WatchProduct>
    ),
    WatchProduct,
    PrefetchHooks Function()>;
typedef $$WatchPriceHistoryTableCreateCompanionBuilder
    = WatchPriceHistoryCompanion Function({
  required String id,
  required String productId,
  required double price,
  required String checkedAt,
  Value<String> source,
  Value<int> rowid,
});
typedef $$WatchPriceHistoryTableUpdateCompanionBuilder
    = WatchPriceHistoryCompanion Function({
  Value<String> id,
  Value<String> productId,
  Value<double> price,
  Value<String> checkedAt,
  Value<String> source,
  Value<int> rowid,
});

class $$WatchPriceHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $WatchPriceHistoryTable> {
  $$WatchPriceHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get checkedAt => $composableBuilder(
      column: $table.checkedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));
}

class $$WatchPriceHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchPriceHistoryTable> {
  $$WatchPriceHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get checkedAt => $composableBuilder(
      column: $table.checkedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));
}

class $$WatchPriceHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchPriceHistoryTable> {
  $$WatchPriceHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$WatchPriceHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $WatchPriceHistoryTable,
    WatchPriceHistoryData,
    $$WatchPriceHistoryTableFilterComposer,
    $$WatchPriceHistoryTableOrderingComposer,
    $$WatchPriceHistoryTableAnnotationComposer,
    $$WatchPriceHistoryTableCreateCompanionBuilder,
    $$WatchPriceHistoryTableUpdateCompanionBuilder,
    (
      WatchPriceHistoryData,
      BaseReferences<_$AppDatabase, $WatchPriceHistoryTable,
          WatchPriceHistoryData>
    ),
    WatchPriceHistoryData,
    PrefetchHooks Function()> {
  $$WatchPriceHistoryTableTableManager(
      _$AppDatabase db, $WatchPriceHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchPriceHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchPriceHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchPriceHistoryTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<double> price = const Value.absent(),
            Value<String> checkedAt = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchPriceHistoryCompanion(
            id: id,
            productId: productId,
            price: price,
            checkedAt: checkedAt,
            source: source,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required double price,
            required String checkedAt,
            Value<String> source = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchPriceHistoryCompanion.insert(
            id: id,
            productId: productId,
            price: price,
            checkedAt: checkedAt,
            source: source,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WatchPriceHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $WatchPriceHistoryTable,
    WatchPriceHistoryData,
    $$WatchPriceHistoryTableFilterComposer,
    $$WatchPriceHistoryTableOrderingComposer,
    $$WatchPriceHistoryTableAnnotationComposer,
    $$WatchPriceHistoryTableCreateCompanionBuilder,
    $$WatchPriceHistoryTableUpdateCompanionBuilder,
    (
      WatchPriceHistoryData,
      BaseReferences<_$AppDatabase, $WatchPriceHistoryTable,
          WatchPriceHistoryData>
    ),
    WatchPriceHistoryData,
    PrefetchHooks Function()>;
typedef $$WatchAlertsTableCreateCompanionBuilder = WatchAlertsCompanion
    Function({
  required String id,
  required String productId,
  required String productName,
  Value<String> imageUrl,
  required double oldPrice,
  required double newPrice,
  required String reason,
  required String createdAt,
  Value<bool> isRead,
  Value<int> rowid,
});
typedef $$WatchAlertsTableUpdateCompanionBuilder = WatchAlertsCompanion
    Function({
  Value<String> id,
  Value<String> productId,
  Value<String> productName,
  Value<String> imageUrl,
  Value<double> oldPrice,
  Value<double> newPrice,
  Value<String> reason,
  Value<String> createdAt,
  Value<bool> isRead,
  Value<int> rowid,
});

class $$WatchAlertsTableFilterComposer
    extends Composer<_$AppDatabase, $WatchAlertsTable> {
  $$WatchAlertsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get oldPrice => $composableBuilder(
      column: $table.oldPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get newPrice => $composableBuilder(
      column: $table.newPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnFilters(column));
}

class $$WatchAlertsTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchAlertsTable> {
  $$WatchAlertsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get oldPrice => $composableBuilder(
      column: $table.oldPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get newPrice => $composableBuilder(
      column: $table.newPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnOrderings(column));
}

class $$WatchAlertsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchAlertsTable> {
  $$WatchAlertsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<double> get oldPrice =>
      $composableBuilder(column: $table.oldPrice, builder: (column) => column);

  GeneratedColumn<double> get newPrice =>
      $composableBuilder(column: $table.newPrice, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);
}

class $$WatchAlertsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $WatchAlertsTable,
    WatchAlert,
    $$WatchAlertsTableFilterComposer,
    $$WatchAlertsTableOrderingComposer,
    $$WatchAlertsTableAnnotationComposer,
    $$WatchAlertsTableCreateCompanionBuilder,
    $$WatchAlertsTableUpdateCompanionBuilder,
    (WatchAlert, BaseReferences<_$AppDatabase, $WatchAlertsTable, WatchAlert>),
    WatchAlert,
    PrefetchHooks Function()> {
  $$WatchAlertsTableTableManager(_$AppDatabase db, $WatchAlertsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchAlertsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchAlertsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchAlertsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> productName = const Value.absent(),
            Value<String> imageUrl = const Value.absent(),
            Value<double> oldPrice = const Value.absent(),
            Value<double> newPrice = const Value.absent(),
            Value<String> reason = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchAlertsCompanion(
            id: id,
            productId: productId,
            productName: productName,
            imageUrl: imageUrl,
            oldPrice: oldPrice,
            newPrice: newPrice,
            reason: reason,
            createdAt: createdAt,
            isRead: isRead,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required String productName,
            Value<String> imageUrl = const Value.absent(),
            required double oldPrice,
            required double newPrice,
            required String reason,
            required String createdAt,
            Value<bool> isRead = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchAlertsCompanion.insert(
            id: id,
            productId: productId,
            productName: productName,
            imageUrl: imageUrl,
            oldPrice: oldPrice,
            newPrice: newPrice,
            reason: reason,
            createdAt: createdAt,
            isRead: isRead,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WatchAlertsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $WatchAlertsTable,
    WatchAlert,
    $$WatchAlertsTableFilterComposer,
    $$WatchAlertsTableOrderingComposer,
    $$WatchAlertsTableAnnotationComposer,
    $$WatchAlertsTableCreateCompanionBuilder,
    $$WatchAlertsTableUpdateCompanionBuilder,
    (WatchAlert, BaseReferences<_$AppDatabase, $WatchAlertsTable, WatchAlert>),
    WatchAlert,
    PrefetchHooks Function()>;
typedef $$WatchTombstonesTableCreateCompanionBuilder = WatchTombstonesCompanion
    Function({
  required String identityKey,
  required String deletedAt,
  Value<int> rowid,
});
typedef $$WatchTombstonesTableUpdateCompanionBuilder = WatchTombstonesCompanion
    Function({
  Value<String> identityKey,
  Value<String> deletedAt,
  Value<int> rowid,
});

class $$WatchTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $WatchTombstonesTable> {
  $$WatchTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get identityKey => $composableBuilder(
      column: $table.identityKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));
}

class $$WatchTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchTombstonesTable> {
  $$WatchTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get identityKey => $composableBuilder(
      column: $table.identityKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));
}

class $$WatchTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchTombstonesTable> {
  $$WatchTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get identityKey => $composableBuilder(
      column: $table.identityKey, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$WatchTombstonesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $WatchTombstonesTable,
    WatchTombstone,
    $$WatchTombstonesTableFilterComposer,
    $$WatchTombstonesTableOrderingComposer,
    $$WatchTombstonesTableAnnotationComposer,
    $$WatchTombstonesTableCreateCompanionBuilder,
    $$WatchTombstonesTableUpdateCompanionBuilder,
    (
      WatchTombstone,
      BaseReferences<_$AppDatabase, $WatchTombstonesTable, WatchTombstone>
    ),
    WatchTombstone,
    PrefetchHooks Function()> {
  $$WatchTombstonesTableTableManager(
      _$AppDatabase db, $WatchTombstonesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchTombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> identityKey = const Value.absent(),
            Value<String> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchTombstonesCompanion(
            identityKey: identityKey,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String identityKey,
            required String deletedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchTombstonesCompanion.insert(
            identityKey: identityKey,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WatchTombstonesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $WatchTombstonesTable,
    WatchTombstone,
    $$WatchTombstonesTableFilterComposer,
    $$WatchTombstonesTableOrderingComposer,
    $$WatchTombstonesTableAnnotationComposer,
    $$WatchTombstonesTableCreateCompanionBuilder,
    $$WatchTombstonesTableUpdateCompanionBuilder,
    (
      WatchTombstone,
      BaseReferences<_$AppDatabase, $WatchTombstonesTable, WatchTombstone>
    ),
    WatchTombstone,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$BudgetEntriesTableTableManager get budgetEntries =>
      $$BudgetEntriesTableTableManager(_db, _db.budgetEntries);
  $$SalaryEntriesTableTableManager get salaryEntries =>
      $$SalaryEntriesTableTableManager(_db, _db.salaryEntries);
  $$ExpenseMonthlyCategoryTableTableManager get expenseMonthlyCategory =>
      $$ExpenseMonthlyCategoryTableTableManager(
          _db, _db.expenseMonthlyCategory);
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
  $$SavedSearchesTableTableManager get savedSearches =>
      $$SavedSearchesTableTableManager(_db, _db.savedSearches);
  $$SavedSearchChatMessagesTableTableManager get savedSearchChatMessages =>
      $$SavedSearchChatMessagesTableTableManager(
          _db, _db.savedSearchChatMessages);
  $$SavedSearchChatSummariesTableTableManager get savedSearchChatSummaries =>
      $$SavedSearchChatSummariesTableTableManager(
          _db, _db.savedSearchChatSummaries);
  $$WatchProductsTableTableManager get watchProducts =>
      $$WatchProductsTableTableManager(_db, _db.watchProducts);
  $$WatchPriceHistoryTableTableManager get watchPriceHistory =>
      $$WatchPriceHistoryTableTableManager(_db, _db.watchPriceHistory);
  $$WatchAlertsTableTableManager get watchAlerts =>
      $$WatchAlertsTableTableManager(_db, _db.watchAlerts);
  $$WatchTombstonesTableTableManager get watchTombstones =>
      $$WatchTombstonesTableTableManager(_db, _db.watchTombstones);
}
