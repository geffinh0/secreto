import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../providers/bot_provider.dart';
import '../../widgets/common/fox_icon.dart';
import '../../widgets/ui/ui.dart';

String _time(DateTime? t) =>
    t == null ? '--:--:--' : DateFormat('HH:mm:ss').format(t.toLocal());

Color _toneColor(AppTone tone) => switch (tone) {
      AppTone.accent => AppColors.accent,
      AppTone.success => AppColors.success,
      AppTone.warning => AppColors.warning,
      AppTone.danger => AppColors.danger,
      AppTone.neutral => AppColors.muted,
    };

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
    if (user != null) {
      msg.load(user.id); // settings tell whether an end message is on
    }
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

    return AppPage(
      children: [
        Reveal(
          child: PageHeader(
            title: 'Robô',
            subtitle: bot.isConnected
                ? null
                : 'Conecte a conta do robô para começar a moderar.',
          ),
        ),
        if (!bot.isConnected)
          Reveal(index: 1, child: _ConnectionForm(bot: bot))
        else
          AppSplit(
            ratio: 0.55,
            primary: Reveal(
              index: 1,
              child: _LiveControl(
                bot: bot,
                streamIdController: _streamIdController,
              ),
            ),
            secondary: Reveal(index: 2, child: _LiveFeed(bot: bot)),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection
// ─────────────────────────────────────────────────────────────────────────────
enum _LoginMode { password, phone, emailCode }

class _ConnectionForm extends StatefulWidget {
  final BotProvider bot;
  const _ConnectionForm({required this.bot});

  @override
  State<_ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<_ConnectionForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
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
      } else if (mode == 'email_code') {
        _mode = _LoginMode.emailCode;
      } else if (mode == 'password') {
        _mode = _LoginMode.password;
      }
      if (email != null && email.isNotEmpty) _emailController.text = email;
      if (phone != null && phone.isNotEmpty) _phoneController.text = phone;
    });
  }

  Future<void> _rememberLogin(
      {String? mode, String? email, String? phone}) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode != null) {
      await prefs.setString(AppConstants.keyLastRobotLoginMode, mode);
    }
    if (email != null) {
      await prefs.setString(AppConstants.keyLastRobotEmail, email);
    }
    if (phone != null) {
      await prefs.setString(AppConstants.keyLastRobotPhone, phone);
    }
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

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _localError = 'Informe o e-mail e a senha do robô.');
      return;
    }
    final ok = await bot.connectRobot(email, password);
    if (ok) {
      await _rememberLogin(mode: 'password', email: email);
      // Don't keep secrets around once the backend has them.
      _passwordController.clear();
    }
  }

  Future<void> _sendPhoneCode({bool resend = false}) async {
    final bot = context.read<BotProvider>();
    final phone = _phoneController.text.trim();
    setState(() => _localError = null);
    if (phone.isEmpty) {
      setState(() => _localError =
          'Informe o telefone com o código do país, ex: +5511999999999.');
      return;
    }

    final retrySeconds = await bot.sendPhoneCode(phone, resend: resend);
    if (!mounted || retrySeconds == null) {
      return; // bot.error already carries the reason
    }
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

  /// For an account whose e-mail has no password set (created via phone or
  /// Google/Apple login, e-mail only linked after) - SuperLive mails a code
  /// instead. Unlike phone, SuperLive doesn't tell us a resend cooldown here,
  /// so there's no countdown: resend is just available right away.
  Future<void> _sendEmailCode({bool resend = false}) async {
    final bot = context.read<BotProvider>();
    final email = _emailController.text.trim();
    setState(() => _localError = null);
    if (email.isEmpty) {
      setState(() => _localError = 'Informe o e-mail da conta do robô.');
      return;
    }

    final ok = await bot.sendEmailCode(email, resend: resend);
    if (!mounted || !ok) return; // bot.error already carries the reason
    setState(() => _codeSent = true);
  }

  Future<void> _verifyEmailCode() async {
    final bot = context.read<BotProvider>();
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    setState(() => _localError = null);
    if (code.isEmpty) {
      setState(() => _localError = 'Informe o código recebido por e-mail.');
      return;
    }

    final ok = await bot.connectRobotWithEmailCode(email, code);
    if (!mounted) return;
    if (ok) {
      await _rememberLogin(mode: 'email_code', email: email);
      _codeController.clear();
      setState(() => _codeSent = false);
    }
  }

  void _changeEmailForCode() {
    _codeController.clear();
    setState(() {
      _codeSent = false;
      _localError = null;
    });
  }

  VoidCallback? _primaryAction(bool isConnecting) {
    if (isConnecting) return null;
    return switch (_mode) {
      _LoginMode.phone => _codeSent ? _verifyPhoneCode : _sendPhoneCode,
      _LoginMode.emailCode => _codeSent ? _verifyEmailCode : _sendEmailCode,
      _LoginMode.password => _connect,
    };
  }

  String get _primaryLabel => switch (_mode) {
        _LoginMode.phone =>
          _codeSent ? 'Confirmar código' : 'Enviar código por SMS',
        _LoginMode.emailCode =>
          _codeSent ? 'Confirmar código' : 'Enviar código por e-mail',
        _LoginMode.password => 'Conectar robô',
      };

  IconData get _primaryIcon => switch (_mode) {
        _LoginMode.phone when !_codeSent => Icons.sms_rounded,
        _LoginMode.emailCode when !_codeSent => Icons.mail_lock_rounded,
        _ => Icons.link_rounded,
      };

  String get _intro => switch (_mode) {
        _LoginMode.password =>
          'Use o e-mail e a senha da conta do robô no SuperLive. A senha serve só '
              'para entrar e não fica guardada.',
        _LoginMode.phone => _codeSent
            ? 'Digite o código recebido por SMS em ${_phoneController.text.trim()}.'
            : 'Informe o número da conta do robô no SuperLive, com o código do país.',
        _LoginMode.emailCode => _codeSent
            ? 'Digite o código recebido por e-mail em ${_emailController.text.trim()}.'
            : 'Para contas sem senha no e-mail, criadas por celular ou login social. '
                'O SuperLive envia um código por e-mail.',
      };

  Widget _fields(bool isConnecting) {
    switch (_mode) {
      case _LoginMode.password:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _emailController,
              label: 'E-mail da conta do robô',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _passwordController,
              label: 'Senha',
              obscureText: _obscurePassword,
              onSubmitted: (_) => _connect(),
              suffix: IconButton(
                tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                icon: Icon(_obscurePassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ],
        );
      case _LoginMode.phone:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _phoneController,
              label: 'Telefone com código do país',
              hint: '+5511999999999',
              enabled: !_codeSent,
              keyboardType: TextInputType.phone,
              onSubmitted: (_) => _codeSent ? null : _sendPhoneCode(),
            ),
            if (_codeSent) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _codeController,
                label: 'Código recebido por SMS',
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _verifyPhoneCode(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AppButton.text(
                    label: 'Usar outro número',
                    onPressed: _changePhoneNumber,
                  ),
                  AppButton.text(
                    label: _resendIn > 0
                        ? 'Reenviar código (${_resendIn}s)'
                        : 'Reenviar código',
                    onPressed: _resendIn > 0 || isConnecting
                        ? null
                        : () => _sendPhoneCode(resend: true),
                  ),
                ],
              ),
            ],
          ],
        );
      case _LoginMode.emailCode:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _emailController,
              label: 'E-mail da conta do robô',
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _codeSent ? null : _sendEmailCode(),
            ),
            if (_codeSent) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _codeController,
                label: 'Código recebido por e-mail',
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _verifyEmailCode(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AppButton.text(
                    label: 'Usar outro e-mail',
                    onPressed: _changeEmailForCode,
                  ),
                  AppButton.text(
                    label: 'Reenviar código',
                    onPressed: isConnecting
                        ? null
                        : () => _sendEmailCode(resend: true),
                  ),
                ],
              ),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bot = widget.bot;
    final isConnecting = bot.connectionState == BotConnectionState.connecting;
    final error = _localError ?? bot.error;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: AppSurface(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _RobotAvatar(radius: 24),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text('Conta do robô no SuperLive',
                      style: AppType.heading),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppChip(
                  label: 'E-mail e senha',
                  selected: _mode == _LoginMode.password,
                  onTap: () => _setMode(_LoginMode.password),
                ),
                AppChip(
                  label: 'Celular',
                  selected: _mode == _LoginMode.phone,
                  onTap: () => _setMode(_LoginMode.phone),
                ),
                AppChip(
                  label: 'Código por e-mail',
                  selected: _mode == _LoginMode.emailCode,
                  onTap: () => _setMode(_LoginMode.emailCode),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(_intro, style: AppType.meta),
            const SizedBox(height: AppSpacing.md),
            _fields(isConnecting),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Notice(text: error, tone: AppTone.danger),
            ],
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              identifier: 'connect_robot_button',
              child: AppButton(
                label: _primaryLabel,
                icon: _primaryIcon,
                loading: isConnecting,
                expand: true,
                onPressed: _primaryAction(isConnecting),
              ),
            ),
            if (isConnecting) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Conectando ao SuperLive. Isso pode levar alguns segundos.',
                  style: AppType.meta),
            ],
          ],
        ),
      ),
    );
  }
}

