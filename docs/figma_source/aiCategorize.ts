/**
 * aiCategorize.ts
 * ─────────────────────────────────────────────────────────────────────────
 * UNIFIED AI categorization pipeline.
 *
 * Both the SCAN flow (bill image → extracted description → here) and the
 * MANUAL flow (user types description → here) go through this single async
 * function.  The function returns a structured result that mirrors what a
 * real LLM API would return, so swapping to Gemini / GPT later is a
 * one-file change.
 *
 * Current engine: rule-based keyword inference + localStorage learnings.
 * To use a real LLM, replace the body of `callInferencePipeline()` with
 * your API call and keep the return shape identical.
 * ─────────────────────────────────────────────────────────────────────────
 */

import type { CategoryLearning } from '../types/expense';

export interface AICategoryResult {
  category: string;
  confidence: 'learned' | 'matched' | 'default';
  /** Short human-readable reasoning for the UI ("Detected keyword: swiggy → Food") */
  reasoning: string;
  /** 0–1 score */
  score: number;
}

// ── Keyword rules (acts as the LLM's internal knowledge base) ────────────
const KEYWORD_RULES: Record<string, string[]> = {
  Food: [
    'restaurant', 'cafe', 'coffee', 'lunch', 'dinner', 'breakfast', 'pizza',
    'burger', 'swiggy', 'zomato', 'food', 'eat', 'meal', 'snack', 'biryani',
    'curry', 'hotel', 'dosa', 'idli', 'paratha', 'chicken', 'mutton', 'fish',
    'dhaba', 'chai', 'tea', 'barbeque', 'bbq', 'sushi', 'pasta', 'sandwich',
    'bread', 'bakery', 'cake', 'dessert', 'ice cream', 'maggi', 'noodles',
    'cloud kitchen', 'tiffin', 'mess',
  ],
  Grocery: [
    'grocery', 'vegetables', 'veggies', 'fruits', 'market', 'supermarket',
    'bigbasket', 'dmart', 'reliance', 'fresh', 'milk', 'eggs', 'flour',
    'oil', 'masala', 'spices', 'dal', 'provisions', 'store', 'kirana',
    'zepto', 'blinkit', 'instamart', 'nature basket', 'grofers',
  ],
  Transport: [
    'uber', 'ola', 'cab', 'taxi', 'fuel', 'petrol', 'diesel', 'bus', 'metro',
    'train', 'auto', 'travel', 'flight', 'ticket', 'rapido', 'namma', 'bmtc',
    'irctc', 'parking', 'toll', 'ferry', 'rickshaw', 'indigo', 'spicejet',
    'airindia', 'vistara', 'go air', 'interstate', 'bpcl', 'iocl', 'hpcl',
  ],
  Entertainment: [
    'movie', 'netflix', 'spotify', 'amazon prime', 'game', 'concert', 'show',
    'cinema', 'theatre', 'hotstar', 'youtube premium', 'prime video', 'disney',
    'zee5', 'sonyliv', 'arcade', 'bowling', 'stream', 'subscription', 'gaming',
    'steam', 'playstation', 'xbox', 'apple music', 'gaana', 'jio cinema',
    'bookmyshow', 'pvr', 'inox',
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
    'society', 'cable', 'tata sky', 'dish tv', 'loan', 'premium', 'bescom',
    'mseb', 'tneb', 'adani electricity',
  ],
  Health: [
    'medicine', 'doctor', 'hospital', 'pharmacy', 'gym', 'health', 'medical',
    'clinic', 'apollo', 'medplus', 'fitpass', 'cult', 'physio', 'dental',
    'optical', 'tablet', 'capsule', 'diagnostic', 'lab', 'test',
    'consultation', 'yoga', 'fitness', 'protein', 'supplement',
  ],
};

function tokenise(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[\s,\-_/().]+/)
    .filter(w => w.length > 2);
}

/**
 * Core inference — replace this function body to plug in a real LLM.
 *
 * Expected return shape stays the same regardless of implementation.
 */
async function callInferencePipeline(
  description: string,
  learnings: CategoryLearning,
): Promise<AICategoryResult> {
  // Simulate async latency (real LLM round-trip would be ~300-800 ms)
  await new Promise(r => setTimeout(r, 420 + Math.random() * 180));

  const tokens = tokenise(description);
  const fullText = description.toLowerCase();

  // ── Step 1: Check user-taught learnings (highest priority) ────────────
  const learnedVotes: Record<string, number> = {};
  const matchedLearningTokens: string[] = [];
  for (const token of tokens) {
    if (learnings[token]) {
      learnedVotes[learnings[token]] = (learnedVotes[learnings[token]] || 0) + 1;
      matchedLearningTokens.push(token);
    }
  }
  if (Object.keys(learnedVotes).length > 0) {
    const top = Object.entries(learnedVotes).sort((a, b) => b[1] - a[1])[0];
    return {
      category: top[0],
      confidence: 'learned',
      reasoning: `AI remembered your correction — keyword "${matchedLearningTokens[0]}" → ${top[0]}`,
      score: 0.97,
    };
  }

  // ── Step 2: Keyword rule matching ─────────────────────────────────────
  for (const [category, keywords] of Object.entries(KEYWORD_RULES)) {
    for (const keyword of keywords) {
      if (fullText.includes(keyword)) {
        return {
          category,
          confidence: 'matched',
          reasoning: `Detected merchant/keyword "${keyword}" → ${category}`,
          score: 0.82,
        };
      }
    }
  }

  // ── Step 3: Fallback ──────────────────────────────────────────────────
  return {
    category: 'Others',
    confidence: 'default',
    reasoning: 'No clear category signal — defaulting to Others',
    score: 0.3,
  };
}

/**
 * Public API — the single entry point used by BOTH scan and manual flows.
 *
 * Usage:
 *   const result = await aiCategorize("Swiggy Order", learnings);
 *   // → { category: "Food", confidence: "matched", reasoning: "...", score: 0.82 }
 */
export async function aiCategorize(
  description: string,
  learnings: CategoryLearning,
): Promise<AICategoryResult> {
  if (!description || description.trim().length < 2) {
    return {
      category: 'Others',
      confidence: 'default',
      reasoning: 'Description too short to classify',
      score: 0,
    };
  }
  return callInferencePipeline(description.trim(), learnings);
}
