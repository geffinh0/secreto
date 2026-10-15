import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/services/portal_api_service.dart';
import '../../core/services/pwa_install_service.dart';
import '../../core/theme/theme_controller.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bot_provider.dart';
import '../../widgets/ui/ui.dart';
import 'import_config_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final bot = context.watch<BotProvider>();

    final account = AppSection(
      title: 'Conta',
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(label: 'Nome', value: user?.shownName ?? '—'),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(label: 'Usuário', value: '@${user?.username ?? '—'}'),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(
              label: 'Tipo',
              value: (user?.isAdmin ?? false) ? 'Administrador' : 'Streamer',
            ),
          ],
        ),
      ),
    );

    final themeController = context.watch<ThemeController>();
    final appearance = AppSection(
      title: 'Aparência',
      subtitle: 'Vale só para este dispositivo. Automático segue o aparelho.',
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final option in const [
            (AppThemeMode.system, 'Automático', Icons.brightness_auto_outlined),
            (AppThemeMode.light, 'Claro', Icons.light_mode_outlined),
            (AppThemeMode.dark, 'Escuro', Icons.dark_mode_outlined),
          ])
            AppChip(
              label: option.$2,
              icon: option.$3,
              selected: themeController.mode == option.$1,
              onTap: () => themeController.setMode(option.$1),
            ),
        ],
      ),
    );

    final security = AppSection(
      title: 'Segurança',
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppButton.secondary(
          label: 'Alterar senha',
          icon: Icons.lock_reset,
          onPressed: () => context.push('/change-password'),
        ),
      ),
    );

    final robot = AppSection(
      title: 'Conta do robô',
      subtitle:
          'Para conectar o robô, abra a página Robô e informe as credenciais da conta oficial.',
      child: AppSurface(
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppChip(
              label: bot.isConnected ? 'Conectado' : 'Desconectado',
              icon:
                  bot.isConnected ? Icons.check_circle_outline : Icons.link_off,
              tone: bot.isConnected ? AppTone.success : AppTone.danger,
            ),
            if (bot.isConnected)
              Text(bot.botProfile?.nickname ?? "Atila's Client",
                  style: AppType.bodyStrong),
          ],
        ),
      ),
    );

    const about = AppSection(
      title: "Sobre o Atila's Client",
      last: true,
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(label: 'Versão', value: AppConstants.appVersion),
            SizedBox(height: AppSpacing.md),
            _InfoRow(label: 'Plataforma', value: 'SuperLive v2.31.0'),
          ],
        ),
      ),
    );

    final logout = AppSection(
      title: 'Sair',
      subtitle:
          'Encerra a sessão neste dispositivo. O robô continua como está.',
      last: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppButton.secondary(
          key: const ValueKey('logout_button'),
          label: 'Sair da conta',
          icon: Icons.logout,
          onPressed: () => context.read<AuthProvider>().logout(),
        ),
      ),
    );

    final primary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        account,
        appearance,
        security,
        const ImportConfigCard(),
        if (AppSpacing.isWide(context)) logout
      ],
    );
    final secondary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PwaInstallSection(),
        robot,
        const _ActivitySection(),
        about,
        if (!AppSpacing.isWide(context)) ...[
          SizedBox(height: AppSpacing.section(context)),
          logout,
        ],
      ],
    );

    return AppPage(
      children: [
        const Reveal(child: PageHeader(title: 'Configurações')),
        Reveal(
            index: 1,
            child:
                AppSplit(primary: primary, secondary: secondary, ratio: 0.55)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppType.meta),
        Text(value, style: AppType.bodyStrong),
      ],
    );
  }
}

/// Installing as a PWA is what lets the dashboard behave like a real app
/// (full-screen, its own icon) instead of a browser tab - but the browser
/// APIs behind it are a dead end without a nudge: Chrome/Android never show
/// their own install button unprompted, and iOS has no install prompt at
/// all, only "Adicionar à Tela de Início" buried in Safari's Share sheet.
/// Hides itself once already installed (standalone) or on a browser that
/// offers neither path (desktop Chrome without the component, Firefox, …).
class _PwaInstallSection extends StatefulWidget {
  const _PwaInstallSection();

