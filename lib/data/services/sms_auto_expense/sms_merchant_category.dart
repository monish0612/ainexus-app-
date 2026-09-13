import '../../../domain/entities/expense_entities.dart';
import '../ai_categorize_service.dart';
import '../expense_category_memory.dart';

/// Offline merchant → category for SMS auto-log.
///
/// Order: [labels] (user-taught VPA/name) → [learnings] + [keywordRules]
/// (same table the add-expense form uses) → extra SMS aliases → Others.
/// Never calls the network.
String suggestSmsCategory(
  String merchant, {
  Map<String, String> labels = const {},
  CategoryLearning learnings = const {},
}) {
  final raw = merchant.trim();
  if (raw.isEmpty) return 'Others';

  final labeled = ExpenseCategoryMemory.lookupLabel(raw, labels);
  if (labeled != null) return labeled;

  final hay = raw.toLowerCase();
  if (hay.contains('amazon') && hay.contains('irctc')) return 'Travel';
  if (_smsGrocery.any((k) => hay.contains(k))) return 'Grocery';
  // "Bharat Petr" contains "pet" and would otherwise become Pets.
  if (_smsAliases['Fuel']!.any((k) => hay.contains(k))) return 'Fuel';
  // "Sundaram Medical" used to hit Health first because that alias
  // list was scanned before Medical.
  if (_looksLikeMedical(hay)) return 'Medical';

  final local = categorizeLocal(raw, learnings);
  if (local.confidence != 'default') return local.category;

  for (final e in _smsAliases.entries) {
    if (e.value.any((k) => hay.contains(k))) return e.key;
  }

  if (hay == 'upi transfer') return 'Others';
  if (_looksLikePersonName(raw)) return 'Personal';
  return 'Others';
}

const _smsGrocery = [
  'blinkit',
  'instamart',
  'santhosh super',
  'grace super',
  'dmart',
];

const Map<String, List<String>> _smsAliases = {
  'Grocery': [
    'blinkit',
    'instamart',
    'santhosh super',
    'grace super',
    'dmart',
  ],
  'Food': ['swiggy', 'zomato', 'payzomato'],
  'Shopping': ['amazon', 'reliance trends', 'twin birds'],
  'Travel': ['irctc', 'toll plaza'],
  'Medical': [
    'sundaram medical',
    'apollo',
    'hospital',
    'clinic',
    'diagnostic',
  ],
  'Health': ['cult', 'fitpass', 'gym'],
  'Subscription': [
    'googlecloud',
    'hostinger',
    'google cloud',
    'google play',
    'anthropic',
    'claude',
    'cursor',
  ],
  'Fuel': ['bharat petr', 'star fuel', 'bharat petroleum'],
  'Insurance': ['hdfc life', 'godigit', 'go digit'],
  'Rent': ['nobroker'],
  'Donation': ['tirumala', 'tirupathi', 'tirupati'],
};

bool _looksLikeMedical(String hay) {
  const needles = [
    'medical',
    'clinic',
    'diagnostic',
    'pharma',
    'pharmacy',
    'apollo',
  ];
  if (needles.any(hay.contains)) return true;
  // Word-bounded so "hospitality" (hotels) does not become Medical.
  return RegExp(r'(^|[^a-z])hospital([^a-z]|$)').hasMatch(hay);
}

bool _looksLikePersonName(String raw) {
  if (raw.contains('@') || RegExp(r'\d').hasMatch(raw)) return false;
  final words = raw
      .split(RegExp(r'\s+'))
      .where((w) => w.replaceAll('.', '').isNotEmpty)
      .toList();
  if (words.length < 2) return false;
  return words.every((w) => RegExp(r'^[A-Za-z.]+$').hasMatch(w));
}
