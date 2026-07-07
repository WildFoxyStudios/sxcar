import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// A nearby event.
class Event {
  final String id;
  final String creatorId;
  final String title;
  final String? description;
  final String locationName;
  final double lat;
  final double lon;
  final String startsAt;
  final String? endsAt;
  final int maxAttendees;
  final String createdAt;
  final int attendeeCount;
  final double? distanceM;
  final String? myStatus;

  const Event({
    required this.id,
    required this.creatorId,
    required this.title,
    this.description,
    required this.locationName,
    required this.lat,
    required this.lon,
    required this.startsAt,
    this.endsAt,
    required this.maxAttendees,
    required this.createdAt,
    required this.attendeeCount,
    this.distanceM,
    this.myStatus,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      locationName: json['location_name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      startsAt: json['starts_at'] as String,
      endsAt: json['ends_at'] as String?,
      maxAttendees: json['max_attendees'] as int,
      createdAt: json['created_at'] as String,
      attendeeCount: json['attendee_count'] as int,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      myStatus: json['my_status'] as String?,
    );
  }
}

/// REST client for the `/events` endpoints.
class EventsService {
  final Dio _dio;

  EventsService(this._dio);

  /// GET /events — list nearby events.
  Future<List<Event>> listNearby({
    required double lat,
    required double lon,
    double radiusM = 50000,
    int limit = 50,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/events',
      queryParameters: {
        'lat': lat,
        'lon': lon,
        'radius_m': radiusM,
        'limit': limit,
      },
    );
    final events = response.data!['events'] as List<dynamic>;
    return events
        .map((e) => Event.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /events — create a new event.
  Future<String> create({
    required String title,
    String? description,
    required String locationName,
    required double lat,
    required double lon,
    required String startsAt,
    String? endsAt,
    int maxAttendees = 0,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/events',
      data: {
        'title': title,
        'description': description,
        'location_name': locationName,
        'lat': lat,
        'lon': lon,
        'starts_at': startsAt,
        'ends_at': endsAt,
        'max_attendees': maxAttendees,
      },
    );
    return response.data!['id'] as String;
  }

  /// GET /events/:id — get event detail.
  Future<Event> getById(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/events/$id');
    return Event.fromJson(response.data!['event'] as Map<String, dynamic>);
  }

  /// POST /events/:id/attend — RSVP to an event.
  Future<void> attend(String eventId, String status) async {
    await _dio.post<Map<String, dynamic>>(
      '/events/$eventId/attend',
      data: {'status': status},
    );
  }

  /// DELETE /events/:id — cancel/delete an event (creator only).
  Future<void> delete(String eventId) async {
    await _dio.delete<void>('/events/$eventId');
  }
}

/// Riverpod provider for EventsService.
final eventsServiceProvider = Provider<EventsService>((ref) {
  final dio = ref.watch(dioProvider);
  return EventsService(dio);
});
