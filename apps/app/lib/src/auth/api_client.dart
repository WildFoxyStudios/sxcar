import 'package:dio/dio.dart';
import 'token_storage.dart';
import 'models.dart';
import '../config.dart';

Dio createAuthClient(TokenStorage tokenStorage) {
  final dio = Dio(BaseOptions(
    baseUrl: apiUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Content-Type': 'application/json',
    },
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Don't add auth header to refresh requests
      if (options.path.contains('/auth/refresh')) {
        handler.next(options);
        return;
      }
      final token = await tokenStorage.getAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      if (error.response?.statusCode != 401) {
        handler.next(error);
        return;
      }

      // Only attempt refresh if we haven't already tried
      final requestOptions = error.requestOptions;
      if (requestOptions.extra['_retry'] == true) {
        handler.next(error);
        return;
      }

      // Don't try to refresh if the failed request was itself a refresh
      if (requestOptions.path.contains('/auth/refresh')) {
        await tokenStorage.clearTokens();
        handler.next(error);
        return;
      }

      try {
        final refreshToken = await tokenStorage.getRefreshToken();
        if (refreshToken == null) {
          await tokenStorage.clearTokens();
          handler.next(error);
          return;
        }

        final response = await dio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refresh': refreshToken},
        );

        final newAccess = response.data!['access'] as String;
        final newRefresh = response.data!['refresh'] as String;
        await tokenStorage.saveTokens(access: newAccess, refresh: newRefresh);

        final retryOptions = RequestOptions(
          path: requestOptions.path,
          method: requestOptions.method,
          data: requestOptions.data,
          queryParameters: requestOptions.queryParameters,
          headers: {
            ...requestOptions.headers,
            'Authorization': 'Bearer $newAccess',
          },
          extra: {...requestOptions.extra, '_retry': true},
          responseType: requestOptions.responseType,
          contentType: requestOptions.contentType,
        );

        final retryResponse = await dio.fetch(retryOptions);
        handler.resolve(retryResponse);
      } catch (e) {
        await tokenStorage.clearTokens();
        handler.next(DioException(
          requestOptions: requestOptions,
          error: AuthException('Session expired. Please login again.'),
          response: null,
          type: DioExceptionType.badResponse,
        ));
      }
    },
  ));

  return dio;
}
