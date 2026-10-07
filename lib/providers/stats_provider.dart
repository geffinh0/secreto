import 'package:flutter/material.dart';
import '../core/models/models.dart';
import '../core/services/portal_api_service.dart';

class StatsProvider extends ChangeNotifier {
  StatsProvider({PortalApiService? api}) : _api = api ?? PortalApiService();

  final PortalApiService _api;

  ModerationStats? _stats;
  bool _isLoading = false;
  String? _error;
  int _days = 30;

  ModerationStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get days => _days;

  void reset() {
    _stats = null;
    _error = null;
    _days = 30;
    notifyListeners();
  }

  Future<void> load(int userId, {int? days}) async {
    _days = days ?? _days;
    _isLoading = true;
    notifyListeners();

    final result = await _api.get('/stats?user_id=$userId&days=$_days');
    if (result['success'] == true) {
      _stats = ModerationStats.fromJson(result['data']);
      _error = null;
    } else {
      _error = PortalApiService.errorMessage(result, 'Erro ao carregar estatísticas');
    }

    _isLoading = false;
    notifyListeners();
  }
}