class _RobotAvatar extends StatelessWidget {
  final double radius;
  final String? imageUrl;
  const _RobotAvatar({required this.radius, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    // The icon stays underneath; the photo only covers it once it loads, so a
    // broken or missing avatar URL still looks right.
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.raised,
      foregroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
      onForegroundImageError: imageUrl != null ? (_, __) {} : null,
      child: FoxIcon(size: radius + 4),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final AppTone tone;
  final IconData icon;

  const _Notice({
    required this.text,
    this.tone = AppTone.neutral,
    this.icon = Icons.info_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      raised: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tone == AppTone.danger ? Icons.error_outline_rounded : icon,
            size: 20,
            color: _toneColor(tone),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: AppType.body)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live control (state, primary action, configuration)
// ─────────────────────────────────────────────────────────────────────────────
class _LiveControl extends StatefulWidget {
  final BotProvider bot;
  final TextEditingController streamIdController;

  const _LiveControl({required this.bot, required this.streamIdController});

  @override
  State<_LiveControl> createState() => _LiveControlState();
}

class _LiveControlState extends State<_LiveControl> {
  final _streamerIdController = TextEditingController();
  bool _looking = false;
  bool _togglingWatch = false;
  bool _pinging = false;
  StreamerLookup? _lookupResult;

  @override
  void initState() {
    super.initState();
    final savedId = widget.bot.watch.sharedId;
    if (savedId != null) _streamerIdController.text = savedId;
  }

  @override
  void didUpdateWidget(covariant _LiveControl old) {
    super.didUpdateWidget(old);
    // While the robot is running it may auto-detect a new live ID on its own
    // (the streamer ended one live and started another) - keep the field in
    // sync so it always shows what the robot is actually moderating.
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

  /// Tells the server she is live so the robot joins now, not at the next
  /// scheduled check (which can be a few minutes when many creators are watched).
  Future<void> _pingWatch() async {
    setState(() => _pinging = true);
    final error = await context.read<BotProvider>().pingWatch();
    if (!mounted) return;
    setState(() => _pinging = false);
    showAppSnack(
      context,
      error ?? 'Aviso enviado. O robô entra na sua live em instantes.',
      error: error != null,
    );
  }

  /// Resolves the streamer's public SuperLive id to her current live ID (if
  /// she's live) and, when found, fills [widget.streamIdController] with it.
  Future<void> _lookupStreamer() async {
    final sharedId = _streamerIdController.text.trim();
    if (sharedId.isEmpty) {
      showAppSnack(context, 'Informe o ID público do streamer.', error: true);
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
      showAppSnack(
        context,
        context.read<BotProvider>().error ??
            'Não foi possível buscar essa conta. Confira o ID e tente de novo.',
        error: true,
      );
      return;
    }
    if (result.live && result.livestreamId != null) {
      widget.streamIdController.text = result.livestreamId!;
      showAppSnack(context,
          '${result.nickname} está ao vivo agora. ID da live preenchido.');
    }
  }

  /// Favourites (or un-favourites) a streamer so the robot auto-joins her live
  /// by itself. [sharedId] defaults to whatever is currently in the search
  /// field, so the switch on the saved favourite can also call this.
  Future<void> _toggleWatch(bool active, {String? sharedId}) async {
    final id = sharedId ?? _streamerIdController.text.trim();
    if (id.isEmpty) {
      showAppSnack(context, 'Informe o ID público do streamer.', error: true);
      return;
    }
    setState(() => _togglingWatch = true);
    final ok = await context.read<BotProvider>().setWatch(id, active);
    if (!mounted) return;
    setState(() => _togglingWatch = false);
    if (ok) {
      showAppSnack(
        context,
        active
            ? 'Moderação automática ativada. O robô entra e modera a live assim que ela começar.'
            : 'Streamer favorito desativado.',
      );
    } else {
      showAppSnack(
        context,
        context.read<BotProvider>().error ??
            'Não foi possível salvar. Tente de novo.',
        error: true,
      );
    }
  }

  Future<void> _start() async {
    final liveId = widget.streamIdController.text.trim();
    if (liveId.isEmpty) {
      showAppSnack(context, 'Informe o ID da live antes de iniciar.',
          error: true);
      return;
    }
    final ok = await context.read<BotProvider>().startSession(liveId);
    if (!mounted) return;
    if (ok) {
      showAppSnack(context, 'Robô entrou na live e está moderando.');
    } else {
      showAppSnack(
        context,
        context.read<BotProvider>().error ??
            'Não foi possível iniciar. Tente de novo.',
        error: true,
      );
    }
  }

  Future<void> _stop() async {
    await context.read<BotProvider>().stopSession();
  }

  Future<void> _disconnect() async {
    final bot = context.read<BotProvider>();
    if (bot.isRunning) {
      final confirm = await showAppConfirm(
        context,
        title: 'Desconectar robô?',
        message: 'A moderação desta live será interrompida.',
        confirmLabel: 'Desconectar robô',
        destructive: true,
      );
      if (!confirm) return;
    }
    await bot.disconnectRobot();
  }

  @override
  Widget build(BuildContext context) {
    final bot = widget.bot;
    final session = bot.session;
    final running = session.running;
    final waiting = session.state == 'waiting_for_live';
    final locked = running || bot.isBusy;
    final armedWithoutId = bot.watch.hasTarget &&
        bot.watch.active &&
        widget.streamIdController.text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StateHero(
          bot: bot,
          action: running
              ? Semantics(
                  identifier: 'stop_robot_button',
                  child: AppButton.secondary(
                    label: 'Parar moderação',
                    icon: Icons.stop_rounded,
                    expand: true,
                    onPressed: bot.isBusy ? null : _stop,
                  ),
                )
              : Semantics(
                  identifier: 'start_robot_button',
                  child: AppButton(
                    label: 'Iniciar moderação',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    loading: bot.isBusy,
                    onPressed: bot.isBusy ? null : _start,
                  ),
                ),
          hint: armedWithoutId && !running && !waiting
              ? 'A moderação automática está armada. Para iniciar agora, informe o ID da live.'
              : null,
        ),
        if (bot.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Notice(text: bot.error!, tone: AppTone.danger),
        ],
        if (session.lastError != null && session.state != 'idle') ...[
          const SizedBox(height: AppSpacing.md),
          _Notice(
              text: session.lastError!,
              tone: AppTone.warning,
              icon: Icons.warning_amber_rounded),
        ],
        if (!running &&
            session.state != 'idle' &&
            session.stopReason != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Notice(text: 'Sessão encerrada: ${session.stopReason}'),
        ],
        const SizedBox(height: AppSpacing.xl),
        AppSection(
          title: 'Live',
          subtitle:
              'Para silenciar e banir, o robô precisa ser moderador da live. Peça ao streamer para adicioná-lo antes de começar.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (waiting) ...[
                const _Notice(
                  icon: Icons.hourglass_top_rounded,
                  tone: AppTone.warning,
                  text:
                      'A live anterior terminou. O robô acompanha o perfil do streamer e volta a moderar quando ele abrir uma nova live.',
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (bot.watch.hasTarget && bot.watch.active && !running) ...[
                _SentinelRow(pinging: _pinging, onPing: _pingWatch),
                const SizedBox(height: AppSpacing.md),
              ],
              AppTextField(
                controller: widget.streamIdController,
                enabled: !locked && !waiting,
                label: waiting ? 'Aguardando próxima live' : 'ID da live',
                helper: waiting
                    ? 'O ID aparece aqui quando o streamer abrir uma nova transmissão.'
                    : 'Opcional se o streamer estiver favoritado. Necessário para iniciar manualmente.',
              ),
            ],
          ),
        ),
        AppSection(
          title: 'Streamer',
          subtitle: 'Não sabe o ID da live? Busque pelo ID público do perfil.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _streamerIdController,
                enabled: !locked && !_looking,
                label: 'ID público do streamer',
                hint: 'Exemplo: 69622983',
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _lookupStreamer(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton.secondary(
                  label: 'Buscar streamer',
                  icon: Icons.search_rounded,
                  loading: _looking,
                  onPressed: (locked || _looking) ? null : _lookupStreamer,
                ),
              ),
              if (_lookupResult != null) ...[
                const SizedBox(height: AppSpacing.md),
                _LookupResult(result: _lookupResult!),
                if (_streamerIdController.text.trim() != bot.watch.sharedId ||
                    !bot.watch.active) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton.text(
                      label: 'Favoritar e moderar automaticamente',
                      icon: Icons.favorite_rounded,
                      onPressed:
                          _togglingWatch ? null : () => _toggleWatch(true),
                    ),
                  ),
                ],
              ],
              if (bot.watch.hasTarget) ...[
                const SizedBox(height: AppSpacing.md),
                _FavoriteStreamer(
                  watch: bot.watch,
                  running: running,
                  sessionState: session.state,
                  isBusy: _togglingWatch || bot.isBusy,
                  watchWaitingSeconds: session.watchWaitingSeconds,
                  onToggle: (active) =>
                      _toggleWatch(active, sharedId: bot.watch.sharedId),
                ),
              ],
            ],
          ),
        ),
        AppSection(
          title: 'Conta do robô',
          last: true,
          child: _AccountRow(bot: bot, onDisconnect: _disconnect),
        ),
      ],
    );
  }
}

