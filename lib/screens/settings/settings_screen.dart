import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/services/portal_api_service.dart';
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile section
          _SectionCard(
            title: 'Sua conta',
            icon: Icons.person_rounded,
            iconColor: AppTheme.primary,
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
                endColor: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Robot account section
          _SectionCard(
            title: 'Conta do Robô (SuperLive)',
            icon: Icons.smart_toy_rounded,
            iconColor: AppTheme.accent,
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
                    Text(
                      bot.isConnected
                          ? 'Conectado como: ${bot.botProfile?.nickname ?? "Atila's Client"}'
                          : 'Robô desconectado',
                      style: TextStyle(
                        color: bot.isConnected
                            ? AppTheme.textPrimary
                            : AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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
            title: 'Sobre o Super Moderator',
            icon: Icons.info_rounded,
            iconColor: AppTheme.textMuted,
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
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
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
      icon: Icons.history_rounded,
      iconColor: AppTheme.primary,
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
