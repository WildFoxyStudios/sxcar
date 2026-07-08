import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/models/profile_options.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

class RelationshipStatusCard extends StatefulWidget {
  const RelationshipStatusCard({
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
  State<RelationshipStatusCard> createState() => _RelationshipStatusCardState();
}

class _RelationshipStatusCardState extends State<RelationshipStatusCard> {
  bool _busy = false;
  String? _error;
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingCardScaffold(
      card: widget.card,
      primaryLabel: l10n.onboarding_next,
      primaryEnabled: !_busy && _selected != null,
      onPrimary: _submit,
      onSkip: widget.onSkip,
      child: RadioGroup<String>(
        groupValue: _selected,
        onChanged: (v) => setState(() => _selected = v),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...kRelationshipStatusOptions.map((o) => RadioListTile<String>(
                  title: Text(o),
                  value: o,
                )),
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
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.provider.completeCard('relationship_status', {
        'relationship_status': _selected,
      });
      widget.onComplete(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