/// The robot's state is the loudest thing on the screen: display type, one
/// chip with icon + text, and the single primary action right under it.
class _StateHero extends StatelessWidget {
  final BotProvider bot;
  final Widget action;
  final String? hint;

  const _StateHero({required this.bot, required this.action, this.hint});

  @override
  Widget build(BuildContext context) {
    final session = bot.session;
    final String title;
    final String detail;
    final String chipLabel;
    final IconData chipIcon;
    final AppTone tone;

    if (session.running) {
      final chatUp = session.wsState == 'connected';
      title = 'Moderando';
      detail =
          'O robô está na live e aplica as regras de moderação em tempo real.';
      chipLabel = chatUp ? 'Chat conectado' : 'Reconectando';
      chipIcon =
          chatUp ? Icons.check_circle_outline_rounded : Icons.sync_rounded;
      tone = chatUp ? AppTone.success : AppTone.warning;
    } else if (session.state == 'waiting_for_live') {
      title = 'Aguardando live';
      detail =
          'A live anterior terminou. O robô volta a moderar quando o streamer abrir uma nova.';
      chipLabel = 'Aguardando nova live';
      chipIcon = Icons.hourglass_top_rounded;
      tone = AppTone.warning;
    } else if (bot.watch.hasTarget && bot.watch.active) {
      title = 'Em espera';
      detail = 'O robô entra sozinho assim que o streamer iniciar a live.';
      chipLabel = 'Sentinela armada';
      chipIcon = Icons.radar_rounded;
      tone = AppTone.accent;
    } else {
      title = 'Parado';
      detail = 'Informe o ID da live para iniciar a moderação.';
      chipLabel = 'Robô parado';
      chipIcon = Icons.pause_circle_outline_rounded;
      tone = AppTone.neutral;
    }

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AppChip(label: chipLabel, icon: chipIcon, tone: tone),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            header: true,
            child: Text(title,
                style: AppType.display,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(hint ?? detail, style: AppType.meta),
          const SizedBox(height: AppSpacing.lg),
          action,
        ],
      ),
    );
  }
}

