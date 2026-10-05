import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bot_provider.dart';
import '../../providers/moderation_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../widgets/common/stat_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.id;
    if (userId == null) return;

    context.read<BotProvider>().refresh();
    context.read<ModerationProvider>().loadRules(userId);
    context.read<AutoMessageProvider>().load(userId);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final bot = context.watch<BotProvider>();
    final mod = context.watch<ModerationProvider>();
    final msg = context.watch<AutoMessageProvider>();
    final user = auth.user;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primary,
      backgroundColor: AppTheme.bgCard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header
            _buildWelcomeHeader(user?.displayName ?? user?.username ?? 'Usuário', bot),
            const SizedBox(height: 28),

            // Stats row
            _buildStatsGrid(bot, mod, msg),
            const SizedBox(height: 28),

            // Bot status card
            _buildBotStatusCard(bot),
            const SizedBox(height: 24),

            // Two-column cards row
            _buildActivityRow(mod, msg),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(String name, BotProvider bot) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Bom dia'
        : hour < 18
            ? 'Boa tarde'
            : 'Boa noite';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, $name! 👋',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                bot.isConnected
                    ? 'Robô ativo e pronto para moderar suas lives.'
                    : 'Configure o robô para começar a moderação automática.',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(
    BotProvider bot,
    ModerationProvider mod,
    AutoMessageProvider msg,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 700 ? 4 : 2;
        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // fixed row height: an aspect ratio made the cards overflow on some widths
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 122,
          ),
          children: [
            StatCard(
              icon: Icons.smart_toy_rounded,
              label: 'Status do Robô',
              value: bot.isConnected ? 'Conectado' : 'Offline',
              valueColor: bot.isConnected ? AppTheme.success : AppTheme.error,
              gradient: bot.isConnected ? AppTheme.successGradient : AppTheme.dangerGradient,
            ),
            StatCard(
              icon: Icons.shield_rounded,
              label: 'Regras de Moderação',
              value: '${mod.rules.length}',
              valueColor: AppTheme.primary,
              gradient: AppTheme.primaryGradient,
            ),
            StatCard(
              icon: Icons.chat_bubble_rounded,
              label: 'Mensagens na Fila',
              value: '${msg.messages.length}',
              valueColor: AppTheme.accent,
              gradient: const LinearGradient(colors: [AppTheme.accent, AppTheme.primary]),
            ),
            StatCard(
              icon: Icons.block_rounded,
              label: 'Ações Executadas',
              value: '${bot.totalActionsOk}',
              valueColor: AppTheme.warning,
              gradient: const LinearGradient(colors: [AppTheme.warning, AppTheme.secondary]),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBotStatusCard(BotProvider bot) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1428), Color(0xFF120F20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bot.isConnected
              ? AppTheme.primary.withValues(alpha: 0.4)
              : AppTheme.border,
        ),
        boxShadow: bot.isConnected
            ? [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: bot.isConnected
                  ? AppTheme.primaryGradient
                  : const LinearGradient(
                      colors: [AppTheme.bgElevated, AppTheme.bgSurface]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              color: bot.isConnected ? Colors.white : AppTheme.textMuted,
              size: 28,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Robô Moderador',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusBadge(isActive: bot.isConnected),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  bot.isConnected
                      ? 'Conta: ${bot.botProfile?.nickname ?? "Carregando..."}'
                      : bot.error ?? 'Configure as credenciais do robô na aba "Robô"',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                if (bot.isConnected && bot.isRunning) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.error,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'AO VIVO',
                        style: TextStyle(
                          color: AppTheme.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${bot.session.messagesSent} msgs enviadas · '
                        '${bot.session.actionsOk} ações',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityRow(ModerationProvider mod, AutoMessageProvider msg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final children = [
          _QuickInfoCard(
            title: 'Últimas regras de moderação',
            icon: Icons.shield_rounded,
            iconColor: AppTheme.primary,
            emptyText: 'Nenhuma regra cadastrada ainda',
            items: mod.rules.take(4).map((r) {
              return _QuickInfoItem(
                label: '"${r.keyword}"',
                badge: r.action == 'mute' ? 'Silenciar' : 'Banir',
                badgeColor: r.action == 'mute'
                    ? AppTheme.warning
                    : AppTheme.error,
                isActive: r.isActive,
              );
            }).toList(),
          ),
          _QuickInfoCard(
            title: 'Fila de mensagens automáticas',
            icon: Icons.chat_bubble_rounded,
            iconColor: AppTheme.accent,
            emptyText: 'Nenhuma mensagem na fila',
            items: msg.messages.take(4).map((m) {
              return _QuickInfoItem(
                label: m.content.length > 40
                    ? '${m.content.substring(0, 40)}...'
                    : m.content,
                badge: '#${m.sortOrder + 1}',
                badgeColor: AppTheme.accent,
                isActive: m.isActive,
              );
            }).toList(),
          ),
        ];

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[0]),
              const SizedBox(width: 16),
              Expanded(child: children[1]),
            ],
          );
        }
        return Column(
          children: [
            children[0],
            const SizedBox(height: 16),
            children[1],
          ],
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? AppTheme.success : AppTheme.error).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isActive ? AppTheme.success : AppTheme.error).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppTheme.success : AppTheme.error,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isActive ? 'Online' : 'Offline',
            style: TextStyle(
              color: isActive ? AppTheme.success : AppTheme.error,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickInfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String emptyText;
  final List<_QuickInfoItem> items;

  const _QuickInfoCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.emptyText,
    required this.items,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  emptyText,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            color: item.isActive
                                ? AppTheme.textPrimary
                                : AppTheme.textMuted,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: item.badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          item.badge,
                          style: TextStyle(
                            color: item.badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _QuickInfoItem {
  final String label;
  final String badge;
  final Color badgeColor;
  final bool isActive;

  const _QuickInfoItem({
    required this.label,
    required this.badge,
    required this.badgeColor,
    this.isActive = true,
  });
}
