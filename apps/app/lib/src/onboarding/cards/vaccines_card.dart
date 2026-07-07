import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

class VaccinesCard extends StatefulWidget {
  const VaccinesCard({
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
  State<VaccinesCard> createState() => _VaccinesCardState();
}

class _VaccinesCardState extends State<VaccinesCard> {
  bool _busy = false;
  String? _error;
  final Set<String> _selected = {};

  static const _options = [
    'HPV', 'Hepatitis A', 'Hepatitis B', 'Meningitis',
    'COVID-19', 'Flu', 'MPOX', 'Other',
  ];

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
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _options.map((o) {
              final isSelected = _selected.contains(o);
              return FilterChip(
                label: Text(o),
                selected: isSelected,
                onSelected: (v) => setState(() {
                  if (v) {
                    _selected.add(o);
                  } else {
                    _selected.remove(o);
                  }
                }),
              );
            }).toList(),
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
      await widget.provider.completeCard('vaccines', {
        'vaccines': _selected.toList(),
      });
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }
}