class _SentinelRow extends StatelessWidget {
  final bool pinging;
  final VoidCallback onPing;
  const _SentinelRow({required this.pinging, required this.onPing});

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Moderação pré-ativada', style: AppType.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Você não precisa apertar nada. O robô entra na live e aplica as regras de silenciar e banir assim que ela iniciar.',
            style: AppType.meta,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.text(
            label: 'Avisar que entrei ao vivo',
            icon: Icons.bolt_rounded,
            onPressed: pinging ? null : onPing,
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final BotProvider bot;
  final VoidCallback onDisconnect;
  const _AccountRow({required this.bot, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    final profile = bot.botProfile;
    final mode = switch (profile?.authMode) {
      'token' => 'Conectado com token de sessão',
      'phone' => 'Conectado com celular',
      'email_code' => 'Conectado com código por e-mail',
      _ => 'Conectado com e-mail e senha',
    };

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _RobotAvatar(radius: 24, imageUrl: profile?.avatar),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile?.nickname ?? "Atila's Client",
                        style: AppType.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text(mode, style: AppType.meta),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton.danger(
              label: 'Desconectar robô',
              icon: Icons.link_off_rounded,
              onPressed: bot.isBusy ? null : onDisconnect,
            ),
          ),
        ],
      ),
    );
  }
}

