// Header
import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/models/profile_options.dart';
import 'package:app/src/theme/app_theme.dart';
import 'package:app/src/theme/widgets.dart';

// ─── Single-select sheets ───────────────────────────────────────────────────

Future<String?> showEthnicitySheet(BuildContext context, {String? current}) =>
    _singleSelectSheet(context, titleKey: 'sheetSelectEthnicity',
        options: kEthnicityOptions, current: current);

Future<String?> showBodyTypeSheet(BuildContext context, {String? current}) =>
    _singleSelectSheet(context, titleKey: 'sheetSelectBodyType',
        options: kBodyTypeOptions, current: current);

Future<String?> showPositionSheet(BuildContext context, {String? current}) =>
    _singleSelectSheet(context, titleKey: 'sheetSelectPosition',
        options: kPositionOptions, current: current);

Future<String?> showPronounsSheet(BuildContext context, {String? current}) =>
    _singleSelectSheet(context, titleKey: 'sheetSelectPronouns',
        options: kPronounsOptions, current: current);

Future<String?> showRelationshipSheet(BuildContext context, {String? current}) =>
    _singleSelectSheet(context, titleKey: 'sheetSelectRelationship',
        options: kRelationshipStatusOptions, current: current);

Future<String?> showRoleSheet(BuildContext context, {String? current}) =>
    _singleSelectSheet(context, titleKey: 'sheetSelectRole',
        options: kRoleOptions, current: current);

// ─── Multi-select sheets (wrap ChipMultiSelect) ─────────────────────────────

Future<Set<String>?> showLookingForSheet(BuildContext context,
    {Set<String> current = const <String>{}}) =>
    _multiSelectSheet(context, titleKey: 'sheetSelectLookingFor',
        options: kLookingForOptions, current: current);

Future<Set<String>?> showMeetAtSheet(BuildContext context,
    {Set<String> current = const <String>{}}) =>
    _multiSelectSheet(context, titleKey: 'sheetSelectMeetAt',
        options: kMeetAtOptions, current: current);

Future<Set<String>?> showTagsSheet(BuildContext context,
    {Set<String> current = const <String>{}}) =>
    _multiSelectSheet(context, titleKey: 'sheetSelectTags',
        options: kTagOptions, current: current);

// ─── Numeric sheets (height cm / weight kg) ─────────────────────────────────

Future<int?> showHeightSheet(BuildContext context, {int? currentCm}) =>
    _numericSheet(context, titleKey: 'sheetSelectHeight',
        min: 140, max: 220, step: 1, unit: 'cm', current: currentCm);

Future<int?> showWeightSheet(BuildContext context, {int? currentKg}) =>
    _numericSheet(context, titleKey: 'sheetSelectWeight',
        min: 40, max: 200, step: 1, unit: 'kg', current: currentKg);

// ─── Implementation helpers (private) ───────────────────────────────────────

Future<String?> _singleSelectSheet(
  BuildContext context, {
  required String titleKey,
  required List<String> options,
  String? current,
}) async {
  final result = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: VibraTheme.kSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _SingleSelectSheet(
      title: _localizedTitle(ctx, titleKey),
      options: options,
      current: current,
    ),
  );
  return result;
}

Future<Set<String>?> _multiSelectSheet(
  BuildContext context, {
  required String titleKey,
  required List<String> options,
  required Set<String> current,
}) async {
  final result = await showModalBottomSheet<Set<String>>(
    context: context,
    backgroundColor: VibraTheme.kSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _MultiSelectSheet(
      title: _localizedTitle(ctx, titleKey),
      options: options,
      current: current,
    ),
  );
  return result;
}

Future<int?> _numericSheet(
  BuildContext context, {
  required String titleKey,
  required int min,
  required int max,
  required int step,
  required String unit,
  int? current,
}) async {
  final result = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: VibraTheme.kSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _NumericSheet(
      title: _localizedTitle(ctx, titleKey),
      min: min,
      max: max,
      step: step,
      unit: unit,
      current: current,
    ),
  );
  return result;
}

