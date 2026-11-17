import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../assistant/assistant_chat.dart';
import '../module/module_providers.dart';
import '../module/health_pro_module.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/friendly_error.dart';
import '../utils/validators.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import '../widgets/motion.dart';
import '../widgets/splash.dart';
import 'auth_layout.dart';
import 'install_app_button.dart';
import 'auth_repository.dart';

/// Why a code was emailed, which decides where entering it leads.
enum CodePurpose { signUp, signIn, resetCode }

/// The email a code went to, between asking for it and entering it.
class PendingCode {
  final String email;
  final CodePurpose purpose;
  final String? next;

  const PendingCode({required this.email, required this.purpose, this.next});

  /// New accounts and resets choose their 6-digit sign-in code next.
  bool get choosesCode => purpose != CodePurpose.signIn;
}

final pendingCodeProvider = StateProvider<PendingCode?>((ref) => null);

/// For visitors: the lead module's own Welcome (HealthProModule.buildWelcome)
/// or, without one, what Health Pro has (each module's public pages), and
/// signing up or in.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(enabledModulesProvider);
    // The splash while the modules load, rather than flashing the plain page
    // before a module's own.
    // With the floating Ask AI button: Health Pro's assistant, for visitors.
    return SplashGate(
      ready: enabled.hasValue || !enabled.isLoading,
      builder: (context) => AssistantFrame(
        location: CoreRoutes.welcome,
        child: _page(context, enabled.valueOrNull ?? const <HealthProModule>[]),
      ),
    );
  }

  Widget _page(BuildContext context, List<HealthProModule> modules) {
    for (final m in modules) {
      final page = m.buildWelcome(context);
      if (page != null) return page;
    }
    return AppPage(
      body: ListView(
        padding: pagePadding(context, horizontal: 20),
        children: [
          const Center(child: HealthProLogo(height: 150)),
          const SizedBox(height: 4),
          Text(
            'Gyms across Bhutan, with one account.',
            textAlign: TextAlign.center,
            style: context.text.titleMedium?.copyWith(color: context.brand.muted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          for (final m in modules)
            for (final item in m.playerMenuItems().where((i) => i.isExternal || m.publicPaths.contains(i.route)))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: MenuTile(
                  icon: item.icon,
                  title: item.title,
                  subtitle: item.subtitle,
                  trailing: item.isExternal ? const Icon(Icons.open_in_new_rounded, size: 20) : null,
                  onTap: () => item.open(context),
                ),
              ),
          const SizedBox(height: 28),
          FilledButton(onPressed: () => context.push(CoreRoutes.signUp), child: const Text('Create an account')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => context.push(CoreRoutes.signIn), child: const Text('Sign in')),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () => context.push(CoreRoutes.registerVenue),
            icon: const Icon(Icons.storefront_rounded),
            label: const Text('Run a gym? Register your venue'),
          ),
        ],
      ),
    );
  }
}

class SignInScreen extends ConsumerStatefulWidget {
  final String? next;

  const SignInScreen({super.key, this.next});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  /// All six digits are in: Sign in is only live then.
  bool get _codeComplete => Validators.signInCode(_code.text) == null;

  @override
  void initState() {
    super.initState();
    _code.addListener(_codeChanged);
  }

  void _codeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _code.removeListener(_codeChanged);
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      await ref.read(authRepositoryProvider).signIn(email: _email.text, code: _code.text);
      if (mounted) context.go(widget.next ?? CoreRoutes.home);
    });
  }

  /// Emails a code: to sign in without their own code, or to choose a new
  /// one.
  Future<void> _sendCode(CodePurpose purpose) async {
    if (Validators.email(_email.text) != null) {
      setState(() => _error = 'Enter your email first, then tap this again.');
      return;
    }
    await _run(() async {
      await ref.read(authRepositoryProvider).sendLoginCode(_email.text);
      ref.read(pendingCodeProvider.notifier).state =
          PendingCode(email: _email.text.trim().toLowerCase(), purpose: purpose, next: widget.next);
      if (mounted) context.push(CoreRoutes.verify);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      side: AuthSide.signIn,
      title: 'Welcome Back!',
      subtitle: 'Sign in to continue to your account',
      onBack: () => context.go(CoreRoutes.welcome),
      children: [
        // First thing on the card, above the email (until it's installed).
        const InstallAppButton(),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  validator: Validators.email,
                ),
                const SizedBox(height: 8),
                CodeBoxes(
                  controller: _code,
                  label: 'Your 6-digit code',
                  hidden: _hide,
                  onToggleHidden: () => setState(() => _hide = !_hide),
                  autofillHints: const [AutofillHints.password],
                  // The sixth digit signs them in: no button to press.
                  onCompleted: (_) => _signIn(),
                  onSubmitted: (_) => _signIn(),
                  validator: Validators.signInCode,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : () => _sendCode(CodePurpose.resetCode),
            style: TextButton.styleFrom(
              foregroundColor: context.brand.accent,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            child: const Text('Forgot code?'),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 4), AuthError(_error!), const SizedBox(height: 14)],
        const SizedBox(height: 6),
        AuthPrimaryButton(label: 'Sign in', icon: Icons.arrow_forward_rounded, busy: _busy, onPressed: _codeComplete ? _signIn : null),
        const SizedBox(height: 22),
        const AuthDivider(text: 'or continue with'),
        const SizedBox(height: 18),
        AuthSecondaryButton(
          label: 'Email me a code instead',
          icon: Icons.mark_email_read_outlined,
          onPressed: _busy ? null : () => _sendCode(CodePurpose.signIn),
        ),
        const SizedBox(height: 18),
        AuthSwitchLink(
          question: "Don't have an account?",
          action: 'Register here',
          onPressed: () => context.pushReplacement(CoreRoutes.signUpFor(widget.next)),
        ),
      ],
    );
  }
}

