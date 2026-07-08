import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/models/profile_options.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

class GenderPositionCard extends StatefulWidget {
  const GenderPositionCard({
    super.key,
    required this.card,
    required this.provider,
    required this.onComplete,
  });

  final OnboardingCard card;
  final OnboardingProvider provider;
  final ValueChanged<bool> onComplete;

  @override
  State<GenderPositionCard> createState() => _GenderPositionCardState();
}

class _GenderPositionCardState extends State<GenderPositionCard> {
  bool _busy = false;
  String? _error;
  String? _selectedGender;
  String? _selectedPosition;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ready = _selectedGender != null && _selectedPosition != null;
    return OnboardingCardScaffold(
      card: widget.card,
      primaryLabel: l10n.onboarding_next,
      primaryEnabled: !_busy && ready,
      onPrimary: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.onboarding_card_gender_position_label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _selectedGender,
            onChanged: (v) => setState(() => _selectedGender = v),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: kGenderOptions
                  .map((g) => RadioListTile<String>(title: Text(g), value: g))
                  .toList(),
            ),
          ),
          const Divider(height: 24),
          Text(l10n.onboarding_card_position_preference_label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _selectedPosition,
            onChanged: (v) => setState(() => _selectedPosition = v),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: kPositionOptions
                  .map((p) => RadioListTile<String>(title: Text(p), value: p))
                  .toList(),
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
      await widget.provider.completeCard('gender_position', {
        'gender': _selectedGender,
        'position': _selectedPosition,
      });
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }
}
