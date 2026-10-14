import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../providers/bot_provider.dart';
import '../../providers/moderation_provider.dart';
import '../../widgets/ui/ui.dart';

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

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final bot = context.watch<BotProvider>();
    final mod = context.watch<ModerationProvider>();
    final msg = context.watch<AutoMessageProvider>();
    final name = user?.shownName ?? 'Usuário';

    return AppPage(
      onRefresh: _loadData,
      children: [
        Reveal(
          child: PageHeader(title: 'Painel', subtitle: '${_greeting()}, $name'),
        ),
        Reveal(
          index: 1,
          child: AppSection(
            child: AppSplit(
              ratio: 0.62,
              primary: _RobotStatus(bot: bot),
              secondary: _Numbers(
                rules: mod.rules.length,
                queued: msg.messages.length,
                actions: bot.totalActionsOk,
              ),
            ),
          ),
        ),
        Reveal(
          index: 2,
          child: AppSection(
            child: AppSplit(
              ratio: 0.5,
              primary: _RulesList(rules: mod.rules),
              secondary: _MessagesList(messages: msg.messages),
            ),
          ),
        ),
        Reveal(
          index: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppButton.text(
              label: 'Ver estatísticas',
              icon: Icons.arrow_forward,
              // go(), not push(): /stats is a sibling route inside the same
              // ShellRoute as Dashboard - pushing it stacks a second shell
              // over the first instead of swapping the child route.
              onPressed: () => context.go('/stats'),
            ),
          ),
        ),
      ],
    );
  }
}

class _RobotStatus extends StatelessWidget {
  final BotProvider bot;
  const _RobotStatus({required this.bot});

  @override
  Widget build(BuildContext context) {
    final connected = bot.isConnected;
    final live = connected && bot.isRunning;

    final String headline;
    final String detail;
    final AppChip chip;
    if (live) {
      headline = 'Moderando a live';
      detail = '${bot.session.messagesSent} mensagens enviadas nesta live.';
      chip = const AppChip(
          label: 'Ao vivo', icon: Icons.sensors, tone: AppTone.success);
    } else if (connected) {
      headline = 'Aguardando a live';
      detail = 'O robô está conectado e não há live no momento.';
      chip =
          const AppChip(label: 'Conectado', icon: Icons.pause_circle_outline);
    } else {
      headline = 'Robô desligado';
      detail = bot.error ?? 'Conecte o robô para começar a moderar.';
      chip = const AppChip(
          label: 'Desconectado', icon: Icons.link_off, tone: AppTone.warning);
    }

    final last = bot.recentActions.isEmpty ? null : bot.recentActions.last;

    return AppSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: AppType.display),
          const SizedBox(height: AppSpacing.sm),
          Text(detail, style: AppType.body),
          const SizedBox(height: AppSpacing.md),
          chip,
          if (last != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _LastAction(action: last),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: connected ? 'Abrir o robô' : 'Conectar robô',
            icon: connected ? Icons.smart_toy_outlined : Icons.link,
            onPressed: () => context.go('/bot'),
          ),
        ],
      ),
    );
  }
}

class _LastAction extends StatelessWidget {
  final ModerationAction action;
  const _LastAction({required this.action});

  @override
  Widget build(BuildContext context) {
    final mute = action.action == 'mute';
    final title = action.ok
        ? '${mute ? 'Silenciou' : 'Baniu'} ${action.targetName}'
        : 'Falhou ao ${mute ? 'silenciar' : 'banir'} ${action.targetName}';
    final time = action.timestamp == null
        ? ''
        : ' às ${DateFormat('HH:mm').format(action.timestamp!.toLocal())}';
    return AppSurface(
      raised: true,
      child: Row(
        children: [
          Icon(
            action.ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 20,
            color: action.ok ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppType.bodyStrong,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text('Palavra "${action.keyword}"$time',
                    style: AppType.meta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Numbers extends StatelessWidget {
  final int actions;
  final int rules;
  final int queued;
  const _Numbers(
      {required this.actions, required this.rules, required this.queued});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$actions', style: AppType.title),
          Text('ações realizadas', style: AppType.meta),
          const SizedBox(height: AppSpacing.lg),
          Text('$rules', style: AppType.title),
          Text('regras ativas', style: AppType.meta),
          const SizedBox(height: AppSpacing.md),
          Text('$queued', style: AppType.title),
          Text('mensagens na fila', style: AppType.meta),
        ],
      ),
    );
  }
}

class _RulesList extends StatelessWidget {
  final List<ModerationRule> rules;
  const _RulesList({required this.rules});

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: 'Regras de moderação',
      last: true,
      child: rules.isEmpty
          ? const AppStateView(
              title: 'Nenhuma regra cadastrada',
              message: 'Adicione palavras em Moderação.')
          : AppRowList(children: [
              for (final r in rules.take(4))
                AppListRow(
                  title: r.keyword,
                  subtitle: r.isActive ? null : 'Desativada',
                  trailing: AppChip(
                    label: r.action == 'mute' ? 'Silenciar' : 'Banir',
                    icon: r.action == 'mute' ? Icons.volume_off : Icons.block,
                    tone: r.action == 'mute' ? AppTone.warning : AppTone.danger,
                  ),
                ),
            ]),
    );
  }
}

class _MessagesList extends StatelessWidget {
  final List<AutoMessage> messages;
  const _MessagesList({required this.messages});

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: 'Fila de mensagens',
      last: true,
      child: messages.isEmpty
          ? const AppStateView(
              title: 'Nenhuma mensagem na fila',
              message: 'Adicione mensagens automáticas em Mensagens.')
          : AppRowList(children: [
              for (final m in messages.take(4))
                AppListRow(
                  title: m.content,
                  subtitle: m.isActive ? null : 'Desativada',
                  trailing: AppChip(label: '#${m.sortOrder + 1}'),
                ),
            ]),
    );
  }
}
