import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/models/models.dart';
import '../core/services/portal_api_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({PortalApiService? api}) : _api = api ?? PortalApiService() {
    // Any authenticated request answered with 401 (expired session) logs us out.
    PortalApiService.onUnauthorized = _handleUnauthorized;
  }

  final PortalApiService _api;

  PortalUser? _user;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  PortalUser? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  bool get isInitialized => _isInitialized;

  /// Restore the saved session (if any) and check it against the server.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.keyPortalToken);
    final userJson = prefs.getString(AppConstants.keyPortalUser);

    if (token != null && userJson != null) {
      try {
        _user = PortalUser.fromJson(jsonDecode(userJson));
        final result = await _api.get('/auth/me');
        if (result['success'] == true) {
          _user = PortalUser.fromJson(result['data']);
          await _saveUser(_user!);
        } else if (result['statusCode'] == 401) {
          await _dropSession(expired: true);
        }
        // Server unreachable (statusCode 0) or failing: keep the saved session so a
        // backend restart does not log the user out. The next request that gets a
        // 401 will.
      } catch (_) {
        await _dropSession();
      }
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    return _authenticate(
      '/auth/login',
      {'username': username, 'password': password},
      fallbackError: 'Credenciais inválidas',
    );
  }

  Future<bool> register(String username, String password, String displayName,
      String agencyCode) async {
    return _authenticate(
      '/auth/register',
      {
        'username': username,
        'password': password,
        'display_name': displayName,
        'agency_code': agencyCode,
      },
      fallbackError: 'Não foi possível criar a conta. Confira os dados e tente de novo.',
    );
  }

  /// True while the user holds a temporary password released by the admin: the router
  /// then only lets her reach the "choose a new password" screen.
  bool get mustChangePassword => _user?.mustChangePassword ?? false;

  /// Sets the user's own password (voluntary, or forced after an admin release).
  /// Other logins of hers are signed out by the server; this one stays.
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _api.post('/auth/change-password', {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
      if (result['success'] == true) {
        final me = await _api.get('/auth/me');
        if (me['success'] == true) {
          _user = PortalUser.fromJson(me['data']);
          await _saveUser(_user!);
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _error = PortalApiService.errorMessage(result, 'Não foi possível trocar a senha. Tente de novo.');
    } catch (_) {
      _error = 'O servidor respondeu algo inesperado. Tente de novo.';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> _authenticate(
    String path,
    Map<String, dynamic> body, {
    required String fallbackError,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.post(path, body, requireAuth: false);
      if (result['success'] == true) {
        final data = result['data'];
        final user = PortalUser.fromJson(data['user']);
        await _saveSession(data['access_token'] as String, user);
        _user = user;
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _error = PortalApiService.errorMessage(result, fallbackError);
    } catch (_) {
      _error = 'O servidor respondeu algo inesperado. Tente de novo.';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    // Revoke the session on the server too (best effort).
    await _api.post('/auth/logout', {});
    await _dropSession();
  }

  void _handleUnauthorized() {
    if (_user == null) return;
    _dropSession(expired: true);
  }

  /// [expired]: the server rejected the saved token (expired, or sessions were
  /// reset) - say so on the login screen instead of dropping the user there silently.
  Future<void> _dropSession({bool expired = false}) async {
    await _clearSession();
    _user = null;
    _error = expired ? 'Sua sessão expirou. Entre novamente.' : null;
    notifyListeners();
  }

  Future<void> _saveSession(String token, PortalUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyPortalToken, token);
    await _saveUser(user);
  }

  Future<void> _saveUser(PortalUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyPortalUser, jsonEncode(user.toJson()));
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyPortalToken);
    await prefs.remove(AppConstants.keyPortalUser);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
