import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// A saved chat phrase (text + display order).
class Phrase {
  final String id;
  final String text;
  final int position;

  const Phrase({
    required this.id,
    required this.text,
    required this.position,
  });

  factory Phrase.fromJson(Map<String, dynamic> json) {
    return Phrase(
      id: json['id'] as String,
      text: json['phrase'] as String,
      position: (json['position'] as int?) ?? 0,
    );
  }
}

/// REST client for the `/phrases` endpoint.
class PhrasesService {
  final Dio _dio;

  PhrasesService(this._dio);

  /// GET /phrases — list the current user's saved phrases.
  Future<List<Phrase>> list() async {
    final response = await _dio.get<Map<String, dynamic>>('/phrases');
    final data = response.data!;
    final list = data['phrases'] as List<dynamic>;
    return list
        .map((p) => Phrase.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// POST /phrases — add a new phrase. Returns the created phrase.
  Future<Phrase> add(String text) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/phrases',
      data: {'phrase': text},
    );
    return Phrase.fromJson(response.data!['phrase'] as Map<String, dynamic>);
  }

  /// DELETE /phrases/:id — remove a phrase.
  Future<void> delete(String id) async {
    await _dio.delete<void>('/phrases/$id');
  }

  /// PUT /phrases/order — reorder phrases by their new id sequence.
  Future<void> reorder(List<String> ids) async {
    await _dio.put<void>(
      '/phrases/order',
      data: {'ids': ids},
    );
  }
}

/// Riverpod provider for the PhrasesService.
final phrasesServiceProvider = Provider<PhrasesService>((ref) {
  final dio = ref.watch(dioProvider);
  return PhrasesService(dio);
});

/// FutureProvider for the list of saved phrases.
final phrasesProvider = FutureProvider<List<Phrase>>((ref) async {
  final service = ref.watch(phrasesServiceProvider);
  return service.list();
});