  @override
  State<_PwaInstallSection> createState() => _PwaInstallSectionState();
}

class _PwaInstallSectionState extends State<_PwaInstallSection> {
  bool _installing = false;

  Future<void> _install() async {
    setState(() => _installing = true);
    PwaInstallService.triggerInstall();
    // The browser's own prompt is modal-ish but not awaitable from here;
    // give it a moment, then re-check - canPromptInstall flips false once
    // the user accepts (or the event is spent either way).
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _installing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (PwaInstallService.isStandalone) return const SizedBox.shrink();

    final isIos = PwaInstallService.isIos;
    final canPrompt = PwaInstallService.canPromptInstall;
    if (!isIos && !canPrompt) return const SizedBox.shrink();

    return AppSection(
      title: 'Instalar como app',
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isIos
                  ? 'No Safari, toque em compartilhar e depois em "Adicionar à Tela de Início".'
                  : "Instale o Atila's Client como app: abre em tela cheia, com ícone próprio e sem a barra de endereço.",
              style: AppType.body,
            ),
            if (!isIos) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton.secondary(
                key: const ValueKey('install_pwa_button'),
                label: 'Instalar app',
                icon: Icons.install_mobile,
                loading: _installing,
                onPressed: _installing ? null : _install,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the logged-in user has done in the portal: login, rule/message/settings
/// changes, robot connect/disconnect, moderation start/stop (`GET /activity`).
class _ActivitySection extends StatefulWidget {
  const _ActivitySection();

  @override
  State<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<_ActivitySection> {
  final _api = PortalApiService();
  List<ActivityEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _api.get('/activity?limit=20');
    if (!mounted) return;
    if (result['success'] == true && result['data'] is List) {
      setState(() {
        _entries = (result['data'] as List)
            .whereType<Map>()
            .map((e) => ActivityEntry.fromJson(e.cast<String, dynamic>()))
            .toList();
        _error = null;
      });
    } else {
      setState(() => _error = PortalApiService.errorMessage(
          result, 'Não foi possível carregar a atividade. Tente de novo.'));
    }
  }

  static IconData _iconFor(String action) => switch (action) {
        'login' || 'account_created' => Icons.login,
        'rule_created' ||
        'rule_updated' ||
        'rule_deleted' =>
          Icons.shield_outlined,
        'message_created' ||
        'message_updated' ||
        'message_deleted' =>
          Icons.chat_bubble_outline,
        'settings_updated' => Icons.tune,
        'robot_connected' || 'robot_disconnected' => Icons.smart_toy_outlined,
        'session_started' || 'session_stopped' => Icons.live_tv_outlined,
        _ => Icons.history,
      };

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final Widget content;
    if (_error != null) {
      content = AppStateView(
        kind: AppStateKind.error,
        title: 'Atividade indisponível',
        message: _error,
        actionLabel: 'Tentar de novo',
        onAction: _load,
      );
    } else if (entries == null) {
      content = const AppStateView.loading(message: 'Carregando atividade');
    } else if (entries.isEmpty) {
      content = const AppStateView(
        title: 'Nenhuma atividade ainda',
        message: 'As ações feitas nesta conta aparecem aqui.',
      );
    } else {
      content = AppRowList(
        children: [
          for (final entry in entries)
            AppListRow(
              leading: Icon(_iconFor(entry.action),
                  color: AppColors.muted, size: 20),
              title: entry.label,
              subtitle: (entry.detail != null && entry.detail!.isNotEmpty)
                  ? entry.detail
                  : null,
              trailing: entry.createdAt == null
                  ? null
                  : Text(
                      DateFormat('dd/MM HH:mm')
                          .format(entry.createdAt!.toLocal()),
                      style: AppType.meta,
                    ),
            ),
        ],
      );
    }

    return AppSection(title: 'Atividade da conta', child: content);
  }
}
