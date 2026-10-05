import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bot_provider.dart';
import '../common/fox_icon.dart';

class MainShell extends StatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final List<_NavItem> _navItems = [
    const _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard', path: '/dashboard'),
    const _NavItem(icon: Icons.shield_rounded, label: 'Moderação', path: '/moderation'),
    const _NavItem(icon: Icons.chat_bubble_rounded, label: 'Mensagens', path: '/messages'),
    const _NavItem(icon: Icons.smart_toy_rounded, label: 'Robô', path: '/bot'),
    const _NavItem(icon: Icons.settings_rounded, label: 'Configurações', path: '/settings'),
  ];

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _navItems.length; i++) {
      if (location.startsWith(_navItems[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Row(
        children: [
          if (isWide) _buildSidebar(context, currentIndex),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide ? null : _buildBottomNav(context, currentIndex),
    );
  }

  Widget _buildSidebar(BuildContext context, int currentIndex) {
    final botProvider = context.watch<BotProvider>();

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const FoxIcon(size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Super',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'Moderator',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bot status indicator
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: botProvider.isConnected
                        ? AppTheme.success
                        : AppTheme.error,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    botProvider.isConnected
                        ? botProvider.botProfile?.nickname ?? 'Robô conectado'
                        : 'Robô desconectado',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Nav items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _navItems.length,
              itemBuilder: (context, i) {
                final item = _navItems[i];
                final isActive = currentIndex == i;
                return _SidebarItem(
                  item: item,
                  isActive: isActive,
                  onTap: () => context.go(item.path),
                );
              },
            ),
          ),

          // User info
          const Divider(color: AppTheme.border),
          _buildUserTile(context),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildUserTile(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
            child: Text(
              (user?.displayName ?? user?.username ?? 'U')[0].toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? user?.username ?? 'Usuário',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user?.email ?? '',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 18, color: AppTheme.textMuted),
            tooltip: 'Sair',
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final (routeIcon, routeTitle) = _getRouteTitleInfo(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Icon(routeIcon, color: AppTheme.primary, size: 20),
          const SizedBox(width: 10),
          Text(
            routeTitle,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String) _getRouteTitleInfo(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/moderation')) return (Icons.shield_rounded, 'Moderação');
    if (location.startsWith('/messages')) {
      return (Icons.chat_bubble_rounded, 'Mensagens Automáticas');
    }
    if (location.startsWith('/bot')) return (Icons.smart_toy_rounded, 'Controle do Robô');
    if (location.startsWith('/settings')) return (Icons.settings_rounded, 'Configurações');
    return (Icons.dashboard_rounded, 'Dashboard');
  }

  Widget _buildBottomNav(BuildContext context, int currentIndex) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_navItems[i].path),
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.textMuted,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: _navItems
            .map((item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  const _NavItem({required this.icon, required this.label, required this.path});
}

class _SidebarItem extends StatefulWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppTheme.primary.withValues(alpha: 0.15)
                : _hovered
                    ? AppTheme.bgSurface
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.isActive
                ? Border.all(color: AppTheme.primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.item.icon,
                size: 20,
                color: widget.isActive ? AppTheme.primary : AppTheme.textMuted,
              ),
              const SizedBox(width: 12),
              Text(
                widget.item.label,
                style: TextStyle(
                  color: widget.isActive ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (widget.isActive) ...[
                const Spacer(),
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

