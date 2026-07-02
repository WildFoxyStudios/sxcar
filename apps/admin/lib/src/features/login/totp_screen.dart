import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/admin_auth_provider.dart';
import '../../theme/admin_theme.dart';

class TotpScreen extends ConsumerStatefulWidget {
  /// The mfa_token received from the login step.
  final String mfaToken;

  const TotpScreen({super.key, required this.mfaToken});

  @override
  ConsumerState<TotpScreen> createState() => _TotpScreenState();
}

class _TotpScreenState extends ConsumerState<TotpScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _codeFocusNode  = FocusNode();

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    if (!_formKey.currentState!.validate()) return;

    final code         = _codeController.text.trim();
    final authNotifier = ref.read(authProvider.notifier);
    final success      = await authNotifier.verify2FA(widget.mfaToken, code);

    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      backgroundColor: AdminTheme.kBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: AdminTheme.kCard,
                borderRadius: BorderRadius.circular(12),
                border: const Border.fromBorderSide(
                  BorderSide(color: AdminTheme.kBorder),
                ),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AdminTheme.kAccentBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AdminTheme.kAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.security,
                            color: AdminTheme.kAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Two-Factor Auth',
                          style: TextStyle(
                            color: AdminTheme.kText,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enter the 6-digit code from your authenticator app.',
                          style: TextStyle(
                            color: AdminTheme.kMuted,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // TOTP input
                    TextFormField(
                      controller: _codeController,
                      focusNode: _codeFocusNode,
                      style: const TextStyle(
                        color: AdminTheme.kAccent,
                        fontSize: 28,
                        letterSpacing: 10,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'TOTP Code',
                        hintText: '000000',
                        prefixIcon: Icon(Icons.pin_outlined),
                        counterText: '',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
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

                    // Error banner
                    if (authState.error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AdminTheme.kRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AdminTheme.kRed.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AdminTheme.kRed, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                authState.error!,
                                style: const TextStyle(
                                    color: AdminTheme.kRed, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Submit
                    FilledButton(
                      onPressed: isLoading ? null : _handleVerify,
                      child: isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF1A1400),
                              ),
                            )
                          : const Text('Verify'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('← Back to login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
