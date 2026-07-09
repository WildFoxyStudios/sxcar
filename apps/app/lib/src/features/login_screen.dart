import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../auth/google_sign_in_service.dart';
import '../auth/models.dart';
import '../auth/widgets/auth_shell.dart';
import '../theme/app_theme.dart';
import '../utils/email_validator.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _googleSignIn = GoogleSignInService();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _busy => _isLoading || _isGoogleLoading;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });
    try {
      final result = await _googleSignIn.signIn();
      if (!mounted) return;
      if (result.cancelled) {
        setState(() => _isGoogleLoading = false);
        return;
      }
      if (!result.isSuccess) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = result.error ?? l10n.login_error_google;
          _isGoogleLoading = false;
        });
        return;
      }
      await ref.read(authStateProvider.notifier).signInWithGoogle(
            result.idToken!,
            email: result.email,
          );
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() => _error = l10n.login_error_google);
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(authStateProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text,
          );
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() => _error = l10n.login_error_network);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Form(
      key: _formKey,
      child: AuthShell(
        subtitle: l10n.login_subtitle,
        children: [
          TextFormField(
            controller: _emailController,
            decoration: authInput(
              label: l10n.login_email_label,
              icon: Icons.mail_outline,
            ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.login_email_empty_error;
              }
              if (!validateEmail(email: value.trim())) {
                return l10n.login_email_invalid_error;
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            decoration: authInput(
              label: l10n.login_password_label,
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20, color: VibraTheme.kTextSecondary),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _submit(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.login_password_empty_error;
              }
              return null;
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : () => context.push('/recover'),
              child: Text(l10n.login_forgot_password),
            ),
          ),
          if (_error != null) AuthErrorText(_error!),
          const SizedBox(height: 12),
          AuthPrimaryButton(
            label: l10n.login_button,
            loading: _isLoading,
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Divider(color: VibraTheme.kDivider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(l10n.login_or_divider,
                  style: const TextStyle(color: VibraTheme.kTextSecondary)),
            ),
            const Expanded(child: Divider(color: VibraTheme.kDivider)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: VibraTheme.kText,
                side: const BorderSide(color: VibraTheme.kDivider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _busy ? null : _signInWithGoogle,
              icon: _isGoogleLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.g_mobiledata, size: 28),
              label: Text(l10n.login_google_button),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.login_no_account,
                  style: const TextStyle(color: VibraTheme.kTextSecondary)),
              TextButton(
                onPressed: _busy ? null : () => context.go('/register'),
                child: Text(l10n.login_register_link),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