class _LookupResult extends StatelessWidget {
  final StreamerLookup result;
  const _LookupResult({required this.result});

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      raised: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surface,
            foregroundImage:
                result.avatar != null ? NetworkImage(result.avatar!) : null,
            onForegroundImageError: result.avatar != null ? (_, __) {} : null,
            child: const Icon(Icons.person_rounded,
                color: AppColors.muted, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(result.nickname,
                style: AppType.bodyStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: AppChip(
              label: result.live ? 'ao vivo agora' : 'não está ao vivo',
              icon: result.live
                  ? Icons.sensors_rounded
                  : Icons.pause_circle_outline_rounded,
              tone: result.live ? AppTone.success : AppTone.neutral,
            ),
          ),
        ],
      ),
    );
  }
}

/// The streamer the robot remembers and auto-joins the moment she goes live,
/// with a switch to turn that off without losing who she is.
class _FavoriteStreamer extends StatelessWidget {
  final StreamerWatch watch;
  final bool running;
  final String sessionState;
  final bool isBusy;
  final ValueChanged<bool> onToggle;

  /// Seconds since the robot noticed it's parked on a live ID that still
  /// matches what it was stopped on - see RobotSession.watchWaitingSeconds.
  final double? watchWaitingSeconds;

  const _FavoriteStreamer({
    required this.watch,
    required this.running,
    required this.sessionState,
    required this.isBusy,
    required this.onToggle,
    this.watchWaitingSeconds,
  });

