import 'package:flutter/foundation.dart';

/// Mirrors block types from `NewsData.ts` — content is the primary payload;
/// [label] is optional (e.g. quote attribution `"Name, Role"` or stat description).
@immutable
class ArticleBlock {
  const ArticleBlock({
    required this.type,
    required this.content,
    this.label,
  });

  /// `'paragraph' | 'heading' | 'quote' | 'stat'`
  final String type;
  final String content;
  final String? label;
}

@immutable
class Article {
  const Article({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.source,
    required this.category,
    required this.imageUrl,
    required this.readTime,
    required this.date,
    required this.blocks,
    this.summaryMarkdown,
    this.summaryShort,
    this.originalUrl,
    this.tag,
    this.timeAgo,
    this.isFeatured = false,
    this.publishedAt,
    this.isSaved = false,
    this.isRead = false,
    this.isFullContent = false,
  });

  final String id;
  final String title;
  final String excerpt;
  final String source;
  final String category;
  final String imageUrl;
  final int readTime;
  final String date;
  final List<ArticleBlock> blocks;
  final String? summaryMarkdown;

  /// AI-generated 1-2 sentence quick summary (Gemini 2.5 Flash Lite).
  /// Populated by the For You "Summarize" batch flow and cached in SQLite.
  final String? summaryShort;
  final String? originalUrl;
  final String? tag;
  final String? timeAgo;
  final bool isFeatured;
  final DateTime? publishedAt;
  final bool isSaved;
  final bool isRead;

  /// `true` when this article carries the FULL original article body (no AI
  /// summarization) and should be rendered in the interactive reader by
  /// default, with AI summarization offered as an explicit on-demand action.
  ///
  /// Driven by the backend `isFullContent` flag (feeds flagged
  /// `skip_summary`). Falls back to a [kNoSummarizeCategories] membership
  /// check in the repository so the existing Movies/General feeds behave
  /// identically before the backend starts emitting the flag.
  final bool isFullContent;

  Article copyWith({
    String? id,
    String? title,
    String? excerpt,
    String? source,
    String? category,
    String? imageUrl,
    int? readTime,
    String? date,
    List<ArticleBlock>? blocks,
    String? summaryMarkdown,
    String? summaryShort,
    String? originalUrl,
    String? tag,
    String? timeAgo,
    bool? isFeatured,
    DateTime? publishedAt,
    bool? isSaved,
    bool? isRead,
    bool? isFullContent,
  }) {
    return Article(
      id: id ?? this.id,
      title: title ?? this.title,
      excerpt: excerpt ?? this.excerpt,
      source: source ?? this.source,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      readTime: readTime ?? this.readTime,
      date: date ?? this.date,
      blocks: blocks ?? this.blocks,
      summaryMarkdown: summaryMarkdown ?? this.summaryMarkdown,
      summaryShort: summaryShort ?? this.summaryShort,
      originalUrl: originalUrl ?? this.originalUrl,
      tag: tag ?? this.tag,
      timeAgo: timeAgo ?? this.timeAgo,
      isFeatured: isFeatured ?? this.isFeatured,
      publishedAt: publishedAt ?? this.publishedAt,
      isSaved: isSaved ?? this.isSaved,
      isRead: isRead ?? this.isRead,
      isFullContent: isFullContent ?? this.isFullContent,
    );
  }
}

/// Filter chips (excluding **All**).
// ignore: constant_identifier_names — matches React `NewsData` export name.
const List<String> CATEGORIES = [
  'Finance',
  'AI News',
  'Movies',
  'General',
];

/// Category → hex color (parse to [Color] in presentation).
// ignore: constant_identifier_names — matches React `NewsData` export name.
const Map<String, String> CAT_COLOR = {
  'Finance': '#10B981',
  'AI News': '#F59E0B',
  'Movies': '#EC4899',
  'General': '#38BDF8',
};

/// Categories that ship the FULL original article body (no AI summarization).
///
/// These feeds are intentionally excluded from:
///   1. The **All** chip's "unread" feed in the For You tab — they get
///      their own dedicated chips and should not blend into the generic
///      pile.
///   2. The For You speed-dial FAB **Summarize / Clear All** when scope is
///      "All categories" — the catch-up summarize flow is designed for
///      AI-condensed articles, not for full long-form reading.
///
/// The follow-up chat / save / mark-read / dedup paths are completely
/// unaffected — those work identically regardless of category.
// ignore: constant_identifier_names — convention matches CATEGORIES/CAT_COLOR.
const Set<String> kNoSummarizeCategories = <String>{
  'Movies',
  'General',
};

