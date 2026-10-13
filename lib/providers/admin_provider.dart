import 'package:flutter/material.dart';
import '../core/models/models.dart';
import '../core/services/admin_api_service.dart';

/// The admin panel's own auth + data, entirely separate from AuthProvider
/// (the regular portal login). Backed by admin_accounts/admin_sessions on
/// the server - a portal session token is never valid here, and logging out
/// of one never affects the other.
class AdminProvider extends ChangeNotifier {
  AdminProvider({AdminApiService? api}) : _api = api ?? AdminApiService();

  final AdminApiService _api;

  bool _isAuthenticated = false;
  bool _isRestoringSession = true; // true until the saved token (if any) is checked
  String? _adminUsername;
  List<AdminUserSummary> _users = [];
  List<AdminSessionSummary> _sessions = [];
  bool _isLoading = false;
  bool _isLoggingIn = false;
  String? _error;

  bool get isAuthenticated => _isAuthenticated;
  bool get isRestoringSession => _isRestoringSession;
  String? get adminUsername => _adminUsername;
  List<AdminUserSummary> get users => _users;
  List<AdminSessionSummary> get sessions => _sessions;
  bool get isLoading => _isLoading;
  bool get isLoggingIn => _isLoggingIn;
  String? get error => _error;

  /// Call once when the admin screen first mounts: if a saved token still
  /// works, goes straight to the panel instead of asking to log in again.
  Future<void> restoreSession() async {
    final token = await _api.getToken();
    if (token == null) {
      _isRestoringSession = false;
      notifyListeners();
      return;
    }
    final ok = await _tryLoad();
    _isAuthenticated = ok;
    _isRestoringSession = false;
    if (!ok) await _api.setToken(null); // stale/expired - don't keep retrying it
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoggingIn = true;
    _error = null;
    notifyListeners();

    final result = await _api.post(
      '/admin/login', {'username': username, 'password': password},
      requireAuth: false,
    );
    if (result['success'] == true && result['data'] is Map) {
      final data = (result['data'] as Map).cast<String, dynamic>();
      await _api.setToken(data['access_token'] as String?);
      final admin = (data['admin'] as Map?)?.cast<String, dynamic>();
      _adminUsername = admin?['display_name'] as String? ?? admin?['username'] as String?;
      _isAuthenticated = true;
      _isLoggingIn = false;
      notifyListeners();
      await load();
      return true;
    }
    _error = AdminApiService.errorMessage(result, 'Usuário ou senha inválidos.');
    _isLoggingIn = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await _api.post('/admin/logout', {});
    await _api.setToken(null);
    _isAuthenticated = false;
    _adminUsername = null;
    _users = [];
    _sessions = [];
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    final ok = await _tryLoad();
    if (!ok && _users.isEmpty && _sessions.isEmpty) {
      // couldn't load anything at all - likely the session expired mid-use
      _isAuthenticated = false;
      await _api.setToken(null);
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Fetches both lists; returns whether at least the users list loaded.
  Future<bool> _tryLoad() async {
    final usersResult = await _api.get('/admin/users');
    final sessionsResult = await _api.get('/admin/sessions');

    final usersOk = usersResult['success'] == true && usersResult['data'] is List;
    if (usersOk) {
      _users = (usersResult['data'] as List)
          .whereType<Map>()
          .map((e) => AdminUserSummary.fromJson(e.cast<String, dynamic>()))
          .toList();
    } else {
      _error = AdminApiService.errorMessage(usersResult, 'Erro ao carregar usuárias');
    }

    if (sessionsResult['success'] == true && sessionsResult['data'] is List) {
      _sessions = (sessionsResult['data'] as List)
          .whereType<Map>()
          .map((e) => AdminSessionSummary.fromJson(e.cast<String, dynamic>()))
          .toList();
    } else if (usersOk) {
      _error = AdminApiService.errorMessage(sessionsResult, 'Erro ao carregar sessões');
    }

    return usersOk;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
