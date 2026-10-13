import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/admin_provider.dart';

/// Read-only oversight panel - usuárias cadastradas, status do robô de cada
/// uma e sessões de moderação ativas agora. Rota própria (/admin), fora do
/// shell normal de navegação e com login PRÓPRIO (admin_accounts no
/// backend) - entrar com uma conta normal da criadora não dá acesso a isto;
/// é um usuário/senha completamente separado (ver AdminProvider). Nada aqui
/// modifica dado nenhum.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AdminProvider>().restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    if (admin.isRestoringSession) {
      return const Scaffold(
        backgroundColor: AppTheme.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (!admin.isAuthenticated) {
      return const _AdminLoginScreen();
    }
    return const _AdminPanelScaffold();
  }
}

class _AdminPanelScaffold extends StatefulWidget {
  const _AdminPanelScaffold();

  @override
  State<_AdminPanelScaffold> createState() => _AdminPanelScaffoldState();
}

class _AdminPanelScaffoldState extends State<_AdminPanelScaffold>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primary, size: 20),
            const SizedBox(width: 10),
            const Text('Painel Administrativo',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            if (admin.adminUsername != null) ...[
              const SizedBox(width: 10),
              Text('· ${admin.adminUsername}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'Atualizar',
            onPressed: admin.isLoading ? null : () => context.read<AdminProvider>().load(),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            tooltip: 'Sair do painel',
            onPressed: () => context.read<AdminProvider>().logout(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: 'Usuárias (${admin.users.length})'),
            Tab(text: 'Sessões ativas (${admin.sessions.length})'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
          child: TabBarView(
            controller: _tabController,
            children: const [_UsersTab(), _SessionsTab()],
          ),
        ),
      ),
    );
  }
}

/// Login form for the admin panel's OWN credentials (admin_accounts on the
/// backend) - never the portal's regular e-mail/senha. There is no "criar
/// conta" link here on purpose: the first (and so far only) admin account is
/// created from env vars on the server, not through this screen.
class _AdminLoginScreen extends StatefulWidget {
  const _AdminLoginScreen();

  @override
  State<_AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<_AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<AdminProvider>().login(
          _usernameController.text.trim(),
          _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textMuted),
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/dashboard'),
                      tooltip: 'Voltar',
                    ),
                  ],
                ),
                const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primary, size: 36),
                const SizedBox(height: 16),
                const Text('Painel Administrativo',
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  'Login próprio, separado da conta de criadora.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 28),
                if (admin.error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_rounded, color: AppTheme.error, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(admin.error!,
                              style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Usuário administrativo',
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                        validator: (v) => (v?.isEmpty ?? true) ? 'Campo obrigatório' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) => (v?.isEmpty ?? true) ? 'Campo obrigatório' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: admin.isLoggingIn ? null : _submit,
                          child: admin.isLoggingIn
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppTheme.onAccent),
                                )
                              : const Text('Entrar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    if (admin.isLoading && admin.users.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (admin.error != null && admin.users.isEmpty) {
      return _ErrorState(message: admin.error!, onRetry: () => context.read<AdminProvider>().load());
    }
    if (admin.users.isEmpty) {
      return const _EmptyState(
        icon: Icons.people_outline_rounded,
        text: 'Nenhuma usuária cadastrada ainda.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<AdminProvider>().load(),
      color: AppTheme.primary,
      backgroundColor: AppTheme.bgCard,
      child: ListView.builder(
        padding: AppSpacing.page(context),
        itemCount: admin.users.length,
        itemBuilder: (context, i) => _UserCard(user: admin.users[i]),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final AdminUserSummary user;
  const _UserCard({required this.user});

  (Color, IconData) _statusVisual(String status) => switch (status) {
        'ativo' => (AppTheme.success, Icons.shield_rounded),
        'aguardando' => (AppTheme.warning, Icons.hourglass_top_rounded),
        'erro' => (AppTheme.error, Icons.error_outline_rounded),
        'conectado (parado)' => (AppTheme.info, Icons.pause_circle_outline_rounded),
        _ => (AppTheme.textMuted, Icons.smart_toy_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusIcon) = _statusVisual(user.robotStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.18),
                child: Text(
                  (user.displayName ?? user.username).substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.displayName ?? user.username,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (user.isAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('admin',
                                style: TextStyle(
                                    color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    Text('@${user.username} · ${user.email}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 13, color: statusColor),
                    const SizedBox(width: 5),
                    Text(user.robotStatus,
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _MiniFact(label: 'Robô', value: user.robot?.nickname ?? '—'),
              _MiniFact(
                label: 'Favoritada',
                value: user.watchActive ? (user.watchNickname ?? 'ativa') : 'nenhuma',
              ),
              _MiniFact(label: 'Regras', value: '${user.rulesCount}'),
              _MiniFact(label: 'Mensagens', value: '${user.messagesCount}'),
              if (user.sessionLivestreamId != null)
                _MiniFact(label: 'Live atual', value: user.sessionLivestreamId!),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  final String label;
  final String value;
  const _MiniFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _SessionsTab extends StatelessWidget {
  const _SessionsTab();

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    if (admin.isLoading && admin.sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (admin.error != null && admin.sessions.isEmpty) {
      return _ErrorState(message: admin.error!, onRetry: () => context.read<AdminProvider>().load());
    }
    if (admin.sessions.isEmpty) {
      return const _EmptyState(
        icon: Icons.live_tv_outlined,
        text: 'Nenhuma sessão do robô em memória agora.\nIsso inclui sessões recém-paradas, não só as ao vivo.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<AdminProvider>().load(),
      color: AppTheme.primary,
      backgroundColor: AppTheme.bgCard,
      child: ListView.builder(
        padding: AppSpacing.page(context),
        itemCount: admin.sessions.length,
        itemBuilder: (context, i) => _SessionCard(session: admin.sessions[i]),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final AdminSessionSummary session;
  const _SessionCard({required this.session});

  (Color, String) _stateVisual(String state) => switch (state) {
        'running' => (AppTheme.success, 'Moderando ao vivo'),
        'starting' => (AppTheme.warning, 'Conectando'),
        'waiting_for_live' => (AppTheme.warning, 'Aguardando próxima live'),
        'stopping' => (AppTheme.textMuted, 'Parando'),
        'error' => (AppTheme.error, 'Erro'),
        _ => (AppTheme.info, 'Parada'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, label) = _stateVisual(session.state);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('@${session.username}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _MiniFact(label: 'Live', value: session.livestreamId ?? '—'),
              _MiniFact(label: 'Chat', value: 'conexão ${session.wsState}'),
              _MiniFact(label: 'Msgs vistas', value: '${session.chatSeen}'),
              _MiniFact(label: 'Ações', value: '${session.actionsOk}'),
              if (session.watchWaitingSeconds != null)
                _MiniFact(
                  label: 'Esperando ID novo',
                  value: '${session.watchWaitingSeconds!.round()}s',
                ),
            ],
          ),
          if (session.lastError != null) ...[
            const SizedBox(height: 10),
            Text(session.lastError!,
                style: const TextStyle(color: AppTheme.error, fontSize: 12, height: 1.3)),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.textDisabled, size: 40),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
