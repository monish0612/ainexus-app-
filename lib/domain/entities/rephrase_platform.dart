import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Segment in the bubble panel. Tutor dropdown stays on [kRephrasePlatforms].
enum RephraseGroup { rewrite, tone, chat }

/// A rephrase target ("platform") offered by `POST /api/v1/ai/rephrase`.
///
/// The [id] values must stay in sync with `AI_REPHRASE_PLATFORM_META` on the
/// server — anything the backend does not recognise silently falls back to
/// `casual`. Shared by the Tutor Rephrase tab and the floating bubble overlay
/// so both offer exactly the same set.
class RephrasePlatform {
  const RephrasePlatform({
    required this.id,
    required this.label,
    required this.emoji,
    required this.color,
    required this.icon,
    required this.group,
    this.busyLabel = 'Rephrasing…',
  });

  final String id;
  final String label;
  final String emoji;
  final Color color;
  final IconData icon;
  final RephraseGroup group;

  /// Header copy while this action is in flight.
  final String busyLabel;

  /// Chip text the panel tests look up — emoji + label, unchanged from v1.
  String get chipLabel => '$emoji $label';
}

/// `own` is first: it takes a free-form instruction (sent as `intent`) instead
/// of a fixed tone.
const List<RephrasePlatform> kRephrasePlatforms = [
  RephrasePlatform(
    id: 'own',
    label: 'Own',
    emoji: '✨',
    color: Color(0xFF0D59F2),
    icon: LucideIcons.wand2,
    group: RephraseGroup.tone,
    busyLabel: 'Rephrasing…',
  ),
  RephrasePlatform(
    id: 'casual',
    label: 'Casual',
    emoji: '😊',
    color: Color(0xFF60A5FA),
    icon: LucideIcons.smile,
    group: RephraseGroup.tone,
  ),
  RephrasePlatform(
    id: 'sarcastic',
    label: 'Sarcastic',
    emoji: '😏',
    color: Color(0xFFF87171),
    icon: LucideIcons.flame,
    group: RephraseGroup.tone,
    busyLabel: 'Adding bite…',
  ),
  RephrasePlatform(
    id: 'slack',
    label: 'Slack',
    emoji: '💬',
    color: Color(0xFFC084FC),
    icon: LucideIcons.messageSquare,
    group: RephraseGroup.chat,
  ),
  RephrasePlatform(
    id: 'email-short',
    label: 'Email Short',
    emoji: '✉️',
    color: Color(0xFFFCD34D),
    icon: LucideIcons.inbox,
    group: RephraseGroup.chat,
  ),
  RephrasePlatform(
    id: 'email-long',
    label: 'Email Long',
    emoji: '📧',
    color: Color(0xFFF59E0B),
    icon: LucideIcons.mail,
    group: RephraseGroup.chat,
  ),
  RephrasePlatform(
    id: 'whatsapp',
    label: 'WhatsApp',
    emoji: '📱',
    color: Color(0xFF4ADE80),
    icon: LucideIcons.smartphone,
    group: RephraseGroup.chat,
  ),
  RephrasePlatform(
    id: 'zoom',
    label: 'Zoom',
    emoji: '🎥',
    color: Color(0xFF60A5FA),
    icon: LucideIcons.video,
    group: RephraseGroup.chat,
  ),
  RephrasePlatform(
    id: 'twitter',
    label: 'Twitter / X',
    emoji: '𝕏',
    color: Color(0xFFE7E9EA),
    icon: LucideIcons.hash,
    group: RephraseGroup.chat,
  ),
  RephrasePlatform(
    id: 'linkedin',
    label: 'LinkedIn',
    emoji: '💼',
    color: Color(0xFF60A5FA),
    icon: LucideIcons.briefcase,
    group: RephraseGroup.chat,
  ),
  RephrasePlatform(
    id: 'forum',
    label: 'Forum',
    emoji: '🌐',
    color: Color(0xFF818CF8),
    icon: LucideIcons.globe,
    group: RephraseGroup.chat,
  ),
];

