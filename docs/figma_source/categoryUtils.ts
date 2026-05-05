import type { CategoryLearning } from '../types/expense';

const KEYWORD_RULES: Record<string, string[]> = {
  Food: [
    'restaurant', 'cafe', 'coffee', 'lunch', 'dinner', 'breakfast', 'pizza',
    'burger', 'swiggy', 'zomato', 'food', 'eat', 'meal', 'snack', 'biryani',
    'curry', 'hotel', 'dosa', 'idli', 'paratha', 'chicken', 'mutton', 'fish',
    'dhaba', 'chai', 'tea', 'barbeque', 'bbq', 'sushi', 'pasta', 'sandwich',
    'bread', 'bakery', 'cake', 'dessert', 'ice cream', 'maggi', 'noodles',
  ],
  Grocery: [
    'grocery', 'vegetables', 'veggies', 'fruits', 'market', 'supermarket',
    'bigbasket', 'dmart', 'reliance', 'fresh', 'milk', 'eggs', 'flour',
    'oil', 'masala', 'spices', 'dal', 'provisions', 'store', 'kirana',
    'zepto', 'blinkit', 'instamart', 'nature basket',
  ],
  Transport: [
    'uber', 'ola', 'cab', 'taxi', 'fuel', 'petrol', 'diesel', 'bus', 'metro',
    'train', 'auto', 'travel', 'flight', 'ticket', 'rapido', 'namma',
    'bmtc', 'irctc', 'parking', 'toll', 'ferry', 'rickshaw', 'indigo',
    'spicejet', 'airindia', 'vistara', 'go air', 'interstate',
  ],
  Entertainment: [
    'movie', 'netflix', 'spotify', 'amazon prime', 'game', 'concert', 'show',
    'cinema', 'theatre', 'hotstar', 'youtube premium', 'prime video', 'disney',
    'zee5', 'sonyliv', 'arcade', 'bowling', 'stream', 'subscription', 'gaming',
    'steam', 'playstation', 'xbox', 'apple music', 'gaana', 'jio cinema',
  ],
  Shopping: [
    'amazon', 'flipkart', 'clothes', 'shoes', 'mall', 'myntra', 'meesho',
    'nykaa', 'shirt', 'dress', 'pant', 'jeans', 'watch', 'bag', 'apparel',
    'fashion', 'accessories', 'electronics', 'gadget', 'phone', 'laptop',
    'headphone', 'earphone', 'ajio', 'limeroad', 'purplle',
  ],
  Bills: [
    'electricity', 'water', 'gas', 'internet', 'broadband', 'recharge',
    'bill', 'rent', 'emi', 'insurance', 'bsnl', 'airtel', 'jio', 'vi',
    'wifi', 'mobile', 'prepaid', 'postpaid', 'utility', 'maintenance',
    'society', 'cable', 'tata sky', 'dish tv', 'loan', 'premium',
  ],
  Health: [
    'medicine', 'doctor', 'hospital', 'pharmacy', 'gym', 'health', 'medical',
    'clinic', 'apollo', 'medplus', 'fitpass', 'cult', 'physio', 'dental',
    'optical', 'tablet', 'capsule', 'diagnostic', 'lab', 'test', 'scan',
    'consultation', 'yoga', 'fitness', 'protein', 'supplement',
  ],
};

function extractKeywords(description: string): string[] {
  return description
    .toLowerCase()
    .split(/[\s,\-_/]+/)
    .filter(w => w.length > 2);
}

export function categorizeExpense(
  description: string,
  learnings: CategoryLearning
): { category: string; confidence: 'learned' | 'matched' | 'default' } {
  const words = extractKeywords(description);
  const fullText = description.toLowerCase();

  // First: check learned mappings
  const learnedCounts: Record<string, number> = {};
  for (const word of words) {
    if (learnings[word]) {
      learnedCounts[learnings[word]] = (learnedCounts[learnings[word]] || 0) + 1;
    }
  }

  if (Object.keys(learnedCounts).length > 0) {
    const top = Object.entries(learnedCounts).sort((a, b) => b[1] - a[1])[0][0];
    return { category: top, confidence: 'learned' };
  }

  // Then: keyword rules
  for (const [category, keywords] of Object.entries(KEYWORD_RULES)) {
    for (const keyword of keywords) {
      if (fullText.includes(keyword)) {
        return { category, confidence: 'matched' };
      }
    }
  }

  return { category: 'Others', confidence: 'default' };
}

export function learnFromCorrection(
  description: string,
  category: string,
  learnings: CategoryLearning
): CategoryLearning {
  const words = extractKeywords(description);
  const updated = { ...learnings };
  for (const word of words) {
    if (word.length > 3) {
      updated[word] = category;
    }
  }
  return updated;
}

export function formatCurrency(amount: number): string {
  const abs = Math.abs(amount);
  const formatted = new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    maximumFractionDigits: 2,
    minimumFractionDigits: 0,
  }).format(abs);
  return amount < 0 ? `-${formatted}` : formatted;
}

export function formatDate(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (diffDays === 0) return 'Today';
  if (diffDays === 1) return 'Yesterday';
  if (diffDays < 7) return `${diffDays} days ago`;

  return date.toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: date.getFullYear() !== now.getFullYear() ? 'numeric' : undefined,
  });
}

export function formatTime(dateStr: string): string {
  return new Date(dateStr).toLocaleTimeString('en-IN', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  });
}
