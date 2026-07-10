import '../theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../auth/models.dart';
import '../../l10n/gen/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 6) {
      setState(() => _error = l10n.errorCodigo6Digitos);
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
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = (data is Map) ? data['message'] as String? : null;
      setState(() => _error = message ?? l10n.verificacionFallida);
    } catch (e) {
      setState(() => _error = l10n.verificacionFallida);
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
        SnackBar(content: Text(AppLocalizations.of(context)!.codigoEnviado)),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.data?['message'] as String? ??
            AppLocalizations.of(context)!.errorReenviarCodigo;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context)!.errorReenviarCodigo);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(title: Text(l10n.verificarEmail)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.verificarEmailInstrucciones,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: l10n.codigoVerificacion,
                border: const OutlineInputBorder(),
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
                    : Text(l10n.verificar),
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
                  : Text(l10n.reenviarCodigo),
            ),
            const SizedBox(height: 8),
            // Escape hatch: if the verification email never arrives (wrong
            // address, lost inbox), the router otherwise traps emailUnverified
            // users on this screen forever. Letting them sign out drops to
            // unauthenticated → router sends to /login.
            TextButton(
              onPressed: (_isLoading || _isResending)
                  ? null
                  : () => ref.read(authStateProvider.notifier).logout(),
              child: Text(
                l10n.cerrarSesion,
                style: const TextStyle(color: VibraTheme.kTextSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
