import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/services/app_update_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bot_provider.dart';
import '../common/fox_icon.dart';
import '../ui/ui.dart';

class _Dest {
  final IconData icon;
  final String label;
  final String path;
  const _Dest(this.icon, this.label, this.path);
}

const _painel = _Dest(Icons.grid_view_outlined, 'Painel', '/dashboard');
const _moderacao = _Dest(Icons.shield_outlined, 'Moderação', '/moderation');
const _robo = _Dest(Icons.smart_toy_outlined, 'Robô', '/bot');
const _mensagens =
    _Dest(Icons.chat_bubble_outline, 'Mensagens automáticas', '/messages');
const _estatisticas = _Dest(Icons.bar_chart, 'Estatísticas', '/stats');
const _configuracoes =
    _Dest(Icons.settings_outlined, 'Configurações', '/settings');

const _primary = [_painel, _moderacao, _robo];
const _more = [_mensagens, _estatisticas, _configuracoes];
const _all = [..._primary, ..._more];

bool _matches(String location, _Dest d) => location.startsWith(d.path);

/// App frame. Phone: slim top bar, content, bottom bar with Painel,
/// Moderação, Robô and Mais. Desktop (>= 900): fixed 240px sidebar with every
/// destination. Pages draw their own PageHeader; the shell never titles them.
class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final wide = AppSpacing.isWide(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (wide) _Sidebar(location: location),
            Expanded(
              child: Column(
                children: [
                  if (!wide) const _TopBar(),
                  const _UpdateNotice(),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: AppSpacing.maxContentWidth),
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide ? null : _BottomBar(location: location),
    );
  }
}

/// Shown while the app stays open and the server has a newer build. One tap
/// clears the old caches and reloads into it.
class _UpdateNotice extends StatefulWidget {
  const _UpdateNotice();

  @override
  State<_UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<_UpdateNotice> {
  Timer? _poll;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    final now = AppUpdateService.available;
    if (now != _available && mounted) setState(() => _available = now);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final gutter = AppSpacing.pageHorizontal(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.sm),
      child: SizedBox(
        width: double.infinity,
        child: AppSurface(
          raised: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Há uma nova versão do app.', style: AppType.bodyStrong),
              const AppButton(
                label: 'Atualizar agora',
                icon: Icons.refresh,
                onPressed: AppUpdateService.apply,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const FoxIcon(size: 32),
        const SizedBox(width: 12),
        Text('Super Moderator', style: AppType.heading),
      ],
    );
  }
}

class _BotStatus extends StatelessWidget {
  const _BotStatus();

  @override
  Widget build(BuildContext context) {
    final online = context.select<BotProvider, bool>((b) => b.isConnected);
    return AppChip(
      label: online ? 'Robô online' : 'Robô offline',
      icon: online ? Icons.check_circle_outline : Icons.remove_circle_outline,
      tone: online ? AppTone.success : AppTone.danger,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 400;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding:
          EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal(context)),
      child: Row(
        children: [
          if (compact) const FoxIcon(size: 32) else const _Brand(),
          const Spacer(),
          const _BotStatus(),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final String location;
  const _BottomBar({required this.location});

  @override
  Widget build(BuildContext context) {
    final inMore = _more.any((d) => _matches(location, d));
    // Four fixed-height tabs: past 130% the labels would be clipped.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: Material(
          color: AppColors.surface,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (final d in _primary)
                    Expanded(
                      child: _BarItem(
                        icon: d.icon,
                        label: d.label,
                        active: _matches(location, d),
                        onTap: () => context.go(d.path),
                      ),
                    ),
                  Expanded(
                    child: _BarItem(
                      icon: Icons.more_horiz,
                      label: 'Mais',
                      active: inMore,
                      onTap: () => _openMore(context, location),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
  }

  void _openMore(BuildContext context, String location) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Mais', style: AppType.title),
              const SizedBox(height: 16),
              AppRowList(children: [
                for (final d in _more)
                  AppListRow(
                    raised: true,
                    selected: _matches(location, d),
                    leading: Icon(d.icon, size: 22),
                    title: d.label,
                    trailing:
                        const Icon(Icons.chevron_right, color: AppColors.muted),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.go(d.path);
                    },
                  ),
              ]),
              const SizedBox(height: 16),
              const _UserBlock(labeled: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BarItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.onAccent : AppColors.muted;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.curve,
          color: active ? AppColors.accent : Colors.transparent,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    style: AppType.label.copyWith(color: fg), maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String location;
  const _Sidebar({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppColors.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft, child: _BotStatus()),
          const SizedBox(height: 32),
          Expanded(
            child: ListView(
              children: [
                for (final d in _all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SidebarItem(dest: d, active: _matches(location, d)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _UserBlock(),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _Dest dest;
  final bool active;
  const _SidebarItem({required this.dest, required this.active});

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.onAccent : AppColors.ink;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? AppColors.accent : Colors.transparent,
        child: InkWell(
          onTap: () => context.go(dest.path),
          hoverColor: AppColors.raised,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(dest.icon, size: 20, color: fg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(dest.label,
                        style: AppType.label.copyWith(color: fg),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserBlock extends StatelessWidget {
  final bool labeled;
  const _UserBlock({this.labeled = false});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final name = user?.shownName ?? 'Usuário';
    return AppSurface(
      raised: true,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.accent,
            child: Text(
              name.isEmpty ? 'U' : name[0].toUpperCase(),
              style: AppType.label.copyWith(color: AppColors.onAccent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: AppType.label, overflow: TextOverflow.ellipsis),
                Text('@${user?.username ?? ''}',
                    style: AppType.meta, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (labeled)
            AppButton.text(
              label: 'Sair',
              icon: Icons.logout,
              onPressed: () => context.read<AuthProvider>().logout(),
            )
          else
            IconButton(
              icon: const Icon(Icons.logout, size: 20),
              tooltip: 'Sair',
              onPressed: () => context.read<AuthProvider>().logout(),
            ),
        ],
      ),
    );
  }
}
