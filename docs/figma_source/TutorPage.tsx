import { useState, useRef, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  Mic, Sparkles, Copy, Check, Search, X,
  Lightbulb, Trash2, BookOpen, Zap, Volume2, BookmarkCheck,
  RotateCcw, ChevronDown, ArrowRight,
} from 'lucide-react';
import { useSettings } from '../utils/settingsContext';
import { usePalette } from '../utils/palette';

const F = "'Plus Jakarta Sans', sans-serif";
const PU = '#7C3AED';
const LP = '#A78BFA';
const MAX_REPHRASE = 500;
const MAX_COACH = 300;

type TutorTab = 'rephrase' | 'coach' | 'dictionary';
type CoachPlatform = 'Zoom' | 'Slack' | 'WhatsApp' | 'Email' | 'Teams';
type ToneVariant = 'Casual' | 'Professional' | 'Urgent';

// ── Rephrase platform config ───────────────────────────────────────────────────
interface RephrasePlatform {
  id: string;
  label: string;
  emoji: string;
  color: string;
  charLimit: number | null;
  badge: string;
  hint: string;
}

const REPHRASE_PLATFORMS: RephrasePlatform[] = [
  { id: 'email-long',  label: 'Email Long',   emoji: '📧', color: '#F59E0B', charLimit: null, badge: 'FORMAL',        hint: 'Full greeting · body · sign-off' },
  { id: 'email-short', label: 'Email Short',  emoji: '✉️', color: '#FCD34D', charLimit: 150,  badge: 'CONCISE',       hint: 'Subject + 1–2 lines max' },
  { id: 'slack',       label: 'Slack',        emoji: '💬', color: '#C084FC', charLimit: 200,  badge: 'CASUAL WORK',   hint: 'Conversational · @mentions · emoji' },
  { id: 'whatsapp',    label: 'WhatsApp',     emoji: '📱', color: '#4ADE80', charLimit: 300,  badge: 'PERSONAL',      hint: 'Warm · relaxed · natural flow' },
  { id: 'twitter',     label: 'Twitter / X',  emoji: '𝕏',  color: '#E7E9EA', charLimit: 280,  badge: 'PUNCHY',        hint: 'Hook first · max 280 chars · hashtags' },
  { id: 'linkedin',    label: 'LinkedIn',     emoji: '💼', color: '#60A5FA', charLimit: null, badge: 'PROFESSIONAL',  hint: 'Story-driven · value-first · authority' },
  { id: 'teams',       label: 'Teams',        emoji: '🟣', color: '#818CF8', charLimit: null, badge: 'STRUCTURED',    hint: '@team · bullet points · action item' },
];

interface RephrasePlatformResult {
  platformId: string;
  text: string;
  whyItWorks: string[];
  techniques: string[];
}

// ── Coach config ───────────────────────────────────────────────────────────────
interface CoachResult {
  corrected: string;
  highlights: string[];
  variations: Record<CoachPlatform, Record<ToneVariant, string>>;
  protip: string;
}

const COACH_PLATFORMS: { id: CoachPlatform; color: string; label: string }[] = [
  { id: 'Zoom',     color: '#60A5FA', label: '🎥 Zoom' },
  { id: 'Slack',    color: '#C084FC', label: '💬 Slack' },
  { id: 'WhatsApp', color: '#4ADE80', label: '📱 WhatsApp' },
  { id: 'Email',    color: '#F59E0B', label: '✉️ Email' },
  { id: 'Teams',    color: '#818CF8', label: '🟣 Teams' },
];

const VARIANT_META: { id: ToneVariant; color: string; icon: string; desc: string }[] = [
  { id: 'Casual',       color: '#60A5FA', icon: '😊', desc: 'Friendly · relaxed · approachable' },
  { id: 'Professional', color: '#A78BFA', icon: '💼', desc: 'Polished · respectful · formal' },
  { id: 'Urgent',       color: '#FBBF24', icon: '⚡', desc: 'Direct · action-oriented · brief' },
];

// ── Saved word types ───────────────────────────────────────────────────────────
interface SavedWord {
  id: string;
  word: string;
  pronunciation: string;
  definition: string;
  example: string;
}

// ── Mock AI: Platform rephrase ─────────────────────────────────────────────────
function mockRephraseForPlatform(text: string, platformId: string): RephrasePlatformResult {
  const t = text.trim();
  const lo = t.toLowerCase();
  const isQuestion = lo.includes('?') || lo.startsWith('can') || lo.startsWith('could') || lo.startsWith('would');
  const firstCap = t.charAt(0).toUpperCase() + t.slice(1).replace(/[?!.]?$/, '');

  switch (platformId) {
    case 'email-long':
      return {
        platformId,
        text: `Subject: ${isQuestion ? 'Query — Action Required' : 'Update — For Your Attention'}\n\nHi [Name],\n\nI hope this message finds you well. I am writing to ${isQuestion ? 'kindly request your guidance on' : 'bring to your attention'} the following: ${firstCap}.\n\nI would greatly appreciate your input or feedback at your earliest convenience. Please do not hesitate to reach out should you need any additional context.\n\nThank you sincerely for your time.\n\nWarm regards,\n[Your Name]`,
        whyItWorks: [
          'Subject line sets context before the reader even opens — 64% of recipients decide to open based on subject alone',
          '"I hope this message finds you well" is a low-friction opener that signals professionalism without fluff',
          'Closing with gratitude + open invitation increases reply rate by ~48% vs blunt endings',
        ],
        techniques: ['Subject line hook', 'Formal salutation', 'Soft CTA', 'Open invitation', 'Warm sign-off'],
      };

    case 'email-short':
      return {
        platformId,
        text: `Hi [Name], quick one — ${isQuestion ? `could you help with: ${t.toLowerCase().replace(/[?]?$/, '')}?` : `${firstCap}.`} Let me know! Thanks 🙏`,
        whyItWorks: [
          '"Quick one" primes the reader that this won\'t take long — dramatically reduces friction to respond',
          'Single ask per email outperforms multi-ask emails by 3× in response rates',
          'Emoji + "Thanks" creates warmth without adding length — keeps the tone human',
        ],
        techniques: ['Low-friction opener', 'Single ask', 'Brevity signal', 'Warm close'],
      };

    case 'slack':
      return {
        platformId,
        text: `${isQuestion ? `:wave: hey @channel — quick q: ${t.toLowerCase().replace(/[?]?$/, '')}? drop a reply when you can! 🙏` : `:mega: heads up — ${t.toLowerCase()} — let me know your thoughts 👇`}`,
        whyItWorks: [
          'Slack emoji reactions increase visibility — messages with emoji get 3× more responses in team channels',
          '@mention or @channel routes to the right people fast — critical in busy workspaces',
          'Trailing "👇" or "let me know" is a low-commitment CTA that feels natural in async chat culture',
        ],
        techniques: ['Emoji lead', '@mention routing', 'Async-friendly tone', 'Micro-CTA'],
      };

    case 'whatsapp':
      return {
        platformId,
        text: `${isQuestion ? `Hey! ${firstCap}? Would really appreciate your help on this 😊` : `Hey! Just wanted to let you know — ${t.toLowerCase()} 😊 Let me know what you think!`}`,
        whyItWorks: [
          'WhatsApp is a personal-first platform — starting with "Hey" mimics how friends talk and bypasses defensive reading',
          'Single emoji (😊) increases warmth perception without seeming unprofessional in personal contexts',
          '"Would really appreciate" is a vulnerability signal — shown to increase compliance and warmth in personal networks',
        ],
        techniques: ['Personal opener', 'Warmth emoji', 'Gratitude language', 'Conversational close'],
      };

    case 'twitter':
      return {
        platformId,
        text: `${isQuestion ? `${firstCap}?\n\nAnyone dealt with this before? Drop your thoughts 👇 #community` : `${firstCap}.\n\nHere\'s the thing: [your key insight here].\n\nAgree? Let\'s talk 👇`}`,
        whyItWorks: [
          'Twitter\'s algorithm rewards replies — ending with a direct question is the single most effective engagement tactic',
          'Line breaks (not paragraphs) boost readability by 60% in feed-scroll context — always break into 1–2 line stanzas',
          'A relevant hashtag adds discoverable context and can 2× organic reach for public accounts',
        ],
        techniques: ['Hook-first structure', 'Line break formatting', 'Engagement CTA', 'Hashtag reach'],
      };

    case 'linkedin':
      return {
        platformId,
        text: `${firstCap}.\n\nHere's what I've learned from working through this:\n\n→ Context sets the foundation — be clear about the situation\n→ Your ask matters — frame it around shared value, not just need\n→ Follow up with insight — your perspective makes you memorable\n\nWhat has your experience been? I'd love to hear different viewpoints in the comments.`,
        whyItWorks: [
          'LinkedIn posts with 3-point "→" bullet structures get 45% higher comment engagement than plain paragraphs',
          'Ending with a personal question transforms a post into a conversation — the algorithm rewards comment velocity heavily',
          'Story-framed professional content gets 3× more reach than announcement-style posts on LinkedIn',
        ],
        techniques: ['Story framing', '→ bullet structure', 'Value-first positioning', 'Community invite CTA'],
      };

    case 'teams':
      return {
        platformId,
        text: `@team — quick update:\n\n📌 Context: ${firstCap}.\n✅ Action needed: [specify who does what by when]\n🗓 Deadline: [add date]\n\nPlease confirm receipt. Reach out if you need clarification.`,
        whyItWorks: [
          'Teams culture is action-oriented — the 📌✅🗓 structure creates instant visual scanability in dense notification feeds',
          '@team mention guarantees notification delivery — critical for async professional environments',
          '"Confirm receipt" creates accountability without being aggressive — a best practice for cross-team communication',
        ],
        techniques: ['Emoji structure', '@mention visibility', 'Action + deadline framing', 'Receipt request'],
      };

    default:
      return {
        platformId,
        text: `${firstCap}.`,
        whyItWorks: ['Clear and concise message', 'Platform-appropriate tone', 'Single focus improves clarity'],
        techniques: ['Clarity', 'Brevity', 'Focus'],
      };
  }
}

