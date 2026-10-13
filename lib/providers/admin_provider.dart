import 'package:flutter/material.dart';
import '../core/models/models.dart';
import '../core/services/portal_api_service.dart';

/// Read-only cross-user oversight (GET /admin/*) - only ever usable by an
/// is_admin account; the backend refuses everyone else with 403. See
/// main.py's require_admin.
class AdminProvider extends ChangeNotifier {
  AdminProvider({PortalApiService? api}) : _api = api ?? PortalApiService();

  final PortalApiService _api;

  List<AdminUserSummary> _users = [];
  List<AdminSessionSummary> _sessions = [];
  bool _isLoading = false;
  String? _error;

  List<AdminUserSummary> get users => _users;
  List<AdminSessionSummary> get sessions => _sessions;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final usersResult = await _api.get('/admin/users');
    final sessionsResult = await _api.get('/admin/sessions');

    if (usersResult['success'] == true && usersResult['data'] is List) {
      _users = (usersResult['data'] as List)
          .whereType<Map>()
          .map((e) => AdminUserSummary.fromJson(e.cast<String, dynamic>()))
          .toList();
    } else {
      _error = PortalApiService.errorMessage(usersResult, 'Erro ao carregar usuárias');
    }

    if (sessionsResult['success'] == true && sessionsResult['data'] is List) {
      _sessions = (sessionsResult['data'] as List)
          .whereType<Map>()
          .map((e) => AdminSessionSummary.fromJson(e.cast<String, dynamic>()))
          .toList();
    } else {
      _error ??= PortalApiService.errorMessage(sessionsResult, 'Erro ao carregar sessões');
    }

    _isLoading = false;
    notifyListeners();
  }

  void reset() {
    _users = [];
    _sessions = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
