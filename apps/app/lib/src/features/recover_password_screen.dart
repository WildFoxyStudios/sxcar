import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/auth_shell.dart';
import '../theme/app_theme.dart';
import '../utils/email_validator.dart';

/// Two-step password recovery, wired to the existing backend:
///   1. POST /auth/password/reset-request { email }   → always 200
///   2. POST /auth/password/reset { email, code, new_password } → 204
class RecoverPasswordScreen extends ConsumerStatefulWidget {
  const RecoverPasswordScreen({super.key});

  @override
  ConsumerState<RecoverPasswordScreen> createState() =>
      _RecoverPasswordScreenState();
}

class _RecoverPasswordScreenState
    extends ConsumerState<RecoverPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_emailController.text.trim().isEmpty ||
        !validateEmail(email: _emailController.text.trim())) {
      setState(() =>
          _error = AppLocalizations.of(context)!.login_email_invalid_error);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(dioProvider).post('/auth/password/reset-request',
          data: {'email': _emailController.text.trim()});
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _notice = AppLocalizations.of(context)!.recover_code_sent;
      });
    } catch (_) {
      if (!mounted) return;
      // Endpoint is non-enumerating (always 200); a failure here is network.
      setState(
          () => _error = AppLocalizations.of(context)!.login_error_network);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(dioProvider).post('/auth/password/reset', data: {
        'email': _emailController.text.trim(),
        'code': _codeController.text.trim(),
        'new_password': _passwordController.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.recover_success),
          backgroundColor: VibraTheme.kSuccess,
        ),
      );
      context.go('/login');
    } on DioException {
      if (!mounted) return;
      setState(() => _error = l10n.recover_error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.login_error_network);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Form(
      key: _formKey,
      child: AuthShell(
        subtitle: l10n.recover_subtitle,
        onBack: _loading ? null : () => context.go('/login'),
        children: [
          TextFormField(
            controller: _emailController,
            enabled: !_codeSent,
            decoration: authInput(
                label: l10n.login_email_label, icon: Icons.mail_outline),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
          ),
          if (_codeSent) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _codeController,
              decoration: authInput(
                  label: l10n.recover_code_label, icon: Icons.pin_outlined),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              validator: (v) => (v == null || v.trim().length < 4)
                  ? l10n.recover_code_empty
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              decoration: authInput(
                label: l10n.recover_new_password_label,
                icon: Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: VibraTheme.kTextSecondary),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              obscureText: _obscure,
              validator: (v) => (v == null || v.length < 8)
                  ? l10n.register_password_min_length_error
                  : null,
            ),
          ],
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_notice!,
                  style: const TextStyle(
                      color: VibraTheme.kSuccess, fontSize: 13)),
            ),
          if (_error != null) AuthErrorText(_error!),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: _codeSent
                ? l10n.recover_reset_button
                : l10n.recover_send_code,
            loading: _loading,
            onPressed: _loading ? null : (_codeSent ? _reset : _sendCode),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading ? null : _sendCode,
              child: Text(l10n.recover_send_code),
            ),
          ],
        ],
      ),
    );
  }
}
