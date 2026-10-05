import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models/models.dart';
import '../core/services/portal_api_service.dart';

enum BotConnectionState { disconnected, connecting, connected, error }

/// Controls the robot through the backend. The backend holds the SuperLive
/// account, joins the live and applies the moderation rules; this provider only
/// sends commands and mirrors the status it reports.
class BotProvider extends ChangeNotifier {
  BotProvider({PortalApiService? api, this.pollInterval = const Duration(seconds: 3)})
      : _api = api ?? PortalApiService();

  final PortalApiService _api;

  /// How often the status is refreshed while a live session is running.
  final Duration pollInterval;

  /// Robot calls can take a while (login, joining the live, final message).
  static const Duration _robotTimeout = Duration(seconds: 60);

  RobotStatus _status = const RobotStatus();
  BotConnectionState _connectionState = BotConnectionState.disconnected;
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  Timer? _pollTimer;
  bool _disposed = false;

  // ── getters ────────────────────────────────────────────────────────────
  BotConnectionState get connectionState => _connectionState;
  bool get isConnected => _status.connected;
  RobotInfo? get botProfile => _status.robot;
  RobotSession get session => _status.session;
  bool get isRunning => _status.session.running;
  bool get isBusy => _busy;
  bool get isLoaded => _loaded;
  String? get error => _error;

  /// Moderation actions executed over the account's whole history.
  int get totalActionsOk => _status.totalActionsOk;
  int get totalActionsFailed => _status.totalActionsFailed;

  List<ChatMessage> get chatMessages => _status.session.recentChat;
  List<ModerationAction> get recentActions => _status.session.recentActions;

  // ── commands ───────────────────────────────────────────────────────────

  /// Reload the robot/session status from the backend.
  Future<void> refresh() async {
    final result = await _api.get('/robot/status');
    if (_disposed) return;
    if (result['success'] == true && result['data'] is Map) {
      _apply(result['data'] as Map);
      _loaded = true;
      if (_connectionState != BotConnectionState.error) _error = null;
    } else if (!_loaded) {
      _loaded = true;
      _connectionState = BotConnectionState.disconnected;
      _error = PortalApiService.errorMessage(result, 'Erro ao carregar o status do robô');
    }
    notifyListeners();
  }

  /// Connect the robot's SuperLive account with e-mail and password.
  Future<bool> connectRobot(String email, String password) =>
      _connect({'email': email, 'password': password});

  /// Connect the robot with an existing SuperLive session token.
  Future<bool> connectRobotWithToken(String token) => _connect({'token': token});

  /// Step 1 of phone login: ask SuperLive to text a code to [phoneNumber] (E.164,
  /// e.g. `+5511999999999`). Returns how many seconds until a resend is allowed, or
  /// null on failure (see [error]).
  Future<int?> sendPhoneCode(String phoneNumber, {bool resend = false}) async {
    _connectionState = BotConnectionState.connecting;
    _error = null;
    notifyListeners();

    final result = await _api.post(
      '/robot/connect/phone/send_code',
      {'phone_number': phoneNumber, 'resend': resend},
      timeout: _robotTimeout,
    );
    if (_disposed) return null;
    if (result['success'] == true && result['data'] is Map) {
      final retry = (result['data'] as Map)['retry_timeout_seconds'];
      _connectionState = BotConnectionState.disconnected; // not connected yet, just the code was sent
      notifyListeners();
      return retry is num ? retry.toInt() : 60;
    }
    _error = PortalApiService.errorMessage(result, 'Não foi possível enviar o código por SMS.');
    _connectionState = BotConnectionState.error;
    notifyListeners();
    return null;
  }

  /// Step 2 of phone login: confirm the SMS code sent to [phoneNumber].
  Future<bool> connectRobotWithPhoneCode(String phoneNumber, String code) async {
    _connectionState = BotConnectionState.connecting;
    _error = null;
    notifyListeners();

    final result = await _api.post(
      '/robot/connect/phone/verify',
      {'phone_number': phoneNumber, 'code': code},
      timeout: _robotTimeout,
    );
    if (_disposed) return false;
    if (result['success'] == true && result['data'] is Map) {
      _apply(result['data'] as Map);
      _loaded = true;
      notifyListeners();
      return true;
    }
    _error = PortalApiService.errorMessage(result, 'Código inválido ou expirado.');
    _connectionState = BotConnectionState.error;
    notifyListeners();
    return false;
  }