/// Translate the sheet title via the AppLocalizations key added in T4.5.
String _localizedTitle(BuildContext context, String key) {
  final l10n = AppLocalizations.of(context);
  switch (key) {
    case 'sheetSelectEthnicity':     return l10n?.sheetSelectEthnicity     ?? 'Selecciona etnia';
    case 'sheetSelectBodyType':      return l10n?.sheetSelectBodyType      ?? 'Tipo de cuerpo';
    case 'sheetSelectPosition':      return l10n?.sheetSelectPosition      ?? 'Posición';
    case 'sheetSelectPronouns':      return l10n?.sheetSelectPronouns      ?? 'Pronombres';
    case 'sheetSelectRelationship':  return l10n?.sheetSelectRelationship  ?? 'Estado civil';
    case 'sheetSelectRole':          return l10n?.sheetSelectRole          ?? 'Rol';
    case 'sheetSelectLookingFor':    return l10n?.sheetSelectLookingFor    ?? 'Busco';
    case 'sheetSelectMeetAt':        return l10n?.sheetSelectMeetAt        ?? 'Quedamos en';
    case 'sheetSelectTags':          return l10n?.sheetSelectTags          ?? 'Intereses';
    case 'sheetSelectHeight':        return l10n?.sheetSelectHeight        ?? 'Altura (cm)';
    case 'sheetSelectWeight':        return l10n?.sheetSelectWeight        ?? 'Peso (kg)';
    default: return key;
  }
}

// ─── Sheet bodies ───────────────────────────────────────────────────────────

class _SingleSelectSheet extends StatelessWidget {
  final String title;
  final List<String> options;
  final String? current;
  const _SingleSelectSheet({
    required this.title,
    required this.options,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VibraTheme.kPadPage, 16, VibraTheme.kPadPage, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: VibraTheme.displayName,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: VibraTheme.kTextSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: VibraTheme.kDivider),
            // Options list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options[i];
                  final isSelected = opt == current;
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(opt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: VibraTheme.kPadPage, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? VibraTheme.kBrandPrimary
                                : VibraTheme.kTextSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              opt,
                              style: TextStyle(
                                color: isSelected
                                    ? VibraTheme.kTextPrimary
                                    : VibraTheme.kTextSecondary,
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final Set<String> current;
  const _MultiSelectSheet({
    required this.title,
    required this.options,
    required this.current,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late Set<String> _picked;

  @override
  void initState() {
    super.initState();
    _picked = Set<String>.from(widget.current);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VibraTheme.kPadPage, 16, VibraTheme.kPadPage, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: VibraTheme.displayName,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_picked),
                    child: const Text('OK',
                        style: TextStyle(
                            color: VibraTheme.kBrandPrimary,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: VibraTheme.kDivider),
            // Chips
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ChipMultiSelect(
                options: widget.options,
                selected: _picked,
                onChanged: (next) => setState(() => _picked = next),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumericSheet extends StatefulWidget {
  final String title;
  final int min;
  final int max;
  final int step;
  final String unit;
  final int? current;
  const _NumericSheet({
    required this.title,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.current,
  });

  @override
  State<_NumericSheet> createState() => _NumericSheetState();
}

class _NumericSheetState extends State<_NumericSheet> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.current ?? ((widget.min + widget.max) ~/ 2);
  }

  void _bump(int delta) {
    final next = (_value + delta).clamp(widget.min, widget.max);
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  VibraTheme.kPadPage, 16, VibraTheme.kPadPage, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: VibraTheme.displayName,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: VibraTheme.kTextSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: VibraTheme.kDivider),
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 32, horizontal: VibraTheme.kPadPage),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: VibraTheme.kBrandPrimary, size: 36),
                    onPressed: () => _bump(-widget.step),
                  ),
                  const SizedBox(width: 24),
                  Text(
                    '$_value ${widget.unit}',
                    style: const TextStyle(
                      color: VibraTheme.kTextPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: VibraTheme.kBrandPrimary, size: 36),
                    onPressed: () => _bump(widget.step),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(VibraTheme.kPadPage),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_value),
                  child: const Text('OK'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}