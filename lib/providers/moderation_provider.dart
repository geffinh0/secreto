import 'package:flutter/material.dart';
import '../core/models/models.dart';
import '../core/services/portal_api_service.dart';

class ModerationProvider extends ChangeNotifier {
  ModerationProvider({PortalApiService? api}) : _api = api ?? PortalApiService();

  final PortalApiService _api;

  List<ModerationRule> _rules = [];
  bool _isLoading = false;
  String? _error;

  List<ModerationRule> get rules => _rules;
  List<ModerationRule> get muteRules =>
      _rules.where((r) => r.action == 'mute').toList();
  List<ModerationRule> get kickRules =>
      _rules.where((r) => r.action == 'kick').toList();
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadRules(int userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _api.get('/moderation/rules?user_id=$userId');
    if (result['success'] == true && result['data'] is List) {
      final List<dynamic> data = result['data'] as List<dynamic>;
      _rules = data.map((r) => ModerationRule.fromJson(r)).toList();
    } else {
      _error = PortalApiService.errorMessage(result, 'Erro ao carregar regras');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addRule({
    required int userId,
    required String keyword,
    required String action,
  }) async {
    _error = null;
    final rule = ModerationRule(userId: userId, keyword: keyword, action: action);
    final result = await _api.post('/moderation/rules', rule.toJson());

    if (result['success'] == true) {
      _rules.insert(0, ModerationRule.fromJson(result['data']));
      notifyListeners();
      return true;
    }
    _error = PortalApiService.errorMessage(result, 'Erro ao adicionar regra');
    notifyListeners();
    return false;
  }

  Future<bool> updateRule(ModerationRule rule) async {
    final result = await _api.put('/moderation/rules/${rule.id}', rule.toJson());
    if (result['success'] == true) {
      final idx = _rules.indexWhere((r) => r.id == rule.id);
      if (idx != -1) {
        _rules[idx] = ModerationRule.fromJson(result['data']);
        notifyListeners();
      }
      return true;
    }
    _error = PortalApiService.errorMessage(result, 'Erro ao atualizar regra');
    notifyListeners();
    return false;
  }

  Future<bool> deleteRule(int ruleId) async {
    final result = await _api.delete('/moderation/rules/$ruleId');
    if (result['success'] == true) {
      _rules.removeWhere((r) => r.id == ruleId);
      notifyListeners();
      return true;
    }
    _error = PortalApiService.errorMessage(result, 'Erro ao remover regra');
    notifyListeners();
    return false;
  }

  Future<bool> toggleRule(ModerationRule rule) async {
    return updateRule(rule.copyWith(isActive: !rule.isActive));
  }

  /// Runs [text] through the user's own active rules server-side (same
  /// matcher the robot uses) - lets her check a tricky spelling before
  /// trusting it live. Returns `null` on a network/server error.
  Future<PhraseTestResult?> testPhrase({required int userId, required String text}) async {
    final result = await _api.post('/moderation/test', {'user_id': userId, 'text': text});
    if (result['success'] == true) return PhraseTestResult.fromJson(result['data']);
    _error = PortalApiService.errorMessage(result, 'Erro ao testar a frase');
    notifyListeners();
    return null;
  }

  /// Adds every keyword in [keywords] under the same [action] in one request
  /// - paste a batch instead of one at a time. Returns what the server
  /// actually created/skipped so the caller can show a precise summary.
  Future<BulkRuleResult?> addRulesBulk({
    required int userId,
    required String action,
    required List<String> keywords,
  }) async {
    final result = await _api.post('/moderation/rules/bulk', {
      'user_id': userId,
      'action': action,
      'keywords': keywords,
    });
    if (result['success'] == true) {
      final bulkResult = BulkRuleResult.fromJson(result['data']);
      if (bulkResult.created.isNotEmpty) {
        _rules.insertAll(0, bulkResult.created);
        notifyListeners();
      }
      return bulkResult;
    }
    _error = PortalApiService.errorMessage(result, 'Erro ao adicionar palavras em lote');
    notifyListeners();
    return null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Forget everything (called when the logged user changes).
  void reset() {
    _rules = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
