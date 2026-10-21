import 'package:flutter/material.dart';
import '../core/models/models.dart';
import '../core/services/portal_api_service.dart';

class StatsProvider extends ChangeNotifier {
  StatsProvider({PortalApiService? api}) : _api = api ?? PortalApiService();

  final PortalApiService _api;

  List<LiveRanking> _rankings = const [];
  bool _rankingsFailed = false;

  List<LiveRanking> get rankings => _rankings;
  bool get rankingsFailed => _rankingsFailed;

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
    _rankings = const [];
    _rankingsFailed = false;
    notifyListeners();
  }

  /// Rankings of the last lives (diamonds per sender, one list per live).
  Future<void> loadRankings() async {
    final result = await _api.get('/live_rankings');
    if (result['success'] == true && result['data'] is Map) {
      _rankings = [
        for (final r in ((result['data'] as Map)['rankings'] as List? ?? const [])
            .whereType<Map>())
          LiveRanking.fromJson(r.cast<String, dynamic>())
      ];
      _rankingsFailed = false;
    } else {
      _rankingsFailed = true;
    }
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
      _stats = null;
      _error = PortalApiService.errorMessage(result, 'Não foi possível carregar as estatísticas. Tente de novo.');
    }

    _isLoading = false;
    notifyListeners();
  }
}
