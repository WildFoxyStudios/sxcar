import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

class AgeCard extends StatefulWidget {
  const AgeCard({
    super.key,
    required this.card,
    required this.provider,
    required this.onComplete,
  });

  final OnboardingCard card;
  final OnboardingProvider provider;
  final ValueChanged<bool> onComplete;

  @override
  State<AgeCard> createState() => _AgeCardState();
}

class _AgeCardState extends State<AgeCard> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final age = int.tryParse(_ctrl.text);
      if (age == null || age < 18 || age > 120) {
        throw Exception('Please enter a valid age (18-120)');
      }
      await widget.provider.completeCard('age', {'age': age});
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingCardScaffold(
      card: widget.card,
      primaryLabel: l10n.onboarding_next,
      primaryEnabled: !_busy && _ctrl.text.trim().isNotEmpty,
      onPrimary: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Age',
              hintText: 'Enter your age',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