  static String _roundedDuration(double seconds) {
    if (seconds < 60) return '${seconds.round()}s';
    final minutes = (seconds / 60).round();
    return minutes == 1 ? '1 minuto' : '$minutes minutos';
  }

  @override
  Widget build(BuildContext context) {
    final String description;
    final String badgeLabel;
    final AppTone tone;
    final IconData badgeIcon;

    final isWaiting = sessionState == 'waiting_for_live';
    final isStuckOnOldId = watchWaitingSeconds != null;

    if (!watch.active) {
      badgeLabel = 'Desativado';
      description = 'A moderação automática está pausada para este streamer.';
      tone = AppTone.neutral;
      badgeIcon = Icons.pause_circle_outline_rounded;
    } else if (isWaiting) {
      badgeLabel = 'Aguardando live';
      description =
          'A transmissão anterior terminou. O robô continua de olho na próxima live.';
      tone = AppTone.warning;
      badgeIcon = Icons.hourglass_top_rounded;
    } else if (isStuckOnOldId) {
      // Distinct from "Sentinela armada" on purpose: the robot was stopped and
      // the lookup keeps resolving the same transmission it was stopped on.
      // Typing a fresh live ID and starting manually is the way out.
      badgeLabel = 'Aguardando nova transmissão';
      description =
          'O robô foi parado numa transmissão que ainda não mudou de ID no '
          'SuperLive. Espera há ${_roundedDuration(watchWaitingSeconds!)}. '
          'Ele não reinicia sozinho na mesma transmissão. Se já for uma live nova, '
          'informe o ID da live manualmente.';
      tone = AppTone.accent;
      badgeIcon = Icons.sync_problem_rounded;
    } else if (running) {
      badgeLabel = 'Moderando ao vivo';
      description =
          'Conectado à transmissão agora, aplicando as regras em tempo real.';
      tone = AppTone.success;
      badgeIcon = Icons.shield_rounded;
    } else {
      badgeLabel = 'Sentinela armada';
      description =
          'O robô monitora o perfil e começa a moderar sozinho quando o streamer iniciar a live.';
      tone = AppTone.accent;
      badgeIcon = Icons.radar_rounded;
    }

    return AppSurface(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surface,
                foregroundImage:
                    watch.avatar != null ? NetworkImage(watch.avatar!) : null,
                onForegroundImageError:
                    watch.avatar != null ? (_, __) {} : null,
                child: const Icon(Icons.favorite_rounded,
                    color: AppColors.muted, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(watch.nickname ?? 'Streamer favorito',
                        style: AppType.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text('ID público: ${watch.sharedId}', style: AppType.meta),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AppSwitch(
                value: watch.active,
                onChanged: isBusy ? null : onToggle,
                semanticLabel: 'Moderação automática',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: AppChip(label: badgeLabel, icon: badgeIcon, tone: tone),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(description, style: AppType.meta),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed: counters, live chat, moderation actions
// ─────────────────────────────────────────────────────────────────────────────
class _LiveFeed extends StatelessWidget {
  final BotProvider bot;
  const _LiveFeed({required this.bot});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSection(
          title: 'Sessão',
          child: _SessionStats(session: bot.session),
        ),
        AppSection(
          title: 'Chat ao vivo',
          trailing: bot.isRunning
              ? const AppChip(
                  label: 'Ao vivo',
                  icon: Icons.sensors_rounded,
                  tone: AppTone.success,
                )
              : null,
          child: _ChatList(bot: bot),
        ),
        AppSection(
          title: 'Ações de moderação',
          trailing: Text('${bot.totalActionsOk} no total', style: AppType.meta),
          last: true,
          child: _ActionList(bot: bot),
        ),
      ],
    );
  }
}

class _SessionStats extends StatelessWidget {
  final RobotSession session;
  const _SessionStats({required this.session});

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('Mensagens vistas', session.chatSeen),
      ('Mensagens enviadas', session.messagesSent),
      ('Ações de moderação', session.actionsOk),
    ];

    return AppSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              children: [
                for (final (label, value) in stats)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(child: Text(label, style: AppType.body)),
                        Text('$value', style: AppType.title),
                      ],
                    ),
                  ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in stats)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$value', style: AppType.title),
                      Text(label, style: AppType.meta),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The live feed never animates: rows swap in place as messages arrive.
class _ChatList extends StatelessWidget {
  final BotProvider bot;
  const _ChatList({required this.bot});

