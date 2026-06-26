import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.bg4,
    required this.text,
    required this.text2,
    required this.text3,
    required this.text4,
    required this.text5,
    required this.border,
    required this.border2,
    required this.headerBg,
    required this.navBg,
    required this.shadowColor,
    required this.glassFill,
    required this.scrim,
    required this.cardGradientTop,
    required this.cardGradientBottom,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.isDark,
  });

  final Color bg;
  final Color bg1;
  final Color bg2;
  final Color bg3;
  final Color bg4;
  final Color text;
  final Color text2;
  final Color text3;
  final Color text4;
  final Color text5;
  final Color border;
  final Color border2;
  final Color headerBg;
  final Color navBg;

  /// Drop-shadow color for elevated cards/sheets. Soft cool slate on white so
  /// surfaces lift without the harsh pure-black look.
  final Color shadowColor;

  /// Frosted/glass overlay fill used for blurred surfaces and pills.
  final Color glassFill;

  /// Barrier/scrim color painted behind modal sheets and dialogs.
  final Color scrim;

  /// Subtle elevated-surface gradient (top → bottom).
  final Color cardGradientTop;
  final Color cardGradientBottom;

  /// Loading skeleton shimmer base + highlight.
  final Color shimmerBase;
  final Color shimmerHighlight;

  final bool isDark;

  static const dark = AppColors(
    bg: Color(0xFF000000),
    bg1: Color(0xFF060608),
    bg2: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    bg3: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    bg4: Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
    text: Color(0xFFF1F5F9),
    text2: Color(0xFF94A3B8),
    text3: Color(0x6BFFFFFF), // rgba(255,255,255,0.42)
    text4: Color(0x47FFFFFF), // rgba(255,255,255,0.28)
    text5: Color(0x2EFFFFFF), // rgba(255,255,255,0.18)
    border: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    border2: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    headerBg: Color(0xFF000000),
    navBg: Color(0xF8000000), // rgba(0,0,0,0.97)
    shadowColor: Color(0x66000000), // rgba(0,0,0,0.4)
    glassFill: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    scrim: Color(0x99000000), // rgba(0,0,0,0.6)
    cardGradientTop: Color(0xFF0B0B0F),
    cardGradientBottom: Color(0xFF060608),
    shimmerBase: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    shimmerHighlight: Color(0x2EFFFFFF), // rgba(255,255,255,0.18)
    isDark: true,
  );

  static const white = AppColors(
    bg: Color(0xFFFFFFFF),
    bg1: Color(0xFFF8FAFC),
    bg2: Color(0x0A000000), // rgba(0,0,0,0.04)
    bg3: Color(0x0F000000), // rgba(0,0,0,0.06)
    bg4: Color(0x17000000), // rgba(0,0,0,0.09)
    text: Color(0xFF0F172A),
    text2: Color(0xFF475569),
    text3: Color(0x8C000000), // rgba(0,0,0,0.55)
    text4: Color(0x61000000), // rgba(0,0,0,0.38)
    text5: Color(0x40000000), // rgba(0,0,0,0.25)
    border: Color(0x17000000), // rgba(0,0,0,0.09)
    border2: Color(0x0F000000), // rgba(0,0,0,0.06)
    headerBg: Color(0xFFFFFFFF),
    navBg: Color(0xF8FFFFFF), // rgba(255,255,255,0.97)
    // Soft cool-slate shadow so cards lift on white without a heavy black halo.
    shadowColor: Color(0x14101828), // rgba(16,24,40,0.08)
    glassFill: Color(0xCCFFFFFF), // rgba(255,255,255,0.8) frosted
    scrim: Color(0x52101828), // rgba(16,24,40,0.32)
    cardGradientTop: Color(0xFFFFFFFF),
    cardGradientBottom: Color(0xFFF8FAFC),
    shimmerBase: Color(0x0F000000), // rgba(0,0,0,0.06)
    shimmerHighlight: Color(0x05000000), // rgba(0,0,0,0.02)
    isDark: false,
  );

  // Accent blue used across settings, buttons, profile ring
  static const accent = Color(0xFF0D59F2);
  static const accentCyan = Color(0xFF22D3EE);

  // Category colors (from expense.ts CATEGORY_COLORS)
  static const categoryFood = Color(0xFFFF6B6B);
  static const categoryGrocery = Color(0xFF51CF66);
  static const categoryTransport = Color(0xFF339AF0);
  static const categoryEntertainment = Color(0xFFCC5DE8);
  static const categoryShopping = Color(0xFFFF922B);
  static const categoryBills = Color(0xFFFCC419);
  static const categoryHealth = Color(0xFFF06595);
  static const categoryOthers = Color(0xFF868E96);
  static const categoryFuel = Color(0xFFFF8787);
  static const categoryTravel = Color(0xFF74C0FC);
  static const categorySubscription = Color(0xFF9775FA);
  static const categoryElectronics = Color(0xFF38D9A9);
  static const categoryFashion = Color(0xFFE599F7);
  static const categoryMedical = Color(0xFFE03131);
  static const categoryEducation = Color(0xFF4DABF7);
  static const categoryFamily = Color(0xFFFFD43B);
  static const categoryFriends = Color(0xFF69DB7C);
  static const categoryPersonal = Color(0xFF748FFC);
  static const categoryInvestment = Color(0xFF20C997);
  static const categoryRent = Color(0xFFFFA94D);
  static const categoryInsurance = Color(0xFFE64980);
  static const categoryGifts = Color(0xFFDA77F2);
  static const categoryCharity = Color(0xFFF76707);
  static const categoryDonation = Color(0xFF845EF7);
  static const categoryPets = Color(0xFF3BC9DB);
  static const categoryLoan = Color(0xFFFAB005);

  // Category emoji icons (from expense.ts CATEGORY_ICONS)
  static const categoryIcons = <String, String>{
    'Food': '🍽️',
    'Grocery': '🛒',
    'Transport': '🚗',
    'Entertainment': '🎬',
    'Shopping': '🛍️',
    'Bills': '📄',
    'Health': '💊',
    'Fuel': '⛽',
    'Travel': '✈️',
    'Subscription': '📱',
    'Electronics': '💻',
    'Fashion': '👗',
    'Medical': '🏥',
    'Education': '📚',
    'Family': '👨‍👩‍👧',
    'Friends': '🤝',
    'Personal': '👤',
    'Investment': '📈',
    'Rent': '🏠',
    'Insurance': '🛡️',
    'Gifts': '🎁',
    'Charity': '❤️',
    'Donation': '🙏',
    'Pets': '🐾',
    'Loan': '💰',
    'Others': '📦',
  };

  static const categoryColors = <String, Color>{
    'Food': categoryFood,
    'Grocery': categoryGrocery,
    'Transport': categoryTransport,
    'Entertainment': categoryEntertainment,
    'Shopping': categoryShopping,
    'Bills': categoryBills,
    'Health': categoryHealth,
    'Fuel': categoryFuel,
    'Travel': categoryTravel,
    'Subscription': categorySubscription,
    'Electronics': categoryElectronics,
    'Fashion': categoryFashion,
    'Medical': categoryMedical,
    'Education': categoryEducation,
    'Family': categoryFamily,
    'Friends': categoryFriends,
    'Personal': categoryPersonal,
    'Investment': categoryInvestment,
    'Rent': categoryRent,
    'Insurance': categoryInsurance,
    'Gifts': categoryGifts,
    'Charity': categoryCharity,
    'Donation': categoryDonation,
    'Pets': categoryPets,
    'Loan': categoryLoan,
    'Others': categoryOthers,
  };

  // Bank colors (from expense.ts BANK_COLORS)
  static const bankColors = <String, Color>{
    'HDFC': Color(0xFF004C8F),
    'ICICI': Color(0xFFB02A2A),
    'AXIS': Color(0xFF800020),
    'SCAPIA': Color(0xFF6366F1),
    'CASH': Color(0xFF22C55E),
  };

  // Bank palette for settings (from settingsContext.tsx)
  static const bankPalette = <Color>[
    Color(0xFF0D59F2),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFDC2626),
    Color(0xFFD97706),
    Color(0xFF0891B2),
    Color(0xFF9333EA),
    Color(0xFF0F766E),
    Color(0xFFBE185D),
  ];

  // Cloud Hub colors
  static const vaultCyan = Color(0xFF00E6E6);
  static const vaultCyanLight = Color(0xFFC1FFFE);
  static const vaultPurple = Color(0xFFD575FF);
  static const vaultBlue = Color(0xFF63BAFF);

  @override
  AppColors copyWith({
    Color? bg,
    Color? bg1,
    Color? bg2,
    Color? bg3,
    Color? bg4,
    Color? text,
    Color? text2,
    Color? text3,
    Color? text4,
    Color? text5,
    Color? border,
    Color? border2,
    Color? headerBg,
    Color? navBg,
    Color? shadowColor,
    Color? glassFill,
    Color? scrim,
    Color? cardGradientTop,
    Color? cardGradientBottom,
    Color? shimmerBase,
    Color? shimmerHighlight,
    bool? isDark,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      bg1: bg1 ?? this.bg1,
      bg2: bg2 ?? this.bg2,
      bg3: bg3 ?? this.bg3,
      bg4: bg4 ?? this.bg4,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      text4: text4 ?? this.text4,
      text5: text5 ?? this.text5,
      border: border ?? this.border,
      border2: border2 ?? this.border2,
      headerBg: headerBg ?? this.headerBg,
      navBg: navBg ?? this.navBg,
      shadowColor: shadowColor ?? this.shadowColor,
      glassFill: glassFill ?? this.glassFill,
      scrim: scrim ?? this.scrim,
      cardGradientTop: cardGradientTop ?? this.cardGradientTop,
      cardGradientBottom: cardGradientBottom ?? this.cardGradientBottom,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      bg1: Color.lerp(bg1, other.bg1, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      bg3: Color.lerp(bg3, other.bg3, t)!,
      bg4: Color.lerp(bg4, other.bg4, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      text4: Color.lerp(text4, other.text4, t)!,
      text5: Color.lerp(text5, other.text5, t)!,
      border: Color.lerp(border, other.border, t)!,
      border2: Color.lerp(border2, other.border2, t)!,
      headerBg: Color.lerp(headerBg, other.headerBg, t)!,
      navBg: Color.lerp(navBg, other.navBg, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      cardGradientTop: Color.lerp(cardGradientTop, other.cardGradientTop, t)!,
      cardGradientBottom:
          Color.lerp(cardGradientBottom, other.cardGradientBottom, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
