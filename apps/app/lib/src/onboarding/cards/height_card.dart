import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

class HeightCard extends StatefulWidget {
  const HeightCard({
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
  State<HeightCard> createState() => _HeightCardState();
}

class _HeightCardState extends State<HeightCard> {
  int _heightCm = 175;
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
      onSkip: widget.onSkip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$_heightCm cm',
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Slider(
            value: _heightCm.toDouble(),
            min: 140,
            max: 220,
            divisions: 80,
            label: '$_heightCm cm',
            onChanged: (v) => setState(() => _heightCm = v.round()),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 36),
                onPressed: () =>
                    setState(() => _heightCm = (_heightCm - 1).clamp(140, 220)),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 36),
                onPressed: () =>
                    setState(() => _heightCm = (_heightCm + 1).clamp(140, 220)),
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
          .completeCard('height', {'height_cm': _heightCm});
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }
}
