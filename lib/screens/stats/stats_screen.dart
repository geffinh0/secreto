import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stats_provider.dart';

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

    return RefreshIndicator(
      onRefresh: () async => _load(provider.days),
      color: AppTheme.primary,
      backgroundColor: AppTheme.bgCard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [7, 30, 90]
                  .map((d) => _DaysChip(
                        label: '${d}d',
                        selected: provider.days == d,
                        onTap: () => _load(d),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            if (provider.isLoading && stats == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              )
            else if (provider.error != null && stats == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(provider.error!,
                    style: const TextStyle(color: AppTheme.error)),
              )
            else if (stats != null) ...[
              _buildTotals(stats),
              const SizedBox(height: 20),
              _buildTopKeywords(stats),
              const SizedBox(height: 20),
              _buildByDay(stats),
              const SizedBox(height: 20),
              _buildRecentLives(stats),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotals(ModerationStats stats) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 480;
        final tiles = [
          _StatTile(value: '${stats.totalActions}', label: 'ações no total'),
          _StatTile(value: '${stats.mutes}', label: 'silenciadas', color: AppTheme.warning),
          _StatTile(value: '${stats.kicks}', label: 'banidas', color: AppTheme.error),
          _StatTile(
            value: stats.successRate == null
                ? '—'
                : '${(stats.successRate! * 100).round()}%',
            label: 'taxa de sucesso',
            color: AppTheme.success,
          ),
        ];
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: narrow
              ? Wrap(
                  spacing: 20,
                  runSpacing: 16,
                  children: [
                    for (final t in tiles)
                      SizedBox(width: (constraints.maxWidth - 60) / 2, child: t)
                  ],
                )
              : Row(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0)
                        Container(
                          width: 1,
                          height: 36,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          color: AppTheme.border,
                        ),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTopKeywords(ModerationStats stats) {
    return _Card(
      title: 'Palavras mais acionadas',
      icon: Icons.label_outline_rounded,
      child: stats.topKeywords.isEmpty
          ? const _EmptyHint('Nenhuma ação registrada nesse período.')
          : Column(
              children: [
                for (final k in stats.topKeywords)
                  _KeywordBar(
                    keyword: k.keyword,
                    count: k.count,
                    maxCount: stats.topKeywords.first.count,
                  ),
              ],
            ),
    );
  }

  Widget _buildByDay(ModerationStats stats) {
    return _Card(
      title: 'Ações por dia',
      icon: Icons.show_chart_rounded,
      child: stats.byDay.isEmpty
          ? const _EmptyHint('Nenhuma ação registrada nesse período.')
          : SizedBox(
              height: 120,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const minBarWidth = 26.0;
                  final maxCount = stats.byDay
                      .map((e) => e.count)
                      .reduce((a, b) => a > b ? a : b);
                  Widget bar(DayCount d) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Tooltip(
                          message: '${d.count} em ${DateFormat('dd/MM').format(d.day)}',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: 6 + 80 * (d.count / maxCount),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                DateFormat('dd/MM').format(d.day),
                                style: const TextStyle(
                                    color: AppTheme.textMuted, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      );

                  // Many days (e.g. the 90-day view) squeezed into Expanded
                  // columns end up unreadably thin - past a minimum bar
                  // width, scroll horizontally instead of shrinking further.
                  final fitsWithoutScroll =
                      constraints.maxWidth / stats.byDay.length >= minBarWidth;
                  if (fitsWithoutScroll) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in stats.byDay) Expanded(child: bar(d)),
                      ],
                    );
                  }
                  return Scrollbar(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final d in stats.byDay)
                            SizedBox(width: minBarWidth, child: bar(d)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildRecentLives(ModerationStats stats) {
    return _Card(
      title: 'Lives recentes',
      icon: Icons.live_tv_rounded,
      child: stats.recentLives.isEmpty
          ? const _EmptyHint('Nenhuma live com ações nesse período.')
          : Column(
              children: [
                for (final live in stats.recentLives)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, color: AppTheme.textMuted, size: 8),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            live.firstAt != null
                                ? DateFormat("dd/MM 'às' HH:mm").format(live.firstAt!.toLocal())
                                : 'Live ${live.livestreamId}',
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${live.count} ações',
                            style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
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

class _DaysChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DaysChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _StatTile({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Card({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
              Icon(icon, color: AppTheme.accent, size: 18),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _KeywordBar extends StatelessWidget {
  final String keyword;
  final int count;
  final int maxCount;
  const _KeywordBar({required this.keyword, required this.count, required this.maxCount});

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : count / maxCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('"$keyword"',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              ),
              Text('$count', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) => Container(
              height: 6,
              width: constraints.maxWidth,
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 6,
                  width: constraints.maxWidth * fraction,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
    );
  }
}
