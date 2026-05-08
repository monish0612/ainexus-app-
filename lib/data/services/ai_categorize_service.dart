import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/expense_entities.dart';

/// Single source of truth for keyword → category mapping.
/// Used by both [AICategorizeService] and the add-expense modal's local
/// categorizer. Do NOT duplicate this map elsewhere.
const Map<String, List<String>> keywordRules = {
  'Food': [
    'restaurant', 'cafe', 'coffee', 'lunch', 'dinner', 'breakfast', 'pizza',
    'burger', 'swiggy', 'zomato', 'food', 'eat', 'meal', 'snack', 'biryani',
    'curry', 'hotel', 'dosa', 'idli', 'paratha', 'chicken', 'mutton', 'fish',
    'dhaba', 'chai', 'tea', 'barbeque', 'bbq', 'sushi', 'pasta', 'sandwich',
    'bread', 'bakery', 'cake', 'dessert', 'ice cream', 'maggi', 'noodles',
    'cloud kitchen', 'tiffin', 'mess',
  ],
  'Grocery': [
    'grocery', 'vegetables', 'veggies', 'fruits', 'market', 'supermarket',
    'bigbasket', 'dmart', 'reliance fresh', 'milk', 'eggs', 'flour',
    'oil', 'masala', 'spices', 'dal', 'provisions', 'kirana',
    'zepto', 'blinkit', 'instamart', 'nature basket', 'grofers',
  ],
  'Transport': [
    'uber', 'ola', 'cab', 'taxi', 'bus', 'metro', 'train', 'auto',
    'rapido', 'namma', 'bmtc', 'parking', 'toll', 'ferry', 'rickshaw',
  ],
  'Fuel': [
    'fuel', 'petrol', 'diesel', 'bpcl', 'iocl', 'hpcl', 'petrol pump',
    'gas station', 'cng', 'ev charging', 'charging station',
  ],
  'Travel': [
    'flight', 'ticket', 'indigo', 'spicejet', 'airindia', 'vistara',
    'go air', 'interstate', 'irctc', 'makemytrip', 'goibibo', 'cleartrip',
    'yatra', 'booking.com', 'airbnb', 'oyo', 'hotel booking', 'resort',
    'travel', 'trip', 'vacation', 'holiday', 'airport',
  ],
  'Entertainment': [
    'movie', 'game', 'concert', 'show', 'cinema', 'theatre', 'arcade',
    'bowling', 'gaming', 'playstation', 'xbox', 'bookmyshow', 'pvr',
    'inox', 'amusement', 'theme park', 'waterpark',
  ],
  'Subscription': [
    'netflix', 'spotify', 'amazon prime', 'hotstar', 'youtube premium',
    'prime video', 'disney', 'zee5', 'sonyliv', 'apple music', 'gaana',
    'jio cinema', 'steam', 'subscription', 'premium', 'renewal',
    'annual plan', 'monthly plan',
  ],
  'Shopping': [
    'amazon', 'flipkart', 'mall', 'meesho', 'nykaa', 'purplle',
    'shopping', 'store', 'buy', 'purchase', 'order',
  ],
  'Electronics': [
    'electronics', 'gadget', 'phone', 'laptop', 'headphone', 'earphone',
    'tablet', 'computer', 'charger', 'cable', 'speaker', 'monitor',
    'keyboard', 'mouse', 'printer', 'camera', 'smartwatch', 'iphone',
    'samsung', 'oneplus', 'macbook', 'ipad', 'croma', 'reliance digital',
    'vijay sales',
  ],
  'Fashion': [
    'clothes', 'shoes', 'shirt', 'dress', 'pant', 'jeans', 'watch',
    'bag', 'apparel', 'fashion', 'accessories', 'myntra', 'ajio',
    'limeroad', 'saree', 'kurta', 'jacket', 'sneakers', 'sunglasses',
    'jewellery', 'jewelry', 'necklace', 'ring', 'bracelet',
  ],
  'Bills': [
    'electricity', 'water', 'gas', 'internet', 'broadband', 'recharge',
    'bill', 'bsnl', 'airtel', 'jio', 'vi', 'wifi', 'mobile', 'prepaid',
    'postpaid', 'utility', 'maintenance', 'society', 'cable', 'tata sky',
    'dish tv', 'bescom', 'mseb', 'tneb', 'adani electricity',
  ],
  'Rent': [
    'rent', 'house rent', 'flat rent', 'room rent', 'pg', 'hostel',
    'landlord', 'lease', 'security deposit',
  ],
  'Insurance': [
    'insurance', 'lic', 'policy', 'term plan', 'health insurance',
    'car insurance', 'bike insurance', 'life insurance', 'premium payment',
  ],
  'Loan': [
    'loan', 'emi', 'interest', 'mortgage', 'home loan', 'car loan',
    'personal loan', 'education loan', 'repayment', 'installment',
  ],
  'Health': [
    'pharmacy', 'gym', 'health', 'medplus', 'fitpass', 'cult', 'physio',
    'dental', 'optical', 'medicine', 'capsule', 'yoga', 'fitness',
    'protein', 'supplement', 'wellness', 'ayurveda',
  ],
  'Medical': [
    'hospital', 'doctor', 'clinic', 'apollo', 'diagnostic', 'lab',
    'test', 'consultation', 'surgery', 'operation', 'x-ray', 'mri',
    'scan', 'blood test', 'checkup', 'emergency', 'ambulance',
    'specialist', 'icu',
  ],
  'Education': [
    'school', 'college', 'university', 'course', 'tutorial', 'udemy',
    'coursera', 'book', 'notebook', 'tuition', 'class', 'study',
    'exam', 'certification', 'library', 'stationery', 'pen',
    'unacademy', 'byju', 'workshop', 'seminar',
  ],
  'Family': [
    'family', 'kids', 'children', 'baby', 'diaper', 'school fees',
    'daycare', 'parenting', 'toys', 'daughter', 'son', 'wife',
    'husband', 'parents', 'mother', 'father',
  ],
  'Friends': [
    'friends', 'party', 'treat', 'outing', 'hangout', 'reunion',
    'get together', 'celebration', 'pub', 'bar', 'drinks',
  ],
  'Personal': [
    'salon', 'haircut', 'grooming', 'spa', 'parlour', 'beauty',
    'skincare', 'self care', 'massage', 'laundry', 'dry clean',
    'tailor', 'personal',
  ],
  'Investment': [
    'mutual fund', 'sip', 'stocks', 'share', 'trading', 'investment',
    'nps', 'ppf', 'fixed deposit', 'fd', 'demat', 'zerodha',
    'groww', 'upstox', 'crypto', 'bitcoin', 'gold', 'bond',
  ],
  'Gifts': [
    'gift', 'present', 'birthday', 'anniversary', 'surprise',
    'wedding gift', 'christmas', 'diwali gift',
  ],
  'Charity': [
    'charity', 'ngo', 'donate', 'social cause', 'fundraiser',
    'crowdfunding', 'helpline',
  ],
  'Donation': [
    'temple', 'church', 'mosque', 'gurudwara', 'donation', 'religious',
    'offering', 'dakshina', 'pooja', 'puja',
  ],
  'Pets': [
    'pet', 'dog', 'cat', 'vet', 'veterinary', 'pet food', 'animal',
    'puppy', 'kitten', 'grooming', 'pet shop', 'aquarium',
  ],
};

