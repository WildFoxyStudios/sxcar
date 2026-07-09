import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/gen/app_localizations.dart';
import '../events/events_service.dart';
import '../auth/auth_provider.dart';
import '../theme/app_theme.dart';

/// Provider to fetch event details by id.
final eventDetailProvider = FutureProvider.family<Event, String>((ref, id) {
  final service = ref.watch(eventsServiceProvider);
  return service.getById(id);
});

/// Accent color matching the events list.
const Color _kEventAccent = VibraTheme.kEventAccent;

/// Event detail screen shown after tapping an event card.
class EventDetailScreen extends ConsumerWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        title: Text(
          l10n.events_detail_title,
          style: const TextStyle(color: Colors.white),
        ),
        elevation: 0,
      ),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _DetailError(
          message: err is DioException
              ? l10n.events_load_error
              : '$err',
          onRetry: () => ref.invalidate(eventDetailProvider(eventId)),
        ),
        data: (event) => _DetailContent(
          event: event,
          onStatusChanged: () => ref.invalidate(eventDetailProvider(eventId)),
        ),
      ),
    );
  }
}

class _DetailContent extends ConsumerWidget {
  final Event event;
  final VoidCallback onStatusChanged;

  const _DetailContent({
    required this.event,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final userId = ref.watch(authStateProvider).userId;
    final isCreator = userId == event.creatorId;

    final startsAt = DateTime.tryParse(event.startsAt);
    final endsAt = event.endsAt != null ? DateTime.tryParse(event.endsAt!) : null;

    final dateStr = startsAt != null
        ? '${startsAt.year}-${startsAt.month.toString().padLeft(2, '0')}-${startsAt.day.toString().padLeft(2, '0')}'
        : event.startsAt;
    final timeStr = startsAt != null
        ? '${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}'
        : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header accent block
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _kEventAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  event.locationName,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Date/time section
          _InfoRow(
            icon: Icons.calendar_today,
            label: l10n.events_form_date,
            value: dateStr,
          ),
          if (timeStr.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.access_time,
              label: l10n.events_form_time,
              value: timeStr,
            ),
          ],
          if (endsAt != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.event_busy,
              label: l10n.events_ends,
              value: '${endsAt.month}/${endsAt.day} ${endsAt.hour.toString().padLeft(2, '0')}:${endsAt.minute.toString().padLeft(2, '0')}',
            ),
          ],
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.people,
            label: l10n.events_attendees,
            value: l10n.events_attendee_count(event.attendeeCount),
          ),

          // Description
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              l10n.events_form_description,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              event.description!,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],

          const SizedBox(height: 32),

          // RSVP Buttons
          if (!isCreator) ...[
            Row(
              children: [
                Expanded(
                  child: _RsvpButton(
                    label: l10n.events_going,
                    icon: Icons.check_circle_outline,
                    isActive: event.myStatus == 'going',
                    color: Colors.green,
                    onPressed: () => _attend(context, ref, 'going'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RsvpButton(
                    label: l10n.events_maybe,
                    icon: Icons.help_outline,
                    isActive: event.myStatus == 'maybe',
                    color: Colors.orange,
                    onPressed: () => _attend(context, ref, 'maybe'),
                  ),
                ),
              ],
            ),
          ],

          // My status badge (creator or after RSVP)
          if (event.myStatus != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: event.myStatus == 'going'
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  event.myStatus == 'going'
                      ? l10n.events_you_are_going
                      : l10n.events_you_are_maybe,
                  style: TextStyle(
                    color: event.myStatus == 'going' ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],

          // Creator delete button
          if (isCreator) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _deleteEvent(context, ref),
                icon: const Icon(Icons.delete, color: Colors.red),
                label: Text(
                  l10n.events_cancel,
                  style: const TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _attend(BuildContext context, WidgetRef ref, String status) async {
    try {
      final service = ref.read(eventsServiceProvider);
      await service.attend(event.id, status);
      onStatusChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'going'
                  ? AppLocalizations.of(context)!.events_rsvp_going
                  : AppLocalizations.of(context)!.events_rsvp_maybe,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.events_rsvp_error)),
        );
      }
    }
  }

  Future<void> _deleteEvent(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibraTheme.kSurface,
        title: Text(l10n.events_cancel_confirm_title,
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.events_cancel_confirm_body,
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.events_cancel_no,
                style: const TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.events_cancel_yes,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = ref.read(eventsServiceProvider);
        await service.delete(event.id);
        if (context.mounted) {
          Navigator.of(context).pop(); // go back to list
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.events_cancelled)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.events_delete_error)),
          );
        }
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _kEventAccent, size: 20),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }
}

class _RsvpButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color color;
  final VoidCallback onPressed;

  const _RsvpButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? color.withValues(alpha: 0.3) : VibraTheme.kSurface,
        foregroundColor: isActive ? color : Colors.white70,
        side: BorderSide(
          color: isActive ? color : Colors.grey.shade600,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DetailError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
