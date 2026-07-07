import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/models/profile_options.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

class LookingForCard extends StatefulWidget {
  const LookingForCard({
    super.key,
    required this.card,
    required this.provider,
    required this.onComplete,
    this.onSkip,
  });

  final OnboardingCard card;
  final OnboardingProvider provider;
  final ValueChanged<bool> onComplete;
  final VoidCallback? onSkip;

  @override
  State<LookingForCard> createState() => _LookingForCardState();
}

class _LookingForCardState extends State<LookingForCard> {
  bool _busy = false;
  String? _error;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingCardScaffold(
      card: widget.card,
      primaryLabel: l10n.onboarding_next,
      primaryEnabled: !_busy,
      onPrimary: _submit,
      onSkip: widget.onSkip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...kLookingForOptions.map(
            (o) => CheckboxListTile(
              title: Text(o),
              value: _selected.contains(o),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(o);
                } else {
                  _selected.remove(o);
                }
              }),
            ),
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

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.provider.completeCard('looking_for', {
        'looking_for': _selected.toList(),
      });
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }
}