/// Tokenize text the same way as the old `tokenise` helper.
List<String> tokenize(String text) {
  return text
      .toLowerCase()
      .split(RegExp(r'[\s,\-_/().]+'))
      .where((w) => w.length > 2)
      .toList();
}

/// Offline keyword categorizer — used for instant local classification
/// when the modal opens or text changes. No network call.
AICategoryResult categorizeLocal(
  String description,
  Map<String, String> learnings,
) {
  final trimmed = description.trim();
  if (trimmed.length < 2) {
    return const AICategoryResult(
      category: 'Others',
      confidence: 'default',
      reasoning: 'Description too short to classify',
      score: 0,
    );
  }

  final tokens = tokenize(trimmed);
  final fullText = trimmed.toLowerCase();

  final learnedVotes = <String, int>{};
  final matchedTokens = <String>[];
  for (final t in tokens) {
    final cat = learnings[t];
    if (cat != null) {
      learnedVotes[cat] = (learnedVotes[cat] ?? 0) + 1;
      matchedTokens.add(t);
    }
  }
  if (learnedVotes.isNotEmpty) {
    final top = learnedVotes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final c = top.first.key;
    return AICategoryResult(
      category: c,
      confidence: 'learned',
      reasoning:
          'AI remembered your correction — keyword "${matchedTokens.first}" → $c',
      score: 0.97,
    );
  }

  for (final e in keywordRules.entries) {
    final category = e.key;
    for (final keyword in e.value) {
      if (fullText.contains(keyword)) {
        return AICategoryResult(
          category: category,
          confidence: 'matched',
          reasoning: 'Detected merchant/keyword "$keyword" → $category',
          score: 0.82,
        );
      }
    }
  }

  return const AICategoryResult(
    category: 'Others',
    confidence: 'default',
    reasoning: 'No clear category signal — defaulting to Others',
    score: 0.3,
  );
}

class AICategorizeService {
  AICategorizeService(this._apiClient);

  final ApiClient _apiClient;

  final Connectivity _connectivity = Connectivity();

  Future<AICategoryResult> categorize(
    String description,
    Map<String, String> learnings, {
    String? liteModel,
  }) async {
    final trimmed = description.trim();
    if (trimmed.length < 2) {
      return const AICategoryResult(
        category: 'Others',
        confidence: 'default',
        reasoning: 'Description too short to classify',
        score: 0,
      );
    }

    // 1. Check user learnings
    final learned = _matchLearnings(trimmed, learnings);
    if (learned != null) return learned;

    // 2. Check keyword rules
    final keywordHit = _matchKeywordRules(trimmed);
    if (keywordHit != null) return keywordHit;

    // 3. LLM fallback (if online)
    if (await _hasNetwork()) {
      final llm = await _categorizeViaBackend(trimmed, liteModel: liteModel);
      if (llm != null) return llm;
    }

    return const AICategoryResult(
      category: 'Others',
      confidence: 'default',
      reasoning: 'No clear category signal — defaulting to Others',
      score: 0.3,
    );
  }