class SignUpScreen extends ConsumerStatefulWidget {
  final String? next;

  const SignUpScreen({super.key, this.next});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = _phone.text.trim().isEmpty ? null : Validators.normalizePhone(_phone.text);
      await ref.read(authRepositoryProvider).sendSignUpCode(email: _email.text, fullName: _name.text, phone: phone);
      ref.read(pendingCodeProvider.notifier).state =
          PendingCode(email: _email.text.trim().toLowerCase(), purpose: CodePurpose.signUp, next: widget.next);
      if (mounted) context.push(CoreRoutes.verify);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      side: AuthSide.join,
      title: 'Create Your Account',
      subtitle: 'Get started with Health Pro today',
      onBack: () => context.go(CoreRoutes.welcome),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.person_outline_rounded)),
                  validator: (v) => Validators.required(v, 'Your name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email address *', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  validator: Validators.email,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    helperText: 'Optional: so your gym can reach you',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: Validators.phone,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const AuthNote(
          icon: Icons.mark_email_unread_outlined,
          text: "We'll email you a 6-digit code to confirm it's you, then you choose "
              'your own 6-digit code to sign in with. The same account works on the website and in the app.',
        ),
        if (_error != null) ...[const SizedBox(height: 14), AuthError(_error!)],
        const SizedBox(height: 22),
        AuthPrimaryButton(label: 'Register account', icon: Icons.person_add_alt_1_rounded, busy: _busy, onPressed: _submit),
        const SizedBox(height: 14),
        AuthSwitchLink(
          question: 'Already have an account?',
          action: 'Sign in here',
          onPressed: () => context.pushReplacement(
              widget.next == null ? CoreRoutes.signIn : CoreRoutes.signInFor(widget.next!)),
        ),
      ],
    );
  }
}