// ── Mock AI: Coach ─────────────────────────────────────────────────────────────
function mockCoach(text: string): CoachResult {
  const lo = text.toLowerCase().trim();
  const hasMeeting = lo.includes('meeting') || lo.includes('call') || lo.includes('late') || lo.includes('join');
  const hasFamily  = lo.includes('drop') || lo.includes('pick') || lo.includes('son') || lo.includes('family') || lo.includes('kid');

  const corrected = hasMeeting
    ? '"I will be joining the meeting shortly. Please proceed without me for now."'
    : hasFamily
    ? '"I need to step away briefly to handle a family matter. I\'ll return shortly."'
    : `"${text.charAt(0).toUpperCase() + text.slice(1).replace(/\bi\b/g, 'I').trim()}."`;

  const highlights = hasMeeting
    ? ['will be joining', 'shortly', 'proceed without me']
    : hasFamily
    ? ['step away', 'briefly', 'family matter', 'return shortly']
    : [];

  const mv = (c: string, p: string, u: string): Record<ToneVariant, string> =>
    ({ Casual: c, Professional: p, Urgent: u });

  const variations: Record<CoachPlatform, Record<ToneVariant, string>> = {
    Zoom: hasMeeting
      ? mv('"Hey team, give me 5 — joining super soon! 🙌"',
           '"I apologize for the delay. I\'ll be joining momentarily. Please proceed."',
           '"Running 5 min late — start without me!"')
      : hasFamily
      ? mv('"Hey all, hopping off to grab my kid. Back soon! 🚀"',
           '"I need to drop off the call for a family commitment. I\'ll catch up on the recording."',
           '"Dropping off now — family emergency. Back in 15!"')
      : mv(`"Hey team — quick note: ${text.toLowerCase()} 😊"`,
           `"I'd like to bring this to the team's attention: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}."`,
           `"URGENT: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}. Team response needed now."`),

    Slack: hasMeeting
      ? mv('"brt! 5 mins 🏃 keep it rolling!"',
           '"Apologies — delayed. Joining shortly. Please continue."',
           '"⚡ Late 5 min. Don\'t wait on me."')
      : hasFamily
      ? mv('"brb — grabbing my kid 🏃"',
           '"Stepping away briefly. Back in ~15. Ping if urgent."',
           '"⚡ OOO 15min — family situation. @here if critical."')
      : mv(`":mega: heads up — ${text.toLowerCase()} 👀"`,
           `"Team update: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}."`,
           `"⚡ URGENT: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}. Action needed ASAP."`),

    WhatsApp: hasMeeting
      ? mv('"Hey! Give me 5, joining soon 😅"',
           '"Hi, I\'ll be a few minutes late. Please proceed."',
           '"Running late — joining ASAP. Start without me!"')
      : hasFamily
      ? mv('"Hey! Gotta run get my son 😊 Back in a bit!"',
           '"Hi, stepping away briefly for a family commitment. Back shortly."',
           '"Need to leave immediately — will call back ASAP."')
      : mv(`"Hey! Just a heads-up — ${text.toLowerCase()} 😊"`,
           `"Hi, I wanted to let you know: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}."`,
           `"IMPORTANT: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}. Please respond."`),

    Email: hasMeeting
      ? mv('"Hey! Flagging I\'ll be a few minutes late. Start without me!"',
           '"Please accept my apologies for the delay. I will join within minutes. Kindly proceed."',
           '"URGENT: Delayed. Please begin — I\'ll join immediately."')
      : hasFamily
      ? mv('"Hey team! Stepping away briefly — family stuff. Won\'t be long! 😊"',
           '"I need to briefly step away for a family commitment. I will return shortly."',
           '"Urgent family matter. Will respond as soon as available."')
      : mv(`"Hey! Quick note — ${text.toLowerCase()}. Thoughts?"`,
           `"I am writing to inform you: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}."`,
           `"URGENT: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}. Immediate response required."`),

    Teams: hasMeeting
      ? mv('"Hey all — hopping on in 5! Start the call 😊"',
           '"Apologies for the delay. Joining shortly. Please proceed as scheduled."',
           '"Delayed 5 mins. @team cover opening points — joining ASAP."')
      : hasFamily
      ? mv('"Brb — picking up my kid 🚀 Back in 15."',
           '"Stepping away for a brief family matter. Will catch up on missed updates."',
           '"⚡ Urgent family matter. @team please cover. Back ASAP."')
      : mv(`"Hey all — ${text.toLowerCase()} 😊 Thoughts?"`,
           `"Team, please note: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}. Feedback welcome."`,
           `"@team URGENT: ${text.charAt(0).toUpperCase() + text.slice(1).toLowerCase()}. Immediate attention needed."`),
  };

  const protip = hasMeeting
    ? 'Use "will be joining" instead of "gonna join" in professional settings — it signals commitment and reliability.'
    : hasFamily
    ? 'Say "step away briefly" instead of "dropping off" — it sounds intentional rather than abrupt.'
    : 'Structure your message: context first, then your request. This improves clarity and response rates significantly.';

  return { corrected, highlights, variations, protip };
}

// ── Saved words data ───────────────────────────────────────────────────────────
const DEFAULT_WORDS: SavedWord[] = [
  { id: 'w1', word: 'Ephemeral',   pronunciation: '/ɪˈfem(ə)r(ə)l/', definition: 'Lasting for a very short time; fleeting or transitory. Often used to describe moments, trends, or experiences that are beautifully brief and impermanent.', example: '"The ephemeral beauty of cherry blossoms reminds us to cherish every moment."' },
  { id: 'w2', word: 'Serendipity', pronunciation: '/ˌserənˈdɪpɪti/', definition: 'The occurrence of fortunate events by chance in a happy or beneficial way — a pleasant surprise that wasn\'t planned or expected.', example: '"Finding my dream job through a casual coffee chat was pure serendipity."' },
  { id: 'w3', word: 'Eloquent',    pronunciation: '/ˈeləkwənt/', definition: 'Fluent or persuasive in speaking or writing. Able to express ideas clearly and with strong, compelling impact on the audience.', example: '"Her eloquent speech moved the entire audience to tears."' },
  { id: 'w4', word: 'Mellifluous', pronunciation: '/məˈlɪfluəs/', definition: 'Sweet or musical; pleasant to hear. Describes a voice or sound that flows smoothly and agreeably, like liquid honey.', example: '"His mellifluous voice made even routine announcements sound poetic."' },
];

const WORD_DB: Record<string, Omit<SavedWord, 'id'>> = {
  perspicacious: { word: 'Perspicacious', pronunciation: '/ˌpɜːspɪˈkeɪʃəs/', definition: 'Having a ready insight into things; shrewd and perceptive. Describes someone with an unusually clear and deep understanding of complex situations.', example: '"Her perspicacious analysis uncovered issues others had overlooked for years."' },
  ubiquitous:    { word: 'Ubiquitous',    pronunciation: '/juːˈbɪkwɪtəs/', definition: 'Present, appearing, or found everywhere. Something so widespread it seems to exist in every place simultaneously.', example: '"Smartphones have become ubiquitous in modern society."' },
  tenacious:     { word: 'Tenacious',     pronunciation: '/tɪˈneɪʃəs/', definition: 'Tending to keep a firm hold; persistent and determined. Not giving up easily, clinging to goals with unwavering resolve.', example: '"Her tenacious spirit helped her overcome every obstacle in her path."' },
  laconic:       { word: 'Laconic',       pronunciation: '/ləˈkɒnɪk/', definition: 'Using very few words. Brief and concise in speech or expression, often to striking and memorable effect.', example: '"His laconic reply — just "No" — ended the debate instantly."' },
  sanguine:      { word: 'Sanguine',      pronunciation: '/ˈsæŋɡwɪn/', definition: 'Optimistic or positive, especially in a difficult situation. Cheerfully confident about the future despite challenges.', example: '"Despite setbacks, she remained sanguine about the project\'s eventual success."' },
  loquacious:    { word: 'Loquacious',    pronunciation: '/ləˈkweɪʃəs/', definition: 'Tending to talk a great deal; excessively chatty. Describes someone who speaks freely and at length without restraint.', example: '"The loquacious host kept the party lively with endless stories."' },
  pernicious:    { word: 'Pernicious',    pronunciation: '/pəˈnɪʃəs/', definition: 'Having a harmful effect, especially in a gradual or subtle way. Slowly causing damage that is difficult to detect at first.', example: '"The pernicious effects of misinformation spread quietly through the community."' },
  inscrutable:   { word: 'Inscrutable',   pronunciation: '/ɪnˈskruːtəb(ə)l/', definition: 'Impossible to understand or interpret; mysterious. A person or expression that gives no clear indication of thoughts or feelings.', example: '"The inscrutable smile on her face left everyone guessing her true intention."' },
  sagacious:     { word: 'Sagacious',     pronunciation: '/səˈɡeɪʃəs/', definition: 'Having or showing keen mental discernment and good judgment; wise. Someone with deep practical wisdom and sound decision-making.', example: '"The sagacious mentor guided her team through every crisis with calm clarity."' },
};

function lookupWord(word: string): Omit<SavedWord, 'id'> {
  const key = word.toLowerCase().trim();
  if (WORD_DB[key]) return WORD_DB[key];
  const w = word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
  return {
    word: w,
    pronunciation: `/${key.slice(0, 2)}·${key.slice(2, 5) || 'əl'}/`,
    definition: `AI-generated definition for "${w}": A nuanced term with rich contextual usage across both formal and informal English. Its meaning shifts subtly based on context, tone, and intended audience.`,
    example: `"Careful use of ${word.toLowerCase()} in professional settings adds precision and impact to any message."`,
  };
}

// ── Extended rich lookup (10 examples + usage contexts) ───────────────────────
interface WordLookupResult {
  word: string;
  pronunciation: string;
  partOfSpeech: string;
  definition: string;
  examples: string[];
  usageContexts: { label: string; emoji: string; color: string; fits: boolean }[];
}

