import 'sms_models.dart';

/// On-device debit SMS parser. Regex first (offline, instant); no network.
///
/// HDFC T1–T6 + T8 (UPI a/c debit), Axis card, ICICI card, Scapia/Federal
/// credit. T7 (`E-Mandate!` / `will be deducted`) is discarded *before* any
/// debit-keyword match. Credits, OTPs and promos return null.
class BankSmsParser {
  BankSmsParser._();

  static final _futureMandate = RegExp(
    r'will be deducted|E-Mandate!',
    caseSensitive: false,
  );
  static final _otp = RegExp(
    r'\bOTP\b|one[ -]?time password|verification code',
    caseSensitive: false,
  );
  /// Collect / request / failed alerts are not a completed spend. `\bsent\b`
  /// is a real HDFC T1 debit verb, so we cannot drop every "sent" — only
  /// request-shaped SMS (the Axis/HDFC UPI pair in the screenshot).
  static final _nonCompleted = RegExp(
    r'collect request|'
    r'payment request|'
    r'request to (?:pay|accept)|'
    r'requested (?:you |to pay|rs\.?|inr|₹)|'
    r'has requested|'
    r'\bto accept\b|'
    r'accept in (?:your )?upi|'
    r'tap to (?:pay|approve|accept)|'
    r'enter upi pin|'
    r'upi pin to|'
    r'approve (?:in|using|via|the)|'
    r'kindly (?:approve|accept)|'
    r'\bcollect of\b|'
    r'\bsent you\b|'
    r'has sent (?:you |rs\.?|inr|₹)|'
    r'being processed|under process|'
    r'\bdeclined\b|'
    r'\bfailed\b|'
    r'\bfailure\b|'
    r'unsuccessful|'
    r'\bcancelled\b|'
    r'\bcanceled\b|'
    r'\breversed\b|'
    r'insufficient funds|'
    r'not successful|'
    r'could not (?:be )?process|'
    r'\bexpired\b|'
    r'\binitiated\b|'
    r'pending (?:collect|request|payment)|'
    r'awaiting (?:payee|confirmation)|'
    r'waiting for|'
    r'mandate request',
    caseSensitive: false,
  );
  static final _credit = RegExp(
    r'\bcredited\b|\breceived\b|\bdeposited\b|\brefund(?:ed)?\b',
    caseSensitive: false,
  );
  static final _debitHint = RegExp(
    r'\bspent\b|\bsent\b|\btxn\b|\bdeducted\b|\bdebited\b|\bwithdrawn\b|'
    r'\bpaid\b|\bpurchase\b',
    caseSensitive: false,
  );

