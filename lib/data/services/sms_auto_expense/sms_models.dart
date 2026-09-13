/// Structured debit extracted from a bank SMS. Never includes the raw
/// body in [toJson] used for logging — [rawBody] stays local-only.
class ParsedSmsDebit {
  const ParsedSmsDebit({
    required this.amount,
    required this.merchantRaw,
    required this.instrument,
    required this.instrumentLast4,
    required this.transactionDate,
    required this.bank,
    required this.cardType,
    this.referenceId,
    this.balanceAfter,
    this.templateId = 'unmatched',
    this.rawBody = '',
  });

  final double amount;

  /// Cleaned merchant / payee / VPA. Empty when the SMS had none.
  final String merchantRaw;

  /// BANK_ACCOUNT, CREDIT_CARD, DEBIT_CARD, MANDATE.
  final String instrument;
  final String? instrumentLast4;

  /// Local calendar date of the txn (date-only, midnight).
  final DateTime transactionDate;

  /// App bank pill: HDFC / ICICI / AXIS / SCAPIA / …
  final String bank;

  /// App card type: `CC` or `DB`. SMS never logs Cash.
  final String cardType;

  final String? referenceId;
  final double? balanceAfter;
  final String templateId;

  /// Original SMS. Kept for re-parse / review UI; never written to the
  /// expense row or sent off-device.
  final String rawBody;

  bool get hasMerchant => merchantRaw.trim().isNotEmpty;

  Map<String, dynamic> toQueueJson({
    required String id,
    required String sender,
    required int receivedAt,
  }) {
    return {
      'id': id,
      'sender': sender,
      'amount': amount,
      'merchantRaw': merchantRaw,
      'instrument': instrument,
      'instrumentLast4': instrumentLast4,
      'transactionDate': transactionDate.millisecondsSinceEpoch,
      'bank': bank,
      'cardType': cardType,
      'referenceId': referenceId,
      'balanceAfter': balanceAfter,
      'templateId': templateId,
      'receivedAt': receivedAt,
      'rawBody': rawBody,
    };
  }

  factory ParsedSmsDebit.fromQueueJson(Map<String, dynamic> json) {
    final ts = json['transactionDate'];
    DateTime date;
    if (ts is num) {
      date = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    } else {
      date = DateTime.tryParse(ts?.toString() ?? '') ?? DateTime.now();
    }
    final amountRaw = json['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString() ?? '') ?? 0;
    return ParsedSmsDebit(
      amount: amount,
      merchantRaw: (json['merchantRaw'] ?? '').toString(),
      instrument: (json['instrument'] ?? 'BANK_ACCOUNT').toString(),
      instrumentLast4: json['instrumentLast4']?.toString(),
      transactionDate: DateTime(date.year, date.month, date.day),
      bank: (json['bank'] ?? 'HDFC').toString(),
      cardType: (json['cardType'] ?? 'DB').toString(),
      referenceId: json['referenceId']?.toString(),
      balanceAfter: json['balanceAfter'] is num
          ? (json['balanceAfter'] as num).toDouble()
          : double.tryParse(json['balanceAfter']?.toString() ?? ''),
      templateId: (json['templateId'] ?? 'unmatched').toString(),
      rawBody: (json['rawBody'] ?? '').toString(),
    );
  }
}

class SmsPendingItem {
  const SmsPendingItem({
    required this.id,
    required this.sender,
    required this.debit,
    required this.receivedAt,
    this.status = 'pending',
  });

  final String id;
  final String sender;
  final ParsedSmsDebit debit;
  final int receivedAt;

  /// pending | approved | rejected | saved
  final String status;

  factory SmsPendingItem.fromJson(Map<String, dynamic> json) {
    return SmsPendingItem(
      id: (json['id'] ?? '').toString(),
      sender: (json['sender'] ?? '').toString(),
      debit: ParsedSmsDebit.fromQueueJson(json),
      receivedAt: json['receivedAt'] is num
          ? (json['receivedAt'] as num).toInt()
          : int.tryParse(json['receivedAt']?.toString() ?? '') ??
              DateTime.now().millisecondsSinceEpoch,
      status: (json['status'] ?? 'pending').toString(),
    );
  }
}
