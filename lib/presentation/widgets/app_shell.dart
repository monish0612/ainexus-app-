import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide ProcessTextService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:async';

import '../../core/auth/auth_service.dart';
import '../../core/platform/platform_capabilities.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/process_text_service.dart';
import '../../core/services/telegram_logger.dart';
import '../../core/theme/app_colors.dart';
import '../screens/expense/expense_screen.dart';
import '../screens/news/news_screen.dart';
import '../screens/tutor/dictionary_lookup_screen.dart';
import '../screens/tutor/rephrase_lookup_screen.dart';
import '../screens/tutor/search_lookup_screen.dart';
import '../screens/tutor/tutor_screen.dart';
import '../screens/cloud/cloud_screen.dart';
import 'bottom_nav.dart';

final currentTabProvider = StateProvider<int>((ref) => 0);
final pendingSubtabProvider = StateProvider<int?>((ref) => null);
final pendingWidgetLaunchProvider = StateProvider<bool>((ref) => false);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _screens = <Widget>[
    ExpenseScreen(),
    NewsScreen(),
    TutorScreen(),
    CloudScreen(),
  ];

  bool _chooserVisible = false;
  static const _shortcutChannel =
      MethodChannel('app.ainexus.ai_nexus/shortcuts');
  StreamSubscription<String>? _notifSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ProcessTextService.initialize already no-ops on web (kIsWeb guard
    // inside the service); keeping the call here unconditional preserves
    // identical Android behaviour.
    ProcessTextService.initialize(
      onTextReceived: _onIncomingText,
      onSharedReceived: _onSharedContent,
      onSharedImageReceived: _onSharedImage,
    );

    if (PlatformCapabilities.canUseShortcuts) {
      _shortcutChannel.setMethodCallHandler((call) async {
        if (call.method == 'onShortcut') {
          try {
            final args = Map<String, String>.from(call.arguments as Map);
            TLog.i('Shortcut', 'Received via push: $args');
            _handleShortcut(args);
          } catch (e) {
            TLog.e('Shortcut', 'Failed to parse onShortcut args', error: e);
          }
        }
      });
    }

    _notifSub = notificationPayloadStream.stream.listen((payload) {
      if (payload == 'expense_tab') {
        ref.read(currentTabProvider.notifier).state = 0;
      } else if (payload == 'news_tab') {
        ref.read(currentTabProvider.notifier).state = 1;
      } else if (payload == 'tutor_tab') {
        ref.read(currentTabProvider.notifier).state = 2;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForProcessedText();
      _checkForSharedText();
      _checkForShortcut();
    });
  }

  Future<void> _checkForShortcut() async {
    if (!PlatformCapabilities.canUseShortcuts) return;
    try {
      final result = await _shortcutChannel.invokeMethod('getShortcutAction');
      if (!mounted) return;
      if (result != null && result is Map) {
        final data = <String, String>{};
        for (final entry in result.entries) {
          data[entry.key.toString()] = entry.value.toString();
        }
        TLog.i('Shortcut', 'Received via pull: $data');
        _handleShortcut(data);
      }
    } catch (e) {
      TLog.w('Shortcut', 'getShortcutAction failed', error: e);
    }
  }

  void _handleShortcut(Map<String, String> data) {
    try {
      final tabStr = data['tab'];
      if (tabStr == null || tabStr.isEmpty) return;

      final tab = int.tryParse(tabStr);
      if (tab == null || tab < 0 || tab > 3) {
        TLog.w('Shortcut', 'Invalid tab: $tabStr');
        return;
      }

      final subtab = int.tryParse(data['subtab'] ?? '');
      final isWidgetLaunch = data['widget_launch'] == 'true';

      TLog.i(
        'Shortcut',
        'Navigating → tab=$tab, subtab=$subtab, widget=$isWidgetLaunch',
      );
      ref.read(currentTabProvider.notifier).state = tab;
      if (subtab != null) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          activeTutorSubtabSwitcher?.call(subtab);
        });
      }
      if (isWidgetLaunch) {
        TLog.i('Widget', 'Home screen widget tap → opening Summarizer');
        ref.read(pendingWidgetLaunchProvider.notifier).state = true;
      }
    } catch (e) {
      TLog.e('Shortcut', 'Failed to handle shortcut data: $data', error: e);
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AuthService.instance.checkSessionValidity();
      _checkForProcessedText();
      _checkForSharedText();
      _checkForShortcut();
    }
  }

  static final _urlPattern = RegExp(r'https?://\S+', caseSensitive: false);

  Future<void> _checkForProcessedText() async {
    final text = await ProcessTextService.getProcessedText();
    if (text != null && text.isNotEmpty) {
      _onIncomingText(text);
    }
  }

  Future<void> _checkForSharedText() async {
    final imagePath = await ProcessTextService.getSharedImagePath();
    if (imagePath != null && imagePath.isNotEmpty) {
      _onSharedImage(imagePath);
      return;
    }
    final text = await ProcessTextService.getSharedText();
    if (text != null && text.isNotEmpty) {
      _onSharedContent(text);
    }
  }

  void _onIncomingText(String text) {
    if (_chooserVisible) return;
    _showFeatureChooser(text);
  }

  void _onSharedContent(String text) {
    if (_chooserVisible) return;
    _showShareChooser(text: text);
  }

  void _onSharedImage(String imagePath) {
    if (_chooserVisible) return;
    _showShareChooser(imagePath: imagePath);
  }

  void _showShareChooser({String? text, String? imagePath}) {
    _chooserVisible = true;
    final colors = Theme.of(context).extension<AppColors>()!;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final hasUrl = text != null && _urlPattern.hasMatch(text);

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ShareChooser(
        text: text,
        hasImage: hasImage,
        hasUrl: hasUrl,
        colors: colors,
      ),
    ).then((feature) {
      _chooserVisible = false;
      if (feature == null || !mounted) return;

      switch (feature) {
        case 'expense':
          ref.read(currentTabProvider.notifier).state = 0;
          if (hasImage) {
            ref.read(pendingExpenseImageProvider.notifier).state = imagePath;
          }
        case 'summarizer':
          final url = text != null
              ? _urlPattern.firstMatch(text)?.group(0) ?? text
              : '';
          ref.read(currentTabProvider.notifier).state = 2;
          Future.delayed(const Duration(milliseconds: 200), () {
            activeTutorSubtabSwitcher?.call(0);
            ref.read(pendingSummarizerUrlProvider.notifier).state = url;
          });
        case 'dictionary':
          if (text != null && mounted) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DictionaryLookupScreen(word: text),
              ),
            );
          }
        case 'rephrase':
          if (text != null && mounted) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => RephraseLookupScreen(text: text),
              ),
            );
          }
      }
    });
  }

  void _showFeatureChooser(String text) {
    _chooserVisible = true;
    final colors = Theme.of(context).extension<AppColors>()!;

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ProcessTextChooser(
        text: text,
        colors: colors,
      ),
    ).then((feature) {
      _chooserVisible = false;
      if (feature == null || !context.mounted) return;

      switch (feature) {
        case 'rephrase':
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => RephraseLookupScreen(text: text),
            ),
          );
        case 'search':
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => SearchLookupScreen(query: text),
            ),
          );
        default:
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => DictionaryLookupScreen(word: text),
            ),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentTabProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: currentTab,
          children: _screens,
        ),
      ),
      bottomNavigationBar: BottomNav(
        currentIndex: currentTab,
        onTap: (i) => ref.read(currentTabProvider.notifier).state = i,
      ),
    );
  }
}

