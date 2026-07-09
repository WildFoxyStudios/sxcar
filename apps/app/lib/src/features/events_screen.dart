import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/gen/app_localizations.dart';
import '../events/events_service.dart';
import '../location/location_service.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Provider — fetches events using the user's current location
// ---------------------------------------------------------------------------

final nearbyEventsProvider = FutureProvider<List<Event>>((ref) async {
  final service = ref.watch(eventsServiceProvider);
  // Use .future to get the unwrapped Position? value
  final position = await ref.read(currentPositionProvider.future);
  final lat = position?.latitude ?? 0.0;
  final lon = position?.longitude ?? 0.0;
  return service.listNearby(lat: lat, lon: lon);
});

/// Header image color for event cards.
const Color _kEventAccent = VibraTheme.kEventAccent;

// ---------------------------------------------------------------------------
// EventsScreen — list of nearby events
// ---------------------------------------------------------------------------

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final eventsAsync = ref.watch(nearbyEventsProvider);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        title: Text(
          l10n.events_title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateEventSheet(context, ref),
        backgroundColor: _kEventAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(l10n.events_create),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is DioException
              ? l10n.events_load_error
              : '$err',
          onRetry: () => ref.invalidate(nearbyEventsProvider),
        ),
        data: (events) {
          if (events.isEmpty) {
            return _EmptyView(
              title: l10n.events_empty_title,
              subtitle: l10n.events_empty_subtitle,
              onCreate: () => _showCreateEventSheet(context, ref),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(nearbyEventsProvider);
              await ref.read(nearbyEventsProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: events.length,
              itemBuilder: (_, i) => _EventCard(
                event: events[i],
                onTap: () => context.push('/events/${events[i].id}'),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCreateEventSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VibraTheme.kSurface,
      builder: (_) => _CreateEventSheet(
        onCreated: () => ref.invalidate(nearbyEventsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event card widget
// ---------------------------------------------------------------------------

class _EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;

  const _EventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final startsAt = DateTime.tryParse(event.startsAt);
    final dateStr = startsAt != null
        ? '${startsAt.month}/${startsAt.day} ${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}'
        : event.startsAt;

    // Format distance
    final distStr = event.distanceM != null
        ? event.distanceM! >= 1000
            ? '${(event.distanceM! / 1000).toStringAsFixed(1)} km'
            : '${event.distanceM!.toStringAsFixed(0)} m'
        : null;

    return Card(
      color: VibraTheme.kSurface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Text(
                event.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Location
              Row(
                children: [
                  const Icon(Icons.location_on, color: VibraTheme.kTextSecondary, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      event.locationName,
                      style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Date/time
              Row(
                children: [
                  const Icon(Icons.access_time, color: VibraTheme.kTextSecondary, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    dateStr,
                    style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Bottom row: distance + attendees
              Row(
                children: [
                  if (distStr != null) ...[
                    const Icon(Icons.near_me, color: _kEventAccent, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      distStr,
                      style: const TextStyle(color: _kEventAccent, fontSize: 13),
                    ),
                    const SizedBox(width: 16),
                  ],
                  const Icon(Icons.people, color: VibraTheme.kTextSecondary, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    l10n.events_attendee_count(event.attendeeCount),
                    style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  if (event.myStatus != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: event.myStatus == 'going'
                            ? VibraTheme.kSuccess.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        event.myStatus == 'going' ? l10n.events_going : l10n.events_maybe,
                        style: TextStyle(
                          color: event.myStatus == 'going' ? VibraTheme.kSuccess : Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyView extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onCreate;

  const _EmptyView({
    required this.title,
    required this.subtitle,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event, size: 64, color: VibraTheme.kTextSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(l10n.events_create),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kEventAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: VibraTheme.kError),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(l10n.events_retry),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create event bottom sheet
// ---------------------------------------------------------------------------

class _CreateEventSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateEventSheet({required this.onCreated});

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      _dateCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: 19, minute: 0),
    );
    if (picked != null) {
      _timeCtrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _submit(WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    if (_titleCtrl.text.trim().isEmpty ||
        _locationCtrl.text.trim().isEmpty ||
        _dateCtrl.text.isEmpty ||
        _timeCtrl.text.isEmpty) {
      return;
    }

    setState(() => _loading = true);
    try {
      final service = ref.read(eventsServiceProvider);
      final position = await ref.read(currentPositionProvider.future);
      final locationLat = position?.latitude ?? 0.0;
      final locationLon = position?.longitude ?? 0.0;
      final startsAt = '${_dateCtrl.text}T${_timeCtrl.text}:00Z';

      await service.create(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        locationName: _locationCtrl.text.trim(),
        lat: locationLat,
        lon: locationLon,
        startsAt: startsAt,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.events_created)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.events_create_error)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Use a builder to get the ref
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Consumer(
        builder: (context, ref, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.events_create,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: l10n.events_form_title,
                  labelStyle: const TextStyle(color: VibraTheme.kTextSecondary),
                  hintText: l10n.events_form_title_hint,
                  hintStyle: const TextStyle(color: VibraTheme.kTextSecondary),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: l10n.events_form_description,
                  labelStyle: const TextStyle(color: VibraTheme.kTextSecondary),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: l10n.events_form_location,
                  labelStyle: const TextStyle(color: VibraTheme.kTextSecondary),
                  hintText: l10n.events_form_location_hint,
                  hintStyle: const TextStyle(color: VibraTheme.kTextSecondary),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dateCtrl,
                      readOnly: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: l10n.events_form_date,
                        labelStyle: const TextStyle(color: VibraTheme.kTextSecondary),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today, color: VibraTheme.kTextSecondary),
                          onPressed: _pickDate,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _timeCtrl,
                      readOnly: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: l10n.events_form_time,
                        labelStyle: const TextStyle(color: VibraTheme.kTextSecondary),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.access_time, color: VibraTheme.kTextSecondary),
                          onPressed: _pickTime,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : () => _submit(ref),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kEventAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.events_form_create),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}