const RICH_WORD_DB: Record<string, WordLookupResult> = {
  ephemeral: {
    word: 'Ephemeral', pronunciation: '/ɪˈfem(ə)r(ə)l/', partOfSpeech: 'adjective',
    definition: 'Lasting for a very short time; fleeting or transitory. Often used to describe moments, trends, or experiences that are beautifully brief.',
    examples: [
      '"The ephemeral glow of sunset lasted only minutes before the sky turned dark."',
      '"Social media trends are often ephemeral — viral today, forgotten tomorrow."',
      '"She found deep beauty in the ephemeral nature of cherry blossoms."',
      '"The startup\'s initial success proved ephemeral as competition intensified."',
      '"Snapchat built its entire empire around the concept of ephemeral content."',
      '"His fame was ephemeral, fading as quickly as it had arrived."',
      '"The ephemeral connection they shared on that train left a lasting impression."',
      '"In the digital age, even memories can feel ephemeral."',
      '"Morning frost is ephemeral — gone before most people even wake."',
      '"Philosophers debate whether true happiness is ephemeral or can be sustained."',
    ],
    usageContexts: [
      { label: 'Academic Writing',  emoji: '📝', color: '#60A5FA', fits: true  },
      { label: 'Creative Writing',  emoji: '✍️', color: '#F472B6', fits: true  },
      { label: 'Presentations',     emoji: '🎤', color: '#A78BFA', fits: true  },
      { label: 'LinkedIn Posts',    emoji: '💼', color: '#34D399', fits: true  },
      { label: 'Journalism',        emoji: '📰', color: '#F59E0B', fits: true  },
      { label: 'Business Email',    emoji: '✉️', color: '#818CF8', fits: false },
      { label: 'Casual Chat',       emoji: '💬', color: '#94A3B8', fits: false },
      { label: 'WhatsApp / Slack',  emoji: '📱', color: '#94A3B8', fits: false },
    ],
  },
  serendipity: {
    word: 'Serendipity', pronunciation: '/ˌserənˈdɪpɪti/', partOfSpeech: 'noun',
    definition: 'The occurrence of fortunate events by chance in a happy or beneficial way — a pleasant surprise that wasn\'t planned or expected.',
    examples: [
      '"Finding my dream job through a casual coffee chat was pure serendipity."',
      '"The serendipity of their meeting on the last flight that night changed both their lives."',
      '"Great scientific discoveries often involve a significant element of serendipity."',
      '"By serendipity, the two co-founders sat next to each other at a startup conference."',
      '"She believed in serendipity — that the universe conspires for those who stay open."',
      '"It was serendipity that brought her the exact book she needed at that moment."',
      '"The product\'s biggest feature came from a moment of serendipity during a bug fix."',
      '"Serendipity brought them together; shared values kept them together."',
      '"Traveling slowly creates more room for serendipity to enter your life."',
      '"The entire deal was closed through serendipity — a chance encounter at an airport."',
    ],
    usageContexts: [
      { label: 'Creative Writing',  emoji: '✍️', color: '#F472B6', fits: true  },
      { label: 'LinkedIn Posts',    emoji: '💼', color: '#34D399', fits: true  },
      { label: 'Casual Chat',       emoji: '💬', color: '#4ADE80', fits: true  },
      { label: 'Presentations',     emoji: '🎤', color: '#A78BFA', fits: true  },
      { label: 'Academic Writing',  emoji: '📝', color: '#60A5FA', fits: true  },
      { label: 'WhatsApp / Slack',  emoji: '📱', color: '#4ADE80', fits: true  },
      { label: 'Business Email',    emoji: '✉️', color: '#94A3B8', fits: false },
      { label: 'Interviews',        emoji: '🤝', color: '#94A3B8', fits: false },
    ],
  },
  eloquent: {
    word: 'Eloquent', pronunciation: '/ˈeləkwənt/', partOfSpeech: 'adjective',
    definition: 'Fluent or persuasive in speaking or writing. Able to express ideas clearly and with strong, compelling impact on the audience.',
    examples: [
      '"Her eloquent speech moved the entire audience to tears."',
      '"He was known for his eloquent responses under pressure during debates."',
      '"The CEO\'s eloquent vision for the company\'s future rallied the entire team."',
      '"An eloquent email can turn a firm "no" into "let\'s talk more"."',
      '"Her eloquent defence of the proposal left the board with no objections."',
      '"The eloquent poet found words for feelings others couldn\'t name."',
      '"Being eloquent is not about big words — it\'s about being clear and compelling."',
      '"His eloquent apology was the turning point in restoring client trust."',
      '"Eloquent silence can sometimes say more than a thousand words."',
      '"The professor\'s eloquent lecture made even a dry topic feel alive."',
    ],
    usageContexts: [
      { label: 'Presentations',     emoji: '🎤', color: '#A78BFA', fits: true  },
      { label: 'Academic Writing',  emoji: '📝', color: '#60A5FA', fits: true  },
      { label: 'Business Email',    emoji: '✉️', color: '#F59E0B', fits: true  },
      { label: 'Interviews',        emoji: '🤝', color: '#60A5FA', fits: true  },
      { label: 'LinkedIn Posts',    emoji: '💼', color: '#34D399', fits: true  },
      { label: 'Creative Writing',  emoji: '✍️', color: '#F472B6', fits: true  },
      { label: 'Casual Chat',       emoji: '💬', color: '#94A3B8', fits: false },
      { label: 'WhatsApp / Slack',  emoji: '📱', color: '#94A3B8', fits: false },
    ],
  },
  tenacious: {
    word: 'Tenacious', pronunciation: '/tɪˈneɪʃəs/', partOfSpeech: 'adjective',
    definition: 'Tending to keep a firm hold; persistent and determined. Not giving up easily, clinging to goals with unwavering resolve.',
    examples: [
      '"Her tenacious spirit helped her overcome every obstacle in her path."',
      '"The tenacious negotiator refused to accept the first offer."',
      '"He was tenacious in his pursuit of excellence, working 18-hour days."',
      '"A tenacious grip on market share separates great companies from good ones."',
      '"Despite three rejections, her tenacious follow-ups eventually won the contract."',
      '"The tenacious reporter spent years uncovering the corruption story."',
      '"Tenacious performers don\'t just practice hard — they practice smart."',
      '"His tenacious belief in the product kept the team motivated through the downturn."',
      '"The startup survived because of the founders\' tenacious attitude."',
      '"She was tenacious in her recovery, attending therapy every single day."',
    ],
    usageContexts: [
      { label: 'LinkedIn Posts',    emoji: '💼', color: '#34D399', fits: true  },
      { label: 'Presentations',     emoji: '🎤', color: '#A78BFA', fits: true  },
      { label: 'Business Email',    emoji: '✉️', color: '#F59E0B', fits: true  },
      { label: 'Interviews',        emoji: '🤝', color: '#60A5FA', fits: true  },
      { label: 'Academic Writing',  emoji: '📝', color: '#60A5FA', fits: true  },
      { label: 'Casual Chat',       emoji: '💬', color: '#4ADE80', fits: true  },
      { label: 'Creative Writing',  emoji: '✍️', color: '#F472B6', fits: true  },
      { label: 'WhatsApp / Slack',  emoji: '📱', color: '#94A3B8', fits: false },
    ],
  },
  ubiquitous: {
    word: 'Ubiquitous', pronunciation: '/juːˈbɪkwɪtəs/', partOfSpeech: 'adjective',
    definition: 'Present, appearing, or found everywhere. Something so widespread it seems to exist in every place simultaneously.',
    examples: [
      '"Smartphones have become ubiquitous in modern society."',
      '"The company\'s logo is so ubiquitous you\'ll spot it in every airport."',
      '"Coffee shops have become ubiquitous on every city block."',
      '"AI tools are now ubiquitous in the tech industry."',
      '"His ubiquitous smile made everyone feel immediately at ease."',
      '"The internet has made ubiquitous access to information a global reality."',
      '"Noise-cancelling headphones are now ubiquitous in open-plan offices."',
      '"Her presence at every industry event made her a networking legend."',
      '"Pop-up notifications have become so ubiquitous that users now ignore them."',
      '"The brand became ubiquitous almost overnight after their viral campaign."',
    ],
    usageContexts: [
      { label: 'Business Email',    emoji: '✉️', color: '#F59E0B', fits: true  },
      { label: 'Presentations',     emoji: '🎤', color: '#A78BFA', fits: true  },
      { label: 'Academic Writing',  emoji: '📝', color: '#60A5FA', fits: true  },
      { label: 'LinkedIn Posts',    emoji: '💼', color: '#34D399', fits: true  },
      { label: 'Journalism',        emoji: '📰', color: '#F59E0B', fits: true  },
      { label: 'Casual Chat',       emoji: '💬', color: '#4ADE80', fits: true  },
      { label: 'Creative Writing',  emoji: '✍️', color: '#F472B6', fits: true  },
      { label: 'WhatsApp / Slack',  emoji: '📱', color: '#94A3B8', fits: false },
    ],
  },
};

function lookupWordFull(word: string): WordLookupResult {
  const key = word.toLowerCase().trim();
  if (RICH_WORD_DB[key]) return RICH_WORD_DB[key];
  const w = word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
  return {
    word: w,
    pronunciation: `/${key.slice(0, 2)}·${key.slice(2, 5) || 'əl'}/`,
    partOfSpeech: 'word',
    definition: `A nuanced term with rich contextual usage across formal and informal English. Its meaning shifts subtly based on context, tone, and intended audience.`,
    examples: [
      `"The concept of ${word.toLowerCase()} is widely recognized in professional settings."`,
      `"She demonstrated remarkable ${word.toLowerCase()} throughout the entire project."`,
      `"His understanding of ${word.toLowerCase()} set him apart from other candidates."`,
      `"The team\'s ${word.toLowerCase()} was evident in every deliverable they produced."`,
      `"Developing ${word.toLowerCase()} takes years of deliberate practice and reflection."`,
      `"Her ${word.toLowerCase()} in this situation showed true leadership maturity."`,
      `"The book explores ${word.toLowerCase()} as a cornerstone of effective communication."`,
      `"Without ${word.toLowerCase()}, even the best strategies can fall apart."`,
      `"Clients often mention ${word.toLowerCase()} as the key reason they return."`,
      `"True ${word.toLowerCase()} reveals itself most clearly when you\'re under pressure."`,
    ],
    usageContexts: [
      { label: 'Business Email',    emoji: '✉️', color: '#F59E0B', fits: true  },
      { label: 'Presentations',     emoji: '🎤', color: '#A78BFA', fits: true  },
      { label: 'Academic Writing',  emoji: '📝', color: '#60A5FA', fits: true  },
      { label: 'LinkedIn Posts',    emoji: '💼', color: '#34D399', fits: true  },
      { label: 'Casual Chat',       emoji: '💬', color: '#4ADE80', fits: false },
      { label: 'Creative Writing',  emoji: '✍️', color: '#F472B6', fits: true  },
      { label: 'Interviews',        emoji: '🤝', color: '#60A5FA', fits: true  },
      { label: 'WhatsApp / Slack',  emoji: '📱', color: '#94A3B8', fits: false },
    ],
  };
}

// ── Shared UI helpers ──────────────────────────────────────────────────────────
function HighlightedText({ text, phrases }: { text: string; phrases: string[] }) {
  if (!phrases.length) return <span style={{ color: '#F1F5F9' }}>{text}</span>;
  const segs: { t: string; h: boolean }[] = [];
  let rem = text;
  while (rem.length > 0) {
    let best = { idx: -1, len: 0, src: '' };
    for (const p of phrases) {
      const idx = rem.toLowerCase().indexOf(p.toLowerCase());
      if (idx >= 0 && (best.idx === -1 || idx < best.idx))
        best = { idx, len: p.length, src: rem.slice(idx, idx + p.length) };
    }
    if (best.idx === -1) { segs.push({ t: rem, h: false }); break; }
    if (best.idx > 0) segs.push({ t: rem.slice(0, best.idx), h: false });
    segs.push({ t: best.src, h: true });
    rem = rem.slice(best.idx + best.len);
  }
  return (
    <>
      {segs.map((s, i) =>
        s.h
          ? <span key={i} style={{ color: LP, textDecoration: 'underline', textDecorationColor: `${LP}70` }}>{s.t}</span>
          : <span key={i} style={{ color: '#F1F5F9' }}>{s.t}</span>
      )}
    </>
  );
}

function CopyBtn({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <motion.button
      onClick={() => { navigator.clipboard.writeText(text.replace(/^"|"$/g, '')); setCopied(true); setTimeout(() => setCopied(false), 2000); }}
      whileTap={{ scale: 0.82 }}
      className="flex items-center gap-1.5 rounded-full px-3 py-1.5 shrink-0"
      style={{ background: copied ? 'rgba(52,211,153,0.15)' : 'rgba(255,255,255,0.07)', border: `1px solid ${copied ? 'rgba(52,211,153,0.4)' : 'rgba(255,255,255,0.12)'}`, transition: 'all 0.2s' }}>
      <AnimatePresence mode="wait">
        {copied
          ? <motion.div key="y" initial={{ scale: 0 }} animate={{ scale: 1 }} exit={{ scale: 0 }}><Check size={11} color="#34D399" /></motion.div>
          : <motion.div key="n" initial={{ scale: 0 }} animate={{ scale: 1 }} exit={{ scale: 0 }}><Copy size={11} color="rgba(255,255,255,0.5)" /></motion.div>}
      </AnimatePresence>
      <span style={{ fontSize: 11, fontWeight: 700, color: copied ? '#34D399' : 'rgba(255,255,255,0.5)', fontFamily: F }}>{copied ? 'Copied!' : 'Copy'}</span>
    </motion.button>
  );
}

function LoadingDots() {
  return (
    <div className="flex items-center gap-1.5">
      {[0, 1, 2].map(i => (
        <motion.div key={i} className="rounded-full"
          style={{ width: 6, height: 6, background: LP }}
          animate={{ scale: [1, 1.5, 1], opacity: [0.4, 1, 0.4] }}
          transition={{ duration: 0.9, repeat: Infinity, delay: i * 0.18 }} />
      ))}
    </div>
  );
}