  @override
  Widget build(BuildContext context) {
    final messages = bot.chatMessages.reversed.toList(); // newest first
    final running = bot.isRunning;

    if (messages.isEmpty) {
      return AppSurface(
        child: AppStateView(
          title: running ? 'Aguardando mensagens' : 'Nenhuma mensagem ainda',
          message: running
              ? 'As mensagens do chat aparecem aqui assim que chegarem.'
              : 'O chat aparece aqui quando o robô estiver em uma live.',
        ),
      );
    }

    return AppSurface(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: SizedBox(
        height: 360,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: messages.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => _ChatRow(message: messages[index]),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final ChatMessage message;
  const _ChatRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final moderated = message.action != null;
    final kick = message.action == 'kick';
    final tone = kick ? AppTone.danger : AppTone.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_time(message.timestamp), style: AppType.meta),
            if (moderated)
              AppChip(
                label: kick ? 'banido' : 'silenciado',
                icon: kick ? Icons.block_rounded : Icons.volume_off_rounded,
                tone: tone,
              ),
          ],
        ),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${message.username}: ', style: AppType.bodyStrong),
            TextSpan(
              text: message.text,
              style: AppType.body.copyWith(
                  color: moderated ? _toneColor(tone) : AppColors.ink),
            ),
          ]),
        ),
      ],
    );
  }
}

class _ActionList extends StatelessWidget {
  final BotProvider bot;
  const _ActionList({required this.bot});

  @override
  Widget build(BuildContext context) {
    final actions = bot.recentActions.reversed.toList(); // newest first

    if (actions.isEmpty) {
      return const AppSurface(
        child: AppStateView(
          title: 'Nenhuma ação nesta sessão',
          message: 'Silenciamentos e banimentos aparecem aqui.',
        ),
      );
    }

    return AppRowList(
      children: [for (final a in actions.take(30)) _ActionRow(action: a)],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final ModerationAction action;
  const _ActionRow({required this.action});

  @override
  Widget build(BuildContext context) {
    final isKick = action.action == 'kick';
    final failed = !action.ok;
    final verb = isKick ? 'Baniu' : 'Silenciou';
    final title = failed
        ? 'Falhou ao ${isKick ? 'banir' : 'silenciar'} ${action.targetName}'
        : '$verb ${action.targetName}';
    final color = failed || isKick ? AppColors.danger : AppColors.warning;

    return AppSurface(
      raised: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isKick ? Icons.block_rounded : Icons.volume_off_rounded,
              color: color, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.bodyStrong),
                Text(
                  'palavra "${action.keyword}" · "${action.messageText}"',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta,
                ),
                if (failed && action.detail != null)
                  Text(action.detail!, style: AppType.meta),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(_time(action.timestamp), style: AppType.meta),
        ],
      ),
    );
  }
}