  Map<String, String> learnFromCorrection(
    String description,
    String category,
    Map<String, String> learnings,
  ) {
    final updated = Map<String, String>.from(learnings);
    final words = description
        .toLowerCase()
        .split(RegExp(r'[\s,\-_/]+'))
        .where((w) => w.length > 2)
        .toList();
    for (final word in words) {
      if (word.length > 3) {
        updated[word] = category;
      }
    }
    return updated;
  }

  /// Parse freeform text (voice) into structured expense via LLM.
  Future<SmartParseResult?> smartParse(
    String text, {
    String? liteModel,
  }) async {
    TLog.d('AICategorize', 'SmartParse → "${text.length > 60 ? '${text.substring(0, 60)}…' : text}"');
    try {
      final body = <String, dynamic>{'text': text};
      _addLiteModel(body, liteModel);
      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.aiSmartParse,
        data: body,
      );
      final data = response.data;
      if (data is! Map) {
        TLog.w('AICategorize', 'SmartParse empty/non-map response');
        return null;
      }
      final m = Map<String, dynamic>.from(data);
      TLog.i('AICategorize', 'SmartParse ✓ model=${m['model']} category=${m['category'] ?? 'Others'} amount=${m['amount']}');
      return SmartParseResult(
        amount: (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0,
        description: m['description']?.toString() ?? text,
        bank: m['bank']?.toString() ?? '',
        cardType: m['cardType']?.toString() ?? m['card_type']?.toString() ?? '',
        category: m['category']?.toString() ?? 'Others',
      );
    } on DioException catch (e, st) {
      TLog.e('AICategorize', 'SmartParse failed', error: e, st: st);
      return null;
    } catch (e, st) {
      TLog.e('AICategorize', 'SmartParse error', error: e, st: st);
      return null;
    }
  }

  AICategoryResult? _matchLearnings(
    String trimmed,
    Map<String, String> learnings,
  ) {
    final tokens = tokenize(trimmed);
    final learnedVotes = <String, int>{};
    final matchedLearningTokens = <String>[];
    for (final token in tokens) {
      final cat = learnings[token];
      if (cat != null) {
        learnedVotes[cat] = (learnedVotes[cat] ?? 0) + 1;
        matchedLearningTokens.add(token);
      }
    }
    if (learnedVotes.isEmpty) return null;

    final top = learnedVotes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final winner = top.first;
    return AICategoryResult(
      category: winner.key,
      confidence: 'learned',
      reasoning:
          'AI remembered your correction — keyword "${matchedLearningTokens.first}" → ${winner.key}',
      score: 0.97,
    );
  }

  AICategoryResult? _matchKeywordRules(String trimmed) {
    final fullText = trimmed.toLowerCase();
    for (final entry in keywordRules.entries) {
      final category = entry.key;
      for (final keyword in entry.value) {
        if (fullText.contains(keyword)) {
          return AICategoryResult(
            category: category,
            confidence: 'matched',
            reasoning: 'Detected merchant/keyword "$keyword" → $category',
            score: 0.82,
          );
        }
      }
    }
    return null;
  }

  Future<bool> _hasNetwork() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Adds the user-configured Gemini Lite model to [body] when [model] is
  /// non-empty. The backend uses this to pin the LiteLLM call to the exact
  /// flash/lite version the user selected in Settings (synced cross-device
  /// via user_preferences). When omitted the backend falls back to its
  /// auto-discovered model priority list.
  void _addLiteModel(Map<String, dynamic> body, String? model) {
    if (model == null) return;
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    body['liteModel'] = trimmed;
  }

  Future<AICategoryResult?> _categorizeViaBackend(
    String description, {
    String? liteModel,
  }) async {
    TLog.d('AICategorize', 'LLM categorize → "${description.length > 50 ? '${description.substring(0, 50)}…' : description}"');
    try {
      final body = <String, dynamic>{'description': description};
      _addLiteModel(body, liteModel);
      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.aiCategorize,
        data: body,
      );
      final data = response.data;
      if (data is! Map) {
        TLog.w('AICategorize', 'LLM categorize empty/non-map response');
        return null;
      }
      final map = Map<String, dynamic>.from(data);
      TLog.i('AICategorize', 'LLM categorize ✓ model=${map['model']} category=${map['category']}');
      return AICategoryResult.fromJson(map);
    } on DioException catch (e, st) {
      TLog.e('AICategorize', 'LLM categorize failed', error: e, st: st);
      return null;
    } catch (e, st) {
      TLog.e('AICategorize', 'LLM categorize parse error', error: e, st: st);
      return null;
    }
  }
}

/// Result from the /ai/smart-parse endpoint.
class SmartParseResult {
  const SmartParseResult({
    required this.amount,
    required this.description,
    required this.bank,
    required this.cardType,
    required this.category,
  });

  final double amount;
  final String description;
  final String bank;
  final String cardType;
  final String category;
}
