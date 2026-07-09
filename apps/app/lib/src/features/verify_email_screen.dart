import '../theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../auth/models.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 6) {
      setState(() => _error = 'Please enter a 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authStateProvider.notifier).verifyEmail(code);
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });
    try {
      // The email is available on authState when status == emailUnverified
      // (set during registration). Pass it if present; the backend also
      // identifies the user via the Bearer token in the Authorization header.
      final email = ref.read(authStateProvider).email;
      await ref.read(dioProvider).post<void>(
        '/auth/resend-email',
        data: email != null ? {'email': email} : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code sent to your email')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.data?['message'] as String? ??
            'Failed to resend code. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Failed to resend code. Please try again.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(title: const Text('Verify Email')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Enter the 6-digit verification code sent to your email',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Verification Code',
                border: OutlineInputBorder(),
                hintText: '123456',
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: VibraTheme.kError),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _verify,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: (_isLoading || _isResending) ? null : _resend,
              child: _isResending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Resend Code'),
            ),
          ],
        ),
      ),
    );
  }
}