const List<RephrasePlatform> kRewritePlatforms = [
  RephrasePlatform(
    id: 'fix',
    label: 'Fix',
    emoji: '✓',
    color: Color(0xFF4ADE80),
    icon: LucideIcons.check,
    group: RephraseGroup.rewrite,
    busyLabel: 'Fixing grammar…',
  ),
  RephrasePlatform(
    id: 'improve',
    label: 'Improve',
    emoji: '↑',
    color: Color(0xFF60A5FA),
    icon: LucideIcons.sparkles,
    group: RephraseGroup.rewrite,
    busyLabel: 'Improving…',
  ),
  RephrasePlatform(
    id: 'shorten',
    label: 'Shorten',
    emoji: '−',
    color: Color(0xFFFCD34D),
    icon: LucideIcons.minimize2,
    group: RephraseGroup.rewrite,
    busyLabel: 'Shortening…',
  ),
  RephrasePlatform(
    id: 'expand',
    label: 'Expand',
    emoji: '+',
    color: Color(0xFFC084FC),
    icon: LucideIcons.maximize2,
    group: RephraseGroup.rewrite,
    busyLabel: 'Expanding…',
  ),
  RephrasePlatform(
    id: 'human',
    label: 'Human',
    emoji: '✎',
    color: Color(0xFFF472B6),
    icon: LucideIcons.heart,
    group: RephraseGroup.rewrite,
    busyLabel: 'Humanizing…',
  ),
];

const List<RephrasePlatform> kExtraTonePlatforms = [
  RephrasePlatform(
    id: 'formal',
    label: 'Formal',
    emoji: '👔',
    color: Color(0xFF94A3B8),
    icon: LucideIcons.landmark,
    group: RephraseGroup.tone,
    busyLabel: 'Formalizing…',
  ),
  RephrasePlatform(
    id: 'emoji',
    label: 'Emoji',
    emoji: '🙂',
    color: Color(0xFFFCD34D),
    icon: LucideIcons.smilePlus,
    group: RephraseGroup.tone,
    busyLabel: 'Adding emoji…',
  ),
];

const List<RephrasePlatform> kExtraChatPlatforms = [
  RephrasePlatform(
    id: 'reply',
    label: 'Reply',
    emoji: '↩',
    color: Color(0xFF818CF8),
    icon: LucideIcons.reply,
    group: RephraseGroup.chat,
    busyLabel: 'Writing a reply…',
  ),
  RephrasePlatform(
    id: 'define',
    label: 'Meaning',
    emoji: '📖',
    color: Color(0xFF60A5FA),
    icon: LucideIcons.bookOpen,
    group: RephraseGroup.chat,
    busyLabel: 'Looking up…',
  ),
];

/// Tone chips in the bubble: Own / Casual / Formal / Sarcastic / Emoji.
List<RephrasePlatform> get kTonePlatforms => [
      kRephrasePlatforms.firstWhere((p) => p.id == 'own'),
      kRephrasePlatforms.firstWhere((p) => p.id == 'casual'),
      kExtraTonePlatforms.firstWhere((p) => p.id == 'formal'),
      kRephrasePlatforms.firstWhere((p) => p.id == 'sarcastic'),
      kExtraTonePlatforms.firstWhere((p) => p.id == 'emoji'),
    ];

/// Chat chips: original channel set plus Reply / Meaning.
List<RephrasePlatform> get kChatPlatforms => [
      ...kRephrasePlatforms.where((p) => p.group == RephraseGroup.chat),
      ...kExtraChatPlatforms,
    ];

/// Every action the bubble can send. Tutor dropdown stays on [kRephrasePlatforms].
List<RephrasePlatform> get kAllRephraseActions => [
      ...kRewritePlatforms,
      ...kTonePlatforms,
      ...kChatPlatforms,
    ];

RephrasePlatform? rephrasePlatformById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final platform in kAllRephraseActions) {
    if (platform.id == id) return platform;
  }
  return null;
}

RephraseGroup groupForPlatformId(String? id) =>
    rephrasePlatformById(id)?.group ?? RephraseGroup.tone;

List<RephrasePlatform> platformsInGroup(RephraseGroup group) {
  switch (group) {
    case RephraseGroup.rewrite:
      return List<RephrasePlatform>.from(kRewritePlatforms);
    case RephraseGroup.tone:
      return List<RephrasePlatform>.from(kTonePlatforms);
    case RephraseGroup.chat:
      return List<RephrasePlatform>.from(kChatPlatforms);
  }
}

String rephraseGroupLabel(RephraseGroup group) => switch (group) {
      RephraseGroup.rewrite => 'Rewrite',
      RephraseGroup.tone => 'Tone',
      RephraseGroup.chat => 'Chat',
    };