  Future<bool> _connect(Map<String, dynamic> body) async {
    _connectionState = BotConnectionState.connecting;
    _error = null;
    notifyListeners();

    final result = await _api.post('/robot/connect', body, timeout: _robotTimeout);
    if (_disposed) return false;
    if (result['success'] == true && result['data'] is Map) {
      _apply(result['data'] as Map);
      _loaded = true;
      notifyListeners();
      return true;
    }
    _error = PortalApiService.errorMessage(
        result, 'Falha ao conectar o robô. Verifique as credenciais.');
    _connectionState = BotConnectionState.error;
    notifyListeners();
    return false;
  }

  Future<void> disconnectRobot() async {
    _busy = true;
    notifyListeners();
    final result =
        await _api.post('/robot/disconnect', {}, timeout: _robotTimeout);
    if (_disposed) return;
    _busy = false;
    if (result['success'] == true && result['data'] is Map) {
      _apply(result['data'] as Map);
    } else {
      _error = PortalApiService.errorMessage(result, 'Erro ao desconectar o robô');
    }
    notifyListeners();
  }

  /// Join [livestreamId] and start moderating it.
  Future<bool> startSession(String livestreamId) async {
    _busy = true;
    _error = null;
    notifyListeners();
    final result = await _api.post(
      '/robot/start',
      {'livestream_id': livestreamId},
      timeout: _robotTimeout,
    );
    if (_disposed) return false;
    _busy = false;
    final ok = result['success'] == true && result['data'] is Map;
    if (ok) {
      _apply(result['data'] as Map);
    } else {
      _error = PortalApiService.errorMessage(result, 'Não foi possível iniciar o robô');
    }
    notifyListeners();
    return ok;
  }

  /// Stop moderating this live.
  Future<bool> stopSession() async {
    _busy = true;
    _error = null;
    notifyListeners();
    final result = await _api.post('/robot/stop', {}, timeout: _robotTimeout);
    if (_disposed) return false;
    _busy = false;
    final ok = result['success'] == true && result['data'] is Map;
    if (ok) {
      _apply(result['data'] as Map);
    } else {
      _error = PortalApiService.errorMessage(result, 'Não foi possível parar o robô');
    }
    notifyListeners();
    return ok;
  }

  /// Resolve the public "ID: ..." shown on a creator's SuperLive profile ([sharedId])
  /// to her current livestream_id, if she is live right now. Not being live is a
  /// normal result (`live: false`), not a failure; null means the lookup itself
  /// failed — see [error].
  Future<StreamerLookup?> lookupStreamer(String sharedId) async {
    _error = null;
    notifyListeners();
    final result = await _api.post(
      '/robot/lookup_streamer',
      {'shared_id': sharedId},
      timeout: _robotTimeout,
    );
    if (_disposed) return null;
    if (result['success'] == true && result['data'] is Map) {
      return StreamerLookup.fromJson((result['data'] as Map).cast<String, dynamic>());
    }
    _error = PortalApiService.errorMessage(result, 'Não foi possível buscar essa conta.');
    notifyListeners();
    return null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Forget everything (called when the logged user changes).
  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _status = const RobotStatus();
    _connectionState = BotConnectionState.disconnected;
    _busy = false;
    _loaded = false;
    _error = null;
    notifyListeners();
  }

  // ── internals ──────────────────────────────────────────────────────────
  void _apply(Map raw) {
    _status = RobotStatus.fromJson(raw.cast<String, dynamic>());
    _connectionState = _status.connected
        ? BotConnectionState.connected
        : BotConnectionState.disconnected;
    _syncPolling();
  }

  /// Poll only while a session is running; it is cheap and keeps the live feed fresh.
  void _syncPolling() {
    if (isRunning) {
      _pollTimer ??= Timer.periodic(pollInterval, (_) => refresh());
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}
