export interface Expense {
  id: string;
  amount: number;
  description: string;
  category: string;
  bank: string;
  cardType: string;
  date: string;
  isManualCategory: boolean;
}

export type CategoryLearning = Record<string, string>;

export const BANKS = ['HDFC', 'ICICI', 'FEDERAL', 'Other'] as const;
export const CARD_TYPES = ['Debit Card', 'Credit Card', 'Cash'] as const;

export const CATEGORIES = [
  'Food', 'Grocery', 'Transport', 'Entertainment',
  'Shopping', 'Bills', 'Health', 'Others'
] as const;

export const CATEGORY_COLORS: Record<string, string> = {
  Food: '#FF6B6B',
  Grocery: '#51CF66',
  Transport: '#339AF0',
  Entertainment: '#CC5DE8',
  Shopping: '#FF922B',
  Bills: '#FCC419',
  Health: '#F06595',
  Others: '#868E96',
};

export const CATEGORY_ICONS: Record<string, string> = {
  Food: '🍽️',
  Grocery: '🛒',
  Transport: '🚗',
  Entertainment: '🎬',
  Shopping: '🛍️',
  Bills: '📄',
  Health: '💊',
  Others: '📦',
};

export const BANK_COLORS: Record<string, string> = {
  HDFC: '#004C8F',
  ICICI: '#B02A2A',
  FEDERAL: '#006B3C',
  Other: '#555',
};

export interface BudgetHistoryEntry {
  id: string;
  amount: number;
  setAt: string; // ISO date string
}