class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({super.key});

  @override
  ConsumerState<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends ConsumerState<VerifyCodeScreen> {
  static const resendSeconds = 45;

  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int _wait = resendSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wait <= 1) t.cancel();
      if (mounted) setState(() => _wait = (_wait - 1).clamp(0, resendSeconds));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify(PendingCode pending) async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6 digits from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyCode(email: pending.email, code: _code.text);
      ref.read(pendingCodeProvider.notifier).state = null;
      if (!mounted) return;
      if (pending.choosesCode) {
        final next = pending.next;
        context.go(next == null ? CoreRoutes.setCode : '${CoreRoutes.setCode}?next=${Uri.encodeComponent(next)}');
      } else {
        context.go(pending.next ?? CoreRoutes.home);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend(PendingCode pending) async {
    try {
      // Supabase made the account with the first sign-up code (its name
      // went with it), so a repeat is a plain sign-in code.
      await ref.read(authRepositoryProvider).sendLoginCode(pending.email);
      _startTimer();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A new code is on its way.')));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingCodeProvider);
    if (pending == null) {
      return AuthLayout(
        side: AuthSide.signIn,
        title: 'Start again',
        subtitle: 'Ask for a new code from the sign-in page.',
        children: [
          AuthPrimaryButton(
            label: 'Go to sign in',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => context.go(CoreRoutes.signIn),
          ),
        ],
      );
    }
    return AuthLayout(
      side: pending.purpose == CodePurpose.signUp ? AuthSide.join : AuthSide.signIn,
      title: 'Check your email',
      subtitle: 'We emailed a 6-digit code to',
      children: [
        // Where it went, with the letter that's on its way.
        Transform.translate(
          offset: const Offset(0, -12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
              decoration: BoxDecoration(
                color: context.brand.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.brand.accent.withValues(alpha: 0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SentMail(),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      pending.email,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.brand.accentText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        CodeBoxes(
          controller: _code,
          autofocus: true,
          autofillHints: const [AutofillHints.oneTimeCode],
          refused: _error != null,
          onCompleted: (_) {
            if (!_busy) _verify(pending);
          },
          onSubmitted: (_) => _verify(pending),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: const Duration(milliseconds: 700),
          offset: 6,
          child: Text(
            "Can't see it? Check your spam folder.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.brand.muted),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 14), AuthError(_error!)],
        const SizedBox(height: 22),
        AuthPrimaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          busy: _busy,
          onPressed: () => _verify(pending),
        ),
        const SizedBox(height: 10),
        // The wait for another code: a ring running down; then the way to
        // ask, popping in.
        Center(
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.page),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: a, curve: Motion.pop)), child: child),
            ),
            child: _wait > 0
                ? Padding(
                    key: const ValueKey('wait'),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: _wait / resendSeconds),
                            duration: Motion.of(context, const Duration(seconds: 1)),
                            builder: (context, v, _) => CircularProgressIndicator(
                              value: v,
                              strokeWidth: 2.5,
                              color: context.brand.accent,
                              backgroundColor: context.brand.accent.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Send a new code in $_wait s',
                          style: TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14, color: context.brand.muted),
                        ),
                      ],
                    ),
                  )
                : TextButton.icon(
                    key: const ValueKey('ready'),
                    onPressed: () => _resend(pending),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Send a new code'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.brand.accent,
                      textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// A letter on its way: an orange badge that pops in, the envelope sliding
/// into it, ringing out a few times and floating gently, then resting.
class _SentMail extends StatelessWidget {
  const _SentMail();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final badge = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brand.themedShade(const Color(0xFFFF8A3D)), brand.accent],
        ),
        boxShadow: [BoxShadow(color: brand.accent.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: const Icon(Icons.mark_email_unread_rounded, size: 16, color: Colors.white),
    );
    if (reduceMotion(context)) return badge;
    // Rings going out (three), fading as they grow, under the badge.
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 3200),
            builder: (context, t, _) {
              if (t == 1 || t < 0.12) return const SizedBox.shrink();
              final r = Motion.ease.transform(((t - 0.12) / 0.88 * 3) % 1);
              return OverflowBox(
                maxWidth: 80,
                maxHeight: 80,
                child: Container(
                  width: 30 * (1 + 0.9 * r),
                  height: 30 * (1 + 0.9 * r),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: brand.accent.withValues(alpha: 0.45 * (1 - r)), width: 2),
                  ),
                ),
              );
            },
          ),
          PopIn(
            delay: const Duration(milliseconds: 240),
            child: GentleFloat(
              distance: 3,
              cycles: 3,
              period: const Duration(milliseconds: 1800),
              child: badge,
            ),
          ),
        ],
      ),
    );
  }
}

/// Choosing the 6-digit code they sign in with, after the emailed code.
class SetCodeScreen extends ConsumerStatefulWidget {
  final String? next;

  const SetCodeScreen({super.key, this.next});

  @override
  ConsumerState<SetCodeScreen> createState() => _SetCodeScreenState();
}

class _SetCodeScreenState extends ConsumerState<SetCodeScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).setSignInCode(_code.text);
      if (mounted) context.go(widget.next ?? CoreRoutes.home);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Their account was made for them with the starting code: they choose
    // their own before going on.
    final forced = ref.watch(authRepositoryProvider).mustChooseCode;
    return AuthLayout(
      side: AuthSide.join,
      title: 'Choose Your 6-Digit Code',
      subtitle: forced
          ? 'Your account started with ${AuthRepository.defaultCode}. Choose a code only you know to go on.'
          : 'Use it with your email to sign in next time, on the website or in the app.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CodeBoxes(
                  controller: _code,
                  label: 'New 6-digit code',
                  autofocus: true,
                  hidden: _hide,
                  onToggleHidden: () => setState(() => _hide = !_hide),
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  onCompleted: (_) => _confirmFocus.requestFocus(),
                  onSubmitted: (_) => _confirmFocus.requestFocus(),
                  validator: (v) =>
                      Validators.signInCode(v) ??
                      (forced && v == AuthRepository.defaultCode
                          ? 'Choose a code other than ${AuthRepository.defaultCode}'
                          : null),
                ),
                const SizedBox(height: 8),
                CodeBoxes(
                  controller: _confirm,
                  focusNode: _confirmFocus,
                  label: 'Type it again',
                  hidden: _hide,
                  validator: (v) => v != _code.text ? "The codes don't match" : null,
                  onSubmitted: (_) => _save(),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 14), AuthError(_error!)],
        const SizedBox(height: 22),
        AuthPrimaryButton(label: 'Save code', icon: Icons.verified_user_outlined, busy: _busy, onPressed: _save),
        if (!forced) const SizedBox(height: 10),
        if (!forced) Center(
          child: TextButton(
            onPressed: _busy ? null : () => context.go(widget.next ?? CoreRoutes.home),
            style: TextButton.styleFrom(foregroundColor: context.brand.muted),
            child: const Text('Skip for now (sign in with emailed codes)'),
          ),
        ),
      ],
    );
  }
}
