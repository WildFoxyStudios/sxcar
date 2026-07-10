import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../auth/models.dart';
import '../auth/widgets/auth_shell.dart';
import '../theme/app_theme.dart';
import '../utils/email_validator.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  DateTime? _birthDate;
  bool _consentChecked = false;
  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  static DateTime get _maxBirthDate => DateTime(
      DateTime.now().year - 18, DateTime.now().month, DateTime.now().day);
  static final DateTime _minBirthDate = DateTime(
      DateTime.now().year - 100, DateTime.now().month, DateTime.now().day);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isAtLeast18(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age >= 18;
  }

  Future<void> _pickDate() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? _maxBirthDate,
      firstDate: _minBirthDate,
      lastDate: _maxBirthDate,
      helpText: l10n.register_dob_picker_help,
      fieldLabelText: l10n.register_dob_picker_field_label,
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    if (_birthDate == null) {
      setState(() => _error = l10n.register_dob_empty_error);
      return;
    }
    if (!_isAtLeast18(_birthDate!)) {
      setState(() => _error = l10n.register_age_gate);
      return;
    }
    if (!_consentChecked) {
      setState(() => _error = l10n.register_consent_error);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final dob = '${_birthDate!.year}-'
        '${_birthDate!.month.toString().padLeft(2, '0')}-'
        '${_birthDate!.day.toString().padLeft(2, '0')}';

    try {
      await ref.read(authStateProvider.notifier).register(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            dob: dob,
            consents: ['tos', 'privacy', 'age'],
          );
      if (mounted) context.go('/verify-email');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 409) {
        setState(() => _error = l10n.register_error_email_taken);
      } else if (statusCode == 403) {
        setState(() => _error = l10n.register_age_gate);
      } else {
        setState(() => _error = l10n.register_error_network);
      }
    } catch (e) {
      setState(() => _error = l10n.register_error_network);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dobText = _birthDate == null
        ? ''
        : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}';
    return Form(
      key: _formKey,
      child: AuthShell(
        subtitle: l10n.register_subtitle,
        onBack: _isLoading ? null : () => context.go('/login'),
        children: [
          TextFormField(
            controller: _emailController,
            decoration: authInput(
                label: l10n.register_email_label, icon: Icons.mail_outline),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.register_email_empty_error;
              }
              if (!validateEmail(email: value.trim())) {
                return l10n.register_email_invalid_error;
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            decoration: authInput(
              label: l10n.register_password_label,
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20, color: VibraTheme.kTextSecondary),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            obscureText: _obscure,
            autofillHints: const [AutofillHints.newPassword],
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.register_password_empty_error;
              }
              if (value.length < 8) {
                return l10n.register_password_min_length_error;
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmPasswordController,
            decoration: authInput(
              // TODO(l10n): no existing confirm-password key in app_en.arb
              label: 'Confirm Password',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20, color: VibraTheme.kTextSecondary),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            obscureText: _obscure,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.register_password_empty_error;
              }
              if (value.trim() != _passwordController.text.trim()) {
                // TODO(l10n): no existing mismatch key in app_en.arb
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: authInput(
                label: l10n.register_dob_label,
                hint: l10n.register_dob_hint,
                icon: Icons.cake_outlined,
                suffix: const Icon(Icons.calendar_today,
                    size: 18, color: VibraTheme.kTextSecondary),
              ),
              child: Text(
                dobText.isEmpty ? l10n.register_dob_hint : dobText,
                style: TextStyle(
                  color: dobText.isEmpty
                      ? VibraTheme.kTextSecondary
                      : VibraTheme.kText,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.register_consent_label,
                style: const TextStyle(
                    fontSize: 13, color: VibraTheme.kTextSecondary)),
            value: _consentChecked,
            activeColor: VibraTheme.kBrandPrimary,
            checkColor: Colors.black,
            onChanged: (v) => setState(() => _consentChecked = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_error != null) AuthErrorText(_error!),
          const SizedBox(height: 16),
          AuthPrimaryButton(
            label: l10n.register_button,
            loading: _isLoading,
            onPressed: _isLoading ? null : _submit,
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.register_have_account,
                  style: const TextStyle(color: VibraTheme.kTextSecondary)),
              TextButton(
                onPressed: _isLoading ? null : () => context.go('/login'),
                child: Text(l10n.register_login_link),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
