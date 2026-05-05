export type BlockType = 'paragraph' | 'heading' | 'quote' | 'stat';

export interface ArticleBlock {
  type: BlockType;
  text?: string;
  author?: string;
  role?: string;
  items?: { value: string; label: string }[];
}

export interface Article {
  id: string;
  title: string;
  category: string;
  tag?: 'Breaking' | 'Trending' | 'Exclusive';
  readTime: number;
  timeAgo: string;
  date: string;
  image: string;
  excerpt: string;
  source: string;
  isFeatured?: boolean;
  content: ArticleBlock[];
}

export const CATEGORIES = ['All', 'Tech', 'Finance', 'AI Labs', 'Global', 'Health'] as const;

export const CAT_COLOR: Record<string, string> = {
  Tech:         '#6366F1',
  Finance:      '#34D399',
  'AI Labs':    '#A78BFA',
  Global:       '#F59E0B',
  Health:       '#EC4899',
  Cybersecurity:'#6366F1',
  Space:        '#60A5FA',
  Crypto:       '#F59E0B',
};

export const ARTICLES: Article[] = [
  {
    id: 'art-001',
    title: 'Quantum leap: New AI model decodes complex proteins in seconds',
    category: 'Tech',
    tag: 'Breaking',
    readTime: 4,
    timeAgo: '12 min ago',
    date: 'Mar 20, 2026',
    image: 'https://images.unsplash.com/photo-1717501219345-06ea2bf3eb80?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    excerpt: 'Researchers unveil a model that resolves protein structures 1,000x faster than existing tools, potentially revolutionizing drug discovery timelines.',
    source: 'Tech Pulse',
    isFeatured: true,
    content: [
      { type: 'paragraph', text: 'A team at Stanford\'s Computational Biology Lab has released ProteoAI-2, a transformer-based model capable of decoding the three-dimensional structure of previously uncharacterized proteins in under two seconds — a task that once consumed weeks of supercomputer time.' },
      { type: 'paragraph', text: 'The breakthrough hinges on a novel attention mechanism the team calls "geometric folding attention," which encodes physical constraints directly into the model architecture rather than treating protein folding as a pure sequence prediction problem.' },
      { type: 'heading', text: 'A New Paradigm in Drug Discovery' },
      { type: 'paragraph', text: 'Pharmaceutical companies have already begun licensing the model. Analysts at Goldman Sachs estimate that reducing early-stage target identification from 3 years to under 6 months could shave $800 million off the average drug development cost.' },
      { type: 'quote', text: 'We\'re not just accelerating drug discovery — we\'re fundamentally changing what questions we can ask about life itself.', author: 'Dr. Sarah Chen', role: 'Lead Researcher, Stanford' },
      { type: 'heading', text: 'The Road Ahead' },
      { type: 'paragraph', text: 'ProteoAI-2 is available under a research license on the project\'s GitHub repository. The team plans to release an enterprise API in Q2 2026 with support for custom fine-tuning on proprietary datasets.' },
      { type: 'stat', items: [{ value: '99.9%', label: 'Structure accuracy' }, { value: '<2s', label: 'Per protein' }, { value: '18K+', label: 'Proteins solved' }] },
    ],
  },
  {
    id: 'art-002',
    title: 'Market rally continues as central banks signal potential rate cuts',
    category: 'Finance',
    readTime: 3,
    timeAgo: '28 min ago',
    date: 'Mar 20, 2026',
    image: 'https://images.unsplash.com/photo-1767424196045-030bbde122a4?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    excerpt: 'Global equities hit a 14-month high after Fed Chair signals a June rate cut is "on the table," sending the S&P 500 up 2.4% in a single session.',
    source: 'Global Markets',
    content: [
      { type: 'paragraph', text: 'Stock markets surged worldwide on Thursday after Federal Reserve Chair Jerome Powell hinted in Congressional testimony that a rate reduction in June remains a live possibility, provided inflation data continues its downward trajectory.' },
      { type: 'paragraph', text: 'The S&P 500 added 2.4%, the Nasdaq Composite rose 3.1%, and European indices posted their best single-day gains since November 2024. Bond yields fell sharply, with the 10-year Treasury dropping 18 basis points to 3.94%.' },
      { type: 'quote', text: 'The market is finally pricing in a Goldilocks scenario — moderate growth, cooling inflation, and accommodative central banks.', author: 'Marcus Webb', role: 'Chief Strategist, Barclays' },
      { type: 'heading', text: 'Sector Rotation in Focus' },
      { type: 'paragraph', text: 'Technology and real estate led the charge, while defensive sectors like utilities lagged. Emerging market ETFs recorded their highest single-day inflows of 2026, suggesting renewed appetite for risk assets.' },
      { type: 'stat', items: [{ value: '+2.4%', label: 'S&P 500' }, { value: '+3.1%', label: 'Nasdaq' }, { value: '3.94%', label: '10Y Yield' }] },
    ],
  },
  {
    id: 'art-003',
    title: 'Advanced encryption: How AI is defending against quantum attacks',
    category: 'Tech',
    tag: 'Exclusive',
    readTime: 5,
    timeAgo: '2 hr ago',
    date: 'Mar 20, 2026',
    image: 'https://images.unsplash.com/photo-1761496847215-46592435aab0?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    excerpt: 'NIST finalizes post-quantum cryptography standards, and a new wave of AI-powered key-management systems is already deploying them at enterprise scale.',
    source: 'Tech Pulse',
    content: [
      { type: 'paragraph', text: 'The U.S. National Institute of Standards and Technology officially finalized its first set of post-quantum cryptographic (PQC) standards this week, marking the end of a decade-long standardization effort and triggering an urgent migration cycle for government and financial systems.' },
      { type: 'heading', text: 'Why Classical Encryption Is Vulnerable' },
      { type: 'paragraph', text: 'Today\'s RSA and ECC encryption rely on mathematical problems — factoring large numbers or computing discrete logarithms — that would take classical computers millions of years to break. Quantum computers running Shor\'s algorithm could solve these problems in hours once hardware matures sufficiently.' },
      { type: 'quote', text: 'The threat isn\'t theoretical anymore. Adversaries are harvesting encrypted data today to decrypt it once quantum hardware is viable — a strategy called "harvest now, decrypt later."', author: 'Ravi Shankar', role: 'CISO, Axis Bank' },
      { type: 'paragraph', text: 'CrowdStrike and Palo Alto Networks have both announced PQC-native endpoint products. Analysts expect the market for quantum-safe security software to reach $12 billion by 2028.' },
      { type: 'stat', items: [{ value: '4', label: 'NIST standards finalized' }, { value: '$12B', label: 'Market by 2028' }, { value: '2031', label: 'Estimated Q-day' }] },
    ],
  },
  {
    id: 'art-004',
    title: 'DeepMind\'s Gemini Ultra 2 achieves human-level reasoning on 43 benchmarks',
    category: 'AI Labs',
    tag: 'Trending',
    readTime: 4,
    timeAgo: '3 hr ago',
    date: 'Mar 20, 2026',
    image: 'https://images.unsplash.com/photo-1760629863094-5b1e8d1aae74?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    excerpt: 'Google DeepMind\'s newest frontier model scores above 90th-percentile human performance across mathematics, coding, scientific reasoning, and legal analysis.',
    source: 'AI Insider',
    content: [
      { type: 'paragraph', text: 'Google DeepMind released Gemini Ultra 2 to enterprise customers on Thursday, posting benchmark results that outpace GPT-5 on 38 of 50 standard evaluations. The model achieves scores in the 90th percentile of human performance on graduate-level mathematics, competitive programming, and bar exam simulations.' },
      { type: 'heading', text: 'Benchmarks Shattered' },
      { type: 'paragraph', text: 'On GPQA Diamond — a set of graduate-level science questions so difficult that even domain experts average only 65% — Gemini Ultra 2 scored 87.4%. Its coding performance on SWE-Bench, which tests real software engineering tasks, reached 62.3%, nearly double the previous state of the art.' },
      { type: 'quote', text: 'This is the first time we\'ve seen a model genuinely surprise our internal experts — not just on narrow tasks, but on open-ended reasoning chains they hadn\'t anticipated.', author: 'Demis Hassabis', role: 'CEO, Google DeepMind' },
      { type: 'paragraph', text: 'The model is available via the Vertex AI API starting today. Pricing is $0.0015 per 1K input tokens, roughly 40% cheaper than its predecessor.' },
      { type: 'stat', items: [{ value: '87.4%', label: 'GPQA Diamond' }, { value: '62.3%', label: 'SWE-Bench' }, { value: '43/50', label: 'SOTA benchmarks' }] },
    ],
  },
  {
    id: 'art-005',
    title: 'How cities are turning concrete into carbon sinks by 2030',
    category: 'Global',
    readTime: 6,
    timeAgo: '5 hr ago',
    date: 'Mar 19, 2026',
    image: 'https://images.unsplash.com/photo-1761662826910-3a2480223933?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    excerpt: 'A new generation of bio-concrete, living walls, and AI-managed green corridors is transforming urban infrastructure from carbon sources into net-negative emitters.',
    source: 'Green World',
    content: [
      { type: 'paragraph', text: 'Singapore\'s Tengah "Forest Town," Paris\'s ring-road retrofit, and Copenhagen\'s harbor biomes represent a seismic shift in urban design philosophy: cities are no longer simply managing their carbon footprint — they\'re engineering it negative.' },
      { type: 'heading', text: 'The Science of Bio-Concrete' },
      { type: 'paragraph', text: 'Pioneered at Delft University, bio-concrete embeds bacteria that synthesize limestone when exposed to water, self-sealing cracks and capturing atmospheric CO₂ in the process. Singapore\'s HDB has begun mandating it for all new public housing above six stories.' },
      { type: 'quote', text: 'Every square meter of bio-concrete absorbs roughly 2.8 kg of CO₂ per year over a 50-year lifespan. At city scale, that\'s not incremental — it\'s transformative.', author: 'Dr. Priya Nair', role: 'Urban Climate Lead, C40 Cities' },
      { type: 'heading', text: 'AI-Managed Green Corridors' },
      { type: 'paragraph', text: 'Barcelona\'s AI-driven "Superilla" project uses real-time sensor data to irrigate rooftop farms and living facades only when soil moisture, temperature, and wind conditions maximize carbon uptake. The system has reduced water use by 34% while increasing biomass by 18%.' },
      { type: 'stat', items: [{ value: '2.8kg', label: 'CO₂/m²/year' }, { value: '34%', label: 'Water saved' }, { value: '67', label: 'Cities enrolled' }] },
    ],
  },
  {
    id: 'art-006',
    title: 'SpaceX Starship successfully completes first fully-reusable orbital flight',
    category: 'Tech',
    readTime: 3,
    timeAgo: '7 hr ago',
    date: 'Mar 19, 2026',
    image: 'https://images.unsplash.com/photo-1597331139945-615efe8f4b04?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    excerpt: 'Both the Super Heavy booster and Ship upper stage returned to their launch towers, completing the first fully reusable orbital round-trip in spaceflight history.',
    source: 'Space Watch',
    content: [
      { type: 'paragraph', text: 'SpaceX achieved a historic milestone on Wednesday when Starship IFT-9 completed a full orbital mission and returned both stages intact to their launch towers at Starbase, Texas — the first demonstration of complete, unmodified vehicle reuse in orbital spaceflight history.' },
      { type: 'paragraph', text: 'The mission carried a pathfinder payload for NASA\'s Artemis V crewed lunar lander, validating the critical propellant transfer technology required for deep-space missions. The booster was caught by its mechazilla arms 8 minutes after liftoff; Ship splashed down 90 minutes later and was recovered by drone ship.' },
      { type: 'quote', text: 'Today we demonstrated that fully reusable orbital rockets are not a dream. They are operational hardware. This changes everything about what\'s economically possible in space.', author: 'Elon Musk', role: 'CEO, SpaceX' },
      { type: 'stat', items: [{ value: '8 min', label: 'Booster return' }, { value: '100%', label: 'Stage reuse' }, { value: '$50/kg', label: 'Target LEO cost' }] },
    ],
  },
  {
    id: 'art-007',
    title: 'CRISPR trial shows 94% remission in late-stage blood cancers',
    category: 'Health',
    readTime: 5,
    timeAgo: '1 day ago',
    date: 'Mar 19, 2026',
    image: 'https://images.unsplash.com/photo-1583912086005-ac9abca6c9db?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    excerpt: 'Phase III data from a joint Stanford–UCSF trial shows unprecedented response rates for CRISPR-edited CAR-T therapy in patients who had failed all prior treatments.',
    source: 'MedBreak',
    content: [
      { type: 'paragraph', text: 'A Phase III clinical trial involving 312 patients with relapsed or refractory diffuse large B-cell lymphoma (DLBCL) found that CRISPR-edited CAR-T cells achieved complete remission in 94% of participants — a rate that far exceeds the 40–60% seen with conventional CAR-T products.' },
      { type: 'heading', text: 'How the Editing Works' },
      { type: 'paragraph', text: 'The therapy, developed by Editas Medicine and UCSF\'s immunology lab, uses base editing to knock out the T-cell exhaustion gene TET2 and simultaneously introduce a synthetic promoter that sustains CAR expression over time. This prevents the "burn-out" that limits current-generation therapies.' },
      { type: 'quote', text: 'We treated patients who had exhausted every available option. Ninety-four percent is not an incremental improvement — it is a redefinition of what late-stage cancer treatment can look like.', author: 'Dr. James Wright', role: 'Oncology Lead, UCSF' },
      { type: 'paragraph', text: 'The FDA has granted Breakthrough Therapy designation. Editas expects to file a Biologics License Application by Q4 2026, with a potential launch in early 2027.' },
      { type: 'stat', items: [{ value: '94%', label: 'Complete remission' }, { value: '312', label: 'Patients treated' }, { value: 'Q1 27', label: 'Expected launch' }] },
    ],
  },
  {
    id: 'art-008',
    title: 'Bitcoin breaks $120K as BlackRock ETF inflows hit weekly record',
    category: 'Finance',
    readTime: 3,
    timeAgo: '2 days ago',
    date: 'Mar 18, 2026',
    image: 'https://images.unsplash.com/photo-1694219782948-afcab5c095d3?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080',
    excerpt: 'Bitcoin crossed $120,000 for the first time as BlackRock\'s IBIT absorbed $2.1 billion in weekly inflows, its largest since the ETF\'s launch.',
    source: 'Crypto Daily',
    content: [
      { type: 'paragraph', text: 'Bitcoin surpassed $120,000 on Thursday morning in Asian trading, driven by a record-breaking week of institutional inflows into U.S. spot Bitcoin ETFs. BlackRock\'s IBIT alone absorbed $2.1 billion — its highest weekly total since the product launched in January 2024.' },
      { type: 'paragraph', text: 'The rally has been attributed to a confluence of factors: the recent Fed pivot signals, the upcoming Bitcoin halving in April, and growing corporate treasury adoption following MicroStrategy\'s latest $1.5 billion purchase announcement.' },
      { type: 'quote', text: 'Bitcoin at $120K is the market pricing in a world where every major sovereign wealth fund has a 1–3% allocation. That day is closer than most people realize.', author: 'Cathie Wood', role: 'CEO, ARK Invest' },
      { type: 'stat', items: [{ value: '$120K', label: 'BTC price' }, { value: '$2.1B', label: 'IBIT weekly inflows' }, { value: '+34%', label: 'Month-to-date' }] },
    ],
  },
];
