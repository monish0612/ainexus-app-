import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import 'login_copy.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  late final AnimationController _entrance;
  late final AnimationController _shake;
  late final AnimationController _pulse;

  late final Animation<double> _orbFade;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _fieldOneFade;
  late final Animation<Offset> _fieldOneSlide;
  late final Animation<double> _fieldTwoFade;
  late final Animation<Offset> _fieldTwoSlide;
  late final Animation<double> _btnFade;
  late final Animation<Offset> _btnSlide;
  late final Animation<double> _footerFade;
  late final Animation<double> _shakeOffset;
  late final Animation<double> _pulseScale;

  bool _obscure = true;
  bool _loading = false;
  String? _error;
  late final bool _sessionExpired = AuthService.instance.didSessionExpire;

  @override
  void initState() {
    super.initState();
    if (_sessionExpired && AuthService.instance.username.isNotEmpty) {
      _usernameCtl.text = AuthService.instance.username;
    }

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    _orbFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
    );
    _logoFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.08, 0.38, curve: Curves.easeOut),
    );
    _titleFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.15, 0.45, curve: Curves.easeOut),
    );
    _subtitleFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.25, 0.55, curve: Curves.easeOut),
    );
    _fieldOneFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
    );
    _fieldOneSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic),
    ));
    _fieldTwoFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.42, 0.72, curve: Curves.easeOut),
    );
    _fieldTwoSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.42, 0.72, curve: Curves.easeOutCubic),
    ));
    _btnFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 0.85, curve: Curves.easeOut),
    );
    _btnSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 0.85, curve: Curves.easeOutCubic),
    ));
    _footerFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.72, 1.0, curve: Curves.easeOut),
    );

    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeOffset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -7), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -7, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _entrance.dispose();
    _shake.dispose();
    _pulse.dispose();
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final user = _usernameCtl.text.trim();
    final pass = _passwordCtl.text;

    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      _triggerShake();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final success = await AuthService.instance.authenticate(user, pass);

      if (!mounted) return;

      if (!success) {
        HapticFeedback.heavyImpact();
        setState(() {
          _loading = false;
          _error = 'Invalid credentials';
        });
        _triggerShake();
      }
      // On success, GoRouter redirect handles navigation automatically.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Login failed. Please try again.';
      });
      _triggerShake();
    }
  }

  void _triggerShake() {
    _shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: colors.bg,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(opacity: _orbFade, child: const _OrbsLayer()),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: CustomScrollView(
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        children: [
                          const Spacer(flex: 3),

                          // ── Logo orb ──
                          FadeTransition(
                            opacity: _logoFade,
                            child: ScaleTransition(
                              scale: _pulseScale,
                              child: const _MiniOrb(),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // ── Title ──
                          FadeTransition(
                            opacity: _titleFade,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                    colors: [
                                      AppColors.accent,
                                      AppColors.accentCyan,
                                    ],
                                  ).createShader(bounds),
                                  child: Text(
                                    'NEXUS',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                Text(
                                  'AI',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                    color: colors.text,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          FadeTransition(
                            opacity: _subtitleFade,
                            child: Text(
                              LoginCopy.subtitle(sessionExpired: _sessionExpired),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: colors.text2,
                              ),
                            ),
                          ),

                          const SizedBox(height: 44),

                          // ── Form (shake-able) ──
                          AnimatedBuilder(
                            animation: _shakeOffset,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(_shakeOffset.value, 0),
                              child: child,
                            ),
                            child: Column(
                              children: [
                                SlideTransition(
                                  position: _fieldOneSlide,
                                  child: FadeTransition(
                                    opacity: _fieldOneFade,
                                    child: _LoginField(
                                      controller: _usernameCtl,
                                      focusNode: _usernameFocus,
                                      hint: 'Username',
                                      icon: LucideIcons.user,
                                      hasError: _error != null,
                                      textInputAction: TextInputAction.next,
                                      onSubmitted: () =>
                                          _passwordFocus.requestFocus(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SlideTransition(
                                  position: _fieldTwoSlide,
                                  child: FadeTransition(
                                    opacity: _fieldTwoFade,
                                    child: _LoginField(
                                      controller: _passwordCtl,
                                      focusNode: _passwordFocus,
                                      hint: 'Password',
                                      icon: LucideIcons.lock,
                                      obscure: _obscure,
                                      hasError: _error != null,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: _handleLogin,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscure
                                              ? LucideIcons.eyeOff
                                              : LucideIcons.eye,
                                          size: 19,
                                          color: colors.text4,
                                        ),
                                        onPressed: () =>
                                            setState(() => _obscure = !_obscure),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Error ──
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: _error != null
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          LucideIcons.alertCircle,
                                          size: 15,
                                          color: Color(0xFFEF4444),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _error!,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFFEF4444),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),

                          const SizedBox(height: 28),

                          // ── Sign-in button ──
                          SlideTransition(
                            position: _btnSlide,
                            child: FadeTransition(
                              opacity: _btnFade,
                              child: _SignInButton(
                                loading: _loading,
                                label: LoginCopy.actionLabel(
                                  sessionExpired: _sessionExpired,
                                ),
                                onTap: _handleLogin,
                              ),
                            ),
                          ),

                          const Spacer(flex: 4),

                          // ── Footer badge ──
                          FadeTransition(
                            opacity: _footerFade,
                            child: Padding(
                              padding:
                                  EdgeInsets.only(bottom: 16 + bottomPad),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.shieldCheck,
                                    size: 13,
                                    color: colors.text5,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Protected with AES-256 encryption',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: colors.text5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Input field with focus glow ──────────────────────────────────────────────

class _LoginField extends StatefulWidget {
  const _LoginField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.hasError = false,
    this.suffixIcon,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final bool obscure;
  final bool hasError;
  final Widget? suffixIcon;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_LoginField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() => _focused = widget.focusNode.hasFocus);

  Color _borderColor(AppColors c) {
    if (widget.hasError) return const Color(0xFFEF4444);
    if (_focused) return AppColors.accent;
    return c.border;
  }

  Color get _glowColor {
    if (widget.hasError) return const Color(0x30EF4444);
    if (_focused) return const Color(0x280D59F2);
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: c.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor(c)),
        boxShadow: [BoxShadow(color: _glowColor, blurRadius: 14)],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: widget.obscure,
        textInputAction: widget.textInputAction,
        onSubmitted: (_) => widget.onSubmitted?.call(),
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: c.text,
        ),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: c.text4,
          ),
          prefixIcon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              widget.icon,
              key: ValueKey(_focused),
              size: 19,
              color: _focused ? AppColors.accent : c.text4,
            ),
          ),
          suffixIcon: widget.suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

// ── Sign-in button with press animation ─────────────────────────────────────

class _SignInButton extends StatefulWidget {
  const _SignInButton({
    required this.loading,
    required this.onTap,
    this.label = LoginCopy.signInLabel,
  });
  final bool loading;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<_SignInButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) => _scale.forward();
  void _onUp(TapUpDetails _) => _scale.reverse();
  void _onCancel() => _scale.reverse();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: 1.0 - (_scale.value * 0.04),
        child: child,
      ),
      child: GestureDetector(
        onTapDown: _onDown,
        onTapUp: _onUp,
        onTapCancel: _onCancel,
        onTap: widget.loading ? null : () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, Color(0xFF1A6BFF)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x440D59F2),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: widget.loading
                  ? const SizedBox(
                      key: ValueKey('loader'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      key: const ValueKey('label'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          LucideIcons.arrowRight,
                          size: 20,
                          color: Colors.white,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Background orbs ─────────────────────────────────────────────────────────

class _OrbsLayer extends StatelessWidget {
  const _OrbsLayer();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -80,
            left: -90,
            child: _BlurOrb(
              diameter: 260,
              colors: [
                AppColors.accent.withValues(alpha: 0.12),
                AppColors.accentCyan.withValues(alpha: 0.05),
                Colors.transparent,
              ],
            ),
          ),
          Positioned(
            top: 60,
            right: -80,
            child: _BlurOrb(
              diameter: 230,
              colors: [
                AppColors.accentCyan.withValues(alpha: 0.10),
                AppColors.accent.withValues(alpha: 0.04),
                Colors.transparent,
              ],
            ),
          ),
          Positioned(
            bottom: 140,
            right: -50,
            child: _BlurOrb(
              diameter: 200,
              colors: [
                AppColors.accent.withValues(alpha: 0.07),
                Colors.transparent,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({required this.diameter, required this.colors});
  final double diameter;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: colors,
            stops: colors.length == 3
                ? const [0.0, 0.45, 1.0]
                : const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

// ── Mini hero orb (branding) ────────────────────────────────────────────────

class _MiniOrb extends StatelessWidget {
  const _MiniOrb();
  static const double _size = 80;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0xFF1A4A9E), AppColors.accent, AppColors.accentCyan],
            stops: [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(color: Color(0x550D59F2), blurRadius: 28),
            BoxShadow(color: Color(0x3322D3EE), blurRadius: 20, spreadRadius: -4),
          ],
        ),
        child: const Center(
          child: Icon(LucideIcons.sparkles, size: 30, color: Color(0xE6FFFFFF)),
        ),
      ),
    );
  }
}
