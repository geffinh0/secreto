import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Talks to the /admin/* endpoints only. Deliberately NOT PortalApiService:
/// the admin panel has its own login (admin_accounts/admin_sessions on the
/// backend), its own token (AppConstants.keyAdminToken, never the portal's
/// own keyPortalToken), and its own notion of "logged out" - none of that
/// should ever mix with the regular creator login.
class AdminApiService {
  final String baseUrl;
  AdminApiService({this.baseUrl = AppConstants.localBackendUrl});

  static const Duration _defaultTimeout = Duration(seconds: 15);

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyAdminToken);
  }

  Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(AppConstants.keyAdminToken);
    } else {
      await prefs.setString(AppConstants.keyAdminToken, token);
    }
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
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': 'application/json',
      };
      if (requireAuth) {
        final token = await getToken();
        if (token != null) headers['Authorization'] = 'Bearer $token';
      }
      final encoded = body == null ? null : jsonEncode(body);
      final http.Response response;
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          response = await http.post(uri, headers: headers, body: encoded).timeout(timeout);
        default:
          throw ArgumentError('Unsupported method $method');
      }

      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        data = null;
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

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
          {bool requireAuth = true}) =>
      _send('POST', path, body: body, requireAuth: requireAuth);

  /// Same shape/behaviour as PortalApiService.errorMessage - kept as its own
  /// copy rather than a shared import, so this file has zero dependency on
  /// the portal's own API service.
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
      // Same rule as the portal service: a URL only helps with a local dev backend.
      const url = AppConstants.localBackendUrl;
      return url.startsWith('http')
          ? 'Não foi possível conectar ao servidor ($url). Ele está rodando?'
          : 'Não foi possível conectar ao servidor. Verifique sua conexão.';
    }
    return fallback;
  }
}
