import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../auth/models.dart';
import '../../src/rust/lib.dart' show validateEmail;

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _dobController = TextEditingController();
  bool _consentChecked = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  bool _isAtLeast18(String dob) {
    try {
      final parts = dob.split('-');
      if (parts.length != 3) return false;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year == null || month == null || day == null) return false;

      final birthDate = DateTime(year, month, day);
      final now = DateTime.now();
      var age = now.year - birthDate.year;
      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      return age >= 18;
    } catch (_) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_consentChecked) {
      setState(() => _error = 'You must accept the terms and privacy policy');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authStateProvider.notifier).register(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            dob: _dobController.text.trim(),
            consents: ['tos', 'privacy', 'age'],
          );
      if (mounted) context.go('/verify-email');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 409) {
        setState(() => _error = 'Email already taken');
      } else if (statusCode == 403) {
        setState(() => _error = 'You must be at least 18 years old');
      } else {
        setState(() => _error = 'Registration failed. Please try again.');
      }
    } catch (e) {
      setState(() => _error = 'Registration failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!validateEmail(email: value.trim())) {
                    return 'Invalid email format';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password (min 8 characters)',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dobController,
                decoration: const InputDecoration(
                  labelText: 'Date of Birth (YYYY-MM-DD)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.datetime,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your date of birth';
                  }
                  if (!_isAtLeast18(value.trim())) {
                    return 'You must be at least 18 years old';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text(
                  'I accept the terms and privacy policy (I am 18+)',
                  style: TextStyle(fontSize: 14),
                ),
                value: _consentChecked,
                onChanged: (v) => setState(() => _consentChecked = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
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
                      : const Text('Register'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading ? null : () => context.go('/login'),
                child: const Text('Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
