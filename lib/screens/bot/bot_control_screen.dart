import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../providers/bot_provider.dart';
import '../../widgets/common/fox_icon.dart';
import '../../widgets/common/gradient_button.dart';

String _time(DateTime? t) =>
    t == null ? '--:--:--' : DateFormat('HH:mm:ss').format(t.toLocal());

class BotControlScreen extends StatefulWidget {
  const BotControlScreen({super.key});

  @override
  State<BotControlScreen> createState() => _BotControlScreenState();
}

class _BotControlScreenState extends State<BotControlScreen> {
  final _streamIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final bot = context.read<BotProvider>();
    final user = context.read<AuthProvider>().user;
    final msg = context.read<AutoMessageProvider>();
    await bot.refresh();
    if (!mounted) return;
    if (user != null) msg.load(user.id); // settings tell whether an end message is on
    // Prefer the live the robot is moderating right now; if it's idle (e.g. the
    // backend restarted), fall back to the last one it moderated so resuming
    // takes one click instead of hunting for the ID again.
    final liveId = bot.session.livestreamId ?? bot.botProfile?.lastLivestreamId;
    if (liveId != null && _streamIdController.text.isEmpty) {
      _streamIdController.text = liveId;
    }
  }

  @override
  void dispose() {
    _streamIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bot = context.watch<BotProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RobotConnectionCard(bot: bot),
          if (bot.isConnected) ...[
            const SizedBox(height: 24),
            _LiveControlCard(bot: bot, streamIdController: _streamIdController),
            const SizedBox(height: 24),
            _LiveFeedCard(bot: bot),
            const SizedBox(height: 24),
            _ActionsCard(bot: bot),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection
// ─────────────────────────────────────────────────────────────────────────────
class _RobotConnectionCard extends StatefulWidget {
  final BotProvider bot;
  const _RobotConnectionCard({required this.bot});

  @override
  State<_RobotConnectionCard> createState() => _RobotConnectionCardState();
}

enum _LoginMode { password, phone, token }

class _RobotConnectionCardState extends State<_RobotConnectionCard> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tokenController = TextEditingController();
  final _phoneController = TextEditingController(text: '+55');
  final _codeController = TextEditingController();

  _LoginMode _mode = _LoginMode.password;
  bool _obscurePassword = true;
  String? _localError;

  // Phone login is two steps: send the SMS code, then confirm it.
  bool _codeSent = false;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _restoreLastLogin();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _tokenController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  /// Starts the form on whichever mode/identifier worked last time, so
  /// reconnecting doesn't mean reselecting "Celular" and retyping the number
  /// (or the e-mail) every single time. Never remembers a password or token.
  Future<void> _restoreLastLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final mode = prefs.getString(AppConstants.keyLastRobotLoginMode);
    final email = prefs.getString(AppConstants.keyLastRobotEmail);
    final phone = prefs.getString(AppConstants.keyLastRobotPhone);
    setState(() {
      if (mode == 'phone') {
        _mode = _LoginMode.phone;
      } else if (mode == 'password') {
        _mode = _LoginMode.password;
      }
      if (email != null && email.isNotEmpty) _emailController.text = email;
      if (phone != null && phone.isNotEmpty) _phoneController.text = phone;
    });
  }

  Future<void> _rememberLogin({String? mode, String? email, String? phone}) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode != null) await prefs.setString(AppConstants.keyLastRobotLoginMode, mode);
    if (email != null) await prefs.setString(AppConstants.keyLastRobotEmail, email);
    if (phone != null) await prefs.setString(AppConstants.keyLastRobotPhone, phone);
  }

  void _setMode(_LoginMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _localError = null;
      _codeSent = false;
      _resendIn = 0;
    });
    _resendTimer?.cancel();
  }

  Future<void> _connect() async {
    final bot = context.read<BotProvider>();
    setState(() => _localError = null);

    final bool ok;
    if (_mode == _LoginMode.token) {
      final token = _tokenController.text.trim();
      if (token.isEmpty) {
        setState(() => _localError = 'Cole o token da sessão do robô.');
        return;
      }
      ok = await bot.connectRobotWithToken(token);
    } else {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (email.isEmpty || password.isEmpty) {
        setState(() => _localError = 'Informe o e-mail e a senha do robô.');
        return;
      }
      ok = await bot.connectRobot(email, password);
      if (ok) await _rememberLogin(mode: 'password', email: email);
    }
    if (ok) {
      // Don't keep secrets around once the backend has them.
      _passwordController.clear();
      _tokenController.clear();
    }
  }

  Future<void> _sendPhoneCode({bool resend = false}) async {
    final bot = context.read<BotProvider>();
    final phone = _phoneController.text.trim();
    setState(() => _localError = null);
    if (phone.isEmpty) {
      setState(() =>
          _localError = 'Informe o telefone com o código do país, ex: +5511999999999.');
      return;
    }

    final retrySeconds = await bot.sendPhoneCode(phone, resend: resend);
    if (!mounted || retrySeconds == null) return; // bot.error already carries the reason
    setState(() => _codeSent = true);
    _startResendCountdown(retrySeconds);
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _verifyPhoneCode() async {
    final bot = context.read<BotProvider>();
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    setState(() => _localError = null);
    if (code.isEmpty) {
      setState(() => _localError = 'Informe o código recebido por SMS.');
      return;
    }

    final ok = await bot.connectRobotWithPhoneCode(phone, code);
    if (!mounted) return;
    if (ok) {
      await _rememberLogin(mode: 'phone', phone: phone);
      _codeController.clear();
      _resendTimer?.cancel();
      setState(() => _codeSent = false);
    }
  }

  void _changePhoneNumber() {
    _resendTimer?.cancel();
    _codeController.clear();
    setState(() {
      _codeSent = false;
      _resendIn = 0;
      _localError = null;
    });
  }

  Future<void> _disconnect() async {
    final bot = context.read<BotProvider>();
    if (bot.isRunning) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Desconectar o robô?',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
          content: const Text(
            'A moderação desta live será interrompida.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Desconectar',
                    style: TextStyle(color: AppTheme.error))),
          ],
        ),
      );
      if (confirm != true) return;
    }
    await bot.disconnectRobot();
  }

  @override
  Widget build(BuildContext context) {
    final bot = widget.bot;
    final isConnected = bot.isConnected;
    final isConnecting = bot.connectionState == BotConnectionState.connecting;
    final profile = bot.botProfile;
    final error = _localError ?? (isConnected ? null : bot.error);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected ? AppTheme.success : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                // The icon stays underneath; the photo only covers it once it loads,
                // so a broken or missing avatar URL still looks right.
                foregroundImage: isConnected && profile?.avatar != null
                    ? NetworkImage(profile!.avatar!)
                    : null,
                onForegroundImageError:
                    isConnected && profile?.avatar != null ? (_, __) {} : null,
                child: const FoxIcon(size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected
                          ? profile?.nickname ?? "Atila's Client"
                          : 'Conta do robô no SuperLive',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConnected
                          ? switch (profile?.authMode) {
                              'token' => 'Conectado com token de sessão',
                              'phone' => 'Conectado com celular',
                              _ => 'Conectado com e-mail e senha',
                            }
                          : 'Configure a conta do robô',
                      style: TextStyle(
                        color:
                            isConnected ? AppTheme.success : AppTheme.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isConnected) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ModeChip(
                  label: 'E-mail e senha',
                  selected: _mode == _LoginMode.password,
                  onTap: () => _setMode(_LoginMode.password),
                ),
                _ModeChip(
                  label: 'Celular',
                  selected: _mode == _LoginMode.phone,
                  onTap: () => _setMode(_LoginMode.phone),
                ),
                _ModeChip(
                  label: 'Colar token',
                  selected: _mode == _LoginMode.token,
                  onTap: () => _setMode(_LoginMode.token),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_mode == _LoginMode.password) ...[
              const Text(
                'Credenciais da conta do robô no SuperLive. A senha é usada só '
                'para entrar e não é guardada.',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail da conta do robô',
                  prefixIcon: Icon(Icons.email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                onSubmitted: (_) => _connect(),
                decoration: InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
            ] else if (_mode == _LoginMode.phone) ...[
              Text(
                _codeSent
                    ? 'Digite o código recebido por SMS em ${_phoneController.text.trim()}.'
                    : 'Número da conta do robô no SuperLive, com o código do país '
                        '(ex: +5511999999999). Se o SuperLive recusar por verificação '
                        'anti-robô, use a opção "Colar token".',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                enabled: !_codeSent,
                keyboardType: TextInputType.phone,
                onSubmitted: (_) => _codeSent ? null : _sendPhoneCode(),
                decoration: const InputDecoration(
                  labelText: 'Telefone (com código do país)',
                  prefixIcon: Icon(Icons.smartphone_rounded),
                  hintText: '+5511999999999',
                ),
              ),
              if (_codeSent) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _verifyPhoneCode(),
                  decoration: const InputDecoration(
                    labelText: 'Código recebido por SMS',
                    prefixIcon: Icon(Icons.sms_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: _changePhoneNumber,
                      child: const Text('Usar outro número'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _resendIn > 0 || isConnecting
                          ? null
                          : () => _sendPhoneCode(resend: true),
                      child: Text(_resendIn > 0
                          ? 'Reenviar código (${_resendIn}s)'
                          : 'Reenviar código'),
                    ),
                  ],
                ),
              ],
            ] else ...[
              const Text(
                'Se o login por senha for bloqueado pela verificação anti-robô do '
                'SuperLive, entre com a conta do robô no app e cole aqui o token '
                'da sessão. Ele fica guardado só no seu servidor.',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tokenController,
                obscureText: true,
                onSubmitted: (_) => _connect(),
                decoration: const InputDecoration(
                  labelText: 'Token da sessão do robô',
                  prefixIcon: Icon(Icons.vpn_key_rounded),
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              _Banner(text: error, color: AppTheme.error),
            ],
            const SizedBox(height: 20),
            GradientButton(
              id: 'connect_robot_button',
              onPressed: isConnecting
                  ? null
                  : switch (_mode) {
                      _LoginMode.phone =>
                        _codeSent ? _verifyPhoneCode : _sendPhoneCode,
                      _ => _connect,
                    },
              isLoading: isConnecting,
              label: switch (_mode) {
                _LoginMode.phone =>
                  _codeSent ? 'Confirmar código' : 'Enviar código por SMS',
                _ => 'Conectar Robô',
              },
              icon: _mode == _LoginMode.phone && !_codeSent
                  ? Icons.sms_rounded
                  : Icons.link_rounded,
            ),
            if (isConnecting) ...[
              const SizedBox(height: 10),
              const _ConnectingStatus(),
            ],
          ] else ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: bot.isBusy ? null : _disconnect,
              icon: const Icon(Icons.link_off_rounded,
                  color: AppTheme.error, size: 18),
              label: const Text('Desconectar',
                  style: TextStyle(color: AppTheme.error)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rotates through short status phrases while the robot is connecting, so a
/// multi-step login (register device -> log in -> load profile) feels like
/// it's actually progressing instead of a single frozen spinner.
class _ConnectingStatus extends StatefulWidget {
  const _ConnectingStatus();

  @override
  State<_ConnectingStatus> createState() => _ConnectingStatusState();
}

class _ConnectingStatusState extends State<_ConnectingStatus> {
  static const _phrases = [
    'Conectando ao SuperLive...',
    'Validando as credenciais...',
    'Carregando o perfil do robô...',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _phrases.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Text(
        _phrases[_index],
        key: ValueKey(_index),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.15)
              : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: selected ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live control
// ─────────────────────────────────────────────────────────────────────────────
class _LiveControlCard extends StatefulWidget {
  final BotProvider bot;
  final TextEditingController streamIdController;

  const _LiveControlCard({required this.bot, required this.streamIdController});

  @override
  State<_LiveControlCard> createState() => _LiveControlCardState();
}

class _LiveControlCardState extends State<_LiveControlCard> {
  final _streamerIdController = TextEditingController();
  bool _looking = false;
  bool _togglingWatch = false;
  StreamerLookup? _lookupResult;

  @override
  void initState() {
    super.initState();
    final savedId = widget.bot.watch.sharedId;
    if (savedId != null) _streamerIdController.text = savedId;
  }

  @override
  void didUpdateWidget(covariant _LiveControlCard old) {
    super.didUpdateWidget(old);
    // While the robot is running it may auto-detect a new livestream_id on its
    // own (the streamer ended one live and started another) - keep the field
    // in sync so it always shows what the robot is actually moderating.
    final liveId = widget.bot.session.livestreamId;
    final isWaiting = widget.bot.session.state == 'waiting_for_live';
    if (isWaiting) {
      if (widget.streamIdController.text.isNotEmpty) {
        widget.streamIdController.clear();
      }
    } else if (widget.bot.session.running &&
        liveId != null &&
        liveId.isNotEmpty &&
        liveId != widget.streamIdController.text) {
      widget.streamIdController.text = liveId;
    }
  }

  @override
  void dispose() {
    _streamerIdController.dispose();
    super.dispose();
  }

  void _snack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  /// Resolves the streamer's public SuperLive id to her current livestream_id (if
  /// she's live) and, when found, fills [widget.streamIdController] with it.
  Future<void> _lookupStreamer() async {
    final sharedId = _streamerIdController.text.trim();
    if (sharedId.isEmpty) {
      _snack('Informe o ID público da streamer', AppTheme.warning);
      return;
    }
    setState(() {
      _looking = true;
      _lookupResult = null;
    });
    final result = await context.read<BotProvider>().lookupStreamer(sharedId);
    if (!mounted) return;
    setState(() {
      _looking = false;
      _lookupResult = result;
    });
    if (result == null) {
      _snack(context.read<BotProvider>().error ?? 'Não foi possível buscar essa conta.',
          AppTheme.error);
      return;
    }
    if (result.live && result.livestreamId != null) {
      widget.streamIdController.text = result.livestreamId!;
      _snack('${result.nickname} está ao vivo agora! ID da live preenchido.',
          AppTheme.success);
    }
  }

  /// Favourites (or un-favourites) a streamer so the robot auto-joins her live
  /// by itself. [sharedId] defaults to whatever is currently in the search
  /// field, so the "ativo" switch on the saved favourite can also call this.
  Future<void> _toggleWatch(bool active, {String? sharedId}) async {
    final id = sharedId ?? _streamerIdController.text.trim();
    if (id.isEmpty) {
      _snack('Informe o ID público da streamer', AppTheme.warning);
      return;
    }
    setState(() => _togglingWatch = true);
    final ok = await context.read<BotProvider>().setWatch(id, active);
    if (!mounted) return;
    setState(() => _togglingWatch = false);
    if (ok) {
      _snack(
        active
            ? 'Pronto! Moderação automática ativada. O robô entrará e moderará a live assim que ela começar.'
            : 'A streamer favorita foi desativada.',
        AppTheme.success,
      );
    } else {
      _snack(context.read<BotProvider>().error ?? 'Não foi possível salvar',
          AppTheme.error);
    }
  }

  Future<void> _start() async {
    final liveId = widget.streamIdController.text.trim();
    if (liveId.isEmpty) {
      _snack('Informe o ID da live primeiro', AppTheme.warning);
      return;
    }
    final ok = await context.read<BotProvider>().startSession(liveId);
    if (!mounted) return;
    if (ok) {
      _snack('Robô entrou na live e está moderando', AppTheme.success);
    } else {
      _snack(context.read<BotProvider>().error ?? 'Não foi possível iniciar',
          AppTheme.error);
    }
  }

  Future<void> _stop() async {
    await context.read<BotProvider>().stopSession();
  }

  @override
  Widget build(BuildContext context) {
    final bot = widget.bot;
    final session = bot.session;
    final running = session.running;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.live_tv_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Controle da Live',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (running) _WsPill(state: session.state, wsState: session.wsState),
            ],
          ),
          const SizedBox(height: 16),
          if (session.state == 'waiting_for_live') ...[
            const _Banner(
              icon: Icons.hourglass_top_rounded,
              color: AppTheme.warning,
              text: 'A live anterior terminou. O robô está de olho no perfil da streamer e '
                  'volta a moderar automaticamente assim que ela abrir uma nova live.',
            ),
            const SizedBox(height: 16),
          ],
          const _Banner(
            icon: Icons.shield_rounded,
            color: AppTheme.accent,
            text: 'Para silenciar e banir, o robô precisa ser moderador da live. '
                'Peça à streamer para adicioná-lo como moderador antes de começar.',
          ),
          if (bot.watch.hasTarget) ...[
            const SizedBox(height: 16),
            _FavoriteStreamerCard(
              watch: bot.watch,
              running: running,
              sessionState: session.state,
              isBusy: _togglingWatch || bot.isBusy,
              onToggle: (active) =>
                  _toggleWatch(active, sharedId: bot.watch.sharedId),
            ),
          ],
          const SizedBox(height: 16),

          // Find the live by the streamer's public profile id (easier to get than the
          // livestream_id itself, which changes every broadcast).
          const Text(
            'Não sabe o ID da live? Busque pelo ID público do perfil dela.',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _streamerIdController,
                  enabled: !running && !bot.isBusy && !_looking,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _lookupStreamer(),
                  decoration: const InputDecoration(
                    labelText: 'ID público da streamer',
                    prefixIcon: Icon(Icons.person_search_rounded),
                    hintText: 'ex: 69622983',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: (running || bot.isBusy || _looking) ? null : _lookupStreamer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.bgSurface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _looking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        )
                      : const Icon(Icons.search_rounded, color: AppTheme.primary),
                ),
              ),
            ],
          ),
          if (_lookupResult != null) ...[
            const SizedBox(height: 10),
            _StreamerLookupResult(result: _lookupResult!),
            if (_streamerIdController.text.trim() != bot.watch.sharedId ||
                !bot.watch.active) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _togglingWatch ? null : () => _toggleWatch(true),
                  icon: const Icon(Icons.favorite_rounded, size: 16),
                  label: const Text('Favoritar: entrar e moderar automaticamente ao vivo'),
                ),
              ),
            ],
          ],

          const SizedBox(height: 20),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 20),

          if (bot.watch.hasTarget && bot.watch.active && !running) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.radar_rounded, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sentinela Ativa: Moderação Pré-ativada',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Você não precisa apertar nada. O robô entrará na live e aplicará as regras de silenciar e banir automaticamente assim que ela iniciar.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          TextField(
            controller: widget.streamIdController,
            enabled: !running && !bot.isBusy && session.state != 'waiting_for_live',
            decoration: InputDecoration(
              labelText: session.state == 'waiting_for_live'
                  ? 'Aguardando próxima live...'
                  : 'ID da Live (livestream_id)',
              prefixIcon: Icon(session.state == 'waiting_for_live'
                  ? Icons.hourglass_top_rounded
                  : Icons.tag_rounded),
              helperText: session.state == 'waiting_for_live'
                  ? 'A live anterior encerrou. O ID será preenchido automaticamente assim que a streamer abrir uma nova transmissão.'
                  : 'Opcional se favoritada; necessário para início manual avulso',
              helperStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  id: 'start_robot_button',
                  onPressed: (running || bot.isBusy) ? null : _start,
                  isLoading: bot.isBusy && !running,
                  label: session.state == 'waiting_for_live'
                      ? 'Aguardando a próxima live...'
                      : running
                          ? 'Moderando a live...'
                          : (bot.watch.hasTarget &&
                                  bot.watch.active &&
                                  widget.streamIdController.text.trim().isEmpty)
                              ? 'Sentinela armada (aguardando live)'
                              : 'Iniciar moderação manual',
                  icon: session.state == 'waiting_for_live'
                      ? Icons.hourglass_top_rounded
                      : running
                          ? Icons.loop_rounded
                          : (bot.watch.hasTarget &&
                                  bot.watch.active &&
                                  widget.streamIdController.text.trim().isEmpty)
                              ? Icons.radar_rounded
                              : Icons.play_arrow_rounded,
                ),
              ),
              if (running) ...[
                const SizedBox(width: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: bot.isBusy ? null : _stop,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Parar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (bot.error != null) ...[
            const SizedBox(height: 12),
            _Banner(text: bot.error!, color: AppTheme.error),
          ],
          if (session.lastError != null && session.state != 'idle') ...[
            const SizedBox(height: 12),
            _Banner(text: session.lastError!, color: AppTheme.warning),
          ],
          if (!running &&
              session.state != 'idle' &&
              session.stopReason != null) ...[
            const SizedBox(height: 12),
            _Banner(
              icon: Icons.info_rounded,
              text: 'Sessão encerrada: ${session.stopReason}',
              color: AppTheme.textMuted,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              _MiniStat(
                icon: Icons.chat_rounded,
                label: 'Msgs vistas',
                value: '${session.chatSeen}',
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              _MiniStat(
                icon: Icons.send_rounded,
                label: 'Msgs enviadas',
                value: '${session.messagesSent}',
                color: AppTheme.accent,
              ),
              const SizedBox(width: 12),
              _MiniStat(
                icon: Icons.shield_rounded,
                label: 'Ações de mod.',
                value: '${session.actionsOk}',
                color: AppTheme.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreamerLookupResult extends StatelessWidget {
  final StreamerLookup result;
  const _StreamerLookupResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.live ? AppTheme.success : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
            foregroundImage:
                result.avatar != null ? NetworkImage(result.avatar!) : null,
            onForegroundImageError: result.avatar != null ? (_, __) {} : null,
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result.nickname,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              result.live ? 'ao vivo agora' : 'não está ao vivo',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// The streamer the robot remembers and auto-joins the moment she goes live,
/// with a switch to turn that off without losing who she is.
class _FavoriteStreamerCard extends StatelessWidget {
  final StreamerWatch watch;
  final bool running;
  final String sessionState;
  final bool isBusy;
  final ValueChanged<bool> onToggle;

  const _FavoriteStreamerCard({
    required this.watch,
    required this.running,
    required this.sessionState,
    required this.isBusy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final String statusDescription;
    final String badgeLabel;
    final Color badgeColor;
    final IconData badgeIcon;

    final isWaiting = sessionState == 'waiting_for_live';

    if (!watch.active) {
      badgeLabel = 'Desativada';
      statusDescription = 'A moderação automática está pausada para esta streamer.';
      badgeColor = AppTheme.textMuted;
      badgeIcon = Icons.pause_circle_outline_rounded;
    } else if (isWaiting) {
      badgeLabel = 'Aguardando live';
      statusDescription = 'A transmissão anterior encerrou. O robô continua vigilante para a próxima live.';
      badgeColor = AppTheme.warning;
      badgeIcon = Icons.hourglass_top_rounded;
    } else if (running) {
      badgeLabel = 'Moderando ao vivo';
      statusDescription = 'Conectado à transmissão agora. Aplicando regras de moderação em tempo real.';
      badgeColor = AppTheme.success;
      badgeIcon = Icons.shield_rounded;
    } else {
      badgeLabel = 'Sentinela armada';
      statusDescription = 'Moderação pré-ativada. O robô monitora o perfil e começará a moderar sozinho assim que ela iniciar a live.';
      badgeColor = AppTheme.primary;
      badgeIcon = Icons.radar_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: watch.active
              ? (isWaiting
                  ? AppTheme.warning.withValues(alpha: 0.45)
                  : running
                      ? AppTheme.success.withValues(alpha: 0.45)
                      : AppTheme.primary.withValues(alpha: 0.35))
              : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                foregroundImage:
                    watch.avatar != null ? NetworkImage(watch.avatar!) : null,
                onForegroundImageError: watch.avatar != null ? (_, __) {} : null,
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            watch.nickname ?? 'Streamer favorita',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(badgeIcon, size: 12, color: badgeColor),
                              const SizedBox(width: 4),
                              Text(
                                badgeLabel,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID Público: ${watch.sharedId}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: watch.active,
                onChanged: isBusy ? null : onToggle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Icon(
                  watch.active ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                  size: 15,
                  color: watch.active ? AppTheme.success : AppTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusDescription,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WsPill extends StatelessWidget {
  final String state;
  final String wsState;
  const _WsPill({required this.state, required this.wsState});

  @override
  Widget build(BuildContext context) {
    final waiting = state == 'waiting_for_live';
    final connected = wsState == 'connected';
    final color = waiting
        ? AppTheme.warning
        : connected
            ? AppTheme.success
            : AppTheme.warning;
    final label = waiting
        ? 'Aguardando nova live'
        : connected
            ? 'Chat conectado'
            : 'Reconectando...';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live feed + actions
// ─────────────────────────────────────────────────────────────────────────────
class _LiveFeedCard extends StatelessWidget {
  final BotProvider bot;
  const _LiveFeedCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    final messages = bot.chatMessages.reversed.toList(); // newest first
    final running = bot.isRunning;

    return _SectionCard(
      icon: Icons.forum_rounded,
      title: 'Chat ao vivo',
      trailing: running ? 'ao vivo' : null,
      child: SizedBox(
        height: 300,
        child: messages.isEmpty
            ? Center(
                child: Text(
                  running
                      ? 'Aguardando mensagens do chat...'
                      : 'O chat aparecerá aqui quando o robô estiver em uma live.',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              )
            : ListView.separated(
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final moderated = msg.action != null;
                  final color = msg.action == 'kick'
                      ? AppTheme.error
                      : AppTheme.warning;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_time(msg.timestamp),
                          style: const TextStyle(
                              color: AppTheme.textDisabled, fontSize: 11)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${msg.username}: ',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            TextSpan(
                              text: msg.text,
                              style: TextStyle(
                                color: moderated ? color : AppTheme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ]),
                        ),
                      ),
                      if (moderated)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            msg.action == 'kick' ? 'banido' : 'silenciado',
                            style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  final BotProvider bot;
  const _ActionsCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    final actions = bot.recentActions.reversed.toList(); // newest first

    return _SectionCard(
      icon: Icons.gavel_rounded,
      title: 'Ações de moderação',
      trailing: '${bot.totalActionsOk} no total',
      child: actions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Nenhuma ação nesta sessão.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ),
            )
          : Column(
              children: [
                for (final a in actions.take(30)) _ActionRow(action: a),
              ],
            ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final ModerationAction action;
  const _ActionRow({required this.action});

  @override
  Widget build(BuildContext context) {
    final isKick = action.action == 'kick';
    final color = !action.ok
        ? AppTheme.error
        : (isKick ? AppTheme.error : AppTheme.warning);
    final verb = isKick ? 'Baniu' : 'Silenciou';
    final title = action.ok
        ? '$verb ${action.targetName}'
        : 'Falhou ao ${isKick ? 'banir' : 'silenciar'} ${action.targetName}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isKick ? Icons.block_rounded : Icons.volume_off_rounded,
              color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(
                  'palavra "${action.keyword}" · "${action.messageText}"',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12, height: 1.3),
                ),
                if (!action.ok && action.detail != null)
                  Text(action.detail!,
                      style: const TextStyle(
                          color: AppTheme.error, fontSize: 11, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_time(action.timestamp),
              style:
                  const TextStyle(color: AppTheme.textDisabled, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared bits
// ─────────────────────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null)
                Text(trailing!,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _Banner({
    required this.text,
    required this.color,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
