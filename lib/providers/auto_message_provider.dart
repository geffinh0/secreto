import 'package:flutter/material.dart';
import '../core/models/models.dart';
import '../core/services/portal_api_service.dart';

class AutoMessageProvider extends ChangeNotifier {
  AutoMessageProvider({PortalApiService? api}) : _api = api ?? PortalApiService();

  final PortalApiService _api;

  List<AutoMessage> _messages = [];
  BotSettings? _settings;
  bool _isLoading = false;
  String? _error;

  List<AutoMessage> get messages => List.from(_messages)
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  BotSettings? get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get autoEnabled => _settings?.autoMessagesEnabled ?? false;
  int get intervalSeconds => _settings?.messageIntervalSeconds ?? 120;

  Future<void> load(int userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final messagesResult = await _api.get('/messages?user_id=$userId');
    final settingsResult = await _api.get('/settings?user_id=$userId');

    if (messagesResult['success'] == true && messagesResult['data'] is List) {
      final List<dynamic> data = messagesResult['data'] as List<dynamic>;
      _messages = data.map((m) => AutoMessage.fromJson(m)).toList();
    } else {
      _error = PortalApiService.errorMessage(messagesResult, 'Erro ao carregar mensagens');
    }

    if (settingsResult['success'] == true) {
      _settings = BotSettings.fromJson(settingsResult['data']);
    } else {
      _settings ??= BotSettings(userId: userId);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addMessage({required int userId, required String content}) async {
    final nextOrder = _messages.isEmpty
        ? 0
        : _messages.map((m) => m.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    final msg = AutoMessage(userId: userId, content: content, sortOrder: nextOrder);
    final result = await _api.post('/messages', msg.toJson());

    if (result['success'] == true) {
      _messages.add(AutoMessage.fromJson(result['data']));
      notifyListeners();
      return true;
    }
    _error = PortalApiService.errorMessage(result, 'Erro ao adicionar mensagem');
    notifyListeners();
    return false;
  }

  Future<bool> updateMessage(AutoMessage message) async {
    final result = await _api.put('/messages/${message.id}', message.toJson());
    if (result['success'] == true) {
      final idx = _messages.indexWhere((m) => m.id == message.id);
      if (idx != -1) {
        _messages[idx] = AutoMessage.fromJson(result['data']);
        notifyListeners();
      }
      return true;
    }
    _error = PortalApiService.errorMessage(result, 'Erro ao atualizar mensagem');
    notifyListeners();
    return false;
  }

  Future<bool> toggleMessage(AutoMessage message) =>
      updateMessage(message.copyWith(isActive: !message.isActive));

  Future<bool> deleteMessage(int messageId) async {
    final result = await _api.delete('/messages/$messageId');
    if (result['success'] == true) {
      _messages.removeWhere((m) => m.id == messageId);
      _reorderAfterDelete();
      notifyListeners();
      return true;
    }
    _error = PortalApiService.errorMessage(result, 'Erro ao remover mensagem');
    notifyListeners();
    return false;
  }

  Future<void> reorderMessages(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final sorted = messages; // sorted copy
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);

    // Update sort_order for all
    for (int i = 0; i < sorted.length; i++) {
      final updated = sorted[i].copyWith(sortOrder: i);
      final idx = _messages.indexWhere((m) => m.id == sorted[i].id);
      if (idx != -1) _messages[idx] = updated;
    }
    notifyListeners();
    for (final m in _messages) {
      await _api.put('/messages/${m.id}', {'sort_order': m.sortOrder});
    }
  }

  Future<bool> saveSettings(BotSettings settings) async {
    final result = await _api.put('/settings/${settings.userId}', settings.toJson());
    if (result['success'] == true) {
      _settings = BotSettings.fromJson(result['data']);
      notifyListeners();
      return true;
    }
    _error = PortalApiService.errorMessage(result, 'Erro ao salvar configurações');
    notifyListeners();
    return false;
  }

  Future<bool> toggleAutoMessages(int userId) async {
    final current = _settings ?? BotSettings(userId: userId);
    return saveSettings(
      current.copyWith(autoMessagesEnabled: !current.autoMessagesEnabled),
    );
  }

  void _reorderAfterDelete() {
    final sorted = messages;
    for (int i = 0; i < sorted.length; i++) {
      final idx = _messages.indexWhere((m) => m.id == sorted[i].id);
      if (idx != -1) _messages[idx] = _messages[idx].copyWith(sortOrder: i);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Forget everything (called when the logged user changes).
  void reset() {
    _messages = [];
    _settings = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
