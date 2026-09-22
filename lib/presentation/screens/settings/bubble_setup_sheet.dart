import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../bubble/bubble_settings_channel.dart';
import '../../../bubble/overlay/bubble.dart';
import '../../../bubble/rephrase/bubble_rephrase_client.dart';
import '../../../bubble/rephrase/resilience.dart';
import '../../../core/theme/app_colors.dart';

const _accent = Color(0xFF0D59F2);
const _good = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);

/// Setup and troubleshooting for the floating rephrase bubble.
///
/// Sideloaded builds need three separate grants, and Android 13+ hides the
/// accessibility toggle behind "Allow restricted settings", so each step is
/// spelled out with its own button.
Future<void> showBubbleSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    useSafeArea: true,
    builder: (_) => const _BubbleSetupSheet(),
  );
}

class _BubbleSetupSheet extends StatefulWidget {
  const _BubbleSetupSheet();

  @override
  State<_BubbleSetupSheet> createState() => _BubbleSetupSheetState();
}

class _BubbleSetupSheetState extends State<_BubbleSetupSheet>
    with WidgetsBindingObserver {
  static const _channel = BubbleSettingsChannel();

  final _testCtrl = TextEditingController(
    text: 'hey can we push the meeting to tomorrow morning please',
  );
  final _client = BubbleRephraseClient();

  BubbleStatus _status = const BubbleStatus.unknown();
  bool _testing = false;
  String? _testResult;
  String? _testError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _testCtrl.dispose();
    super.dispose();
  }

  /// The user leaves for system settings and comes back — re-read the grants.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _channel.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _runTest() async {
    final text = _testCtrl.text.trim();
    if (text.isEmpty || _testing) return;
    setState(() {
      _testing = true;
      _testResult = null;
      _testError = null;
    });
    try {
      final result = await _client.rephrase(text: text, platform: 'casual');
      if (!mounted) return;
      setState(() {
        _testResult = result;
        _testing = false;
      });
    } on BubbleError catch (e) {
      if (!mounted) return;
      setState(() {
        _testError = e.display;
        _testing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testError = 'Rephrase failed';
        _testing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Material(
        color: colors.bg1,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(18, 12, 18, 24 + bottomInset),
            child: Column(
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
                Row(
                  children: [
                    // The real overlay mark, not an approximation — this is
                    // exactly what appears over other apps.
                    const SizedBox(
                      width: 56,
                      height: 56,
                      child: RephraseBubble(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Rephrase bubble setup',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: colors.text,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Type in any app, pause, and the bubble appears next to '
                  'the field. Pick a platform and the text is replaced in place. '
                  'Password fields are skipped and nothing is logged.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.45,
                    color: colors.text3,
                  ),
                ),
                const SizedBox(height: 18),
                _statusRow(
                  colors,
                  label: 'Accessibility service',
                  ok: _status.serviceEnabled,
                  okText: 'Enabled',
                  badText: 'Not enabled',
                ),
                _statusRow(
                  colors,
                  label: 'Bubble switch',
                  ok: _status.enabled,
                  okText: 'On',
                  badText: 'Off',
                ),
                _statusRow(
                  colors,
                  label: 'Battery',
                  ok: _status.batteryUnrestricted,
                  okText: 'Unrestricted',
                  badText: 'Optimised (may be killed)',
                  warnOnly: true,
                ),
                const SizedBox(height: 20),
                _sectionLabel(colors, 'SETUP STEPS'),
                const SizedBox(height: 10),
                _step(
                  colors,
                  index: 1,
                  title: 'Allow restricted settings',
                  body: 'Sideloaded apps have the accessibility toggle greyed out. '
                      'In App info, open the three-dot menu, choose "Allow '
                      'restricted settings" and authenticate.',
                  action: 'Open App info',
                  onTap: _channel.openAppInfo,
                ),
                _step(
                  colors,
                  index: 2,
                  title: 'Turn on the service',
                  body: 'Find "Nexus AI Rephrase Bubble" under Installed apps or '
                      'Downloaded apps and switch it on. After an APK update '
                      'Android turns this off — enable it again.',
                  action: 'Open Accessibility settings',
                  onTap: _channel.openAccessibilitySettings,
                ),
                _step(
                  colors,
                  index: 3,
                  title: 'Keep it alive',
                  body: 'Samsung and Xiaomi kill background services. Set battery '
                      'usage to Unrestricted so the bubble survives.',
                  action: 'Set battery to unrestricted',
                  onTap: _channel.requestIgnoreBatteryOptimizations,
                ),
                _step(
                  colors,
                  index: 4,
                  title: 'Try it',
                  body: 'Open WhatsApp, Gmail, Chrome or a Nexus field, type a '
                      'sentence (8+ characters) and pause. The bubble appears '
                      'next to the field — including inside Nexus AI.',
                ),
                const SizedBox(height: 22),
                _sectionLabel(colors, 'TEST THE REPHRASE CALL'),
                const SizedBox(height: 6),
                Text(
                  'Checks that the bubble can reach the server and is signed in. '
                  'It uses the same endpoint and models as the Rephrase tab.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    height: 1.4,
                    color: colors.text3,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _testCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: colors.text,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colors.bg2,
                    isDense: true,
                    contentPadding: const EdgeInsets.all(12),
                    hintText: 'Something to rephrase',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: colors.text4,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _accent),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _testing ? null : _runTest,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.zap, size: 16),
                    label: Text(
                      _testing ? 'Rephrasing…' : 'Test rephrase (casual)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (_testResult != null || _testError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.bg2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _testError != null
                            ? _warn.withValues(alpha: 0.5)
                            : colors.border,
                      ),
                    ),
                    child: Text(
                      _testError ?? _testResult!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        height: 1.45,
                        color: _testError != null ? _warn : colors.text,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(AppColors colors, String text) => Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: colors.text3,
          letterSpacing: 1.6,
        ),
      );

  Widget _statusRow(
    AppColors colors, {
    required String label,
    required bool ok,
    required String okText,
    required String badText,
    bool warnOnly = false,
  }) {
    final color = ok ? _good : (warnOnly ? _warn : colors.text3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            ok ? LucideIcons.checkCircle2 : LucideIcons.circle,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ),
          Text(
            ok ? okText : badText,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(
    AppColors colors, {
    required int index,
    required String title,
    required String body,
    String? action,
    Future<void> Function()? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '$index',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              height: 1.45,
              color: colors.text3,
            ),
          ),
          if (action != null && onTap != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () => onTap(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  action,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
