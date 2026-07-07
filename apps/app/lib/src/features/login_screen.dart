import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../auth/google_sign_in_service.dart';
import '../auth/models.dart';
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
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    try {
      final result = await _googleSignIn.signIn();
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
      setState(() => _error = e.message);
    } catch (e) {
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
      final l10n = AppLocalizations.of(context)!;
      setState(() => _error = l10n.login_error_network);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.login_title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: l10n.login_email_label,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: l10n.login_password_label,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l10n.login_password_empty_error;
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.login_button),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(l10n.login_or_divider, style: TextStyle(color: Colors.grey[600])),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_isLoading || _isGoogleLoading) ? null : _signInWithGoogle,
                  icon: _isGoogleLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login, size: 20),
                  label: Text(l10n.login_google_button),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading ? null : () => context.go('/register'),
                child: Text(l10n.login_register_link),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
