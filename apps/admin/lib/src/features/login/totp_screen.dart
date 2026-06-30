import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/admin_auth_provider.dart';

class TotpScreen extends ConsumerStatefulWidget {
  /// The mfa_token received from the login step.
  final String mfaToken;

  const TotpScreen({super.key, required this.mfaToken});

  @override
  ConsumerState<TotpScreen> createState() => _TotpScreenState();
}

class _TotpScreenState extends ConsumerState<TotpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _codeController.text.trim();
    final authNotifier = ref.read(authProvider.notifier);
    final success = await authNotifier.verify2FA(widget.mfaToken, code);

    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.security,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Two-Factor Authentication',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-digit code from your authenticator app.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _codeController,
                    focusNode: _codeFocusNode,
                    decoration: const InputDecoration(
                      labelText: 'TOTP Code',
                      hintText: '000000',
                      prefixIcon: Icon(Icons.pin_outlined),
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().length != 6) {
                        return 'Enter a 6-digit code';
                      }
                      if (int.tryParse(value.trim()) == null) {
                        return 'Code must be numeric';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _handleVerify(),
                  ),
                  if (authState.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        authState.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isLoading ? null : _handleVerify,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verify'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Back to Login'),
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
