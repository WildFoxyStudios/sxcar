import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

class WeightCard extends StatefulWidget {
  const WeightCard({
    super.key,
    required this.card,
    required this.provider,
    required this.onComplete,
  });

  final OnboardingCard card;
  final OnboardingProvider provider;
  final ValueChanged<bool> onComplete;

  @override
  State<WeightCard> createState() => _WeightCardState();
}

class _WeightCardState extends State<WeightCard> {
  int _weightKg = 75;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingCardScaffold(
      card: widget.card,
      primaryLabel: l10n.onboarding_next,
      primaryEnabled: !_busy,
      onPrimary: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$_weightKg kg',
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Slider(
            value: _weightKg.toDouble(),
            min: 40,
            max: 200,
            divisions: 160,
            label: '$_weightKg kg',
            onChanged: (v) => setState(() => _weightKg = v.round()),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 36),
                onPressed: () =>
                    setState(() => _weightKg = (_weightKg - 1).clamp(40, 200)),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 36),
                onPressed: () =>
                    setState(() => _weightKg = (_weightKg + 1).clamp(40, 200)),
              ),
            ],
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
      await widget.provider
          .completeCard('weight', {'weight_kg': _weightKg});
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }
}
