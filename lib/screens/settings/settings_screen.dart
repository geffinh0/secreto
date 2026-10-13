import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/services/portal_api_service.dart';
import '../../core/services/pwa_install_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bot_provider.dart';
import '../../widgets/common/gradient_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final bot = context.watch<BotProvider>();

    final gap = AppSpacing.section(context);
    return SingleChildScrollView(
      padding: AppSpacing.page(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PwaInstallCard(),
          SizedBox(height: gap),

          // Profile section
          _SectionCard(
            title: 'Sua conta',
            accent: AppTheme.primary,
            children: [
              _InfoRow(label: 'Nome', value: user?.displayName ?? 'N/A'),
              const SizedBox(height: 12),
              _InfoRow(label: 'Usuário', value: '@${user?.username ?? 'N/A'}'),
              const SizedBox(height: 12),
              _InfoRow(label: 'E-mail', value: user?.email ?? 'N/A'),
              const SizedBox(height: 12),
              _InfoRow(
                  label: 'Tipo',
                  value: (user?.isAdmin ?? false) ? 'Administrador' : 'Criadora'),
              const SizedBox(height: 20),
              GradientButton(
                id: 'logout_button',
                onPressed: () => context.read<AuthProvider>().logout(),
                label: 'Sair da conta',
                icon: Icons.logout_rounded,
                startColor: AppTheme.error,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Robot account section
          _SectionCard(
            title: 'Conta do Robô (SuperLive)',
            accent: AppTheme.accent,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bot.isConnected
                            ? AppTheme.success
                            : AppTheme.error,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bot.isConnected
                            ? 'Conectado como: ${bot.botProfile?.nickname ?? "Atila's Client"}'
                            : 'Robô desconectado',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bot.isConnected
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Para conectar o robô, vá até a aba "Robô" e informe as credenciais da conta oficial.',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Account activity section
          const _ActivitySection(),
          const SizedBox(height: 24),

          // About section
          const _SectionCard(
            title: "Sobre o Atila's Client",
            accent: AppTheme.textDisabled,
            children: [
              _InfoRow(label: 'Versão', value: AppConstants.appVersion),
              SizedBox(height: 12),
              _InfoRow(label: 'Plataforma', value: 'SuperLive v2.31.0'),
              SizedBox(height: 12),
              _InfoRow(label: 'Backend', value: 'FastAPI + SQLite'),
              SizedBox(height: 12),
              _InfoRow(label: 'Frontend', value: 'Flutter Web'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Color accent;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.accent,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 20, 20, 20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          top: const BorderSide(color: AppTheme.border),
          right: const BorderSide(color: AppTheme.border),
          bottom: const BorderSide(color: AppTheme.border),
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
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
class _PwaInstallCard extends StatefulWidget {
  const _PwaInstallCard();

  @override
  State<_PwaInstallCard> createState() => _PwaInstallCardState();
}

class _PwaInstallCardState extends State<_PwaInstallCard> {
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

    return _SectionCard(
      title: 'Instalar como app',
      accent: AppTheme.accent,
      children: [
        if (isIos) ...[
          const Text(
            'No Safari: toque no ícone de compartilhar e depois em '
            '"Adicionar à Tela de Início".',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.ios_share_rounded, color: AppTheme.accent, size: 20),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: AppTheme.textMuted, size: 16),
              SizedBox(width: 8),
              Icon(Icons.add_box_outlined, color: AppTheme.accent, size: 20),
            ],
          ),
        ] else ...[
          const Text(
            'Instale o Atila\'s Client como um app: abre em tela cheia, '
            'com ícone próprio, sem a barra de endereço do navegador.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          GradientButton(
            id: 'install_pwa_button',
            onPressed: _installing ? null : _install,
            isLoading: _installing,
            label: 'Instalar app',
            icon: Icons.install_mobile_rounded,
          ),
        ],
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
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
      setState(() => _error =
          PortalApiService.errorMessage(result, 'Erro ao carregar atividade'));
    }
  }

  static IconData _iconFor(String action) => switch (action) {
        'login' || 'account_created' => Icons.login_rounded,
        'rule_created' || 'rule_updated' || 'rule_deleted' => Icons.shield_rounded,
        'message_created' || 'message_updated' || 'message_deleted' =>
          Icons.chat_bubble_rounded,
        'settings_updated' => Icons.tune_rounded,
        'robot_connected' || 'robot_disconnected' => Icons.smart_toy_rounded,
        'session_started' || 'session_stopped' => Icons.live_tv_rounded,
        _ => Icons.history_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Atividade da conta',
      accent: AppTheme.secondary,
      children: [
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 12.5))
        else if (_entries == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
              ),
            ),
          )
        else if (_entries!.isEmpty)
          const Text('Nenhuma atividade registrada ainda.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13))
        else
          Column(
            children: [
              for (final entry in _entries!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_iconFor(entry.action), color: AppTheme.textMuted, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.label,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            if (entry.detail != null && entry.detail!.isNotEmpty)
                              Text(entry.detail!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppTheme.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (entry.createdAt != null)
                        Text(
                          DateFormat('dd/MM HH:mm').format(entry.createdAt!.toLocal()),
                          style: const TextStyle(
                              color: AppTheme.textDisabled, fontSize: 11),
                        ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
