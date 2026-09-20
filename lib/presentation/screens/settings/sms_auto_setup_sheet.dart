import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/services/sms_auto_expense/sms_auto_expense_service.dart';

const _accent = Color(0xFF0D59F2);
const _good = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);

Future<void> showSmsAutoSetupSheet(
  BuildContext context,
  SmsAutoExpenseController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    useSafeArea: true,
    builder: (_) => _SmsAutoSetupSheet(controller: controller),
  );
}

class _SmsAutoSetupSheet extends StatefulWidget {
  const _SmsAutoSetupSheet({required this.controller});

  final SmsAutoExpenseController controller;

  @override
  State<_SmsAutoSetupSheet> createState() => _SmsAutoSetupSheetState();
}

class _SmsAutoSetupSheetState extends State<_SmsAutoSetupSheet>
    with WidgetsBindingObserver {
  SmsExpenseStatus _status = const SmsExpenseStatus.unknown();
  bool _trying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await widget.controller.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _trySample() async {
    setState(() => _trying = true);
    try {
      await widget.controller.playSample();
    } finally {
      if (mounted) {
        setState(() => _trying = false);
        Navigator.of(context).pop();
      }
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
                    const Icon(LucideIcons.smartphoneNfc, size: 18, color: _accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SMS auto-log setup',
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
                  'When a bank sends a debit SMS, Nexus parses it on the phone '
                  'in a few milliseconds. Auto-save writes it as an expense; '
                  'Ask me shows Approve / Reject. The + button is unchanged. '
                  'Passwords and OTPs are ignored. Tapping one notification '
                  'never drops the other.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.45,
                    color: colors.text3,
                  ),
                ),
                const SizedBox(height: 18),
                _statusRow(
                  colors,
                  label: 'SMS permission',
                  ok: _status.permissionGranted,
                  okText: 'Granted',
                  badText: 'Needed',
                ),
                _statusRow(
                  colors,
                  label: 'Notifications',
                  ok: _status.notificationGranted,
                  okText: 'Granted',
                  badText: 'Needed when Nexus is closed',
                  warnOnly: true,
                ),
                _statusRow(
                  colors,
                  label: 'Auto-detect',
                  ok: _status.enabled,
                  okText: 'On',
                  badText: 'Off',
                ),
                _statusRow(
                  colors,
                  label: 'Battery',
                  ok: _status.batteryUnrestricted,
                  okText: 'Unrestricted',
                  badText: 'Optimised (SMS may be delayed)',
                  warnOnly: true,
                ),
                const SizedBox(height: 16),
                Text(
                  'WHEN A DEBIT ARRIVES',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colors.text3,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 8),
                _modeTile(
                  colors,
                  selected: !_status.auto,
                  title: 'Ask me',
                  body: 'A small sheet with Approve / Reject. Best while you learn it.',
                  onTap: () async {
                    await widget.controller.setMode('ask');
                    await _refresh();
                  },
                ),
                _modeTile(
                  colors,
                  selected: _status.auto,
                  title: 'Auto-save',
                  body:                   'Save immediately, even if Nexus is in the background. '
                  'Fix the category later from the expense list. '
                  'If the app was closed, every queued debit saves the next time you open it — no Approve needed.',
                  onTap: () async {
                    await widget.controller.setMode('auto');
                    await _refresh();
                  },
                ),
                const SizedBox(height: 16),
                _step(
                  colors,
                  index: 1,
                  title: 'Allow SMS',
                  body: 'Nexus only reads incoming bank alerts — never your inbox, '
                      'never replies. Android will ask once.',
                  action: 'Grant SMS permission',
                  onTap: () async {
                    await widget.controller.requestSmsPermission();
                    await _refresh();
                  },
                ),
                _step(
                  colors,
                  index: 2,
                  title: 'Turn auto-detect on',
                  body: 'The listener stays asleep until a bank sender matches, '
                      'or the SMS body is a Scapia / Federal Bank debit. '
                      'No polling, no foreground service.',
                  action: _status.enabled ? 'Enabled' : 'Enable auto-detect',
                  onTap: _status.enabled
                      ? null
                      : () async {
                          await widget.controller.setEnabled(true);
                          await _refresh();
                        },
                ),
                _step(
                  colors,
                  index: 3,
                  title: 'Keep it alive',
                  body: 'Samsung and Xiaomi can delay SMS broadcasts. Set battery '
                      'to Unrestricted so a debit still logs after hours idle.',
                  action: 'Set battery to unrestricted',
                  onTap: () async {
                    await widget.controller.requestBatteryUnrestricted();
                    await _refresh();
                  },
                ),
                _step(
                  colors,
                  index: 4,
                  title: 'Try it',
                  body: 'Runs a sample debit through the same parser used for '
                      'HDFC, Axis, ICICI and Scapia. '
                      'Nothing is charged. Approve to save or Reject to discard. '
                      'If Nexus was killed, queued debits all save the next time you open the app — tap either notification, or just open Nexus. '
                      'An APK update can drop SMS permission — run Set up again.',
                  action: _trying ? 'Trying…' : 'Try with a sample debit',
                  onTap: _trying ? null : _trySample,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  Widget _modeTile(
    AppColors colors, {
    required bool selected,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? _accent.withValues(alpha: 0.10) : colors.bg2,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _accent.withValues(alpha: 0.45) : colors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
                  size: 16,
                  color: selected ? _accent : colors.text3,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          height: 1.4,
                          color: colors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