/// Mock feed (6 categories + 8 articles).
const List<Article> mockArticles = [
  Article(
    id: 'news-001',
    title: 'Quantum leap: New AI model decodes complex proteins in seconds',
    excerpt:
        'Researchers unveil a model that resolves protein structures 1,000x faster than existing tools, potentially revolutionizing drug discovery timelines.',
    source: 'Tech Pulse',
    category: 'Technology',
    imageUrl:
        'https://images.unsplash.com/photo-1717501219345-06ea2bf3eb80?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    readTime: 4,
    date: 'Mar 20, 2026',
    isFeatured: true,
    timeAgo: '4 days ago',
    blocks: [
      ArticleBlock(
        type: 'paragraph',
        content:
            'A team at Stanford\'s Computational Biology Lab has released ProteoAI-2, a transformer-based model capable of decoding the three-dimensional structure of previously uncharacterized proteins in under two seconds — a task that once consumed weeks of supercomputer time.',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'The breakthrough hinges on a novel attention mechanism the team calls "geometric folding attention," which encodes physical constraints directly into the model architecture rather than treating protein folding as a pure sequence prediction problem.',
      ),
      ArticleBlock(
        type: 'heading',
        content: 'A New Paradigm in Drug Discovery',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'Pharmaceutical companies have already begun licensing the model. Analysts estimate that reducing early-stage target identification from 3 years to under 6 months could shave hundreds of crores off the average drug development cost.',
      ),
      ArticleBlock(
        type: 'quote',
        content:
            'We\'re not just accelerating drug discovery — we\'re fundamentally changing what questions we can ask about life itself.',
        label: 'Dr. Sarah Chen, Lead Researcher, Stanford',
      ),
      ArticleBlock(
        type: 'heading',
        content: 'The Road Ahead',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'ProteoAI-2 is available under a research license on the project\'s GitHub repository. The team plans to release an enterprise API in Q2 2026 with support for custom fine-tuning on proprietary datasets.',
      ),
      ArticleBlock(type: 'stat', content: '99.9%', label: 'Structure accuracy'),
      ArticleBlock(type: 'stat', content: '<2s', label: 'Per protein'),
      ArticleBlock(type: 'stat', content: '18K+', label: 'Proteins solved'),
    ],
  ),
  Article(
    id: 'news-002',
    title: 'Market rally continues as central banks signal potential rate cuts',
    excerpt:
        'Global equities hit a 14-month high after Fed Chair signals a June rate cut is "on the table," sending major indices sharply higher in a single session.',
    source: 'Global Markets',
    category: 'Finance',
    imageUrl:
        'https://images.unsplash.com/photo-1767424196045-030bbde122a4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    readTime: 3,
    date: 'Mar 20, 2026',
    timeAgo: '4 days ago',
    blocks: [
      ArticleBlock(
        type: 'paragraph',
        content:
            'Stock markets surged worldwide on Thursday after Federal Reserve Chair Jerome Powell hinted in Congressional testimony that a rate reduction in June remains a live possibility, provided inflation data continues its downward trajectory.',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'Major indices added strongly, and European markets posted their best single-day gains in months. Bond yields fell sharply as investors rotated into risk assets.',
      ),
      ArticleBlock(
        type: 'quote',
        content:
            'The market is finally pricing in a Goldilocks scenario — moderate growth, cooling inflation, and accommodative central banks.',
        label: 'Marcus Webb, Chief Strategist, Barclays',
      ),
      ArticleBlock(
        type: 'heading',
        content: 'Sector Rotation in Focus',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'Technology and real estate led the charge, while defensive sectors like utilities lagged. Emerging market funds recorded strong inflows, suggesting renewed appetite for risk.',
      ),
      ArticleBlock(type: 'stat', content: '+2.4%', label: 'Nifty 50 session'),
      ArticleBlock(type: 'stat', content: '+3.1%', label: 'IT index'),
      ArticleBlock(type: 'stat', content: '3.94%', label: '10Y US yield'),
    ],
  ),
  Article(
    id: 'news-003',
    title: 'Advanced encryption: How AI is defending against quantum attacks',
    excerpt:
        'NIST finalizes post-quantum cryptography standards, and a new wave of AI-powered key-management systems is already deploying them at enterprise scale.',
    source: 'Tech Pulse',
    category: 'Technology',
    imageUrl:
        'https://images.unsplash.com/photo-1761496847215-46592435aab0?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    readTime: 5,
    date: 'Mar 20, 2026',
    timeAgo: '4 days ago',
    blocks: [
      ArticleBlock(
        type: 'paragraph',
        content:
            'The U.S. National Institute of Standards and Technology officially finalized its first set of post-quantum cryptographic (PQC) standards this week, marking the end of a decade-long standardization effort and triggering an urgent migration cycle for government and financial systems.',
      ),
      ArticleBlock(
        type: 'heading',
        content: 'Why Classical Encryption Is Vulnerable',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'Today\'s RSA and ECC encryption rely on mathematical problems that would take classical computers millions of years to break. Quantum computers running Shor\'s algorithm could solve these problems in hours once hardware matures sufficiently.',
      ),
      ArticleBlock(
        type: 'quote',
        content:
            'The threat isn\'t theoretical anymore. Adversaries are harvesting encrypted data today to decrypt it once quantum hardware is viable — a strategy called "harvest now, decrypt later."',
        label: 'Ravi Shankar, CISO, Axis Bank',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'Major security vendors have announced PQC-native endpoint products. Analysts expect the market for quantum-safe security software to grow rapidly through 2028.',
      ),
      ArticleBlock(type: 'stat', content: '4', label: 'NIST standards'),
      ArticleBlock(type: 'stat', content: '\$12B', label: 'Market by 2028'),
      ArticleBlock(type: 'stat', content: '2031', label: 'Estimated Q-day'),
    ],
  ),
  Article(
    id: 'news-004',
    title:
        'Frontier model achieves human-level reasoning on dozens of benchmarks',
    excerpt:
        'A new enterprise-grade model scores above 90th-percentile human performance across mathematics, coding, scientific reasoning, and legal analysis.',
    source: 'AI Insider',
    category: 'AI & ML',
    imageUrl:
        'https://images.unsplash.com/photo-1760629863094-5b1e8d1aae74?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    readTime: 4,
    date: 'Mar 20, 2026',
    timeAgo: '4 days ago',
    blocks: [
      ArticleBlock(
        type: 'paragraph',
        content:
            'The lab released its newest frontier model to enterprise customers on Thursday, posting benchmark results that outpace prior generations on standard evaluations. The model achieves scores in the 90th percentile of human performance on graduate-level mathematics, competitive programming, and bar exam simulations.',
      ),
      ArticleBlock(
        type: 'heading',
        content: 'Benchmarks Shattered',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'On graduate-level science benchmarks, the model scored 87.4%. Its coding performance on real software engineering tasks reached 62.3%, nearly double the previous state of the art.',
      ),
      ArticleBlock(
        type: 'quote',
        content:
            'This is the first time we\'ve seen a model genuinely surprise our internal experts — not just on narrow tasks, but on open-ended reasoning chains they hadn\'t anticipated.',
        label: 'Demis Hassabis, CEO, Google DeepMind',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'The model is available via cloud APIs starting today, with aggressive per-token pricing relative to its predecessor.',
      ),
      ArticleBlock(type: 'stat', content: '87.4%', label: 'GPQA Diamond'),
      ArticleBlock(type: 'stat', content: '62.3%', label: 'SWE-Bench'),
      ArticleBlock(type: 'stat', content: '43/50', label: 'SOTA benchmarks'),
    ],
  ),
  Article(
    id: 'news-005',
    title: 'How cities are turning concrete into carbon sinks by 2030',
    excerpt:
        'A new generation of bio-concrete, living walls, and AI-managed green corridors is transforming urban infrastructure from carbon sources into net-negative emitters.',
    source: 'Green World',
    category: 'Climate',
    imageUrl:
        'https://images.unsplash.com/photo-1761662826910-3a2480223933?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    readTime: 6,
    date: 'Mar 19, 2026',
    timeAgo: '5 days ago',
    blocks: [
      ArticleBlock(
        type: 'paragraph',
        content:
            'Singapore\'s forest-town pilots, Paris\'s ring-road retrofit, and Copenhagen\'s harbor biomes represent a seismic shift in urban design philosophy: cities are no longer simply managing their carbon footprint — they\'re engineering it negative.',
      ),
      ArticleBlock(
        type: 'heading',
        content: 'The Science of Bio-Concrete',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'Pioneered at Delft University, bio-concrete embeds bacteria that synthesize limestone when exposed to water, self-sealing cracks and capturing atmospheric CO₂ in the process.',
      ),
      ArticleBlock(
        type: 'quote',
        content:
            'Every square meter of bio-concrete absorbs roughly 2.8 kg of CO₂ per year over a 50-year lifespan. At city scale, that\'s not incremental — it\'s transformative.',
        label: 'Dr. Priya Nair, Urban Climate Lead, C40 Cities',
      ),
      ArticleBlock(
        type: 'heading',
        content: 'AI-Managed Green Corridors',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'Barcelona\'s AI-driven superblock project uses real-time sensor data to irrigate rooftop farms and living facades only when soil moisture, temperature, and wind conditions maximize carbon uptake.',
      ),
      ArticleBlock(type: 'stat', content: '2.8kg', label: 'CO₂/m²/year'),
      ArticleBlock(type: 'stat', content: '34%', label: 'Water saved'),
      ArticleBlock(type: 'stat', content: '67', label: 'Cities enrolled'),
    ],
  ),
  Article(
    id: 'news-006',
    title: 'Starship completes first fully-reusable orbital flight milestone',
    excerpt:
        'Both the Super Heavy booster and Ship upper stage returned to their launch towers, completing the first fully reusable orbital round-trip in spaceflight history.',
    source: 'Space Watch',
    category: 'Science',
    imageUrl:
        'https://images.unsplash.com/photo-1597331139945-615efe8f4b04?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    readTime: 3,
    date: 'Mar 19, 2026',
    timeAgo: '5 days ago',
    blocks: [
      ArticleBlock(
        type: 'paragraph',
        content:
            'The operator achieved a historic milestone when both stages completed a full orbital mission and returned intact to their launch towers — the first demonstration of complete, unmodified vehicle reuse in orbital spaceflight history.',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'The mission carried a pathfinder payload validating critical propellant transfer technology required for deep-space missions.',
      ),
      ArticleBlock(
        type: 'quote',
        content:
            'Today we demonstrated that fully reusable orbital rockets are not a dream. They are operational hardware. This changes everything about what\'s economically possible in space.',
        label: 'Elon Musk, CEO, SpaceX',
      ),
      ArticleBlock(type: 'stat', content: '8 min', label: 'Booster return'),
      ArticleBlock(type: 'stat', content: '100%', label: 'Stage reuse'),
      ArticleBlock(type: 'stat', content: '\$50/kg', label: 'Target LEO cost'),
    ],
  ),
  Article(
    id: 'news-007',
    title: 'CRISPR trial shows 94% remission in late-stage blood cancers',
    excerpt:
        'Phase III data from a joint academic trial shows unprecedented response rates for CRISPR-edited CAR-T therapy in patients who had failed all prior treatments.',
    source: 'MedBreak',
    category: 'Health',
    imageUrl:
        'https://images.unsplash.com/photo-1583912086005-ac9abca6c9db?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    readTime: 5,
    date: 'Mar 19, 2026',
    timeAgo: '5 days ago',
    blocks: [
      ArticleBlock(
        type: 'paragraph',
        content:
            'A Phase III clinical trial involving 312 patients with relapsed or refractory diffuse large B-cell lymphoma found that CRISPR-edited CAR-T cells achieved complete remission in 94% of participants — a rate that far exceeds the 40–60% seen with conventional CAR-T products.',
      ),
      ArticleBlock(
        type: 'heading',
        content: 'How the Editing Works',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'The therapy uses base editing to knock out the T-cell exhaustion gene TET2 and simultaneously introduce a synthetic promoter that sustains CAR expression over time.',
      ),
      ArticleBlock(
        type: 'quote',
        content:
            'We treated patients who had exhausted every available option. Ninety-four percent is not an incremental improvement — it is a redefinition of what late-stage cancer treatment can look like.',
        label: 'Dr. James Wright, Oncology Lead, UCSF',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'Regulators have granted Breakthrough Therapy designation. A Biologics License Application is expected by Q4 2026.',
      ),
      ArticleBlock(type: 'stat', content: '94%', label: 'Complete remission'),
      ArticleBlock(type: 'stat', content: '312', label: 'Patients treated'),
      ArticleBlock(type: 'stat', content: 'Q1 27', label: 'Expected launch'),
    ],
  ),
  Article(
    id: 'news-008',
    title: 'Bitcoin breaks \$120K as spot ETF inflows hit weekly record',
    excerpt:
        'Bitcoin crossed \$120,000 for the first time as institutional ETFs absorbed billions in weekly inflows, the largest since launch.',
    source: 'Crypto Daily',
    category: 'Finance',
    imageUrl:
        'https://images.unsplash.com/photo-1694219782948-afcab5c095d3?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    readTime: 3,
    date: 'Mar 18, 2026',
    timeAgo: '6 days ago',
    blocks: [
      ArticleBlock(
        type: 'paragraph',
        content:
            'Bitcoin surpassed \$120,000 in Asian trading, driven by a record-breaking week of institutional inflows into U.S. spot Bitcoin ETFs.',
      ),
      ArticleBlock(
        type: 'paragraph',
        content:
            'The rally has been attributed to a confluence of factors: recent central-bank signals, the upcoming halving cycle, and growing corporate treasury adoption.',
      ),
      ArticleBlock(
        type: 'quote',
        content:
            'Bitcoin at \$120K is the market pricing in a world where every major sovereign wealth fund has a 1–3% allocation. That day is closer than most people realize.',
        label: 'Cathie Wood, CEO, ARK Invest',
      ),
      ArticleBlock(type: 'stat', content: '\$120K', label: 'BTC price'),
      ArticleBlock(type: 'stat', content: '\$2.1B', label: 'Weekly inflows'),
      ArticleBlock(type: 'stat', content: '+34%', label: 'Month-to-date'),
    ],
  ),
];