// ── Chooser bottom sheet ──────────────────────────────────────────────────────

class _ProcessTextChooser extends StatefulWidget {
  const _ProcessTextChooser({required this.text, required this.colors});

  final String text;
  final AppColors colors;

  @override
  State<_ProcessTextChooser> createState() => _ProcessTextChooserState();
}

class _ProcessTextChooserState extends State<_ProcessTextChooser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slide = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final preview = widget.text.length > 60
        ? '${widget.text.substring(0, 60)}...'
        : widget.text;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slide.value),
        child: Opacity(opacity: _fade.value, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.text5,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'What would you like to do?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '"$preview"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.text3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ChooserOption(
                      emoji: '📖',
                      label: 'Dictionary',
                      sublabel: 'Look up meaning',
                      color: const Color(0xFF339AF0),
                      colors: colors,
                      onTap: () => Navigator.of(context).pop('dictionary'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ChooserOption(
                      emoji: '✨',
                      label: 'Rephrase',
                      sublabel: 'Rewrite text',
                      color: const Color(0xFFC084FC),
                      colors: colors,
                      onTap: () => Navigator.of(context).pop('rephrase'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ChooserOption(
                      emoji: '🔍',
                      label: 'Search',
                      sublabel: 'Search the web',
                      color: const Color(0xFF34D399),
                      colors: colors,
                      onTap: () => Navigator.of(context).pop('search'),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _ChooserOption extends StatelessWidget {
  const _ChooserOption({
    required this.emoji,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.colors,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final String sublabel;
  final Color color;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Share chooser (from ACTION_SEND) ──────────────────────────────────────────

class _ShareChooser extends StatefulWidget {
  const _ShareChooser({
    this.text,
    required this.hasImage,
    required this.hasUrl,
    required this.colors,
  });

  final String? text;
  final bool hasImage;
  final bool hasUrl;
  final AppColors colors;

  @override
  State<_ShareChooser> createState() => _ShareChooserState();
}

class _ShareChooserState extends State<_ShareChooser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final preview = widget.text != null
        ? (widget.text!.length > 50
            ? '${widget.text!.substring(0, 50)}…'
            : widget.text!)
        : 'Image shared';

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _slide.value),
        child: Opacity(opacity: _fade.value, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: c.bg1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.text5,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Send to…',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: c.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '"$preview"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: c.text4,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _ShareOption(
                    icon: Icons.receipt_long_rounded,
                    label: 'Expense',
                    sublabel: 'Scan receipt',
                    color: const Color(0xFFFF6B6B),
                    colors: c,
                    delay: 0,
                    parentAnim: _anim,
                    onTap: () => Navigator.of(context).pop('expense'),
                  ),
                  const SizedBox(width: 8),
                  _ShareOption(
                    icon: Icons.link_rounded,
                    label: 'Summarize',
                    sublabel: 'URL summary',
                    color: const Color(0xFF339AF0),
                    colors: c,
                    delay: 1,
                    parentAnim: _anim,
                    onTap: () => Navigator.of(context).pop('summarizer'),
                  ),
                  const SizedBox(width: 8),
                  _ShareOption(
                    icon: Icons.menu_book_rounded,
                    label: 'Dictionary',
                    sublabel: 'Look up',
                    color: const Color(0xFF51CF66),
                    colors: c,
                    delay: 2,
                    parentAnim: _anim,
                    enabled: widget.text != null,
                    onTap: () => Navigator.of(context).pop('dictionary'),
                  ),
                  const SizedBox(width: 8),
                  _ShareOption(
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Rephrase',
                    sublabel: 'Rewrite',
                    color: const Color(0xFFC084FC),
                    colors: c,
                    delay: 3,
                    parentAnim: _anim,
                    enabled: widget.text != null,
                    onTap: () => Navigator.of(context).pop('rephrase'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _ShareOption extends StatefulWidget {
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.colors,
    required this.delay,
    required this.parentAnim,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final AppColors colors;
  final int delay;
  final Animation<double> parentAnim;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_ShareOption> createState() => _ShareOptionState();
}

class _ShareOptionState extends State<_ShareOption>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  late final Animation<double> _stagger;

  @override
  void initState() {
    super.initState();
    final start = (widget.delay * 0.12).clamp(0.0, 0.7);
    _stagger = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: widget.parentAnim,
        curve: Interval(start, 1.0, curve: Curves.easeOutBack),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final alpha = widget.enabled ? 1.0 : 0.35;

    return Expanded(
      child: AnimatedBuilder(
        animation: _stagger,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 20 * (1 - _stagger.value)),
          child: Opacity(
            opacity: _stagger.value.clamp(0.0, 1.0),
            child: child,
          ),
        ),
        child: GestureDetector(
          onTapDown: widget.enabled
              ? (_) => setState(() => _scale = 0.92)
              : null,
          onTapUp: widget.enabled
              ? (_) {
                  setState(() => _scale = 1.0);
                  widget.onTap();
                }
              : null,
          onTapCancel: () => setState(() => _scale = 1.0),
          child: AnimatedScale(
            scale: _scale,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: Opacity(
              opacity: alpha,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(widget.icon, size: 20, color: widget.color),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.sublabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9.5,
                        color: c.text4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
