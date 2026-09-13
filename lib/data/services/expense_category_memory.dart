import '../../domain/entities/expense_entities.dart';

/// Device-local exact VPA / merchant → category. Keyword memory is the
/// synced `category_learnings` table. Keep the string identical everywhere.
const kSmsMerchantLabelsKey = 'sms_merchant_labels';

/// Fast, offline merchant memory. Teach AI and SMS auto-detect share this
/// so `email@firstcry.com` trains **firstcry**, not a dead full-handle token
/// that the categorizer then splits apart and never finds.
///
/// No I/O. A handful of map lookups on a short string.
class ExpenseCategoryMemory {
  ExpenseCategoryMemory._();

  static const _tlds = {
    'com',
    'net',
    'org',
    'in',
    'co',
    'io',
    'app',
    'shop',
    'store',
    'info',
    'biz',
  };

  /// UPI PSP hosts — never treat these as a shop brand.
  static const _psp = {
    'ybl',
    'ibl',
    'axl',
    'apl',
    'upi',
    'paytm',
    'okaxis',
    'okicici',
    'okhdfcbank',
    'okhdfc',
    'okbizaxis',
    'oksbi',
    'yesbank',
    'kotak',
    'sbi',
    'pnb',
    'axisbank',
    'hdfcbank',
    'icici',
  };

  static const _genericLocals = {
    'email',
    'mail',
    'info',
    'pay',
    'upi',
    'user',
    'care',
    'support',
    'online',
    'shop',
    'store',
    'official',
    'noreply',
    'admin',
    'billing',
    'payments',
    'accounts',
    'finance',
    'order',
    'orders',
    'hello',
    'contact',
  };

  static const _months = {
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  };

  /// Words that would poison every later SMS if saved as a category key.
  static const stopwords = {
    'the',
    'and',
    'for',
    'from',
    'with',
    'this',
    'that',
    'your',
    'you',
    'www',
    'http',
    'https',
    'ltd',
    'pvt',
    'private',
    'limited',
    'india',
    'inc',
    'payment',
    'paid',
    'via',
    'upi',
    'txn',
    'bank',
    'ref',
    'sms',
    'block',
    'auto',
    'detected',
    'not',
  };

  /// SMS auto-log rows (id prefix or the Auto Detected stamp).
  static bool isSmsOrigin(Expense e) {
    if (e.id.startsWith('sms-') || e.id.startsWith('sample-')) return true;
    return '${e.comments} ${e.description}'.contains('Auto Detected');
  }

  static bool isTeachable(String description) => keysFor(description).isNotEmpty;

  /// Ordered keys: exact handle first, then domain, then brand, then tokens.
  /// First learned hit wins — specific before generic.
  static List<String> keysFor(String description) {
    final raw = description.trim();
    if (raw.isEmpty) return const [];
    if (raw.toLowerCase().startsWith('auto detected')) return const [];
    final out = <String>[];
    void add(String s) {
      final k = s.trim().toLowerCase();
      if (k.length < 3) return;
      if (stopwords.contains(k) ||
          _tlds.contains(k) ||
          _genericLocals.contains(k) ||
          _months.contains(k)) {
        return;
      }
      if (RegExp(r'^\d+$').hasMatch(k)) return;
      if (!out.contains(k)) out.add(k);
    }

    add(raw);
    final compact = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9@.]'), '');
    if (compact.contains('@')) {
      add(compact);
      final at = compact.split('@');
      final local = at.first;
      var host = at.length > 1 ? at[1] : '';
      if (host.startsWith('www.')) host = host.substring(4);
      final hostCore = host.split('.').first;
      final psp = _psp.contains(host) || _psp.contains(hostCore);
      if (!psp && host.isNotEmpty) {
        add(host);
        for (final p in host.split('.')) {
          add(p);
        }
      }
      if (local.length >= 4 &&
          !_genericLocals.contains(local) &&
          !RegExp(r'\d').hasMatch(local)) {
        add(local);
      }
    } else {
      if (compact.length >= 4 && compact != raw.toLowerCase()) add(compact);
      for (final t in raw.toLowerCase().split(RegExp(r'[\s,\-_/().@]+'))) {
        add(t);
      }
    }
    return out;
  }

  /// Exact VPA only — never a brand token (those belong in synced learnings).
  static void rememberExact(
    Map<String, String> labels,
    String merchant,
    String category,
  ) {
    final t = merchant.trim();
    final cat = category.trim();
    if (t.isEmpty || cat.isEmpty || cat == 'Others') return;
    labels[t] = cat;
    labels[t.toLowerCase()] = cat;
  }

  static String? lookupLabel(String merchant, Map<String, String> labels) {
    if (labels.isEmpty) return null;
    final raw = merchant.trim();
    if (raw.isEmpty) return null;
    final direct = labels[raw] ?? labels[raw.toLowerCase()];
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    for (final k in keysFor(raw)) {
      final hit = labels[k];
      if (hit != null && hit.trim().isNotEmpty) return hit.trim();
    }
    return null;
  }

  static ({String category, String key})? matchLearned(
    String description,
    Map<String, String> learnings,
  ) {
    if (learnings.isEmpty) return null;
    for (final k in keysFor(description)) {
      final cat = learnings[k];
      if (cat != null && cat.trim().isNotEmpty) {
        return (category: cat.trim(), key: k);
      }
    }
    return null;
  }
}
