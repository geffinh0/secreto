import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../providers/auth_provider.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(30));
  }

  void _load(int days) {
    final user = context.read<AuthProvider>().user;
    if (user != null) context.read<StatsProvider>().load(user.id, days: days);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StatsProvider>();
    final stats = provider.stats;

    return AppPage(
      onRefresh: () async => _load(provider.days),
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
      ],
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
