import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/ai_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/ai_models_service.dart';
import 'settings_controller.dart';

const _signOutRed = Color(0xFFEF4444);

/// Opens the settings sheet (draggable). Syncs [settingsOpen] on the controller.
void showSettingsModal(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(settingsProvider.notifier);
  notifier.openSettings();
  notifier.resyncFromServer();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    enableDrag: true,
    useSafeArea: true,
    builder: (modalContext) {
      final h = MediaQuery.sizeOf(modalContext).height;
      return SizedBox(
        height: h,
        child: DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.75,
          snap: true,
          snapSizes: const [0.35, 0.55, 0.75],
          builder: (sheetCtx, scrollController) {
            return _SettingsSheet(scrollController: scrollController);
          },
        ),
      );
    },
  ).whenComplete(() {
    notifier.closeSettings();
  });
}

/// The sheet body. Uses a [Consumer] builder internally so that Riverpod
/// registers the watch on an element that lives inside the modal overlay —
/// guaranteeing instant rebuilds when settings change.
class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Consumer(
        builder: (context, ref, _) {
          final colors = Theme.of(context).extension<AppColors>()!;
          final settings = ref.watch(settingsProvider);
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          final notifier = ref.read(settingsProvider.notifier);

          return Material(
            color: colors.bg1,
            child: CustomScrollView(
              controller: scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.text5,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Center(
                          child: Text(
                            'Settings',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.text,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      _ProfileSection(colors: colors),
                      Divider(height: 1, thickness: 1, color: colors.border),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _ThemeSection(
                          colors: colors,
                          theme: settings.theme,
                          onSetTheme: (t) => notifier.setTheme(t),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _DeepModelSection(
                          colors: colors,
                          deepModel: settings.deepModel,
                          onChanged: (m) => notifier.setDeepModel(m),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _LiteModelSection(
                          colors: colors,
                          liteModel: settings.liteModel,
                          onChanged: (m) => notifier.setLiteModel(m),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _XGrokSection(
                          colors: colors,
                          enabled: settings.xgrokEnabled,
                          liteModel: settings.xgrokLiteModel,
                          deepModel: settings.xgrokDeepModel,
                          thinkingModel: settings.xgrokThinkingModel,
                          summarizeOverride: settings.summarizeOverride,
                          defaultFollowUpProvider:
                              settings.defaultFollowUpProvider,
                          onlineSearchProvider:
                              settings.onlineSearchProvider,
                          onEnabledChanged: (v) =>
                              notifier.setXGrokEnabled(v),
                          onLiteModelChanged: (m) =>
                              notifier.setXGrokLiteModel(m),
                          onDeepModelChanged: (m) =>
                              notifier.setXGrokDeepModel(m),
                          onThinkingModelChanged: (m) =>
                              notifier.setXGrokThinkingModel(m),
                          onSummarizeOverrideChanged: (v) {
                            notifier.setSummarizeOverride(v);
                            final serverValue =
                                v == 'xgrok' ? 'xgrok' : 'litellm';
                            ref.read(tutorAiServiceProvider).pushAppSetting(
                              'news_summarize_provider',
                              serverValue,
                            );
                          },
                          onDefaultFollowUpChanged: (v) =>
                              notifier.setDefaultFollowUpProvider(v),
                          onOnlineSearchChanged: (v) =>
                              notifier.setOnlineSearchProvider(v),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _BanksSection(
                          colors: colors,
                          banks: settings.banks,
                          notifier: notifier,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _SignOutButton(colors: colors),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          '${AppConstants.appName}  •  ${AppConstants.appVersion}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: colors.text5,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      SizedBox(height: 32 + bottomInset),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Profile ──────────────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final displayName = AuthService.instance.username;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.accent, AppColors.accentCyan],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.isDark ? const Color(0xFF111111) : Colors.white,
                border: Border.all(
                  color: colors.isDark
                      ? Colors.black
                      : const Color(0xFFE2E8F0),
                  width: 2,
                ),
              ),
              child: const Center(
                child: Text(
                  '😎',
                  style: TextStyle(fontSize: 34),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            displayName.isNotEmpty ? displayName : 'User',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: colors.text,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              initial,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Theme toggle ─────────────────────────────────────────────────────────────

class _ThemeSection extends StatelessWidget {
  const _ThemeSection({
    required this.colors,
    required this.theme,
    required this.onSetTheme,
  });

  final AppColors colors;
  final String theme;
  final void Function(String) onSetTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'THEME',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: colors.text3,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ThemeSegment(
                  label: 'AMOLED Dark',
                  icon: LucideIcons.moon,
                  selected: theme == 'dark',
                  colors: colors,
                  onTap: () => onSetTheme('dark'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ThemeSegment(
                  label: 'White',
                  icon: LucideIcons.sun,
                  selected: theme == 'white',
                  colors: colors,
                  onTap: () => onSetTheme('white'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : colors.text3;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    LucideIcons.check,
                    size: 12,
                    color: Colors.white,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Deep Research Model ──────────────────────────────────────────────────────

class _DeepModelSection extends StatefulWidget {
  const _DeepModelSection({
    required this.colors,
    required this.deepModel,
    required this.onChanged,
  });

  final AppColors colors;
  final String deepModel;
  final void Function(String) onChanged;

  @override
  State<_DeepModelSection> createState() => _DeepModelSectionState();
}

class _DeepModelSectionState extends State<_DeepModelSection> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.deepModel);
  }

  @override
  void didUpdateWidget(_DeepModelSection old) {
    super.didUpdateWidget(old);
    if (!_editing && old.deepModel != widget.deepModel) {
      _ctrl.text = widget.deepModel;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final value = _ctrl.text.trim();
    if (value.isNotEmpty && value != widget.deepModel) {
      widget.onChanged(value);
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'DEEP RESEARCH MODEL',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: colors.text3,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Gemini model used for Deep follow-up & research',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: colors.text4,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _editing
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : colors.border,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    LucideIcons.brain,
                    key: ValueKey(_editing),
                    size: 16,
                    color: _editing ? AppColors.accent : colors.text3,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  readOnly: !_editing,
                  onTap: () {
                    if (!_editing) setState(() => _editing = true);
                  },
                  onSubmitted: (_) => _save(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 13,
                    ),
                    hintText: 'e.g. gemini-3.1-pro-preview',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: colors.text5,
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: _editing
                    ? GestureDetector(
                        key: const ValueKey('save'),
                        onTap: _save,
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Save',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        key: const ValueKey('edit'),
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          LucideIcons.pencil,
                          size: 14,
                          color: colors.text4,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Gemini Lite Model ────────────────────────────────────────────────────────

class _LiteModelSection extends ConsumerStatefulWidget {
  const _LiteModelSection({
    required this.colors,
    required this.liteModel,
    required this.onChanged,
  });

  final AppColors colors;
  final String liteModel;
  final void Function(String) onChanged;

  @override
  ConsumerState<_LiteModelSection> createState() => _LiteModelSectionState();
}

class _LiteModelSectionState extends ConsumerState<_LiteModelSection> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  // Async state of the `/api/v1/ai/models` fetch — `null` while
  // idle, populated after the first `_loadModels()` call. Errors
  // are captured into [_listError] so the UI can show a hint
  // instead of throwing.
  GeminiModelList? _modelList;
  bool _listLoading = false;
  String? _listError;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.liteModel);
    // Kick off model discovery on first build so the chips are
    // ready by the time the user taps the field. Cheap (cached
    // server-side 5 min) and avoids a UI stall on tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadModels());
  }

  @override
  void didUpdateWidget(_LiteModelSection old) {
    super.didUpdateWidget(old);
    if (!_editing && old.liteModel != widget.liteModel) {
      _ctrl.text = widget.liteModel;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadModels({bool force = false}) async {
    if (_listLoading) return;
    setState(() {
      _listLoading = true;
      _listError = null;
    });
    try {
      final list = await ref.read(aiModelsServiceProvider).list(force: force);
      if (!mounted) return;
      setState(() {
        _modelList = list;
        _listLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = e is AiError ? e.toastMessage : 'Could not load models';
        _listLoading = false;
      });
    }
  }

  void _save() {
    final value = _ctrl.text.trim();
    if (value.isNotEmpty && value != widget.liteModel) {
      widget.onChanged(value);
    }
    setState(() => _editing = false);
  }

  void _applyModel(String id) {
    if (id.isEmpty) return;
    _ctrl.text = id;
    if (id != widget.liteModel) widget.onChanged(id);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'GEMINI LITE MODEL',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: colors.text3,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Gemini model for fast tasks: bill scan, expense categorize, '
          'news summary, article lite follow-up, tutor (summarizer, '
          'rephrase, coach, dictionary).',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: colors.text4,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _editing
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : colors.border,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    LucideIcons.zap,
                    key: ValueKey(_editing),
                    size: 16,
                    color: _editing ? AppColors.accent : colors.text3,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  readOnly: !_editing,
                  onTap: () {
                    if (!_editing) setState(() => _editing = true);
                  },
                  onSubmitted: (_) => _save(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 13,
                    ),
                    hintText: 'e.g. gemini-3.1-flash-lite-preview',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: colors.text5,
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: _editing
                    ? GestureDetector(
                        key: const ValueKey('save-lite'),
                        onTap: _save,
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Save',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        key: const ValueKey('edit-lite'),
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          LucideIcons.pencil,
                          size: 14,
                          color: colors.text4,
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _AvailableModelsRow(
          colors: colors,
          loading: _listLoading,
          list: _modelList,
          error: _listError,
          currentId: _ctrl.text.trim(),
          onSelect: _applyModel,
          onRefresh: () => _loadModels(force: true),
        ),
      ],
    );
  }
}

// Compact horizontal scroller of model-id chips backed by the live
// `/api/v1/ai/models` endpoint. Solves the original failure mode of
// this screen — the user typing a model id Google has retired or
// hasn't shipped yet — by surfacing only what the configured server
// API key can actually invoke right now. Refresh icon busts the
// 5-minute server-side cache for the case when Google ships a new
// model and the user wants to see it without waiting.
class _AvailableModelsRow extends StatelessWidget {
  const _AvailableModelsRow({
    required this.colors,
    required this.loading,
    required this.list,
    required this.error,
    required this.currentId,
    required this.onSelect,
    required this.onRefresh,
  });

  final AppColors colors;
  final bool loading;
  final GeminiModelList? list;
  final String? error;
  final String currentId;
  final void Function(String id) onSelect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'AVAILABLE MODELS',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: colors.text4,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: loading ? null : onRefresh,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: loading
                          ? CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: colors.text4,
                            )
                          : Icon(LucideIcons.refreshCw, size: 12, color: colors.text4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Refresh',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.text4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    if (error != null) {
      return Text(
        error!,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          color: const Color(0xFFEF4444),
          height: 1.4,
        ),
      );
    }
    final models = list?.models ?? const [];
    if (loading && models.isEmpty) {
      return Text(
        'Loading…',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          color: colors.text4,
        ),
      );
    }
    if (models.isEmpty) {
      return Text(
        'No models discovered. Tap Refresh once the server has GOOGLE_API_KEY configured.',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          color: colors.text4,
          height: 1.5,
        ),
      );
    }
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: models.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final m = models[i];
          final selected = m.id == currentId;
          return GestureDetector(
            onTap: () => onSelect(m.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.16)
                    : colors.bg2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.55)
                      : colors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    const Icon(LucideIcons.check, size: 12, color: AppColors.accent),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    m.id,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.accent : colors.text2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── xGrok Section ────────────────────────────────────────────────────────────

class _XGrokSection extends StatefulWidget {
  const _XGrokSection({
    required this.colors,
    required this.enabled,
    required this.liteModel,
    required this.deepModel,
    required this.thinkingModel,
    required this.summarizeOverride,
    required this.defaultFollowUpProvider,
    required this.onlineSearchProvider,
    required this.onEnabledChanged,
    required this.onLiteModelChanged,
    required this.onDeepModelChanged,
    required this.onThinkingModelChanged,
    required this.onSummarizeOverrideChanged,
    required this.onDefaultFollowUpChanged,
    required this.onOnlineSearchChanged,
  });

  final AppColors colors;
  final bool enabled;
  final String liteModel;
  final String deepModel;
  final String thinkingModel;
  final String summarizeOverride;
  final String defaultFollowUpProvider;
  final String onlineSearchProvider;
  final void Function(bool) onEnabledChanged;
  final void Function(String) onLiteModelChanged;
  final void Function(String) onDeepModelChanged;
  final void Function(String) onThinkingModelChanged;
  final void Function(String) onSummarizeOverrideChanged;
  final void Function(String) onDefaultFollowUpChanged;
  final void Function(String) onOnlineSearchChanged;

  @override
  State<_XGrokSection> createState() => _XGrokSectionState();
}

class _XGrokSectionState extends State<_XGrokSection> {
  late final TextEditingController _liteCtrl;
  late final TextEditingController _deepCtrl;
  late final TextEditingController _thinkingCtrl;
  bool _editingLite = false;
  bool _editingDeep = false;
  bool _editingThinking = false;

  @override
  void initState() {
    super.initState();
    _liteCtrl = TextEditingController(text: widget.liteModel);
    _deepCtrl = TextEditingController(text: widget.deepModel);
    _thinkingCtrl = TextEditingController(text: widget.thinkingModel);
  }

  @override
  void didUpdateWidget(_XGrokSection old) {
    super.didUpdateWidget(old);
    if (!_editingLite && old.liteModel != widget.liteModel) {
      _liteCtrl.text = widget.liteModel;
    }
    if (!_editingDeep && old.deepModel != widget.deepModel) {
      _deepCtrl.text = widget.deepModel;
    }
    if (!_editingThinking && old.thinkingModel != widget.thinkingModel) {
      _thinkingCtrl.text = widget.thinkingModel;
    }
  }

  @override
  void dispose() {
    _liteCtrl.dispose();
    _deepCtrl.dispose();
    _thinkingCtrl.dispose();
    super.dispose();
  }

  void _saveLite() {
    final value = _liteCtrl.text.trim();
    if (value.isNotEmpty && value != widget.liteModel) {
      widget.onLiteModelChanged(value);
    }
    setState(() => _editingLite = false);
  }

  void _saveDeep() {
    final value = _deepCtrl.text.trim();
    if (value.isNotEmpty && value != widget.deepModel) {
      widget.onDeepModelChanged(value);
    }
    setState(() => _editingDeep = false);
  }

  void _saveThinking() {
    final value = _thinkingCtrl.text.trim();
    if (value.isNotEmpty && value != widget.thinkingModel) {
      widget.onThinkingModelChanged(value);
    }
    setState(() => _editingThinking = false);
  }

  static const _xgrokColor = Color(0xFFE8453C);

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'xGROK',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: colors.text3,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => widget.onEnabledChanged(!widget.enabled),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.enabled
                  ? _xgrokColor.withValues(alpha: 0.08)
                  : colors.bg2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.enabled
                    ? _xgrokColor.withValues(alpha: 0.3)
                    : colors.border,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color:
                        widget.enabled ? _xgrokColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: widget.enabled ? _xgrokColor : colors.text4,
                      width: 2,
                    ),
                  ),
                  child: widget.enabled
                      ? const Icon(
                          LucideIcons.check,
                          size: 13,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Enable xGrok Models',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.enabled ? _xgrokColor : colors.text2,
                    ),
                  ),
                ),
                Text(
                  'xAI',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: widget.enabled
                        ? _xgrokColor.withValues(alpha: 0.7)
                        : colors.text5,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          sizeCurve: Curves.easeOutCubic,
          crossFadeState: widget.enabled
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: _buildEnabledContent(colors),
        ),
      ],
    );
  }

  Widget _buildEnabledContent(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _buildModelField(
          label: 'Lite Model',
          ctrl: _liteCtrl,
          editing: _editingLite,
          onTap: () => setState(() => _editingLite = true),
          onSave: _saveLite,
          hint: 'e.g. grok-4-1-fast-non-reasoning',
          colors: colors,
        ),
        const SizedBox(height: 10),
        _buildModelField(
          label: 'Deep Model',
          ctrl: _deepCtrl,
          editing: _editingDeep,
          onTap: () => setState(() => _editingDeep = true),
          onSave: _saveDeep,
          hint: 'e.g. grok-4-0709',
          colors: colors,
        ),
        const SizedBox(height: 10),
        _buildModelField(
          label: 'Thinking Model',
          ctrl: _thinkingCtrl,
          editing: _editingThinking,
          onTap: () => setState(() => _editingThinking = true),
          onSave: _saveThinking,
          hint: 'e.g. grok-4-1-fast-reasoning',
          colors: colors,
        ),
        const SizedBox(height: 14),
        Text(
          'ARTICLE SUMMARIZE OVERRIDE',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: colors.text3,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Override the article summarizer model provider',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: colors.text4,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _OverrideSegment(
                  label: 'Gemini',
                  selected: widget.summarizeOverride == 'gemini',
                  color: AppColors.accent,
                  colors: colors,
                  onTap: () =>
                      widget.onSummarizeOverrideChanged('gemini'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OverrideSegment(
                  label: 'xGrok',
                  selected: widget.summarizeOverride == 'xgrok',
                  color: _xgrokColor,
                  colors: colors,
                  onTap: () =>
                      widget.onSummarizeOverrideChanged('xgrok'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'ONLINE SEARCH',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: colors.text3,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Provider for real-time web search queries',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: colors.text4,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _OverrideSegment(
                  label: 'Gemini',
                  selected: widget.onlineSearchProvider == 'gemini',
                  color: AppColors.accent,
                  colors: colors,
                  onTap: () =>
                      widget.onOnlineSearchChanged('gemini'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OverrideSegment(
                  label: 'xGrok',
                  selected: widget.onlineSearchProvider == 'xgrok',
                  color: _xgrokColor,
                  colors: colors,
                  onTap: () =>
                      widget.onOnlineSearchChanged('xgrok'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'DEFAULT FOLLOW-UP PROVIDER',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: colors.text3,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pre-select the AI provider for article & search follow-ups',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: colors.text4,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _OverrideSegment(
                  label: 'Gemini',
                  selected: widget.defaultFollowUpProvider == 'gemini',
                  color: AppColors.accent,
                  colors: colors,
                  onTap: () =>
                      widget.onDefaultFollowUpChanged('gemini'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OverrideSegment(
                  label: 'xGrok',
                  selected: widget.defaultFollowUpProvider == 'xgrok',
                  color: _xgrokColor,
                  colors: colors,
                  onTap: () =>
                      widget.onDefaultFollowUpChanged('xgrok'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelField({
    required String label,
    required TextEditingController ctrl,
    required bool editing,
    required VoidCallback onTap,
    required VoidCallback onSave,
    required String hint,
    required AppColors colors,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.text3,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: editing
                  ? _xgrokColor.withValues(alpha: 0.5)
                  : colors.border,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(
                  LucideIcons.cpu,
                  size: 14,
                  color: editing ? _xgrokColor : colors.text4,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  readOnly: !editing,
                  onTap: () {
                    if (!editing) onTap();
                  },
                  onSubmitted: (_) => onSave(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 11,
                    ),
                    hintText: hint,
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: colors.text5,
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: editing
                    ? GestureDetector(
                        key: const ValueKey('save-xgrok'),
                        onTap: onSave,
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _xgrokColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Save',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        key: const ValueKey('edit-xgrok'),
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(
                          LucideIcons.pencil,
                          size: 12,
                          color: colors.text5,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Override Segment (shared by summarize + follow-up) ───────────────────────

class _OverrideSegment extends StatelessWidget {
  const _OverrideSegment({
    required this.label,
    required this.selected,
    required this.color,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : colors.text3;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(LucideIcons.check, size: 12, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Banks & Cards ────────────────────────────────────────────────────────────

const Map<String, String> _cardTypeLabels = {
  kCardTypeDebit: 'Debit',
  kCardTypeCredit: 'Credit',
  kCardTypeCash: 'Cash',
};

Color _parseBankColor(String hex) {
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF868E96) : Color(v);
}

class _BanksSection extends StatelessWidget {
  const _BanksSection({
    required this.colors,
    required this.banks,
    required this.notifier,
  });

  final AppColors colors;
  final List<Bank> banks;
  final SettingsController notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'BANKS & CARDS',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: colors.text3,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage the cards you log expenses against. Set each credit card\'s '
          'statement & due dates to power the repayment forecast. Syncs across '
          'all your devices.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: colors.text4,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        if (banks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No banks yet — add your first card below.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.text4,
              ),
            ),
          )
        else
          ...banks.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BankRow(
                colors: colors,
                bank: b,
                onEdit: () => _showBankEditor(
                  context,
                  colors: colors,
                  notifier: notifier,
                  existing: b,
                ),
                onDelete: () => notifier.deleteBank(b.id),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Material(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _showBankEditor(
              context,
              colors: colors,
              notifier: notifier,
            ),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.plus, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Add bank / card',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow({
    required this.colors,
    required this.bank,
    required this.onEdit,
    required this.onDelete,
  });

  final AppColors colors;
  final Bank bank;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = _parseBankColor(bank.color);
    final typeLabel = _cardTypeLabels[bank.cardType] ?? bank.cardType;
    final isCc = bank.cardType == kCardTypeCredit;
    final cycle = isCc && bank.statementDay != null && bank.dueDay != null
        ? 'Statement ${bank.statementDay} · Due ${bank.dueDay}'
        : (isCc ? 'Set statement & due dates' : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        bank.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isCc
                            ? const Color(0x33F59E0B)
                            : colors.bg3,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isCc
                              ? const Color(0xFFF59E0B)
                              : colors.text3,
                        ),
                      ),
                    ),
                  ],
                ),
                if (cycle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    cycle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colors.text4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.pencil, size: 16, color: colors.text3),
            tooltip: 'Edit',
          ),
          IconButton(
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.trash2, size: 16, color: _signOutRed),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet editor for adding a new card or editing an existing one.
void _showBankEditor(
  BuildContext context, {
  required AppColors colors,
  required SettingsController notifier,
  Bank? existing,
}) {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  String cardType = existing?.cardType ?? kCardTypeDebit;
  int statementDay = existing?.statementDay ?? 1;
  int dueDay = existing?.dueDay ?? 1;
  bool attemptedSubmit = false;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final bottomInset = MediaQuery.viewInsetsOf(sheetCtx).bottom;
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final isCc = cardType == kCardTypeCredit;
          final nameError = attemptedSubmit && nameCtrl.text.trim().isEmpty;

          void submit() {
            setSheet(() => attemptedSubmit = true);
            if (nameCtrl.text.trim().isEmpty) return;
            if (existing == null) {
              notifier.addBank(
                nameCtrl.text,
                cardType: cardType,
                statementDay: isCc ? statementDay : null,
                dueDay: isCc ? dueDay : null,
              );
            } else {
              notifier.updateBank(
                existing.id,
                name: nameCtrl.text,
                cardType: cardType,
                statementDay: isCc ? statementDay : null,
                dueDay: isCc ? dueDay : null,
              );
            }
            Navigator.of(ctx).pop();
          }

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Container(
              decoration: BoxDecoration(
                color: colors.bg1,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.text5,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    existing == null ? 'Add bank / card' : 'Edit card',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'BANK NAME',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: colors.text3,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.bg2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: nameError
                            ? _signOutRed.withValues(alpha: 0.5)
                            : colors.border,
                      ),
                    ),
                    child: TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) {
                        if (attemptedSubmit) setSheet(() {});
                      },
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        hintText: 'e.g. HDFC',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: colors.text5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CARD TYPE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: colors.text3,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final t in kBankCardTypes) ...[
                        Expanded(
                          child: _CardTypeChip(
                            label: _cardTypeLabels[t] ?? t,
                            selected: cardType == t,
                            colors: colors,
                            onTap: () => setSheet(() => cardType = t),
                          ),
                        ),
                        if (t != kBankCardTypes.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 220),
                    sizeCurve: Curves.easeOutCubic,
                    crossFadeState: isCc
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _DayStepper(
                                label: 'Statement day',
                                value: statementDay,
                                colors: colors,
                                onChanged: (v) =>
                                    setSheet(() => statementDay = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DayStepper(
                                label: 'Due day',
                                value: dueDay,
                                colors: colors,
                                onChanged: (v) => setSheet(() => dueDay = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Statement closes on the statement day; the bill is '
                          'due on the due day of the following month.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: colors.text4,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: submit,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        child: Text(
                          existing == null ? 'Add card' : 'Save changes',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(nameCtrl.dispose);
}

class _CardTypeChip extends StatelessWidget {
  const _CardTypeChip({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.14) : colors.bg2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : colors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.accent : colors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayStepper extends StatelessWidget {
  const _DayStepper({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  final String label;
  final int value;
  final AppColors colors;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.text3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              _StepBtn(
                icon: LucideIcons.minus,
                colors: colors,
                onTap: () => onChanged(value <= 1 ? 31 : value - 1),
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
              _StepBtn(
                icon: LucideIcons.plus,
                colors: colors,
                onTap: () => onChanged(value >= 31 ? 1 : value + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, size: 16, color: colors.text2),
        ),
      ),
    );
  }
}

// ── Sign Out ─────────────────────────────────────────────────────────────────

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _signOutRed.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          AuthService.instance.logout();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _signOutRed.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                LucideIcons.logOut,
                size: 18,
                color: _signOutRed,
              ),
              const SizedBox(width: 10),
              Text(
                'Sign Out',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _signOutRed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
