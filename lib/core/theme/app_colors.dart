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
    // Role tokens added after the palette shipped. They default to the dark
    // values so the dozens of hand-built `AppColors(...)` literals in the
    // widget tests keep compiling; `dark` and `white` below still pass every
    // one of them explicitly.
    this.modeLite = const Color(0xFF22D3EE),
    this.modeDeep = const Color(0xFF8B5CF6),
    this.modeThinking = const Color(0xFFF5B62C),
    this.providerXgrok = const Color(0xFF94A3B8),
    this.accentText = const Color(0xFF5B8CFF),
    this.danger = const Color(0xFFEF4444),
    this.warning = const Color(0xFFF59E0B),
    this.success = const Color(0xFF34D399),
    this.listening = const Color(0xFFF87171),
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

  // ── Mode identity (Lite / Deep / Thinking) ─────────────────────────────
  //
  // No single hex clears AA text contrast on BOTH #000000 and #FFFFFF — the
  // luminance window is under one percentage point wide — so each mode ships
  // a per-theme pair. Use these when the mode name is *text*; use the
  // `mode*Edge` statics below for borders, focus rings and other non-text.

  /// Lite / live / sync. 11.62:1 on black, 5.36:1 on white.
  final Color modeLite;

  /// Deep research. 4.96:1 on black, 5.70:1 on white.
  final Color modeDeep;

  /// Thinking (xGrok only). 11.61:1 on black, 4.92:1 on white.
  final Color modeThinking;

  /// xGrok provider identity: deliberately FLAT slate, drawn with angular
  /// corners. Gemini is a rounded gradient ([geminiGradient]) so the two read
  /// as different providers in grayscale, not just by hue.
  final Color providerXgrok;

  /// Blue for *text* and icons. [accent] is the CTA fill only — it is
  /// 3.73:1 on black, which fails as text. 6.64:1 / 5.63:1 as this pair.
  final Color accentText;

  /// Destructive / failure. 5.58:1 on black, 4.83:1 on white.
  final Color danger;

  /// Caution, price-watch, rate limits. 9.78:1 on black, 5.02:1 on white.
  final Color warning;

  /// Confirmation. 10.92:1 on black, 5.48:1 on white.
  final Color success;

  /// Live microphone / hold-to-speak. Distinct from [danger] on purpose —
  /// recording is a state, not a failure. 7.59:1 on black, 6.29:1 on white.
  final Color listening;

  final bool isDark;

  static const dark = AppColors(
    bg: Color(0xFF000000),
    bg1: Color(0xFF060608),
    bg2: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    bg3: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    bg4: Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
    text: Color(0xFFF1F5F9),
    text2: Color(0xFF94A3B8),
    text3: Color(0x99FFFFFF), // white @ 0.60 — 7.37:1 on #000000
    text4: Color(0x78FFFFFF), // white @ 0.47 — 4.76:1 on #000000
    text5: Color(0x5CFFFFFF), // white @ 0.36 — 3.14:1, non-text only
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
    modeLite: Color(0xFF22D3EE), // 11.62:1
    modeDeep: Color(0xFF8B5CF6), // 4.96:1
    modeThinking: Color(0xFFF5B62C), // 11.61:1
    providerXgrok: Color(0xFF94A3B8), // 8.19:1
    accentText: Color(0xFF5B8CFF), // 6.64:1
    danger: Color(0xFFEF4444), // 5.58:1
    warning: Color(0xFFF59E0B), // 9.78:1
    success: Color(0xFF34D399), // 10.92:1
    listening: Color(0xFFF87171), // 7.59:1
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
    text3: Color(0xA8000000), // black @ 0.66 — 7.23:1 on #FFFFFF
    text4: Color(0x8C000000), // black @ 0.55 — 4.74:1 on #FFFFFF
    text5: Color(0x6E000000), // black @ 0.43 — 3.15:1, non-text only
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
    modeLite: Color(0xFF0E7490), // 5.36:1
    modeDeep: Color(0xFF7C3AED), // 5.70:1
    modeThinking: Color(0xFFA16207), // 4.92:1
    providerXgrok: Color(0xFF475569), // 7.58:1
    accentText: Color(0xFF0D59F2), // 5.63:1
    danger: Color(0xFFDC2626), // 4.83:1
    warning: Color(0xFFB45309), // 5.02:1
    success: Color(0xFF047857), // 5.48:1
    listening: Color(0xFFBE123C), // 6.29:1
    isDark: false,
  );

  // Accent blue used across settings, buttons, profile ring.
  // CTA FILL ONLY — 3.73:1 on #000000 fails as text. For blue text or icons
  // read `AppColors.of(context).accentText` instead.
  static const accent = Color(0xFF0D59F2);
  static const accentCyan = Color(0xFF22D3EE);

  /// Sugar for the usual `Theme.of(context).extension<AppColors>()!`.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  // ── Mode edges (non-text) ───────────────────────────────────────────────
  //
  // Single hexes that clear the 3:1 non-text threshold on BOTH #000000 and
  // #FFFFFF, so borders, focus rings and dividers need no per-theme branch.
  static const modeLiteEdge = Color(0xFF0891B2); // 5.70 / 3.68
  static const modeDeepEdge = Color(0xFF7D67C1); // 4.58 / 4.58
  static const modeThinkingEdge = Color(0xFF9A6C3F); // 4.59 / 4.57

  // ── Provider identity ───────────────────────────────────────────────────
  //
  // Gemini = rounded/radial GRADIENT. xGrok = angular FLAT slate
  // (`providerXgrok`). The gradient-vs-flat and round-vs-angular contrast
  // survives grayscale, so the two never rely on hue alone. Neither uses
  // [accent] — that stays reserved for the CTA.
  static const geminiGradientStart = Color(0xFF4F8DF7);
  static const geminiGradientEnd = Color(0xFF8B5CF6);
  static const geminiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[geminiGradientStart, geminiGradientEnd],
  );

  /// Radial form of [geminiGradient], for orbs and avatars.
  static const geminiRadialGradient = RadialGradient(
    center: Alignment(-0.3, -0.4),
    radius: 1.1,
    colors: <Color>[geminiGradientStart, geminiGradientEnd],
  );

  // ── Legacy identity hexes, promoted out of inline literals ──────────────
  //
  // Kept as statics so existing call sites can migrate to a named token
  // without a visual change. Prefer the theme-extension fields above for
  // anything that must lerp across a theme switch.
  static const geminiBlue = Color(0xFF4285F4);
  static const xgrokRed = Color(0xFFE8453C);
  static const deepViolet = Color(0xFFC084FC);
  static const composerGradientStart = Color(0xFF6366F1);
  static const composerGradientEnd = Color(0xFF8B5CF6);
  static const dangerRed = Color(0xFFEF4444);
  static const listeningRed = Color(0xFFF87171);
  static const warningAmber = Color(0xFFF59E0B);
  static const successGreen = Color(0xFF34D399);

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
    Color? modeLite,
    Color? modeDeep,
    Color? modeThinking,
    Color? providerXgrok,
    Color? accentText,
    Color? danger,
    Color? warning,
    Color? success,
    Color? listening,
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
      modeLite: modeLite ?? this.modeLite,
      modeDeep: modeDeep ?? this.modeDeep,
      modeThinking: modeThinking ?? this.modeThinking,
      providerXgrok: providerXgrok ?? this.providerXgrok,
      accentText: accentText ?? this.accentText,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      listening: listening ?? this.listening,
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
      modeLite: Color.lerp(modeLite, other.modeLite, t)!,
      modeDeep: Color.lerp(modeDeep, other.modeDeep, t)!,
      modeThinking: Color.lerp(modeThinking, other.modeThinking, t)!,
      providerXgrok: Color.lerp(providerXgrok, other.providerXgrok, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      listening: Color.lerp(listening, other.listening, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
