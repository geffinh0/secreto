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
  List<AdminAgency> _agencies = [];
  AdminAgency? _noAgency;
  AdminCapacity? _capacity;
  bool _isLoading = false;
  bool _isLoggingIn = false;
  String? _error;

  bool get isAuthenticated => _isAuthenticated;
  bool get isRestoringSession => _isRestoringSession;
  String? get adminUsername => _adminUsername;
  List<AdminUserSummary> get users => _users;
  List<AdminSessionSummary> get sessions => _sessions;
  List<AdminAgency> get agencies => _agencies;

  /// Creators who signed up before agencies existed (no agency code).
  AdminAgency? get noAgency => _noAgency;
  AdminCapacity? get capacity => _capacity;
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
    _agencies = [];
    _noAgency = null;
    _capacity = null;
    notifyListeners();
  }

  /// Creates an agency; returns its signup code, or null (see [error]).
  Future<String?> createAgency(String name) async {
    final result = await _api.post('/admin/agencies', {'name': name});
    if (result['success'] == true && result['data'] is Map) {
      final code = (result['data'] as Map)['code'] as String?;
      await _loadAgencies();
      notifyListeners();
      return code;
    }
    _error = AdminApiService.errorMessage(result, 'Não foi possível criar a agência.');
    notifyListeners();
    return null;
  }

  /// Turns an agency's code on/off for NEW signups (existing creators stay).
  Future<bool> setAgencyActive(int agencyId, bool active) async {
    final result = await _api.post('/admin/agencies/$agencyId/active', {'active': active});
    if (result['success'] != true) {
      _error = AdminApiService.errorMessage(result, 'Não foi possível alterar a agência.');
      notifyListeners();
      return false;
    }
    await _loadAgencies();
    notifyListeners();
    return true;
  }

  /// New code for an agency whose code leaked; returns it, or null.
  Future<String?> rotateAgencyCode(int agencyId) async {
    final result = await _api.post('/admin/agencies/$agencyId/rotate_code', {});
    if (result['success'] == true && result['data'] is Map) {
      final code = (result['data'] as Map)['code'] as String?;
      await _loadAgencies();
      notifyListeners();
      return code;
    }
    _error = AdminApiService.errorMessage(result, 'Não foi possível gerar um novo código.');
    notifyListeners();
    return null;
  }

  Future<void> _loadAgencies() async {
    final result = await _api.get('/admin/agencies');
    if (result['success'] == true && result['data'] is Map) {
      final data = (result['data'] as Map).cast<String, dynamic>();
      _agencies = (data['agencies'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => AdminAgency.fromJson(e.cast<String, dynamic>()))
          .toList();
      final legacy = data['no_agency'];
      _noAgency = legacy is Map
          ? AdminAgency.fromJson({...legacy.cast<String, dynamic>(), 'id': 0, 'name': 'Sem agência'})
          : null;
    }
  }

  Future<void> _loadCapacity() async {
    final result = await _api.get('/admin/capacity');
    if (result['success'] == true && result['data'] is Map) {
      _capacity = AdminCapacity.fromJson((result['data'] as Map).cast<String, dynamic>());
    }
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

    if (usersOk) {
      // best effort: the users list is what decides "logged in", these only decorate
      await _loadAgencies();
      await _loadCapacity();
    }

    return usersOk;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