  static final _t1 = RegExp(
    r'Sent Rs\.?\s*([\d,]+(?:\.\d+)?)\s*'
    r'(?:F|f)rom HDFC Bank A[/]?[Cc]\s*\*?(\d{4}).*?'
    r'(?:T|t)o\s+(.+?)\s*'
    r'(?:On\s*)?(\d{2}/\d{2}/\d{2}).*?Ref\s+(\d+)',
    dotAll: true,
  );
  static final _t2 = RegExp(
    r'Txn Rs\.?\s*([\d,]+(?:\.\d+)?)\s*'
    r'On HDFC Bank Card\s+([xX]?\d{4})\s*'
    r'At\s+(.+?)\s*'
    r'by UPI\s+(\d+)\s*'
    r'On\s+(\d{2}-\d{2})',
    dotAll: true,
  );
  static final _t3t4 = RegExp(
    r'Spent Rs\.?\s*([\d,]+(?:\.\d+)?)\s+'
    r'(?:On|From)\s+HDFC Bank Card\s+[xX]?(\d{4})\s+'
    r'At\s+(.+?)\s+'
    r'On\s+(\d{4}-\d{2}-\d{2}:\d{2}:\d{2}:\d{2})'
    r'(?:\s+Bal\s+Rs\.?\s*([\d,]+(?:\.\d+)?))?',
  );
  static final _t5 = RegExp(
    r'Rs\.?\s*([\d,]+(?:\.\d+)?)\s+spent\s+on\s+HDFC Bank Card\s+[xX]?(\d{4})\s+'
    r'at\s+(.+?)\s+'
    r'on\s+(\d{4}-\d{2}-\d{2}:\d{2}:\d{2}:\d{2})'
    r'(?:\s+Avl bal:\s*([\d,]+(?:\.\d+)?))?',
    caseSensitive: false,
  );
  static final _t6 = RegExp(
    r'INR\s+([\d,]+(?:\.\d+)?)\s+deducted from HDFC Bank A/C No\s+(\d+)\s+'
    r'towards\s+(.+?)\s+UMRN',
    caseSensitive: false,
  );
  static final _t8 = RegExp(
    r'HDFC Bank:\s*Rs\.?\s*([\d,]+(?:\.\d+)?)\s+debited from a/c\s*\*?(\d{4})'
    r'\s+on\s+(\d{2}/\d{2}/\d{2})',
    caseSensitive: false,
  );
  static final _axis = RegExp(
    r'Spent\s+(?:INR|Rs\.?)\s*([\d,]+(?:\.\d+)?)\s+'
    r'Axis Bank Card no\.?\s*XX(\d{4})\s+'
    r'(\d{2}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s*IST\s+'
    r'(.+?)\s+Avl Limit',
    caseSensitive: false,
    dotAll: true,
  );
  static final _icici = RegExp(
    r'(?:Rs\.?|INR)\s*([\d,]+(?:\.\d+)?)\s+spent\s+(?:on|using)\s+'
    r'ICICI Bank Card\s+XX(\d{4})\s+on\s+(\d{2}-[A-Za-z]{3}-\d{2})\s+'
    r'(?:at|on)\s+(.+?)\.?\s*Avl',
    caseSensitive: false,
  );
  /// Unique Scapia spend shape. Currency may be ₹ / ₨ / Rs / INR, and a
  /// concatenated UCS-2 SMS often cuts off before "credit card".
  static final _scapia = RegExp(
    r'Your txn of\s*(?:(?:rs\.?|inr)\s*)?['
    '\u20b9\u20a8'
    r']?\s*([\d,]+(?:\.\d+)?)\s+at\s+(.+?)\s+on your\s+Scapia',
    caseSensitive: false,
    dotAll: true,
  );
  static final _blockCode = RegExp(
    r'SMS BLOCK (CC|DC)\s+(\d{4})',
    caseSensitive: false,
  );
  static final _genericAmount = RegExp(
    r'(?:rs\.?|inr|['
    '\u20b9\u20a8'
    r'])\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );
  static final _genericMerchant = RegExp(
    r'\b(?:at|to|towards)\s+(.+?)(?:\s+(?:by\b|on\b|ref\b|not\s+you|avl\b|'
    r'to\s+block|umrn\b)|$)',
    caseSensitive: false,
  );

  /// Returns a debit, or null when the message is not a completed spend.
  static ParsedSmsDebit? parse(
    String body, {
    required int smsReceivedAt,
    String? sender,
  }) {
    final text = normalizeSms(body);
    if (text.isEmpty) return null;
    if (_futureMandate.hasMatch(text)) return null;
    if (_otp.hasMatch(text)) return null;
    if (_nonCompleted.hasMatch(text)) return null;

    final block = _blockCode.firstMatch(text);
    final blockKind = block?.group(1)?.toUpperCase();
    final fromBlock = blockKind == 'CC'
        ? 'CREDIT_CARD'
        : blockKind == 'DC'
            ? 'DEBIT_CARD'
            : null;

    final t1 = _t1.firstMatch(text);
    if (t1 != null) {
      return _hdfc(
        amount: t1.group(1)!,
        last4: t1.group(2),
        merchant: t1.group(3)!,
        date: parseDdMmYy(t1.group(4)!, smsReceivedAt),
        ref: t1.group(5),
        instrument: 'BANK_ACCOUNT',
        cardType: 'DB',
        template: 'T1',
        body: text,
      );
    }

    final t2 = _t2.firstMatch(text);
    if (t2 != null) {
      final instrument = fromBlock ?? 'CREDIT_CARD';
      return _hdfc(
        amount: t2.group(1)!,
        last4: t2.group(2)!.replaceAll(RegExp(r'[xX]'), ''),
        merchant: t2.group(3)!,
        date: parseDdMmInferYear(t2.group(5)!, smsReceivedAt),
        ref: t2.group(4),
        instrument: instrument,
        cardType: instrument == 'CREDIT_CARD' ? 'CC' : 'DB',
        template: 'T2',
        body: text,
      );
    }

    final t34 = _t3t4.firstMatch(text) ?? _t5.firstMatch(text);
    if (t34 != null) {
      final instrument = fromBlock ?? 'CREDIT_CARD';
      final bal = t34.groupCount >= 5 ? t34.group(5) : null;
      return _hdfc(
        amount: t34.group(1)!,
        last4: t34.group(2),
        merchant: t34.group(3)!,
        date: parseIsoDateTime(t34.group(4)!),
        ref: null,
        instrument: instrument,
        cardType: instrument == 'CREDIT_CARD' ? 'CC' : 'DB',
        template: 'T3',
        body: text,
        balanceAfter: _num(bal),
      );
    }

    final t6 = _t6.firstMatch(text);
    if (t6 != null) {
      return _hdfc(
        amount: t6.group(1)!,
        last4: t6.group(2)!.length >= 4
            ? t6.group(2)!.substring(t6.group(2)!.length - 4)
            : t6.group(2),
        merchant: t6.group(3)!,
        date: DateTime.fromMillisecondsSinceEpoch(smsReceivedAt),
        ref: null,
        instrument: 'BANK_ACCOUNT',
        cardType: 'DB',
        template: 'T6',
        body: text,
      );
    }

    final t8 = _t8.firstMatch(text);
    if (t8 != null) {
      return _hdfc(
        amount: t8.group(1)!,
        last4: t8.group(2),
        merchant: 'UPI Transfer',
        date: parseDdMmYy(t8.group(3)!, smsReceivedAt),
        ref: null,
        instrument: 'BANK_ACCOUNT',
        cardType: 'DB',
        template: 'T8',
        body: text,
      );
    }

    final axis = _axis.firstMatch(text);
    if (axis != null) {
      return _hdfc(
        amount: axis.group(1)!,
        last4: axis.group(2),
        merchant: axis.group(5)!,
        date: parseDdMmYyLoose(axis.group(3)!, smsReceivedAt),
        ref: null,
        instrument: 'CREDIT_CARD',
        cardType: 'CC',
        template: 'AXIS',
        body: text,
        bank: 'AXIS',
      );
    }

    final icici = _icici.firstMatch(text);
    if (icici != null) {
      return _hdfc(
        amount: icici.group(1)!,
        last4: icici.group(2),
        merchant: icici.group(4)!,
        date: parseDdMonYy(icici.group(3)!, smsReceivedAt),
        ref: null,
        instrument: 'CREDIT_CARD',
        cardType: 'CC',
        template: 'ICICI',
        body: text,
        bank: 'ICICI',
      );
    }

    final scapia = _scapia.firstMatch(text);
    if (scapia != null) {
      return _hdfc(
        amount: scapia.group(1)!,
        last4: null,
        merchant: _cleanScapiaMerchant(scapia.group(2)!),
        date: DateTime.fromMillisecondsSinceEpoch(smsReceivedAt),
        ref: null,
        instrument: 'CREDIT_CARD',
        cardType: 'CC',
        template: 'SCAPIA',
        body: text,
        bank: 'SCAPIA',
      );
    }

    if (_credit.hasMatch(text) && !_debitHint.hasMatch(text)) return null;
    if (!_debitHint.hasMatch(text)) return null;

    return _generic(text, smsReceivedAt, sender, fromBlock);
  }

  /// Native queue can still hold a debit parsed by an older APK. Re-run
  /// current rules on [stored.rawBody]. Null means drop — never a spend.
  static ParsedSmsDebit? reconcileQueued(
    ParsedSmsDebit stored, {
    required int smsReceivedAt,
    String? sender,
  }) {
    if (stored.rawBody.trim().isEmpty) return stored;
    return parse(
      stored.rawBody,
      smsReceivedAt: smsReceivedAt,
      sender: sender,
    );
  }

  static ParsedSmsDebit? _generic(
    String text,
    int smsReceivedAt,
    String? sender,
    String? fromBlock,
  ) {
    final amt = _genericAmount.firstMatch(text);
    if (amt == null) return null;
    final amount = _num(amt.group(1));
    if (amount == null || amount <= 0) return null;

    String merchant = '';
    for (final m in _genericMerchant.allMatches(text.replaceAll('\n', ' '))) {
      final candidate = cleanMerchant(m.group(1) ?? '');
      if (candidate.length >= 2 && RegExp(r'[A-Za-z]').hasMatch(candidate)) {
        merchant = candidate;
        break;
      }
    }

    final bank = bankFrom(text, sender);
    final instrument = fromBlock ??
        (RegExp(r'block\s+cc|\bcredit\s*card\b', caseSensitive: false)
                .hasMatch(text)
            ? 'CREDIT_CARD'
            : 'BANK_ACCOUNT');
    return ParsedSmsDebit(
      amount: amount,
      merchantRaw: merchant,
      instrument: instrument,
      instrumentLast4: null,
      transactionDate: DateTime.fromMillisecondsSinceEpoch(smsReceivedAt),
      bank: bank,
      cardType: instrument == 'CREDIT_CARD' ? 'CC' : 'DB',
      templateId: 'GENERIC',
      rawBody: text,
    );
  }

  static ParsedSmsDebit? _hdfc({
    required String amount,
    required String? last4,
    required String merchant,
    required DateTime date,
    required String instrument,
    required String cardType,
    required String template,
    required String body,
    String bank = 'HDFC',
    String? ref,
    double? balanceAfter,
  }) {
    final n = _num(amount);
    if (n == null || n <= 0) return null;
    return ParsedSmsDebit(
      amount: n,
      merchantRaw: template == 'T8' ? 'UPI Transfer' : cleanMerchant(merchant),
      instrument: instrument,
      instrumentLast4: last4,
      transactionDate: DateTime(date.year, date.month, date.day),
      bank: bank,
      cardType: cardType,
      referenceId: ref,
      balanceAfter: balanceAfter,
      templateId: template,
      rawBody: body,
    );
  }

  static double? _num(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return double.tryParse(raw.replaceAll(',', ''));
  }

  /// Strip POS truncation (`..NAME_`) and tidy VPA / ALL-CAPS names.
  static String cleanMerchant(String raw) {
    var s = raw.trim();
    while (s.startsWith('.')) {
      s = s.substring(1).trim();
    }
    if (s.endsWith('_')) s = s.substring(0, s.length - 1).trim();
    s = s.replaceAll(RegExp(r'\s+\+\s*U[s]?\s*$'), '');
    s = s.replaceAll(RegExp(r'\s+\+\s*$'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return '';

    if (s.contains('@')) {
      // Spec: never invent a shop name from a bare handle. Only collapse
      // well-known UPI brands (paytm.xxx@ybl → Paytm). Opaque QRs stay as
      // the VPA so the merchant-learning cache can key off them.
      final local = s.split('@').first;
      final brand = local.split(RegExp(r'[.\d]')).first.trim().toLowerCase();
      const known = {
        'paytm',
        'phonepe',
        'gpay',
        'amazon',
        'bhim',
        'okbizaxis',
        'okicici',
        'okhdfcbank',
        'okaxis',
        'apl',
      };
      if (known.contains(brand)) {
        s = brand;
      } else {
        return s.toLowerCase();
      }
    }

    s = s.replaceAll(RegExp(r'\s*\.\s*'), '. ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w.length == 1
            ? w.toUpperCase()
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  static String bankFrom(String body, String? sender) {
    final hay = '${body.toLowerCase()} ${(sender ?? '').toLowerCase()}';
    if (hay.contains('hdfc')) return 'HDFC';
    if (hay.contains('icici')) return 'ICICI';
    if (hay.contains('axis')) return 'AXIS';
    if (hay.contains('scapia')) return 'SCAPIA';
    if (hay.contains('federal')) return 'SCAPIA';
    if (hay.contains('sbi') || hay.contains('state bank')) return 'HDFC';
    return 'HDFC';
  }

  static DateTime parseDdMmYy(String ddMmYy, int smsReceivedAt) {
    final p = ddMmYy.split('/');
    if (p.length != 3) {
      return DateTime.fromMillisecondsSinceEpoch(smsReceivedAt);
    }
    final d = int.tryParse(p[0]) ?? 1;
    final m = int.tryParse(p[1]) ?? 1;
    var y = int.tryParse(p[2]) ?? DateTime.now().year;
    if (y < 100) y += 2000;
    return DateTime(y, m, d);
  }

  static DateTime parseDdMmYyLoose(String raw, int smsReceivedAt) {
    return parseDdMmYy(raw.replaceAll('-', '/'), smsReceivedAt);
  }

  /// ICICI `09-Sep-26`.
  static DateTime parseDdMonYy(String raw, int smsReceivedAt) {
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final m = RegExp(r'^(\d{1,2})-([A-Za-z]{3})-(\d{2})$').firstMatch(raw.trim());
    if (m == null) {
      return DateTime.fromMillisecondsSinceEpoch(smsReceivedAt);
    }
    final d = int.tryParse(m.group(1)!) ?? 1;
    final month = months[m.group(2)!.toLowerCase()];
    var y = int.tryParse(m.group(3)!) ?? DateTime.now().year;
    if (y < 100) y += 2000;
    if (month == null) {
      return DateTime.fromMillisecondsSinceEpoch(smsReceivedAt);
    }
    return DateTime(y, month, d);
  }

  static String _cleanScapiaMerchant(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'\s+\+\s*U[s]?\s*$'), '');
    s = s.replaceAll(RegExp(r'\s+\+\s*$'), '');
    return s.trim();
  }

  /// Flatten NBSP / newlines / ₨ so live SMS matches the same templates
  /// as the UTF-8 fixtures in tests.
  static String normalizeSms(String body) {
    var s = body
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u202F', ' ')
        .replaceAll('\u2007', ' ')
        .replaceAll('\u2008', ' ')
        .replaceAll('\u2009', ' ')
        .replaceAll('\u0085', ' ')
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\u200B', '')
        .replaceAll('\uFEFF', '')
        .replaceAll('\u00AD', '')
        .replaceAll('\u20A8', '\u20B9')
        .replaceAll('\u00E2\u201A\u00B9', '\u20B9')
        .replaceAll('\u00E2\u0082\u00B9', '\u20B9');
    return s.trim().replaceAll(RegExp(r' {2,}'), ' ');
  }

  /// T2 `On 05-09` has no year — use the SMS receipt year, rolling back
  /// when the inferred date is more than two weeks in the future.
  static DateTime parseDdMmInferYear(String ddMm, int smsReceivedAt) {
    final p = ddMm.split('-');
    if (p.length != 2) {
      return DateTime.fromMillisecondsSinceEpoch(smsReceivedAt);
    }
    final d = int.tryParse(p[0]) ?? 1;
    final m = int.tryParse(p[1]) ?? 1;
    final received = DateTime.fromMillisecondsSinceEpoch(smsReceivedAt);
    var dt = DateTime(received.year, m, d);
    if (dt.difference(received).inDays > 14) {
      dt = DateTime(received.year - 1, m, d);
    }
    return dt;
  }

  /// HDFC's `YYYY-MM-DD:HH:MM:SS` (colon between date and time).
  static DateTime parseIsoDateTime(String raw) {
    final normalized = raw.replaceFirstMapped(
      RegExp(r'^(\d{4}-\d{2}-\d{2}):'),
      (m) => '${m[1]}T',
    );
    return DateTime.tryParse(normalized) ?? DateTime.now();
  }
}

/// Whether [sender] looks like an Indian bank / UPI alphanumeric ID.
bool isBankSender(String sender) {
  final n = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (n.isEmpty) return false;
  const tokens = [
    'HDFC',
    'ICICI',
    'AXIS',
    'SCAPIA',
    'SCPIA',
    'SCPCRD',
    'SBI',
    'KOTAK',
    'IDFC',
    'PAYTM',
    'CITI',
    'HSBC',
    'INDUS',
    'FEDERAL',
    'FEDBNK',
    'FEDBANK',
    'FEDADV',
    'FEDOTP',
    'FDRL',
    'CANBNK',
    'UNIONB',
    'PNBSMS',
    'BOBSMS',
    'YESBNK',
    'PNB',
    'BOB',
    'YESB',
    'IDBI',
    'UPI',
  ];
  return tokens.any(n.contains);
}

/// Native receiver gate. Known DLT headers pass. Card-spend bodies also
/// pass when the originating address is numeric, blank, or unknown.
bool smsShouldAccept(String sender, String body) {
  if (isBankSender(sender)) return true;
  return bodyLooksLikeBankDebit(body);
}

bool bodyLooksLikeScapiaOrFederal(String body) => bodyLooksLikeBankDebit(body);

bool bodyLooksLikeBankDebit(String body) {
  final hay = body.toLowerCase();
  if (hay.contains('on your scapia')) return true;
  if (hay.contains('scapia federal')) return true;
  if (RegExp(r'[-–—]\s*federal bank\s*$').hasMatch(hay.trim())) return true;
  if (hay.contains('axis bank')) return true;
  if (hay.contains('icici bank')) return true;
  if (hay.contains('hdfc bank')) return true;
  return false;
}

/// Stamp stored on auto-logged expenses.
String autoDetectedStamp(DateTime at) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final min = at.minute.toString().padLeft(2, '0');
  final ampm = at.hour >= 12 ? 'PM' : 'AM';
  return 'Auto Detected · ${at.day} ${months[at.month - 1]} ${at.year}, '
      '$hour:$min $ampm';
}
