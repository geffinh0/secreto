import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/ui/ui.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load(30);
      _loadRankingState();
    });
  }

  void _load(int days) {
    final user = context.read<AuthProvider>().user;
    if (user != null) context.read<StatsProvider>().load(user.id, days: days);
  }

  void _loadRankingState() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    context.read<StatsProvider>().loadRankings();
    if (context.read<AutoMessageProvider>().settings == null) {
      context.read<AutoMessageProvider>().load(user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StatsProvider>();
    final stats = provider.stats;

    return AppPage(
      onRefresh: () async {
        _load(provider.days);
        _loadRankingState();
      },
      children: [
        Reveal(
          child: PageHeader(
            title: 'Estatísticas',
            subtitle: 'Moderação nos últimos ${provider.days} dias',
          ),
        ),
        Reveal(
          index: 1,
          child: AppSection(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final d in const [7, 30, 90])
                  AppChip(
                    label: '$d dias',
                    selected: provider.days == d,
                    onTap: () => _load(d),
                  ),
              ],
            ),
          ),
        ),
        if (provider.isLoading && stats == null)
          const AppStateView.loading(message: 'Carregando estatísticas')
        else if (provider.error != null && stats == null)
          AppStateView(
            kind: AppStateKind.error,
            pose: FoxPose.lookback,
            title: 'Não foi possível carregar as estatísticas',
            message: provider.error,
            actionLabel: 'Tentar de novo',
            onAction: () => _load(provider.days),
          )
        else if (stats != null) ...[
          Reveal(index: 2, child: _Totals(stats: stats)),
          Reveal(
            index: 3,
            child: AppSplit(
              ratio: 0.5,
              primary: _TopKeywords(stats: stats),
              secondary: _RecentLives(stats: stats),
            ),
          ),
          Reveal(index: 4, child: _ByDay(stats: stats)),
        ],
        const Reveal(index: 5, child: _DiamondRankings()),
      ],
    );
  }
}

/// Switch + the saved ranking of each past live. The list is per live on purpose: nothing here
/// adds one live's diamonds to another's.
class _DiamondRankings extends StatelessWidget {
  const _DiamondRankings();

  static final _intFmt = NumberFormat.decimalPattern('pt_BR');