function Glass({ children, className = '', style = {} }: { children: React.ReactNode; className?: string; style?: React.CSSProperties }) {
  return (
    <div className={`rounded-2xl ${className}`}
      style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.09)', ...style }}>
      {children}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// REPHRASE TAB
// ══════════════════════════════════════════════════════════════════════════════
function RephraseTab() {
  const [input, setInput] = useState('');
  const [selectedIds, setSelectedIds] = useState<string[]>(REPHRASE_PLATFORMS.map(p => p.id));
  const [results, setResults] = useState<RephrasePlatformResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [hasResult, setHasResult] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const toggle = (id: string) =>
    setSelectedIds(prev => prev.includes(id) ? (prev.length > 1 ? prev.filter(x => x !== id) : prev) : [...prev, id]);

  const handleRephrase = async () => {
    if (!input.trim()) return;
    setLoading(true);
    setHasResult(false);
    setExpandedId(null);
    await new Promise(r => setTimeout(r, 1600));
    const res = REPHRASE_PLATFORMS
      .filter(p => selectedIds.includes(p.id))
      .map(p => mockRephraseForPlatform(input, p.id));
    setResults(res);
    setLoading(false);
    setHasResult(true);
    setExpandedId(res[0]?.platformId ?? null);
  };

  return (
    <motion.div className="flex-1 overflow-y-auto" style={{ scrollbarWidth: 'none' }}
      initial={{ opacity: 0, x: -18 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -18 }} transition={{ duration: 0.22 }}>
      <div className="flex flex-col gap-5 px-4 pt-5 pb-28">

        {/* Section label */}
        <div className="flex items-center gap-2">
          <Sparkles size={14} color={LP} />
          <span style={{ fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.38)', fontFamily: F, letterSpacing: 1.1 }}>AI PHRASE REPHRASER</span>
        </div>

        {/* Input card */}
        <Glass>
          <div className="p-4 pb-3">
            <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.32)', fontFamily: F, letterSpacing: 1 }}>YOUR TEXT</span>
            <textarea value={input} onChange={e => setInput(e.target.value.slice(0, MAX_REPHRASE))}
              placeholder="Type or paste a phrase, sentence or message to rephrase…"
              className="w-full mt-2 resize-none"
              rows={4}
              style={{ background: 'transparent', border: 'none', outline: 'none', fontSize: 16, color: input ? '#F1F5F9' : 'rgba(255,255,255,0.22)', fontFamily: F, lineHeight: 1.6 }} />
          </div>
          <div className="flex items-center justify-between px-4 py-3" style={{ borderTop: '1px solid rgba(255,255,255,0.06)' }}>
            <motion.button whileTap={{ scale: 0.9 }} className="flex items-center gap-2 rounded-full px-3 py-1.5"
              style={{ background: 'rgba(124,58,237,0.15)', border: '1px solid rgba(124,58,237,0.28)' }}>
              <Mic size={13} color={LP} />
              <span style={{ fontSize: 11, fontWeight: 700, color: LP, fontFamily: F }}>Voice</span>
            </motion.button>
            <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.28)', fontFamily: F }}>{input.length}/{MAX_REPHRASE}</span>
          </div>
        </Glass>

        {/* Platform selector grid */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <span style={{ fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.35)', fontFamily: F, letterSpacing: 1 }}>SELECT PLATFORMS</span>
            <motion.button whileTap={{ scale: 0.9 }} onClick={() => setSelectedIds(
              selectedIds.length === REPHRASE_PLATFORMS.length ? [REPHRASE_PLATFORMS[0].id] : REPHRASE_PLATFORMS.map(p => p.id)
            )}>
              <span style={{ fontSize: 11, fontWeight: 700, color: LP, fontFamily: F }}>
                {selectedIds.length === REPHRASE_PLATFORMS.length ? 'Deselect all' : 'Select all'}
              </span>
            </motion.button>
          </div>
          <div className="grid gap-2.5" style={{ gridTemplateColumns: 'repeat(2, 1fr)' }}>
            {REPHRASE_PLATFORMS.map(p => {
              const active = selectedIds.includes(p.id);
              return (
                <motion.button key={p.id} whileTap={{ scale: 0.93 }} onClick={() => toggle(p.id)}
                  className="flex items-start gap-2.5 rounded-2xl p-3 text-left"
                  animate={{
                    background: active ? `${p.color}18` : 'rgba(255,255,255,0.04)',
                    borderColor: active ? `${p.color}50` : 'rgba(255,255,255,0.09)',
                    boxShadow: active ? `0 0 20px ${p.color}20` : 'none',
                  }}
                  style={{ border: '1px solid', cursor: 'pointer' }}
                  transition={{ duration: 0.15 }}>
                  <span style={{ fontSize: 20, lineHeight: 1 }}>{p.emoji}</span>
                  <div className="flex-1 min-w-0">
                    <p style={{ fontSize: 13, fontWeight: active ? 700 : 500, color: active ? p.color : 'rgba(255,255,255,0.55)', fontFamily: F }}>{p.label}</p>
                    <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.28)', fontFamily: F, marginTop: 1, lineHeight: 1.4 }}>{p.hint}</p>
                  </div>
                  <div className="shrink-0 mt-0.5">
                    <div className="rounded-full" style={{
                      width: 14, height: 14,
                      background: active ? p.color : 'rgba(255,255,255,0.1)',
                      border: `2px solid ${active ? p.color : 'rgba(255,255,255,0.18)'}`,
                      transition: 'all 0.15s',
                    }} />
                  </div>
                </motion.button>
              );
            })}
          </div>
        </div>

        {/* Rephrase button */}
        <motion.button onClick={handleRephrase} disabled={!input.trim() || loading}
          whileTap={{ scale: 0.97 }} className="w-full rounded-2xl flex items-center justify-center gap-2.5"
          style={{ height: 56, background: input.trim() ? PU : 'rgba(124,58,237,0.18)', cursor: input.trim() ? 'pointer' : 'not-allowed', transition: 'background 0.2s', boxShadow: input.trim() ? '0 0 32px rgba(124,58,237,0.35)' : 'none' }}>
          {loading
            ? <div className="flex items-center gap-3"><LoadingDots /><span style={{ fontSize: 14, fontWeight: 700, color: 'rgba(255,255,255,0.7)', fontFamily: F }}>Generating…</span></div>
            : <><Sparkles size={17} color="#fff" /><span style={{ fontSize: 15, fontWeight: 800, color: '#fff', fontFamily: F }}>Rephrase for {selectedIds.length} Platform{selectedIds.length !== 1 ? 's' : ''}</span></>}
        </motion.button>

        {/* Results */}
        <AnimatePresence>
          {hasResult && (
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="flex flex-col gap-4">
              <div className="flex items-center gap-2">
                <div style={{ flex: 1, height: 1, background: 'rgba(255,255,255,0.07)' }} />
                <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.28)', fontFamily: F, letterSpacing: 1.2 }}>RESULTS — {results.length} PLATFORMS</span>
                <div style={{ flex: 1, height: 1, background: 'rgba(255,255,255,0.07)' }} />
              </div>

              {results.map((res, i) => {
                const plat = REPHRASE_PLATFORMS.find(p => p.id === res.platformId)!;
                const isOpen = expandedId === res.platformId;
                const charCount = res.text.length;
                const charPct = plat.charLimit ? Math.min((charCount / plat.charLimit) * 100, 100) : 0;
                const overLimit = plat.charLimit ? charCount > plat.charLimit : false;

                return (
                  <motion.div key={res.platformId}
                    initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.07 }}>
                    {/* Card header — always visible, click to expand */}
                    <div className="rounded-2xl overflow-hidden"
                      style={{ background: isOpen ? `${plat.color}0e` : 'rgba(255,255,255,0.04)', border: `1px solid ${isOpen ? `${plat.color}40` : 'rgba(255,255,255,0.09)'}`, transition: 'all 0.2s', boxShadow: isOpen ? `0 0 28px ${plat.color}18` : 'none' }}>

                      {/* Collapsed header */}
                      <div className="flex items-center gap-3 px-4 py-3.5 cursor-pointer"
                        onClick={() => setExpandedId(isOpen ? null : res.platformId)}>
                        <span style={{ fontSize: 22 }}>{plat.emoji}</span>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <span style={{ fontSize: 15, fontWeight: 700, color: isOpen ? plat.color : '#E2E8F0', fontFamily: F }}>{plat.label}</span>
                            <span className="rounded-full px-2 py-0.5"
                              style={{ fontSize: 9, fontWeight: 800, color: plat.color, background: `${plat.color}18`, border: `1px solid ${plat.color}30`, fontFamily: F, letterSpacing: 0.8 }}>
                              {plat.badge}
                            </span>
                          </div>
                          <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)', fontFamily: F, marginTop: 1 }}>{plat.hint}</p>
                        </div>
                        <motion.div animate={{ rotate: isOpen ? 90 : 0 }} transition={{ duration: 0.2 }}>
                          <ArrowRight size={15} color={isOpen ? plat.color : 'rgba(255,255,255,0.3)'} />
                        </motion.div>
                      </div>

                      {/* Expanded content */}
                      <AnimatePresence>
                        {isOpen && (
                          <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} style={{ overflow: 'hidden' }}>

                            {/* Divider */}
                            <div style={{ height: 1, background: `${plat.color}25`, margin: '0 16px' }} />

                            {/* The rephrased text */}
                            <div className="px-4 py-4">
                              <div className="flex items-center justify-between mb-2">
                                <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.32)', fontFamily: F, letterSpacing: 1 }}>REPHRASED</span>
                                <CopyBtn text={res.text} />
                              </div>
                              <div className="rounded-xl p-3.5" style={{ background: `${plat.color}12`, border: `1px solid ${plat.color}22` }}>
                                <p style={{ fontSize: 15, color: '#F1F5F9', fontFamily: F, lineHeight: 1.75, whiteSpace: 'pre-line' }}>{res.text}</p>
                              </div>
                            </div>

                            {/* Char count bar */}
                            {plat.charLimit && (
                              <div className="px-4 pb-3">
                                <div className="flex items-center justify-between mb-1.5">
                                  <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.3)', fontFamily: F, letterSpacing: 0.8 }}>CHARACTER COUNT</span>
                                  <span style={{ fontSize: 11, fontWeight: 700, color: overLimit ? '#F87171' : plat.color, fontFamily: F }}>{charCount} / {plat.charLimit}</span>
                                </div>
                                <div className="rounded-full overflow-hidden" style={{ height: 5, background: 'rgba(255,255,255,0.08)' }}>
                                  <motion.div className="h-full rounded-full"
                                    initial={{ width: 0 }}
                                    animate={{ width: `${charPct}%` }}
                                    transition={{ duration: 0.7, delay: 0.15 }}
                                    style={{ background: overLimit ? '#F87171' : plat.color }} />
                                </div>
                                {overLimit && <p style={{ fontSize: 10, color: '#F87171', fontFamily: F, marginTop: 4 }}>⚠ Over limit — consider trimming</p>}
                              </div>
                            )}

                            {/* Why it works */}
                            <div className="px-4 pb-4">
                              <div className="flex items-center gap-1.5 mb-2.5">
                                <Lightbulb size={12} color={plat.color} />
                                <span style={{ fontSize: 10, fontWeight: 700, color: plat.color, fontFamily: F, letterSpacing: 1 }}>WHY IT WORKS</span>
                              </div>
                              <div className="flex flex-col gap-2">
                                {res.whyItWorks.map((why, wi) => (
                                  <div key={wi} className="flex items-start gap-2.5 rounded-xl p-3"
                                    style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.07)' }}>
                                    <div className="rounded-full shrink-0 mt-0.5 flex items-center justify-center"
                                      style={{ width: 18, height: 18, background: `${plat.color}22`, border: `1px solid ${plat.color}40` }}>
                                      <span style={{ fontSize: 9, fontWeight: 900, color: plat.color }}>✓</span>
                                    </div>
                                    <p style={{ fontSize: 12, color: '#94A3B8', fontFamily: F, lineHeight: 1.6, flex: 1 }}>{why}</p>
                                  </div>
                                ))}
                              </div>
                            </div>

                            {/* Techniques chips */}
                            <div className="px-4 pb-4">
                              <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.3)', fontFamily: F, letterSpacing: 1 }}>TECHNIQUES USED</span>
                              <div className="flex flex-wrap gap-1.5 mt-2">
                                {res.techniques.map(tech => (
                                  <span key={tech} className="rounded-full px-2.5 py-1"
                                    style={{ fontSize: 10, fontWeight: 700, color: plat.color, background: `${plat.color}15`, border: `1px solid ${plat.color}30`, fontFamily: F }}>
                                    {tech}
                                  </span>
                                ))}
                              </div>
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </div>
                  </motion.div>
                );
              })}

              {/* Reset */}
              <motion.button whileTap={{ scale: 0.95 }} onClick={() => { setHasResult(false); setResults([]); setInput(''); setExpandedId(null); }}
                className="flex items-center justify-center gap-2 rounded-2xl py-3.5"
                style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>
                <RotateCcw size={14} color="rgba(255,255,255,0.4)" />
                <span style={{ fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,0.4)', fontFamily: F }}>Rephrase Another Message</span>
              </motion.button>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// COACH TAB
// ══════════════════════════════════════════════════════════════════════════════
function CoachTab() {
  const [input, setInput] = useState('');
  const [result, setResult] = useState<CoachResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [platform, setPlatform] = useState<CoachPlatform>('Zoom');

  const handleAnalyze = async () => {
    if (!input.trim()) return;
    setLoading(true);
    setResult(null);
    await new Promise(r => setTimeout(r, 1600));
    setResult(mockCoach(input));
    setLoading(false);
  };

  const platMeta = COACH_PLATFORMS.find(p => p.id === platform)!;

  return (
    <motion.div className="flex-1 overflow-y-auto" style={{ scrollbarWidth: 'none' }}
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.22 }}>
      <div className="flex flex-col gap-5 px-4 pt-5 pb-28">

        <div className="flex items-center gap-2">
          <Zap size={14} color="#34D399" />
          <span style={{ fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.38)', fontFamily: F, letterSpacing: 1.1 }}>ENGLISH COMMUNICATION COACH</span>
        </div>

        {/* Input */}
        <Glass>
          <div className="p-4 pb-2">
            <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.32)', fontFamily: F, letterSpacing: 1 }}>INPUT TEXT</span>
            <textarea value={input} onChange={e => setInput(e.target.value.slice(0, MAX_COACH))}
              placeholder="Type what you want to say… e.g. 'dropping off need to pick my son'"
              className="w-full mt-2 resize-none" rows={4}
              style={{ background: 'transparent', border: 'none', outline: 'none', fontSize: 16, color: input ? '#F1F5F9' : 'rgba(255,255,255,0.22)', fontFamily: F, lineHeight: 1.6 }} />
          </div>
          <div className="flex items-center justify-between px-4 py-3" style={{ borderTop: '1px solid rgba(255,255,255,0.06)' }}>
            <motion.button whileTap={{ scale: 0.9 }} className="flex items-center gap-2 rounded-full px-3 py-1.5"
              style={{ background: 'rgba(124,58,237,0.15)', border: '1px solid rgba(124,58,237,0.28)' }}>
              <Mic size={13} color={LP} />
              <span style={{ fontSize: 11, fontWeight: 700, color: LP, fontFamily: F }}>Speak</span>
            </motion.button>
            <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.28)', fontFamily: F }}>{input.length}/{MAX_COACH}</span>
          </div>
        </Glass>

        {/* Analyze button */}
        <motion.button onClick={handleAnalyze} disabled={!input.trim() || loading}
          whileTap={{ scale: 0.97 }} className="w-full rounded-2xl flex items-center justify-center gap-2.5"
          style={{ height: 56, background: input.trim() ? PU : 'rgba(124,58,237,0.18)', cursor: input.trim() ? 'pointer' : 'not-allowed', transition: 'background 0.2s', boxShadow: input.trim() ? '0 0 32px rgba(124,58,237,0.35)' : 'none' }}>
          {loading
            ? <div className="flex items-center gap-3"><LoadingDots /><span style={{ fontSize: 14, fontWeight: 700, color: 'rgba(255,255,255,0.7)', fontFamily: F }}>Analyzing…</span></div>
            : <><Sparkles size={17} color="#fff" /><span style={{ fontSize: 15, fontWeight: 800, color: '#fff', fontFamily: F }}>Analyze & Coach</span></>}
        </motion.button>

        {/* Results */}
        <AnimatePresence>
          {result && (
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="flex flex-col gap-5">

              {/* ── AI Correction ────────────────────────────────── */}
              <motion.div initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.05 }}>
                <div className="flex items-center justify-between mb-3">
                  <span style={{ fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.4)', fontFamily: F, letterSpacing: 1.1 }}>AI CORRECTION</span>
                  <span className="rounded-full px-2.5 py-0.5"
                    style={{ fontSize: 10, fontWeight: 800, color: '#34D399', background: 'rgba(52,211,153,0.15)', border: '1px solid rgba(52,211,153,0.28)', fontFamily: F }}>
                    ✓ REFINED
                  </span>
                </div>
                <Glass>
                  <div className="px-4 pt-4 pb-3">
                    <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.3)', fontFamily: F, letterSpacing: 1, marginBottom: 8 }}>ORIGINAL</p>
                    <p style={{ fontSize: 14, color: 'rgba(255,255,255,0.35)', fontFamily: F, textDecoration: 'line-through', lineHeight: 1.55 }}>{input}</p>
                  </div>
                  <div className="px-4 pb-4 pt-3" style={{ borderTop: '1px solid rgba(255,255,255,0.07)', background: 'rgba(124,58,237,0.05)' }}>
                    <p style={{ fontSize: 10, fontWeight: 700, color: LP, fontFamily: F, letterSpacing: 1, marginBottom: 8 }}>CORRECTED</p>
                    <p style={{ fontSize: 17, fontFamily: F, lineHeight: 1.65 }}>
                      <HighlightedText text={result.corrected} phrases={result.highlights} />
                    </p>
                    {result.highlights.length > 0 && (
                      <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)', fontFamily: F, marginTop: 8 }}>
                        <span style={{ color: LP }}>Underlined</span> = AI-improved phrases
                      </p>
                    )}
                  </div>
                </Glass>
              </motion.div>

              {/* ── Platform selector ─────────────────────────────── */}
              <motion.div initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.12 }}>
                <p style={{ fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.4)', fontFamily: F, letterSpacing: 1.1, marginBottom: 12 }}>CONTEXTUAL VARIATIONS</p>
                <div className="flex gap-2 overflow-x-auto pb-1" style={{ scrollbarWidth: 'none' }}>
                  {COACH_PLATFORMS.map(p => (
                    <motion.button key={p.id} whileTap={{ scale: 0.88 }} onClick={() => setPlatform(p.id)}
                      className="rounded-xl px-4 py-2.5 shrink-0"
                      animate={{
                        background: platform === p.id ? `${p.color}22` : 'rgba(255,255,255,0.05)',
                        borderColor: platform === p.id ? `${p.color}55` : 'rgba(255,255,255,0.1)',
                        boxShadow: platform === p.id ? `0 0 18px ${p.color}28` : 'none',
                      }}
                      style={{ border: '1px solid', cursor: 'pointer' }} transition={{ duration: 0.15 }}>
                      <span style={{ fontSize: 13, fontWeight: platform === p.id ? 700 : 500, color: platform === p.id ? p.color : 'rgba(255,255,255,0.5)', fontFamily: F }}>
                        {p.label}
                      </span>
                    </motion.button>
                  ))}
                </div>
              </motion.div>

              {/* ── All 3 tone variants stacked ───────────────────── */}
              <AnimatePresence mode="wait">
                <motion.div key={platform}
                  initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} transition={{ duration: 0.22 }}
                  className="flex flex-col gap-3">
                  {VARIANT_META.map((vm, vi) => (
                    <motion.div key={vm.id}
                      initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: vi * 0.07 }}>
                      <div className="rounded-2xl overflow-hidden"
                        style={{ background: `${vm.color}0c`, border: `1px solid ${vm.color}35`, borderLeft: `3px solid ${vm.color}` }}>
                        {/* Tone header */}
                        <div className="flex items-center gap-2.5 px-4 pt-3.5 pb-2">
                          <span style={{ fontSize: 16 }}>{vm.icon}</span>
                          <div className="flex-1">
                            <span style={{ fontSize: 13, fontWeight: 800, color: vm.color, fontFamily: F }}>{vm.id}</span>
                            <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)', fontFamily: F, marginLeft: 8 }}>· {vm.desc}</span>
                          </div>
                          <CopyBtn text={result.variations[platform][vm.id]} />
                        </div>
                        {/* Variation text */}
                        <div className="px-4 pb-4">
                          <p style={{ fontSize: 15, color: '#CBD5E1', fontFamily: F, lineHeight: 1.7 }}>
                            {result.variations[platform][vm.id]}
                          </p>
                        </div>
                      </div>
                    </motion.div>
                  ))}
                </motion.div>
              </AnimatePresence>

              {/* ── Pro-tip ───────────────────────────────────────── */}
              <motion.div initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.32 }}>
                <div className="rounded-2xl p-4 flex items-start gap-3.5"
                  style={{ background: 'rgba(0,242,255,0.04)', border: '1px solid rgba(0,242,255,0.18)', borderLeft: '3px solid rgba(0,242,255,0.5)' }}>
                  <div className="flex items-center justify-center rounded-xl shrink-0"
                    style={{ width: 36, height: 36, background: 'rgba(0,242,255,0.12)' }}>
                    <Lightbulb size={16} color="#00F2FF" />
                  </div>
                  <div>
                    <p style={{ fontSize: 13, fontWeight: 800, color: '#F1F5F9', fontFamily: F, marginBottom: 4 }}>Pro-tip</p>
                    <p style={{ fontSize: 12, color: '#94A3B8', fontFamily: F, lineHeight: 1.65 }}>{result.protip}</p>
                  </div>
                </div>
              </motion.div>

              {/* Reset */}
              <motion.button whileTap={{ scale: 0.95 }} onClick={() => { setResult(null); setInput(''); }}
                className="flex items-center justify-center gap-2 rounded-2xl py-3.5"
                style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>
                <RotateCcw size={14} color="rgba(255,255,255,0.4)" />
                <span style={{ fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,0.4)', fontFamily: F }}>Analyze Another Message</span>
              </motion.button>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SAVED WORDS TAB
// ══════════════════════════════════════════════════════════════════════════════
function SavedWordsTab() {
  const [savedWords, setSavedWords] = useState<SavedWord[]>(() => {
    try { return JSON.parse(localStorage.getItem('tutor_saved_words') || 'null') || []; } catch { return []; }
  });
  // Dedicated lookup input
  const [lookupInput, setLookupInput] = useState('');
  const [lookupLoading, setLookupLoading] = useState(false);
  const [lookupResult, setLookupResult] = useState<WordLookupResult | null>(null);
  const [showAllExamples, setShowAllExamples] = useState(false);
  // Library search
  const [libSearch, setLibSearch] = useState('');
  const [selectedWord, setSelectedWord] = useState<SavedWord | null>(null);
  const [justSaved, setJustSaved] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { localStorage.setItem('tutor_saved_words', JSON.stringify(savedWords)); }, [savedWords]);

  const isAlreadySaved = (word: string) => savedWords.some(w => w.word.toLowerCase() === word.toLowerCase().trim());

  const handleLookup = async () => {
    const q = lookupInput.trim();
    if (!q) return;
    setLookupLoading(true);
    setLookupResult(null);
    setShowAllExamples(false);
    await new Promise(r => setTimeout(r, 1500));
    setLookupResult(lookupWordFull(q));
    setLookupLoading(false);
  };

  const handleSave = () => {
    if (!lookupResult || alreadySaved) return;
    setSavedWords(prev => [{
      id: `w-${Date.now()}`,
      word: lookupResult.word,
      pronunciation: lookupResult.pronunciation,
      definition: lookupResult.definition,
      example: lookupResult.examples[0],
    }, ...prev]);
    setJustSaved(true);
    setTimeout(() => setJustSaved(false), 2500);
  };

  const handleDelete = (id: string) => {
    setSavedWords(prev => prev.filter(w => w.id !== id));
  };

  const libTrimmed = libSearch.trim();
  const filtered = libTrimmed
    ? savedWords.filter(w => w.word.toLowerCase().includes(libTrimmed.toLowerCase()) || w.definition.toLowerCase().includes(libTrimmed.toLowerCase()))
    : savedWords;
  const alreadySaved = lookupResult ? isAlreadySaved(lookupResult.word) : false;
  const isSaved = alreadySaved || justSaved;

  // Alphabet index groups for 100+ words
  const grouped = filtered.reduce<Record<string, SavedWord[]>>((acc, w) => {
    const letter = w.word[0]?.toUpperCase() ?? '#';
    if (!acc[letter]) acc[letter] = [];
    acc[letter].push(w);
    return acc;
  }, {});
  const groupKeys = Object.keys(grouped).sort();

  return (
    <motion.div className="flex-1 overflow-y-auto" style={{ scrollbarWidth: 'none' }}
      initial={{ opacity: 0, x: 18 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: 18 }} transition={{ duration: 0.22 }}>
      <div className="flex flex-col pb-28">

        {/* ══ WORD LOOKUP SECTION ══════════════════════════════════ */}
        <div className="px-4 pt-5">
          {/* Hero headline */}
          <div className="mb-4">
            <div className="flex items-center gap-2 mb-1">
              <span style={{ fontSize: 22 }}>📖</span>
              <span style={{ fontSize: 22, fontWeight: 900, color: '#fff', fontFamily: F, letterSpacing: '-0.5px' }}>Dictionary</span>
            </div>
            <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.4)', fontFamily: F, lineHeight: 1.55 }}>
              Type any word to get its meaning, 10 usage examples & where to use it
            </p>
          </div>

          {/* Lookup card */}
          <div className="rounded-2xl overflow-hidden"
            style={{ background: 'rgba(124,58,237,0.09)', border: '1.5px solid rgba(124,58,237,0.35)', boxShadow: '0 0 32px rgba(124,58,237,0.12)' }}>
            <div className="px-4 pt-4 pb-3">
              <p style={{ fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.38)', fontFamily: F, letterSpacing: 1, marginBottom: 10 }}>ENTER A WORD BELOW 👇</p>
              {/* Input row */}
              <motion.div className="flex items-center gap-3 rounded-xl px-4"
                animate={{ borderColor: lookupInput ? 'rgba(167,139,250,0.6)' : 'rgba(255,255,255,0.1)', boxShadow: lookupInput ? '0 0 0 3px rgba(124,58,237,0.12)' : 'none' }}
                style={{ height: 52, background: 'rgba(0,0,0,0.5)', border: '1px solid' }} transition={{ duration: 0.18 }}>
                <Search size={16} color={lookupInput ? LP : 'rgba(255,255,255,0.25)'} />
                <input
                  ref={inputRef}
                  value={lookupInput}
                  onChange={e => { setLookupInput(e.target.value); setLookupResult(null); }}
                  onKeyDown={e => e.key === 'Enter' && handleLookup()}
                  placeholder="e.g.  tenacious  ·  eloquent  ·  ephemeral"
                  style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', fontSize: 15, color: '#fff', fontFamily: F }}
                />
                {lookupInput && (
                  <motion.button initial={{ opacity: 0, scale: 0.5 }} animate={{ opacity: 1, scale: 1 }}
                    onClick={() => { setLookupInput(''); setLookupResult(null); }}
                    className="flex items-center justify-center rounded-full shrink-0"
                    style={{ width: 22, height: 22, background: 'rgba(255,255,255,0.12)' }}>
                    <X size={11} color="rgba(255,255,255,0.7)" />
                  </motion.button>
                )}
              </motion.div>
            </div>
            <div className="px-4 pb-4">
              <motion.button onClick={handleLookup} disabled={!lookupInput.trim() || lookupLoading}
                whileTap={{ scale: 0.97 }} className="w-full rounded-xl flex items-center justify-center gap-2.5"
                style={{ height: 50, background: lookupInput.trim() ? PU : 'rgba(124,58,237,0.18)', cursor: lookupInput.trim() ? 'pointer' : 'not-allowed', transition: 'background 0.2s', boxShadow: lookupInput.trim() ? '0 0 28px rgba(124,58,237,0.45)' : 'none' }}>
                {lookupLoading
                  ? <div className="flex items-center gap-3"><LoadingDots /><span style={{ fontSize: 13, fontWeight: 700, color: 'rgba(255,255,255,0.7)', fontFamily: F }}>Looking up…</span></div>
                  : <><Sparkles size={16} color="#fff" /><span style={{ fontSize: 14, fontWeight: 800, color: '#fff', fontFamily: F }}>Get Meaning & Examples</span></>}
              </motion.button>
            </div>
          </div>
        </div>

        {/* ══ LOOKUP RESULT ════════════════════════════════════════ */}
        <AnimatePresence>
          {lookupResult && (
            <motion.div initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}
              className="mx-4 mt-4">
              <div className="rounded-2xl overflow-hidden"
                style={{ border: '1px solid rgba(167,139,250,0.28)', background: 'rgba(20,10,40,0.95)', boxShadow: '0 0 48px rgba(124,58,237,0.15)' }}>

                {/* ── Word header */}
                <div className="px-4 pt-5 pb-4" style={{ borderBottom: '1px solid rgba(255,255,255,0.07)', background: 'rgba(124,58,237,0.08)' }}>
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p style={{ fontSize: 28, fontWeight: 900, color: LP, fontFamily: F, letterSpacing: '-0.5px', lineHeight: 1.1 }}>{lookupResult.word}</p>
                      <div className="flex items-center gap-2 mt-2">
                        <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.4)', fontFamily: F }}>{lookupResult.pronunciation}</span>
                        <span className="rounded-full px-2.5 py-0.5"
                          style={{ fontSize: 10, fontWeight: 700, color: '#A78BFA', background: 'rgba(167,139,250,0.15)', border: '1px solid rgba(167,139,250,0.28)', fontFamily: F }}>
                          {lookupResult.partOfSpeech}
                        </span>
                      </div>
                    </div>
                    <motion.button whileTap={{ scale: 0.85 }} className="flex items-center justify-center rounded-full shrink-0"
                      style={{ width: 36, height: 36, background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.12)' }}>
                      <Volume2 size={15} color="rgba(255,255,255,0.45)" />
                    </motion.button>
                  </div>
                </div>

                {/* ── Definition */}
                <div className="px-4 py-4" style={{ borderBottom: '1px solid rgba(255,255,255,0.07)' }}>
                  <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.28)', fontFamily: F, letterSpacing: 1.2, marginBottom: 8 }}>DEFINITION</p>
                  <p style={{ fontSize: 15, color: '#CBD5E1', fontFamily: F, lineHeight: 1.75 }}>{lookupResult.definition}</p>
                </div>

                {/* ── 10 Usage Examples */}
                <div className="px-4 py-4" style={{ borderBottom: '1px solid rgba(255,255,255,0.07)' }}>
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-2">
                      <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.28)', fontFamily: F, letterSpacing: 1.2 }}>USAGE EXAMPLES</p>
                      <span className="rounded-full px-2 py-0.5"
                        style={{ fontSize: 9, fontWeight: 800, color: '#34D399', background: 'rgba(52,211,153,0.15)', border: '1px solid rgba(52,211,153,0.25)', fontFamily: F }}>
                        10
                      </span>
                    </div>
                    <motion.button whileTap={{ scale: 0.9 }} onClick={() => setShowAllExamples(p => !p)}
                      className="flex items-center gap-1 rounded-full px-2.5 py-1"
                      style={{ background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)' }}>
                      <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.45)', fontFamily: F }}>{showAllExamples ? 'Collapse' : 'Show all'}</span>
                      <motion.div animate={{ rotate: showAllExamples ? 180 : 0 }} transition={{ duration: 0.2 }}>
                        <ChevronDown size={11} color="rgba(255,255,255,0.4)" />
                      </motion.div>
                    </motion.button>
                  </div>

                  <div className="flex flex-col gap-2">
                    {lookupResult.examples.slice(0, showAllExamples ? 10 : 3).map((ex, ei) => (
                      <motion.div key={ei}
                        initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: ei * 0.05 }}
                        className="flex items-start gap-3 rounded-xl p-3"
                        style={{ background: 'rgba(255,255,255,0.035)', border: '1px solid rgba(255,255,255,0.07)' }}>
                        <span className="rounded-full shrink-0 flex items-center justify-center"
                          style={{ width: 22, height: 22, background: 'rgba(167,139,250,0.18)', border: '1px solid rgba(167,139,250,0.32)', fontSize: 9, fontWeight: 900, color: LP, fontFamily: F, marginTop: 1 }}>
                          {ei + 1}
                        </span>
                        <p style={{ fontSize: 13, color: '#94A3B8', fontFamily: F, lineHeight: 1.7, fontStyle: 'italic', flex: 1 }}>{ex}</p>
                      </motion.div>
                    ))}
                  </div>

                  {!showAllExamples && (
                    <motion.button onClick={() => setShowAllExamples(true)} whileTap={{ scale: 0.97 }}
                      className="w-full mt-2.5 rounded-xl py-2.5 flex items-center justify-center gap-2"
                      style={{ background: 'rgba(52,211,153,0.07)', border: '1px solid rgba(52,211,153,0.2)' }}>
                      <span style={{ fontSize: 12, fontWeight: 700, color: '#34D399', fontFamily: F }}>Show 7 more examples</span>
                      <ChevronDown size={12} color="#34D399" />
                    </motion.button>
                  )}
                </div>

                {/* ── Where to use it */}
                <div className="px-4 py-4" style={{ borderBottom: '1px solid rgba(255,255,255,0.07)' }}>
                  <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.28)', fontFamily: F, letterSpacing: 1.2, marginBottom: 12 }}>WHERE TO USE IT</p>
                  <div className="grid gap-2" style={{ gridTemplateColumns: 'repeat(2, 1fr)' }}>
                    {lookupResult.usageContexts.map((ctx, ci) => (
                      <motion.div key={ci}
                        initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} transition={{ delay: ci * 0.04 }}
                        className="flex items-center gap-2.5 rounded-xl px-3 py-2.5"
                        style={{ background: ctx.fits ? `${ctx.color}10` : 'rgba(255,255,255,0.025)', border: `1px solid ${ctx.fits ? `${ctx.color}30` : 'rgba(255,255,255,0.06)'}` }}>
                        <span style={{ fontSize: 15 }}>{ctx.emoji}</span>
                        <p style={{ fontSize: 11, fontWeight: ctx.fits ? 700 : 400, color: ctx.fits ? ctx.color : 'rgba(255,255,255,0.2)', fontFamily: F, flex: 1, lineHeight: 1.3 }}>{ctx.label}</p>
                        <span style={{ fontSize: 12, color: ctx.fits ? ctx.color : 'rgba(255,255,255,0.18)' }}>{ctx.fits ? '✓' : '✗'}</span>
                      </motion.div>
                    ))}
                  </div>
                </div>

                {/* ── Save / Already saved */}
                {/* ── Save / Dismiss row */}
                <div className="px-4 pb-4 pt-2 flex items-center gap-3" style={{ borderTop: '1px solid rgba(255,255,255,0.06)' }}>

                  {/* ── Bookmark Save button (News-style) */}
                  <motion.button
                    onClick={handleSave}
                    disabled={isSaved}
                    whileTap={!isSaved ? { scale: 0.91 } : {}}
                    className="flex items-center gap-2.5 rounded-2xl px-5"
                    style={{
                      height: 46, flex: 1,
                      background: isSaved ? 'rgba(52,211,153,0.1)' : 'rgba(124,58,237,0.15)',
                      border: isSaved ? '1.5px solid rgba(52,211,153,0.4)' : '1.5px solid rgba(124,58,237,0.45)',
                      boxShadow: isSaved ? '0 0 20px rgba(52,211,153,0.12)' : '0 0 20px rgba(124,58,237,0.18)',
                      cursor: isSaved ? 'default' : 'pointer',
                      transition: 'all 0.3s cubic-bezier(0.34,1.56,0.64,1)',
                    }}>
                    <AnimatePresence mode="wait">
                      {isSaved ? (
                        <motion.div key="saved-state" initial={{ scale: 0, rotate: -15 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: 'spring', damping: 12, stiffness: 260 }}
                          className="flex items-center gap-2">
                          <BookmarkCheck size={17} color="#34D399" />
                          <span style={{ fontSize: 13, fontWeight: 800, color: '#34D399', fontFamily: F }}>
                            {alreadySaved ? 'Already Saved' : 'Saved!'}
                          </span>
                        </motion.div>
                      ) : (
                        <motion.div key="unsaved-state" initial={{ opacity: 0 }} animate={{ opacity: 1 }}
                          className="flex items-center gap-2">
                          <BookOpen size={17} color={LP} />
                          <span style={{ fontSize: 13, fontWeight: 800, color: LP, fontFamily: F }}>Save to Library</span>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </motion.button>

                  {/* ── Dismiss */}
                  <motion.button whileTap={{ scale: 0.9 }}
                    onClick={() => { setLookupResult(null); setLookupInput(''); setJustSaved(false); }}
                    className="flex items-center justify-center rounded-2xl shrink-0"
                    style={{ width: 46, height: 46, background: 'rgba(255,255,255,0.05)', border: '1.5px solid rgba(255,255,255,0.1)' }}>
                    <X size={15} color="rgba(255,255,255,0.45)" />
                  </motion.button>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* ══ LIBRARY SECTION ══════════════════════════════════════ */}
        <div className="px-4 mt-6 mb-1">
          <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', marginBottom: 16 }} />
          <div className="flex items-center gap-2 mb-3">
            <BookmarkCheck size={13} color={LP} />
            <span style={{ fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.38)', fontFamily: F, letterSpacing: 1.1 }}>
              SAVED WORDS · {savedWords.length}
            </span>
          </div>
          <motion.div className="flex items-center gap-3 rounded-2xl px-4"
            animate={{ borderColor: libSearch ? 'rgba(124,58,237,0.45)' : 'rgba(255,255,255,0.08)' }}
            style={{ height: 44, background: 'rgba(255,255,255,0.04)', border: '1px solid' }} transition={{ duration: 0.15 }}>
            <Search size={14} color={libSearch ? LP : 'rgba(255,255,255,0.22)'} />
            <input value={libSearch} onChange={e => setLibSearch(e.target.value)}
              placeholder="Search your saved words…"
              style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', fontSize: 13, color: '#fff', fontFamily: F }} />
            {libSearch && (
              <button onClick={() => setLibSearch('')} style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer' }}>
                <X size={12} color="rgba(255,255,255,0.4)" />
              </button>
            )}
          </motion.div>
        </div>

        {/* Empty / no-match */}
        {savedWords.length === 0 && (
          <div className="flex flex-col items-center pt-10 gap-3 px-8">
            <motion.span animate={{ scale: [1, 1.08, 1] }} transition={{ duration: 2.5, repeat: Infinity }} style={{ fontSize: 40 }}>📚</motion.span>
            <p style={{ fontSize: 14, fontWeight: 800, color: 'rgba(255,255,255,0.35)', fontFamily: F }}>No saved words yet</p>
            <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.22)', fontFamily: F, textAlign: 'center', lineHeight: 1.6 }}>
              Look up a word above and tap <span style={{ color: LP, fontWeight: 700 }}>Save to Library</span>
            </p>
          </div>
        )}
        {libTrimmed && filtered.length === 0 && savedWords.length > 0 && (
          <div className="flex flex-col items-center pt-8 gap-2">
            <span style={{ fontSize: 28 }}>🔍</span>
            <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.35)', fontFamily: F }}>No matches for "{libTrimmed}"</p>
          </div>
        )}

        {/* Saved word cards — grouped by letter */}
        <div className="flex flex-col px-4 mt-3 pb-4">
          {groupKeys.map(letter => (
            <div key={letter} className="mb-4">
              {/* Letter divider */}
              <div className="flex items-center gap-2 mb-2">
                <span style={{ fontSize: 11, fontWeight: 800, color: LP, fontFamily: F, opacity: 0.7 }}>{letter}</span>
                <div style={{ flex: 1, height: 1, background: 'rgba(167,139,250,0.12)' }} />
                <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.2)', fontFamily: F }}>{grouped[letter].length}</span>
              </div>
              <div className="flex flex-col gap-2">
                <AnimatePresence>
                  {grouped[letter].map((w, i) => (
                    <motion.div key={w.id} layout
                      initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, x: 48, scaleX: 0.85 }}
                      transition={{ duration: 0.22, delay: i * 0.03 }}>
                      <motion.div
                        whileTap={{ scale: 0.985 }}
                        onClick={() => setSelectedWord(w)}
                        className="flex items-center gap-3 rounded-2xl px-4 cursor-pointer"
                        style={{ height: 68, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', transition: 'border-color 0.15s' }}>
                        {/* Left: purple initial badge */}
                        <div className="shrink-0 flex items-center justify-center rounded-xl"
                          style={{ width: 38, height: 38, background: 'rgba(124,58,237,0.14)', border: '1px solid rgba(124,58,237,0.28)' }}>
                          <span style={{ fontSize: 16, fontWeight: 900, color: LP, fontFamily: F }}>{w.word[0]}</span>
                        </div>
                        {/* Middle: word + definition preview */}
                        <div className="flex-1 min-w-0">
                          <p style={{ fontSize: 15, fontWeight: 800, color: '#F1F5F9', fontFamily: F, letterSpacing: '-0.2px' }}>{w.word}</p>
                          <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', fontFamily: F, marginTop: 1, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>
                            {w.definition.slice(0, 55)}{w.definition.length > 55 ? '…' : ''}
                          </p>
                        </div>
                        {/* Right: trash + arrow */}
                        <div className="flex items-center gap-1.5 shrink-0">
                          <motion.button whileTap={{ scale: 0.8 }}
                            onClick={e => { e.stopPropagation(); handleDelete(w.id); }}
                            className="flex items-center justify-center rounded-full"
                            style={{ width: 32, height: 32, background: 'rgba(239,68,68,0.07)', border: '1px solid rgba(239,68,68,0.18)' }}>
                            <Trash2 size={13} color="#F87171" />
                          </motion.button>
                          <div className="flex items-center justify-center rounded-full"
                            style={{ width: 28, height: 28, background: 'rgba(255,255,255,0.05)' }}>
                            <ArrowRight size={13} color="rgba(255,255,255,0.3)" />
                          </div>
                        </div>
                      </motion.div>
                    </motion.div>
                  ))}
                </AnimatePresence>
              </div>
            </div>
          ))}
          {/* Bottom word count */}
          {savedWords.length > 0 && (
            <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.18)', fontFamily: F, textAlign: 'center', marginTop: 4 }}>
              {savedWords.length} word{savedWords.length !== 1 ? 's' : ''} in your library
            </p>
          )}
        </div>

        {/* Word Detail Modal */}
        <WordDetailModal word={selectedWord} onClose={() => setSelectedWord(null)} onDelete={handleDelete} />
      </div>
    </motion.div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// WORD DETAIL MODAL
