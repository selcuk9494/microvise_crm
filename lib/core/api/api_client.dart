import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/app_config.dart';
import '../auth/auth_providers.dart';

final apiClientProvider = Provider<ApiClient?>((ref) {
  final baseUrl = AppConfig.apiBaseUrl;
  if (baseUrl == null || baseUrl.isEmpty) return null;
  return ApiClient(ref: ref, baseUrl: baseUrl);
});

class ApiClient {
  ApiClient({required this.ref, required this.baseUrl});

  final Ref ref;
  final String baseUrl;

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    if (baseUrl.startsWith('http://') || baseUrl.startsWith('https://')) {
      final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final uri = Uri.parse(normalizedBase)
          .resolve(path.startsWith('/') ? path.substring(1) : path);
      return uri.replace(queryParameters: queryParameters);
    }

    if (kIsWeb && baseUrl.startsWith('/')) {
      final uri =
          Uri.base.resolve(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
      final resolved =
          uri.resolve(path.startsWith('/') ? path.substring(1) : path);
      return resolved.replace(queryParameters: queryParameters);
    }

    throw UnsupportedError('API_BASE_URL bu platform için ayarlı değil.');
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? queryParameters,
    bool requiresAuth = true,
  }) async {
    return _requestJson(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      requiresAuth: requiresAuth,
    );
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Object? body,
    Map<String, String>? queryParameters,
    bool requiresAuth = true,
  }) async {
    return _requestJson(
      method: 'PATCH',
      path: path,
      queryParameters: queryParameters,
      requiresAuth: requiresAuth,
      body: body,
    );
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    required bool requiresAuth,
    Object? body,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (requiresAuth) {
      final session = ref.read(sessionProvider);
      final accessToken = session?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Oturum bulunamadı.');
      }
      headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }

    final request = http.Request(method, _buildUri(path, queryParameters));
    request.headers.addAll(headers);
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'API hatası (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {
        if (response.body.isNotEmpty) message = response.body;
      }
      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Beklenmeyen API yanıtı.');
  }
}

