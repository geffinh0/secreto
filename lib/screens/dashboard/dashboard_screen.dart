import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bot_provider.dart';
import '../../providers/moderation_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../widgets/common/fox_icon.dart';

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
            Text(
              '${_greeting()}, ${user?.displayName ?? user?.username ?? "Usuária"}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            // The robot, front and centre: this screen exists to answer one
            // question - "is Atila working right now?" - everything else is
            // secondary detail, not a grid of equally-weighted tiles.
            _buildHero(bot, mod, msg),
            const SizedBox(height: 24),

            _buildActivityRow(mod, msg),
            const SizedBox(height: 16),
            _buildStatsLink(context),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  Widget _buildHero(BotProvider bot, ModerationProvider mod, AutoMessageProvider msg) {
    final connected = bot.isConnected;
    final live = connected && bot.isRunning;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: connected ? AppTheme.primary : AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: connected ? AppTheme.primary : AppTheme.border,
                    width: connected ? 1.5 : 1,
                  ),
                ),
                padding: const EdgeInsets.all(6),
                child: const FoxIcon(
                  size: 60,
                  borderRadius: 14,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected
                          ? bot.botProfile?.nickname ?? "Atila's Client"
                          : "Atila's Client",
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      connected
                          ? (live
                              ? 'Moderando a live agora.'
                              : 'Conectado. Nenhuma live no momento.')
                          : bot.error ?? 'Ainda não conectado - veja a aba "Robô".',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StatusPill(connected: connected, live: live),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final stats = <Widget>[
                _HeroStat(value: '${mod.rules.length}', label: 'regras ativas'),
                _HeroStat(value: '${msg.messages.length}', label: 'mensagens na fila'),
                _HeroStat(
                  value: '${bot.totalActionsOk}',
                  label: 'ações no total',
                  color: AppTheme.warning,
                ),
                if (live)
                  _HeroStat(
                    value: '${bot.session.messagesSent}',
                    label: 'enviadas nesta live',
                    color: AppTheme.accent,
                  ),
              ];

              // Four stats plus three dividers never fit a phone's width
              // without clipping or scrolling off-screen - a 2-column grid
              // keeps every number fully visible instead.
              if (constraints.maxWidth < 480) {
                const gap = 20.0;
                final itemWidth = (constraints.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: 16,
                  children: [
                    for (final stat in stats) SizedBox(width: itemWidth, child: stat),
                  ],
                );
              }

              final children = <Widget>[];
              for (var i = 0; i < stats.length; i++) {
                if (i > 0) children.add(_heroDivider());
                children.add(stats[i]);
              }
              return Row(children: children);
            },
          ),
        ],
      ),
    );
  }

  Widget _heroDivider() => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: AppTheme.border,
      );

  Widget _buildActivityRow(ModerationProvider mod, AutoMessageProvider msg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final children = [
          _QuickInfoCard(
            title: 'Últimas regras de moderação',
            accent: AppTheme.primary,
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
            accent: AppTheme.accent,
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

  Widget _buildStatsLink(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/stats'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bar_chart_rounded, color: AppTheme.accent, size: 20),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estatísticas',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Histórico de moderação, palavras mais acionadas e lives recentes',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Three states, not two: offline / connected-but-idle / live. A live is the
/// one moment worth calling out loudly (red, pulsing-style dot); the other
/// two are quiet by comparison on purpose.
class _StatusPill extends StatelessWidget {
  final bool connected;
  final bool live;
  const _StatusPill({required this.connected, required this.live});

  @override
  Widget build(BuildContext context) {
    final color = live ? AppTheme.error : (connected ? AppTheme.success : AppTheme.textMuted);
    final label = live ? 'AO VIVO' : (connected ? 'Online' : 'Offline');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: live ? 1.0 : 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _HeroStat({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _QuickInfoCard extends StatelessWidget {
  final String title;
  final Color accent;
  final String emptyText;
  final List<_QuickInfoItem> items;

  const _QuickInfoCard({
    required this.title,
    required this.accent,
    required this.emptyText,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 18, 18),
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
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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