// ══════════════════════════════════════════════════════════════════════════════
function WordDetailModal({ word, onClose, onDelete }: { word: SavedWord | null; onClose: () => void; onDelete: (id: string) => void; }) {
  const [showAllEx, setShowAllEx] = useState(false);
  const [copiedIdx, setCopiedIdx] = useState<number | null>(null);
  const [copiedDef, setCopiedDef] = useState(false);

  useEffect(() => { setShowAllEx(false); setCopiedIdx(null); setCopiedDef(false); }, [word?.id]);

  const rich = word ? lookupWordFull(word.word) : null;
  const examples = rich?.examples ?? (word ? [word.example] : []);
  const contexts = rich?.usageContexts ?? [];
  const partOfSpeech = rich?.partOfSpeech ?? '';

  const copyExample = (txt: string, i: number) => {
    navigator.clipboard.writeText(txt).catch(() => {});
    setCopiedIdx(i);
    setTimeout(() => setCopiedIdx(null), 1600);
  };
  const copyDef = () => {
    if (!word) return;
    navigator.clipboard.writeText(`${word.word}: ${word.definition}`).catch(() => {});
    setCopiedDef(true);
    setTimeout(() => setCopiedDef(false), 1600);
  };
  const handleDelete = () => { if (!word) return; onDelete(word.id); onClose(); };
  const visibleEx = showAllEx ? examples : examples.slice(0, 3);

  return (
    <AnimatePresence>
      {word && (
        <>
          <motion.div key="backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.22 }}
            onClick={onClose} style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(7px)', zIndex: 120 }} />
          <motion.div key="sheet"
            initial={{ y: '100%', opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: '100%', opacity: 0 }}
            transition={{ type: 'spring', damping: 28, stiffness: 300, mass: 0.9 }}
            style={{ position: 'fixed', bottom: 0, left: 0, right: 0, zIndex: 121, background: '#0A0A0F',
              borderTop: '1px solid rgba(124,58,237,0.32)', borderRadius: '24px 24px 0 0',
              maxHeight: '90vh', display: 'flex', flexDirection: 'column', boxShadow: '0 -16px 64px rgba(124,58,237,0.2)' }}>

            {/* Drag handle */}
            <div className="flex justify-center pt-3 pb-1 shrink-0">
              <div style={{ width: 40, height: 4, borderRadius: 99, background: 'rgba(255,255,255,0.15)' }} />
            </div>

            {/* Scrollable content */}
            <div className="overflow-y-auto flex-1" style={{ scrollbarWidth: 'none' }}>
              <div className="px-5 pt-3 pb-10">

                {/* Word header */}
                <div className="flex items-start gap-3 mb-5">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap mb-1.5">
                      <h2 style={{ fontSize: 30, fontWeight: 900, color: '#fff', fontFamily: F, letterSpacing: '-0.8px', lineHeight: 1 }}>{word.word}</h2>
                      {partOfSpeech && (
                        <span className="rounded-full px-2.5 py-0.5"
                          style={{ fontSize: 11, fontWeight: 700, color: LP, background: 'rgba(124,58,237,0.15)', border: '1px solid rgba(124,58,237,0.3)', fontFamily: F }}>
                          {partOfSpeech}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-2.5">
                      <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.4)', fontFamily: F }}>{word.pronunciation}</span>
                      <motion.button whileTap={{ scale: 0.85 }} className="flex items-center gap-1.5 rounded-full px-2.5 py-1"
                        style={{ background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)' }}>
                        <Volume2 size={11} color="rgba(255,255,255,0.5)" />
                        <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.45)', fontFamily: F }}>Listen</span>
                      </motion.button>
                    </div>
                  </div>
                  <motion.button whileTap={{ scale: 0.88 }} onClick={onClose}
                    className="flex items-center justify-center rounded-full shrink-0"
                    style={{ width: 38, height: 38, background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.1)', marginTop: 2 }}>
                    <X size={16} color="rgba(255,255,255,0.55)" />
                  </motion.button>
                </div>

                {/* Definition */}
                <div className="rounded-2xl p-4 mb-4" style={{ background: 'rgba(124,58,237,0.07)', border: '1.5px solid rgba(124,58,237,0.22)' }}>
                  <div className="flex items-center justify-between mb-2.5">
                    <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(167,139,250,0.7)', fontFamily: F, letterSpacing: 1.1 }}>DEFINITION</span>
                    <motion.button whileTap={{ scale: 0.88 }} onClick={copyDef}
                      className="flex items-center gap-1.5 rounded-full px-2.5 py-1"
                      style={{ background: copiedDef ? 'rgba(52,211,153,0.1)' : 'rgba(255,255,255,0.06)', border: `1px solid ${copiedDef ? 'rgba(52,211,153,0.3)' : 'rgba(255,255,255,0.1)'}`, transition: 'all 0.2s' }}>
                      {copiedDef ? <Check size={11} color="#34D399" /> : <Copy size={11} color="rgba(255,255,255,0.45)" />}
                      <span style={{ fontSize: 10, fontWeight: 700, color: copiedDef ? '#34D399' : 'rgba(255,255,255,0.4)', fontFamily: F }}>{copiedDef ? 'Copied!' : 'Copy'}</span>
                    </motion.button>
                  </div>
                  <p style={{ fontSize: 15, color: '#E2E8F0', fontFamily: F, lineHeight: 1.72 }}>{word.definition}</p>
                </div>

                {/* Usage Examples */}
                <div className="mb-4">
                  <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.38)', fontFamily: F, letterSpacing: 1.1 }}>
                    USAGE EXAMPLES · {examples.length}
                  </span>
                  <div className="flex flex-col gap-2.5 mt-3">
                    <AnimatePresence initial={false}>
                      {visibleEx.map((ex, i) => (
                        <motion.div key={i}
                          initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }}
                          transition={{ duration: 0.18, delay: i * 0.04 }}
                          className="rounded-xl px-4 py-3 flex items-start gap-3"
                          style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.07)', borderLeft: `2.5px solid ${LP}55` }}>
                          <span style={{ fontSize: 11, fontWeight: 800, color: 'rgba(167,139,250,0.5)', fontFamily: F, minWidth: 18, paddingTop: 1 }}>{i + 1}.</span>
                          <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.68)', fontFamily: F, lineHeight: 1.65, flex: 1, fontStyle: 'italic' }}>{ex}</p>
                          <motion.button whileTap={{ scale: 0.82 }} onClick={() => copyExample(ex, i)}
                            className="shrink-0 flex items-center justify-center rounded-full"
                            style={{ width: 28, height: 28, background: copiedIdx === i ? 'rgba(52,211,153,0.12)' : 'rgba(255,255,255,0.06)', border: `1px solid ${copiedIdx === i ? 'rgba(52,211,153,0.3)' : 'rgba(255,255,255,0.1)'}`, transition: 'all 0.2s' }}>
                            {copiedIdx === i ? <Check size={10} color="#34D399" /> : <Copy size={10} color="rgba(255,255,255,0.4)" />}
                          </motion.button>
                        </motion.div>
                      ))}
                    </AnimatePresence>
                    {examples.length > 3 && (
                      <motion.button whileTap={{ scale: 0.96 }} onClick={() => setShowAllEx(v => !v)}
                        className="w-full flex items-center justify-center gap-2 rounded-xl py-2.5"
                        style={{ background: 'rgba(124,58,237,0.1)', border: '1px solid rgba(124,58,237,0.25)' }}>
                        <motion.div animate={{ rotate: showAllEx ? 180 : 0 }} transition={{ duration: 0.2 }}>
                          <ChevronDown size={14} color={LP} />
                        </motion.div>
                        <span style={{ fontSize: 12, fontWeight: 700, color: LP, fontFamily: F }}>
                          {showAllEx ? 'Show less' : `Show ${examples.length - 3} more examples`}
                        </span>
                      </motion.button>
                    )}
                  </div>
                </div>

                {/* Where to Use */}
                {contexts.length > 0 && (
                  <div className="mb-4">
                    <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.38)', fontFamily: F, letterSpacing: 1.1 }}>WHERE TO USE IT</span>
                    <div className="grid grid-cols-2 gap-2 mt-3">
                      {contexts.map((ctx, i) => (
                        <motion.div key={i} initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} transition={{ delay: i * 0.04 }}
                          className="rounded-xl px-3 py-2.5 flex items-center gap-2.5"
                          style={{ background: ctx.fits ? `${ctx.color}0f` : 'rgba(255,255,255,0.03)', border: `1px solid ${ctx.fits ? `${ctx.color}35` : 'rgba(255,255,255,0.07)'}` }}>
                          <span style={{ fontSize: 15 }}>{ctx.emoji}</span>
                          <p style={{ fontSize: 11, fontWeight: 700, color: ctx.fits ? ctx.color : 'rgba(255,255,255,0.28)', fontFamily: F, flex: 1 }}>{ctx.label}</p>
                          <span style={{ fontSize: 13 }}>{ctx.fits ? '✓' : '✗'}</span>
                        </motion.div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* Sticky bottom bar */}
            <div className="shrink-0 px-5 py-4 flex items-center gap-3"
              style={{ borderTop: '1px solid rgba(255,255,255,0.08)', background: '#0A0A0F' }}>
              <motion.button whileTap={{ scale: 0.9 }} onClick={handleDelete}
                className="flex items-center gap-2 rounded-2xl px-4"
                style={{ height: 48, background: 'rgba(239,68,68,0.08)', border: '1.5px solid rgba(239,68,68,0.25)' }}>
                <Trash2 size={15} color="#F87171" />
                <span style={{ fontSize: 13, fontWeight: 700, color: '#F87171', fontFamily: F }}>Delete</span>
              </motion.button>
              <motion.button whileTap={{ scale: 0.96 }} onClick={onClose}
                className="flex-1 flex items-center justify-center rounded-2xl"
                style={{ height: 48, background: PU, boxShadow: '0 0 24px rgba(124,58,237,0.4)' }}>
                <span style={{ fontSize: 14, fontWeight: 800, color: '#fff', fontFamily: F }}>Done</span>
              </motion.button>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN PAGE
// ══════════════════════════════════════════════════════════════════════════════
export function TutorPage() {
  const [tab, setTab] = useState<TutorTab>('rephrase');
  const { openSettings } = useSettings();
  const p = usePalette();
  const TABS = [
    { id: 'rephrase'   as TutorTab, label: 'Rephrase',   icon: '✦' },
    { id: 'coach'      as TutorTab, label: 'Coach',      icon: '⚡' },
    { id: 'dictionary' as TutorTab, label: 'Dictionary', icon: '📖' },
  ];

  return (
    <div className="flex flex-col h-full" style={{ background: p.bg }}>
      {/* Header */}
      <div className="shrink-0 flex items-center justify-between px-4"
        style={{ height: 52, borderBottom: `1px solid ${p.border}`, background: p.headerBg }}>
        <motion.button
          whileTap={{ scale: 0.84 }}
          onClick={openSettings}
          style={{ width: 32, height: 32, borderRadius: '50%', cursor: 'pointer', background: 'linear-gradient(135deg, #0D59F2, #22D3EE)', padding: 2, border: 'none', outline: 'none', flexShrink: 0 }}
        >
          <div style={{ width: '100%', height: '100%', borderRadius: '50%', background: p.isDark ? '#111' : '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontSize: 11, fontWeight: 800, color: p.isDark ? '#fff' : '#0F172A', fontFamily: F }}>AR</span>
          </div>
        </motion.button>
        <span style={{ fontSize: 17, fontWeight: 800, color: p.text, fontFamily: F, letterSpacing: '-0.3px' }}>Tutor</span>
        <div className="flex items-center justify-center rounded-full"
          style={{ width: 32, height: 32, background: p.bg2, border: `1.5px solid ${p.border}` }}>
          <BookOpen size={15} color={p.text3} />
        </div>
      </div>

      {/* Tab bar */}
      <div className="shrink-0 flex" style={{ borderBottom: `1px solid ${p.border}`, background: p.headerBg }}>
        {TABS.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            className="flex-1 flex flex-col items-center py-2.5 relative"
            style={{ background: 'transparent', border: 'none', outline: 'none', cursor: 'pointer' }}>
            <div className="flex items-center gap-1.5">
              <span style={{ fontSize: 11 }}>{t.icon}</span>
              <span style={{ fontSize: 13, fontFamily: F, fontWeight: tab === t.id ? 700 : 500, color: tab === t.id ? p.text : p.text3, transition: 'color 0.2s' }}>
                {t.label}
              </span>
            </div>
            {tab === t.id && (
              <motion.div layoutId="tutor-tab-line" className="absolute bottom-0"
                style={{ height: 3, left: '16%', right: '16%', background: PU, borderRadius: '3px 3px 0 0' }}
                transition={{ type: 'spring', damping: 30, stiffness: 340 }} />
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden relative">
        <AnimatePresence mode="wait">
          {tab === 'rephrase'   && <RephraseTab   key="rephrase" />}
          {tab === 'coach'      && <CoachTab      key="coach" />}
          {tab === 'dictionary' && <SavedWordsTab key="dictionary" />}
        </AnimatePresence>
      </div>
    </div>
  );
}
