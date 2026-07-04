import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/theme/widgets.dart';

/// Backend-supported vaccine options (lowercase, mirroring T4.5 description).
const _kVaccineOptions = <String>[
  'covid', 'hepb', 'hepa', 'hpv', 'mpox', 'tetanos',
  'fiebre amarilla', 'tifoidea',
];

class VaccinesScreen extends StatefulWidget {
  final Set<String> current;
  final ValueChanged<Set<String>> onChanged;
  const VaccinesScreen({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  State<VaccinesScreen> createState() => _VaccinesScreenState();
}

class _VaccinesScreenState extends State<VaccinesScreen> {
  late Set<String> _picked;

  @override
  void initState() {
    super.initState();
    _picked = Set<String>.from(widget.current);
  }

  void _update(Set<String> next) {
    setState(() => _picked = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.detailsVaccines)),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ChipMultiSelect(
          options: _kVaccineOptions,
          selected: _picked,
          onChanged: _update,
        ),
      ),
    );
  }
}