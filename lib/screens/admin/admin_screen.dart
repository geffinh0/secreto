import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/common/fox_icon.dart';
import '../../widgets/ui/ui.dart';

/// Oversight panel: users, agencies and active robot sessions. Own route
/// (/admin) outside the main shell, with its OWN login (admin_accounts on the
/// backend) - a regular creator account never opens it. The screen draws its
/// own frame (top bar + page) instead of using the shell.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<AdminProvider>().restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    if (admin.isRestoringSession) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: const Center(child: AppStateView.loading()),
      );
    }
    if (!admin.isAuthenticated) return const _AdminLogin();
    return const _AdminPanel();
  }
}

// ---------------------------------------------------------------- login

class _AdminLogin extends StatefulWidget {
  const _AdminLogin();

  @override
  State<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<_AdminLogin> {
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
    final gutter = AppSpacing.pageHorizontal(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              gutter, AppSpacing.md, gutter, AppSpacing.xxl),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const FoxIcon(size: 28),
                      const Spacer(),
                      AppButton.text(
                        label: 'Voltar',
                        icon: Icons.arrow_back,
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/dashboard'),
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpacing.section(context)),
                  Reveal(
                    child: Semantics(
                      header: true,
                      child: Text('Administração',
                          style: AppType.display,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Reveal(
                    index: 1,
                    child: Text(
                      'Entre com a conta de administrador. Ela é separada da conta de streamer.',
                      style: AppType.meta,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (admin.error != null) ...[
                    AppSurface(
                      raised: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              color: AppColors.danger, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(admin.error!, style: AppType.body)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          controller: _usernameController,
                          label: 'Usuário administrativo',
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'Informe o usuário.'
                              : null,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppTextField(
                          controller: _passwordController,
                          label: 'Senha',
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          suffix: IconButton(
                            tooltip: _obscurePassword
                                ? 'Mostrar senha'
                                : 'Ocultar senha',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.muted,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (v) =>
                              (v?.isEmpty ?? true) ? 'Informe a senha.' : null,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AppButton(
                          label: 'Entrar',
                          expand: true,
                          loading: admin.isLoggingIn,
                          onPressed: _submit,
                        ),
                      ],
                    ),
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

// ---------------------------------------------------------------- panel

enum _Section { users, agencies, sessions }

class _AdminPanel extends StatefulWidget {
  const _AdminPanel();

  @override
  State<_AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<_AdminPanel> {
  _Section _section = _Section.users;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    Widget chip(_Section s, String label) => AppChip(
          label: label,
          selected: _section == s,
          onTap: () => setState(() => _section = s),
        );

    final body = switch (_section) {
      _Section.users => const _UsersSection(),
      _Section.agencies => const _AgenciesSection(),
      _Section.sessions => const _SessionsSection(),
    };

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          _TopBar(admin: admin),
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
              child: AppPage(
                onRefresh: () => context.read<AdminProvider>().load(),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        chip(
                            _Section.users, 'Usuários (${admin.users.length})'),
                        chip(_Section.agencies,
                            'Agências (${admin.agencies.length})'),
                        chip(_Section.sessions,
                            'Sessões ativas (${admin.sessions.length})'),
                      ],
                    ),
                  ),
                  body,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final AdminProvider admin;
  const _TopBar({required this.admin});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal(context),
            vertical: AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
              child: Row(
                children: [
                  const FoxIcon(size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text('Administração',
                              style: AppType.heading,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (admin.adminUsername != null)
                          Text(admin.adminUsername!,
                              style: AppType.meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    color: AppColors.ink,
                    disabledColor: AppColors.muted,
                    icon: const Icon(Icons.refresh),
                    onPressed: admin.isLoading
                        ? null
                        : () => context.read<AdminProvider>().load(),
                  ),
                  AppButton.text(
                    label: 'Sair',
                    icon: Icons.logout,
                    onPressed: () => context.read<AdminProvider>().logout(),
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

// ---------------------------------------------------------------- users

class _UsersSection extends StatefulWidget {
  const _UsersSection();

  @override
  State<_UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<_UsersSection> {
  String _query = '';

  /// -1 = todas, 0 = sem agência, >0 = id da agência
  int _agencyFilter = -1;

  bool _matches(AdminUserSummary u) {
    if (_agencyFilter == 0 && u.agencyId != null) return false;
    if (_agencyFilter > 0 && u.agencyId != _agencyFilter) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return u.username.toLowerCase().contains(q) ||
        (u.displayName ?? '').toLowerCase().contains(q) ||
        (u.robot?.nickname ?? '').toLowerCase().contains(q);
  }

  (AppTone, IconData) _statusVisual(String status) => switch (status) {
        'ativo' => (AppTone.success, Icons.shield_outlined),
        'aguardando' => (AppTone.warning, Icons.hourglass_top),
        'erro' => (AppTone.danger, Icons.error_outline),
        'conectado (parado)' => (AppTone.neutral, Icons.pause_circle_outline),
        _ => (AppTone.neutral, Icons.smart_toy_outlined),
      };

  Future<void> _releaseReset(AdminUserSummary user) async {
    final confirmed = await showAppConfirm(
      context,
      title: 'Liberar troca de senha de @${user.username}?',
      message:
          'A senha atual deixa de funcionar e as sessões abertas são encerradas agora. '
          'Será gerada uma senha provisória, de uso único, para você entregar ao usuário. '
          'Ao entrar com ela, ele cria a própria senha.',
      confirmLabel: 'Gerar senha provisória',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<AdminProvider>();
    final released = await provider.releasePasswordReset(user.id);
    if (!mounted) return;
    if (released == null) {
      showAppSnack(
          context,
          provider.error ??
              'Não foi possível liberar a troca de senha. Tente de novo.',
          error: true);
      return;
    }
    await _showSecret(
      context,
      title: 'Senha provisória de @${user.username}',
      intro: 'Entregue esta senha ao usuário agora. Ela aparece só desta vez, '
          'vale para um único acesso e expira em ${released.hours} horas.',
      secret: released.password,
      copiedMessage: 'Senha copiada',
      closeLabel: 'Já anotei',
      dismissible: false,
    );
  }

  Widget _userCell(AdminUserSummary u) {
    final badges = <Widget>[
      if (u.isAdmin)
        const AppChip(
            label: 'Administrador', icon: Icons.admin_panel_settings_outlined),
      if (u.mustChangePassword)
        const AppChip(
            label: 'Troca de senha pendente',
            icon: Icons.lock_reset,
            tone: AppTone.warning),
    ];
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.raised,
          child:
              Text(_initial(u.displayName, u.username), style: AppType.label),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(u.displayName ?? u.username,
                  style: AppType.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              Text('@${u.username}',
                  style: AppType.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (badges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 8, runSpacing: 4, children: badges),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusCell(AdminUserSummary u) {
    final (tone, icon) = _statusVisual(u.robotStatus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppChip(label: _sentence(u.robotStatus), icon: icon, tone: tone),
        if (u.sessionLivestreamId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('ID da live: ${u.sessionLivestreamId}',
                style: AppType.meta),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final blocking = _dataState(
      context,
      admin,
      isEmpty: admin.users.isEmpty,
      emptyTitle: 'Nenhum usuário cadastrado',
      emptyMessage: 'Os usuários aparecem aqui assim que se cadastrarem.',
    );
    if (blocking != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const PageHeader(title: 'Usuários'), blocking],
      );
    }

    final shown = admin.users.where(_matches).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          child: PageHeader(
            title: 'Usuários',
            subtitle: '${shown.length} de ${admin.users.length} usuários',
          ),
        ),
        Reveal(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: 'Buscar usuário',
                  hint: 'Nome, usuário ou robô',
                  prefix: Icon(Icons.search, color: AppColors.muted),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    AppChip(
                      label: 'Todas as agências',
                      selected: _agencyFilter == -1,
                      onTap: () => setState(() => _agencyFilter = -1),
                    ),
                    AppChip(
                      label: 'Sem agência',
                      selected: _agencyFilter == 0,
                      onTap: () => setState(() => _agencyFilter = 0),
                    ),
                    for (final a in admin.agencies)
                      AppChip(
                        label: a.name,
                        selected: _agencyFilter == a.id,
                        onTap: () => setState(() => _agencyFilter = a.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (shown.isEmpty)
          const AppStateView(
            title: 'Nenhum usuário encontrado',
            message: 'Mude a busca ou o filtro de agência.',
          )
        else
          AppDataTable(
            breakpoint: 1000,
            columns: const [
              AppTableColumn('Usuário', flex: 4),
              AppTableColumn('Status do robô', flex: 3),
              AppTableColumn('Agência', flex: 2),
              AppTableColumn('Nome do robô', flex: 2),
              AppTableColumn('Streamer favorito', flex: 2),
              AppTableColumn('Configuração', flex: 2),
              AppTableColumn('Senha', flex: 3),
            ],
            rows: [
              for (final u in shown)
                [
                  _userCell(u),
                  _statusCell(u),
                  Text(u.agencyName ?? 'Sem agência', style: AppType.body),
                  Text(u.robot?.nickname ?? '—', style: AppType.body),
                  Text(u.watchActive ? (u.watchNickname ?? 'Ativo') : 'Nenhum',
                      style: AppType.body),
                  Text('${u.rulesCount} regras · ${u.messagesCount} mensagens',
                      style: AppType.body),
                  AppButton.text(
                    label: 'Liberar troca de senha',
                    icon: Icons.lock_reset,
                    onPressed: () => _releaseReset(u),
                  ),
                ],
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- agencies

class _AgenciesSection extends StatelessWidget {
  const _AgenciesSection();

  Future<void> _copy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (context.mounted) showAppSnack(context, 'Código copiado');
  }

  Future<void> _create(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewAgencyDialog(),
    );
    if (name == null || name.length < 2 || !context.mounted) return;
    final provider = context.read<AdminProvider>();
    final code = await provider.createAgency(name);
    if (!context.mounted) return;
    if (code != null) {
      await _showSecret(
        context,
        title: 'Agência criada',
        intro:
            'Envie este código à agência. Cada streamer o digita ao se cadastrar.',
        secret: code,
        copiedMessage: 'Código copiado',
        closeLabel: 'Fechar',
      );
    } else if (provider.error != null) {
      showAppSnack(context, provider.error!, error: true);
    }
  }

  Future<void> _rotate(BuildContext context, AdminAgency agency) async {
    final confirmed = await showAppConfirm(
      context,
      title: 'Gerar novo código para ${agency.name}?',
      message: 'O código atual deixa de funcionar para novos cadastros. '
          'Os usuários já cadastrados não são afetados.',
      confirmLabel: 'Gerar novo código',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final code =
        await context.read<AdminProvider>().rotateAgencyCode(agency.id);
    if (code != null && context.mounted) {
      await _showSecret(
        context,
        title: 'Novo código de ${agency.name}',
        intro:
            'Envie este código à agência. Cada streamer o digita ao se cadastrar.',
        secret: code,
        copiedMessage: 'Código copiado',
        closeLabel: 'Fechar',
      );
    }
  }

  Future<void> _setActive(
      BuildContext context, AdminAgency agency, bool value) async {
    final provider = context.read<AdminProvider>();
    final ok = await provider.setAgencyActive(agency.id, value);
    if (!ok && context.mounted) {
      showAppSnack(
          context,
          provider.error ??
              'Não foi possível alterar a agência. Tente de novo.',
          error: true);
    }
  }

  Widget _agencyCell(AdminAgency a, {required bool readOnly}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(a.name,
            style: AppType.bodyStrong,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        if (!readOnly && !a.active)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: AppChip(label: 'Pausada', icon: Icons.pause_circle_outline),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final cap = admin.capacity;
    final legacy = admin.noAgency;
    final legacyShown = legacy != null && legacy.usersTotal > 0;
    final total = admin.agencies.fold<int>(0, (s, a) => s + a.usersTotal) +
        (legacy?.usersTotal ?? 0);
    final empty = admin.agencies.isEmpty && !legacyShown;
    final rows = <({AdminAgency agency, bool readOnly})>[
      for (final a in admin.agencies) (agency: a, readOnly: false),
      if (legacyShown) (agency: legacy, readOnly: true),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          child: PageHeader(
            title: 'Agências',
            subtitle: '$total usuários em ${admin.agencies.length} agências',
            actions: [
              AppButton(
                label: 'Criar agência',
                icon: Icons.add,
                onPressed: () => _create(context),
              ),
            ],
          ),
        ),
        if (cap != null)
          Reveal(
            index: 1,
            child: AppSection(
                title: 'Capacidade', child: _CapacityBlock(capacity: cap)),
          ),
        if (empty)
          _dataState(
                context,
                admin,
                isEmpty: true,
                emptyTitle: 'Nenhuma agência ainda',
                emptyMessage: 'Crie uma agência e envie o código a ela. '
                    'Só quem tem um código consegue se cadastrar.',
              ) ??
              const SizedBox.shrink()
        else
          AppDataTable(
            breakpoint: 1000,
            columns: const [
              AppTableColumn('Agência', flex: 3),
              AppTableColumn('Aceita cadastros', flex: 2),
              AppTableColumn('Código', flex: 2),
              AppTableColumn('Cadastrados'),
              AppTableColumn('Com robô'),
              AppTableColumn('Favorito ligado'),
              AppTableColumn('Moderando agora'),
              AppTableColumn('Código de cadastro', flex: 3),
            ],
            rows: [
              for (final r in rows)
                [
                  _agencyCell(r.agency, readOnly: r.readOnly),
                  r.readOnly
                      ? Text('—', style: AppType.body)
                      : AppSwitch(
                          value: r.agency.active,
                          semanticLabel:
                              'Aceitar cadastros de ${r.agency.name}',
                          onChanged: (v) => _setActive(context, r.agency, v),
                        ),
                  r.readOnly
                      ? Text('—', style: AppType.body)
                      : SelectableText(r.agency.code,
                          style: AppType.bodyStrong),
                  Text('${r.agency.usersTotal}', style: AppType.body),
                  Text('${r.agency.withRobot}', style: AppType.body),
                  Text('${r.agency.watching}', style: AppType.body),
                  Text('${r.agency.runningNow}', style: AppType.body),
                  r.readOnly
                      ? Text('—', style: AppType.body)
                      : Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: [
                            AppButton.text(
                              label: 'Copiar código',
                              icon: Icons.copy,
                              onPressed: () => _copy(context, r.agency.code),
                            ),
                            AppButton.text(
                              label: 'Gerar novo código',
                              icon: Icons.autorenew,
                              onPressed: () => _rotate(context, r.agency),
                            ),
                          ],
                        ),
                ],
            ],
          ),
      ],
    );
  }
}

class _CapacityBlock extends StatelessWidget {
  final AdminCapacity capacity;
  const _CapacityBlock({required this.capacity});

  @override
  Widget build(BuildContext context) {
    final seatsFree = capacity.seatsTotal - capacity.seatsUsed;
    final noSeats = capacity.seatsTotal > 0 && seatsFree <= 0;
    final anyDown = capacity.slots.any((s) => s.networkDown);
    final overloaded = capacity.deepestQueue > 20 ||
        (capacity.maxSessions > 0 &&
            capacity.activeSessions >= capacity.maxSessions);
    final Widget status;
    if (anyDown) {
      status = const AppChip(
          label: 'Um IP não está respondendo',
          icon: Icons.error_outline,
          tone: AppTone.danger);
    } else if (noSeats) {
      status = const AppChip(
          label: 'Sem vagas: adicione um IP',
          icon: Icons.warning_amber,
          tone: AppTone.warning);
    } else if (overloaded) {
      status = const AppChip(
          label: 'Capacidade no limite',
          icon: Icons.warning_amber,
          tone: AppTone.warning);
    } else {
      status = const AppChip(
          label: 'Tudo normal',
          icon: Icons.check_circle_outline,
          tone: AppTone.success);
    }
    return AppSurface(
      raised: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          status,
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.lg,
            children: [
              _Fact(label: 'IPs de saída', value: '${capacity.egressCount}'),
              if (capacity.seatsTotal > 0)
                _Fact(
                  label: 'Vagas livres',
                  value: '${seatsFree < 0 ? 0 : seatsFree} de ${capacity.seatsTotal}',
                ),
              _Fact(
                label: 'Lives agora',
                value: capacity.maxSessions > 0
                    ? '${capacity.activeSessions} / ${capacity.maxSessions}'
                    : '${capacity.activeSessions}',
              ),
              _Fact(
                  label: 'Fila mais longa', value: '${capacity.deepestQueue}'),
              _Fact(
                  label: 'Detecção de live',
                  value: 'até ${capacity.slowestPollSeconds}s'),
            ],
          ),
          if (capacity.slots.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            for (final slot in capacity.slots)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('IP ${slot.slot + 1}', style: AppType.bodyStrong),
                    Text(
                      '${slot.users}${slot.maxUsers > 0 ? ' de ${slot.maxUsers}' : ''} criadoras'
                      ' · ${slot.activeSessions} robôs ligados',
                      style: AppType.body,
                    ),
                    slot.networkDown
                        ? const AppChip(
                            label: 'Sem resposta',
                            icon: Icons.error_outline,
                            tone: AppTone.danger)
                        : slot.full
                            ? const AppChip(label: 'Lotado', icon: Icons.group)
                            : const AppChip(
                                label: 'Rede ok',
                                icon: Icons.check_circle_outline,
                                tone: AppTone.success),
                  ],
                ),
              ),
          ],
          if (noSeats || anyDown) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              anyDown
                  ? 'Um IP sem resposta costuma ser o proxy fora do ar: confira o painel do fornecedor.'
                  : 'Para liberar mais vagas, contrate mais um IP fixo brasileiro e use o botão "Adicionar IP".',
              style: AppType.meta,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: 'Adicionar IP',
            icon: Icons.add,
            onPressed: () => _addEgress(context),
          ),
        ],
      ),
    );
  }
}

Future<void> _addEgress(BuildContext context) async {
  final provider = context.read<AdminProvider>();
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddEgressDialog(provider: provider),
  );
  if (result == null || !context.mounted) return;
  final country = (result['country'] ?? '').toString();
  showAppSnack(
      context,
      'IP adicionado${country.isEmpty ? '' : ' ($country)'}. Mais vagas liberadas.');
  final warning = result['warning'];
  if (warning is String && warning.isNotEmpty) {
    showAppSnack(context, warning, error: true);
  }
}

/// Owns its controller and does the call itself, so it can show progress and the server's
/// refusal ("não consegui conectar...") without closing.
class _AddEgressDialog extends StatefulWidget {
  final AdminProvider provider;
  const _AddEgressDialog({required this.provider});

  @override
  State<_AddEgressDialog> createState() => _AddEgressDialogState();
}

class _AddEgressDialogState extends State<_AddEgressDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.length < 8) {
      setState(() => _error = 'Cole o endereço completo do proxy.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.provider.addEgress(url);
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      setState(() {
        _busy = false;
        _error = widget.provider.error ?? 'Não foi possível adicionar o IP.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: 'Adicionar IP',
      actions: [
        AppButton.secondary(
            label: 'Cancelar',
            onPressed: _busy ? null : () => Navigator.of(context).pop()),
        AppButton(
          label: 'Testar e adicionar',
          loading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
      children: [
        Text(
          'Cole o endereço do proxy fixo brasileiro. O sistema testa a conexão com o '
          'SuperLive antes de aceitar. Cada IP libera mais vagas de criadoras. '
          'Depois de adicionado, ele não pode ser removido nem trocado de posição.',
          style: AppType.body,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _controller,
          label: 'Endereço do proxy',
          hint: 'socks5h://usuario:senha@host:porta',
          helper: 'Se a senha tiver @ : / # ou %, troque pelo código %40 %3A %2F %23 %25.',
          errorText: _error,
          autofocus: true,
          enabled: !_busy,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact({required this.label, required this.value});

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

/// Owns its TextEditingController: disposing one from the caller, right after
/// showDialog returns, breaks the dialog's exit animation.
class _NewAgencyDialog extends StatefulWidget {
  const _NewAgencyDialog();

  @override
  State<_NewAgencyDialog> createState() => _NewAgencyDialogState();
}

class _NewAgencyDialogState extends State<_NewAgencyDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: 'Nova agência',
      actions: [
        AppButton.secondary(
            label: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
        AppButton(
          label: 'Criar agência',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
      children: [
        AppTextField(
          controller: _controller,
          label: 'Nome da agência',
          autofocus: true,
          maxLength: 80,
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- sessions

class _SessionsSection extends StatelessWidget {
  const _SessionsSection();

  (AppTone, IconData, String) _stateVisual(String state) => switch (state) {
        'running' => (
            AppTone.success,
            Icons.check_circle_outline,
            'Moderando ao vivo'
          ),
        'starting' => (AppTone.warning, Icons.hourglass_top, 'Conectando'),
        'waiting_for_live' => (
            AppTone.warning,
            Icons.schedule,
            'Aguardando próxima live'
          ),
        'stopping' => (AppTone.neutral, Icons.pause_circle_outline, 'Parando'),
        'error' => (AppTone.danger, Icons.error_outline, 'Erro'),
        _ => (AppTone.neutral, Icons.stop_circle_outlined, 'Parada'),
      };

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final blocking = _dataState(
      context,
      admin,
      isEmpty: admin.sessions.isEmpty,
      emptyTitle: 'Nenhuma sessão de robô agora',
      emptyMessage: 'A lista inclui sessões recém-paradas, não só as ao vivo.',
    );
    if (blocking != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const PageHeader(title: 'Sessões ativas'), blocking],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Reveal(
          child: PageHeader(
            title: 'Sessões ativas',
            subtitle: 'Inclui sessões recém-paradas.',
          ),
        ),
        AppDataTable(
          columns: const [
            AppTableColumn('Usuário', flex: 2),
            AppTableColumn('Estado', flex: 3),
            AppTableColumn('ID da live', flex: 2),
            AppTableColumn('Chat', flex: 2),
            AppTableColumn('Mensagens vistas'),
            AppTableColumn('Ações'),
            AppTableColumn('Espera por ID novo'),
            AppTableColumn('Último erro', flex: 3),
          ],
          rows: [
            for (final s in admin.sessions)
              () {
                final (tone, icon, label) = _stateVisual(s.state);
                return <Widget>[
                  Text('@${s.username}',
                      style: AppType.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  AppChip(label: label, icon: icon, tone: tone),
                  Text(s.livestreamId ?? '—', style: AppType.body),
                  Text('Conexão ${s.wsState}', style: AppType.body),
                  Text('${s.chatSeen}', style: AppType.body),
                  Text('${s.actionsOk}', style: AppType.body),
                  Text(
                      s.watchWaitingSeconds == null
                          ? '—'
                          : '${s.watchWaitingSeconds!.round()}s',
                      style: AppType.body),
                  s.lastError == null
                      ? Text('—', style: AppType.body)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.error_outline,
                                  color: AppColors.danger, size: 18),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(s.lastError!, style: AppType.body)),
                          ],
                        ),
                ];
              }(),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- shared

String _initial(String? displayName, String username) {
  final trimmedDisplayName = displayName?.trim() ?? '';
  final label =
      trimmedDisplayName.isNotEmpty ? trimmedDisplayName : username.trim();
  return label.isNotEmpty ? label.substring(0, 1).toUpperCase() : '?';
}

String _sentence(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Loading / error / empty block for a list, or null when there is data.
Widget? _dataState(
  BuildContext context,
  AdminProvider admin, {
  required bool isEmpty,
  required String emptyTitle,
  required String emptyMessage,
}) {
  if (admin.isLoading && isEmpty) return const AppStateView.loading();
  if (admin.error != null && isEmpty) {
    return AppStateView(
      kind: AppStateKind.error,
      title: 'Não foi possível carregar',
      message: admin.error,
      actionLabel: 'Tentar de novo',
      onAction: () => context.read<AdminProvider>().load(),
    );
  }
  if (isEmpty) return AppStateView(title: emptyTitle, message: emptyMessage);
  return null;
}

class _DialogFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  const _DialogFrame(
      {required this.title, required this.children, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppType.title),
              const SizedBox(height: AppSpacing.md),
              ...children,
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a value the admin must hand over (temporary password, agency code)
/// with copy + close.
Future<void> _showSecret(
  BuildContext context, {
  required String title,
  required String intro,
  required String secret,
  required String copiedMessage,
  required String closeLabel,
  bool dismissible = true,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: dismissible,
    builder: (ctx) => _DialogFrame(
      title: title,
      actions: [
        AppButton.secondary(
          label: 'Copiar',
          icon: Icons.copy,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: secret));
            if (ctx.mounted) showAppSnack(ctx, copiedMessage);
          },
        ),
        AppButton(label: closeLabel, onPressed: () => Navigator.of(ctx).pop()),
      ],
      children: [
        Text(intro, style: AppType.body),
        const SizedBox(height: AppSpacing.md),
        AppSurface(
          raised: true,
          child: SelectableText(secret, style: AppType.title),
        ),
      ],
    ),
  );
}