  Future<void> _toggle(BuildContext context, String key, bool value) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final provider = context.read<AutoMessageProvider>();
    final ok = await provider.saveSettings(user.id, {key: value});
    if (!ok && context.mounted) {
      showAppSnack(context, provider.error ?? 'Não foi possível salvar. Tente de novo.',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AutoMessageProvider>().settings;
    final enabled = settings?.liveRankingEnabled ?? false;
    final dmEnabled = settings?.liveRankingDmEnabled ?? false;
    final stats = context.watch<StatsProvider>();
    final rankings = stats.rankings;
    return AppSection(
      title: 'Ranking de diamantes por live',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurface(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSwitchRow(
                  title: 'Guardar o ranking quando a live acabar',
                  subtitle: 'Resumo da live pública: quem enviou diamantes e quanto, só naquela live. '
                      'Conta os presentes que o robô viu enquanto estava na live; se ela virar '
                      'premium, o que vem depois não entra. Lives sem presentes não geram ranking.',
                  value: enabled,
                  onChanged: (v) => _toggle(context, 'live_ranking_enabled', v),
                ),
                if (enabled) ...[
                  const SizedBox(height: 8),
                  AppSwitchRow(
                    title: 'Enviar o ranking por mensagem privada para a streamer',
                    subtitle: 'Cerca de 1 minuto depois do fim da live, o robô manda o ranking '
                        'nas mensagens (DM) do SuperLive, não no chat da live. Se a primeira '
                        'mensagem do robô para ela custar moedas, nada é enviado.',
                    value: dmEnabled,
                    onChanged: (v) => _toggle(context, 'live_ranking_dm_enabled', v),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (stats.rankingsFailed)
            const AppStateView(
                title: 'Não foi possível carregar os rankings',
                message: 'Puxe a tela para atualizar.')
          else if (rankings.isEmpty)
            AppStateView(
                title: 'Nenhum ranking ainda',
                message: enabled
                    ? 'O próximo ranking aparece aqui quando uma live com presentes acabar.'
                    : 'Ligue a opção acima para guardar o ranking das próximas lives.')
          else
            for (final r in rankings)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _RankingCard(ranking: r),
              ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  final LiveRanking ranking;
  const _RankingCard({required this.ranking});

  static const _shown = 10;

  @override
  Widget build(BuildContext context) {
    final fmt = _DiamondRankings._intFmt;
    final when = ranking.endedAt != null
        ? DateFormat("dd/MM 'às' HH:mm").format(ranking.endedAt!.toLocal())
        : 'Live ${ranking.livestreamId}';
    final entries = ranking.entries;
    return AppSurface(
      raised: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Resumo da live pública de $when', style: AppType.bodyStrong),
              Text(
                '${fmt.format(ranking.totalDiamonds)} diamantes · '
                '${entries.length} ${entries.length == 1 ? 'pessoa' : 'pessoas'}',
                style: AppType.meta,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < entries.length && i < _shown; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${i + 1}. ${entries[i].name}: enviou ${fmt.format(entries[i].diamonds)} '
                '${entries[i].diamonds == 1 ? 'diamante' : 'diamantes'}',
                style: AppType.body,
              ),
            ),
          if (entries.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('e mais ${entries.length - _shown} (todos vão no texto copiado)',
                  style: AppType.meta),
            ),
          if (ranking.endedBy == 'premium') ...[
            const SizedBox(height: AppSpacing.sm),
            Text('A live virou premium: este resumo cobre só a parte pública, até esse momento.',
                style: AppType.meta),
          ],
          if (ranking.dmStatus != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(ranking.dmStatus!, style: AppType.meta),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton.text(
            label: 'Copiar ranking',
            icon: Icons.copy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: ranking.text));
              if (context.mounted) showAppSnack(context, 'Ranking copiado');
            },
          ),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  final ModerationStats stats;
  const _Totals({required this.stats});

  @override
  Widget build(BuildContext context) {
    final rate = stats.successRate == null
        ? '—'
        : '${(stats.successRate! * 100).round()}%';
    return AppSection(
      child: AppSplit(
        ratio: 0.5,
        primary: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${stats.totalActions}', style: AppType.display),
            Text('ações no total', style: AppType.meta),
          ],
        ),
        secondary: Wrap(
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.md,
          children: [
            _Figure(value: '${stats.mutes}', label: 'silenciadas'),
            _Figure(value: '${stats.kicks}', label: 'banidas'),
            _Figure(value: rate, label: 'taxa de sucesso'),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String value;
  final String label;
  const _Figure({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: AppType.title),
        Text(label, style: AppType.meta),
      ],
    );
  }
}

/// Row with a label, a bar whose width is proportional to [fraction] and the
/// value as text. Bars only ever come from real provider counts.
class _BarRow extends StatelessWidget {
  final String label;
  final int count;
  final double fraction;
  const _BarRow(
      {required this.label, required this.count, required this.fraction});

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: AppType.bodyStrong,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12),
              Text('$count', style: AppType.bodyStrong),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: 8,
            color: AppColors.raised,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopKeywords extends StatelessWidget {
  final ModerationStats stats;
  const _TopKeywords({required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = stats.topKeywords;
    final max = items.isEmpty ? 0 : items.first.count;
    return AppSection(
      title: 'Palavras mais acionadas',
      child: items.isEmpty
          ? const AppStateView(
              title: 'Nenhuma ação registrada',
              message: 'Nenhuma palavra foi acionada nesse período.')
          : AppRowList(children: [
              for (final k in items)
                _BarRow(
                  label: k.keyword,
                  count: k.count,
                  fraction: max == 0 ? 0 : k.count / max,
                ),
            ]),
    );
  }
}

class _RecentLives extends StatelessWidget {
  final ModerationStats stats;
  const _RecentLives({required this.stats});

  @override
  Widget build(BuildContext context) {
    final lives = stats.recentLives;
    return AppSection(
      title: 'Lives recentes',
      child: lives.isEmpty
          ? const AppStateView(
              title: 'Nenhuma live com ações',
              message: 'Nenhuma live teve ações nesse período.')
          : AppDataTable(
              columns: const [
                AppTableColumn('Live', flex: 3),
                AppTableColumn('Ações', alignment: Alignment.centerRight),
              ],
              rows: [
                for (final live in lives)
                  [
                    Text(
                      live.firstAt != null
                          ? DateFormat("dd/MM 'às' HH:mm")
                              .format(live.firstAt!.toLocal())
                          : 'ID da live ${live.livestreamId}',
                      style: AppType.bodyStrong,
                    ),
                    Text('${live.count}', style: AppType.bodyStrong),
                  ],
              ],
            ),
    );
  }
}

class _ByDay extends StatelessWidget {
  final ModerationStats stats;
  const _ByDay({required this.stats});

  @override
  Widget build(BuildContext context) {
    final days = stats.byDay;
    final max = days.isEmpty
        ? 0
        : days.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    return AppSection(
      title: 'Ações por dia',
      last: true,
      child: days.isEmpty
          ? const AppStateView(
              title: 'Nenhuma ação registrada',
              message: 'Nenhuma ação foi feita nesse período.')
          : AppRowList(children: [
              for (final d in days.reversed)
                _BarRow(
                  label: DateFormat('dd/MM').format(d.day),
                  count: d.count,
                  fraction: max == 0 ? 0 : d.count / max,
                ),
            ]),
    );
  }
}
