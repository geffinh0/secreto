import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Service for our own portal backend (FastAPI + SQLite).
///
/// Every method resolves to `{statusCode, data, success, error?}` and never throws.
class PortalApiService {
  final String baseUrl;

  /// Called when an authenticated request is answered with 401 (expired or
  /// revoked session) so the app can send the user back to the login screen.
  static void Function()? onUnauthorized;

  PortalApiService({this.baseUrl = AppConstants.localBackendUrl});

  static const Duration _defaultTimeout = Duration(seconds: 15);

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyPortalToken);
  }

  Future<Map<String, String>> _getHeaders({bool requireAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (requireAuth) {
      final token = await _getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = true,
    Duration timeout = _defaultTimeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      final encoded = body == null ? null : jsonEncode(body);
      final http.Response response;
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          response =
              await http.post(uri, headers: headers, body: encoded).timeout(timeout);
        case 'PUT':
          response =
              await http.put(uri, headers: headers, body: encoded).timeout(timeout);
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(timeout);
        default:
          throw ArgumentError('Unsupported method $method');
      }

      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        data = null; // non-JSON body (e.g. a plain-text 500)
      }
      if (response.statusCode == 401 && requireAuth) {
        onUnauthorized?.call();
      }
      return {
        'statusCode': response.statusCode,
        'data': data,
        'success': response.statusCode >= 200 && response.statusCode < 300,
      };
    } catch (e) {
      return {'statusCode': 0, 'data': null, 'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool requireAuth = true,
    Duration timeout = _defaultTimeout,
  }) =>
      _send('POST', path, body: body, requireAuth: requireAuth, timeout: timeout);

  Future<Map<String, dynamic>> get(
    String path, {
    bool requireAuth = true,
    Duration timeout = _defaultTimeout,
  }) =>
      _send('GET', path, requireAuth: requireAuth, timeout: timeout);

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  /// Readable message for a failed result: the server's `detail` when it sent
  /// one, a hint when the server is unreachable, otherwise [fallback].
  static String errorMessage(Map<String, dynamic> result, String fallback) {
    final data = result['data'];
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) return first['msg'] as String;
      }
    }
    if (result['statusCode'] == 0) {
      return 'Não foi possível conectar ao servidor (${AppConstants.localBackendUrl}). '
          'Ele está rodando?';
    }
    return fallback;
  }
}
