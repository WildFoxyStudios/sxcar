import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/theme/app_theme.dart';

/// One trip entry.
class TripEntry {
  final String date; // ISO yyyy-MM-dd or human "Mar 2024"
  final String location;
  final String? notes;

  const TripEntry({
    required this.date,
    required this.location,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'location': location,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

class AddTripScreen extends StatefulWidget {
  final List<TripEntry> current;
  final ValueChanged<List<TripEntry>> onChanged;
  const AddTripScreen({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  State<AddTripScreen> createState() => _AddTripScreenState();
}

class _AddTripScreenState extends State<AddTripScreen> {
  late List<TripEntry> _trips;

  @override
  void initState() {
    super.initState();
    _trips = List<TripEntry>.from(widget.current);
  }

  Future<void> _openAddForm() async {
    final result = await showModalBottomSheet<TripEntry>(
      context: context,
      backgroundColor: VibraTheme.kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _TripFormSheet(),
    );
    if (result != null) {
      setState(() => _trips = [..._trips, result]);
      widget.onChanged(_trips);
    }
  }

  void _remove(int index) {
    setState(() => _trips = [..._trips]..removeAt(index));
    widget.onChanged(_trips);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.detailsTripCount)),
      body: _trips.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.editProfilePlaceholderTrips,
                  textAlign: TextAlign.center,
                  style: VibraTheme.bodySecondary,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _trips.length,
              itemBuilder: (_, i) {
                final trip = _trips[i];
                return ListTile(
                  title: Text(trip.location,
                      style: const TextStyle(color: VibraTheme.kTextPrimary)),
                  subtitle: Text(
                    [trip.date, if (trip.notes != null) trip.notes!]
                        .join(' · '),
                    style: VibraTheme.bodySecondary,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: VibraTheme.kTextSecondary),
                    onPressed: () => _remove(i),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: VibraTheme.kBrandPrimary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: Text(l10n.editProfileAdd),
        onPressed: _openAddForm,
      ),
    );
  }
}

class _TripFormSheet extends StatefulWidget {
  const _TripFormSheet();

  @override
  State<_TripFormSheet> createState() => _TripFormSheetState();
}

class _TripFormSheetState extends State<_TripFormSheet> {
  final _dateCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _dateError;
  String? _locationError;

  @override
  void dispose() {
    _dateCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _dateError = _dateCtrl.text.trim().isEmpty ? l10n.tripFechaRequerida : null;
      _locationError =
          _locationCtrl.text.trim().isEmpty ? l10n.tripLocalizacionRequerida : null;
    });
    if (_dateError != null || _locationError != null) return;

    Navigator.of(context).pop(TripEntry(
      date: _dateCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: VibraTheme.kPadPage,
          right: VibraTheme.kPadPage,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.nuevoViaje,
                style: const TextStyle(
                  color: VibraTheme.kTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 16),
            TextField(
              controller: _dateCtrl,
              decoration: InputDecoration(
                labelText: l10n.tripFechaLabel,
                errorText: _dateError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              decoration: InputDecoration(
                labelText: l10n.tripLocalizacion,
                errorText: _locationError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.tripNotas,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _save, child: Text(l10n.guardar)),
          ],
        ),
      ),
    );
  }
}