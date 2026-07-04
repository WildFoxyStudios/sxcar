import 'package:flutter/material.dart';
import 'package:app/src/theme/widgets.dart';

/// Sexual practice categories — labels shown to user, values stored in JSON.
const _kPracticeOptions = <String>[
  'Oral', 'Anal', 'Versátil', 'BDSM', 'Fisting', 'Rimming',
  'Three-way', 'Group', 'Chem-friendly', 'Bareback',
];

class PracticesScreen extends StatefulWidget {
  final Set<String> current;
  final ValueChanged<Set<String>> onChanged;
  const PracticesScreen({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  State<PracticesScreen> createState() => _PracticesScreenState();
}

class _PracticesScreenState extends State<PracticesScreen> {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Prácticas')),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ChipMultiSelect(
          options: _kPracticeOptions,
          selected: _picked,
          onChanged: _update,
        ),
      ),
    );
  }
}