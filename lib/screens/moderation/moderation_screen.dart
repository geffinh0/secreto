import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../providers/moderation_provider.dart';
import '../../widgets/ui/ui.dart';

enum _StatusFilter { all, active, inactive }

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  final _keywordController = TextEditingController();
  String _action = 'mute';
  String _query = '';
  _StatusFilter _status = _StatusFilter.all;
  bool _isAdding = false;

  bool get _isMute => _action == 'mute';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    context.read<ModerationProvider>().loadRules(user.id);
    context.read<AutoMessageProvider>().load(user.id);
  }

  Future<void> _addRule() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final mod = context.read<ModerationProvider>();

    setState(() => _isAdding = true);
    final success = await mod.addRule(
      userId: user.id,
      keyword: keyword,
      action: _action,
    );
    if (!mounted) return;
    setState(() => _isAdding = false);

    if (success) {
      _keywordController.clear();
    } else {
      showAppSnack(
        context,
        mod.error ?? 'Não foi possível adicionar a palavra. Tente de novo.',
        error: true,
      );
    }
  }

  Future<void> _confirmDelete(ModerationRule rule) async {
    final effect = _isMute
        ? 'O robô deixa de silenciar quem usar essa palavra.'
        : 'O robô deixa de banir quem usar essa palavra.';
    final ok = await showAppConfirm(
      context,
      title: 'Remover palavra',
      message: 'A palavra "${rule.keyword}" sai da lista. $effect '
          'Para voltar a usar, adicione de novo.',
      confirmLabel: 'Remover palavra',
      destructive: true,
    );
    if (ok && mounted) {
      context.read<ModerationProvider>().deleteRule(rule.id!);
    }
  }

  List<ModerationRule> _visible(List<ModerationRule> rules) {
    final q = _query.trim().toLowerCase();
    return rules.where((r) {
      if (q.isNotEmpty && !r.keyword.toLowerCase().contains(q)) return false;
      switch (_status) {
        case _StatusFilter.all:
          return true;
        case _StatusFilter.active:
          return r.isActive;
        case _StatusFilter.inactive:
          return !r.isActive;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final mod = context.watch<ModerationProvider>();
    final rules = _isMute ? mod.muteRules : mod.kickRules;

    final actionChips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AppChip(
          label: 'Silenciar (${mod.muteRules.length})',
          icon: Icons.volume_off_outlined,
          selected: _isMute,
          onTap: () => setState(() => _action = 'mute'),
        ),
        AppChip(
          label: 'Banir (${mod.kickRules.length})',
          icon: Icons.block,
          selected: !_isMute,
          onTap: () => setState(() => _action = 'kick'),
        ),
      ],
    );

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          index: 1,
          child: AppSection(
            child: _AddWordBlock(
              controller: _keywordController,
              isMute: _isMute,
              loading: _isAdding,
              onAdd: _addRule,
            ),
          ),
        ),
        Reveal(
          index: 2,
          child: AppSection(
            title: _countTitle(rules.length),
            last: true,
            child: _RuleList(
              loading: mod.isLoading,
              total: rules.length,
              rules: _visible(rules),
              isMute: _isMute,
              status: _status,
              onQuery: (v) => setState(() => _query = v),
              onStatus: (s) => setState(() => _status = s),
              onToggle: (r) => context.read<ModerationProvider>().toggleRule(r),
              onDelete: _confirmDelete,
            ),
          ),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Reveal(
          index: 3,
          child: AppSection(
            title: 'Como o robô aplica',
            child: _OptionsBlock(),
          ),
        ),
        Reveal(
          index: 4,
          child: AppSection(
            title: 'Testar regras',
            last: true,
            child: _TesterBlock(),
          ),
        ),
      ],
    );

    return AppPage(
      onRefresh: _load,
      children: [
        const Reveal(
          child: PageHeader(
            title: 'Moderação',
            subtitle: 'Palavras que o robô silencia ou bane no chat da live.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: actionChips,
        ),
        AppSplit(primary: left, secondary: right, ratio: 0.62),
      ],
    );
  }

  String _countTitle(int n) {
    final verb = _isMute ? 'para silenciar' : 'para banir';
    return '$n ${n == 1 ? "palavra" : "palavras"} $verb';
  }
}

class _AddWordBlock extends StatelessWidget {
  final TextEditingController controller;
  final bool isMute;
  final bool loading;
  final VoidCallback onAdd;

  const _AddWordBlock({
    required this.controller,
    required this.isMute,
    required this.loading,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final compact = AppSpacing.isCompact(context);
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppButton(
          label: 'Adicionar palavra',
          icon: Icons.add,
          loading: loading,
          expand: compact,
          onPressed: onAdd,
        ),
        AppButton.text(
          label: 'Adicionar várias',
          icon: Icons.playlist_add,
          expand: compact,
          onPressed: () => showDialog(
            context: context,
            builder: (_) => _BulkImportDialog(action: isMute ? 'mute' : 'kick'),
          ),
        ),
      ],
    );

    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: controller,
            label: isMute ? 'Palavra para silenciar' : 'Palavra para banir',
            hint: isMute ? 'Exemplo: xingamento' : 'Exemplo: spam',
            helper: 'A palavra vale inteira, sem diferenciar maiúsculas nem '
                'acentos. Use * no fim para pegar variações, como puta*.',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAdd(),
          ),
          const SizedBox(height: 16),
          buttons,
        ],
      ),
    );
  }
}

class _RuleList extends StatelessWidget {
  final bool loading;
  final int total;
  final List<ModerationRule> rules;
  final bool isMute;
  final _StatusFilter status;
  final ValueChanged<String> onQuery;
  final ValueChanged<_StatusFilter> onStatus;
  final ValueChanged<ModerationRule> onToggle;
  final ValueChanged<ModerationRule> onDelete;

  const _RuleList({
    required this.loading,
    required this.total,
    required this.rules,
    required this.isMute,
    required this.status,
    required this.onQuery,
    required this.onStatus,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const AppStateView.loading(message: 'Carregando palavras');
    }
    if (total == 0) {
      return AppStateView(
        pose: FoxPose.sleeping,
        title: 'Nenhuma palavra cadastrada',
        message: isMute
            ? 'Adicione uma palavra acima para o robô começar a silenciar.'
            : 'Adicione uma palavra acima para o robô começar a banir.',
      );
    }

    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AppChip(
          label: 'Todas',
          selected: status == _StatusFilter.all,
          onTap: () => onStatus(_StatusFilter.all),
        ),
        AppChip(
          label: 'Ativas',
          icon: Icons.check_circle_outline,
          selected: status == _StatusFilter.active,
          onTap: () => onStatus(_StatusFilter.active),
        ),
        AppChip(
          label: 'Desativadas',
          icon: Icons.pause_circle_outline,
          selected: status == _StatusFilter.inactive,
          onTap: () => onStatus(_StatusFilter.inactive),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Buscar palavra',
          hint: 'Digite parte da palavra',
          prefix: const Icon(Icons.search),
          onChanged: onQuery,
        ),
        const SizedBox(height: 12),
        filters,
        const SizedBox(height: 16),
        if (rules.isEmpty)
          const AppStateView(
            title: 'Nenhuma palavra encontrada',
            message: 'Mude a busca ou o filtro para ver outras palavras.',
          )
        else
          AppRowList(
            children: [
              for (final rule in rules)
                _RuleRow(
                  key: ValueKey('rule-${rule.id}'),
                  rule: rule,
                  onToggle: () => onToggle(rule),
                  onDelete: () => onDelete(rule),
                ),
            ],
          ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  final ModerationRule rule;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _RuleRow({
    super.key,
    required this.rule,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final active = rule.isActive;
    return AppListRow(
      leading: Icon(
        active ? Icons.check_circle_outline : Icons.pause_circle_outline,
        size: 20,
        color: active ? AppColors.success : AppColors.muted,
      ),
      title: rule.keyword,
      subtitle: active ? 'Ativa' : 'Desativada',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSwitch(
            value: active,
            semanticLabel: 'Ativar ${rule.keyword}',
            onChanged: (_) => onToggle(),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppColors.danger),
            tooltip: 'Remover ${rule.keyword}',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Switches that change how the robot applies the rules. Saved right away and
/// picked up by a running live within a few seconds.
class _OptionsBlock extends StatefulWidget {
  const _OptionsBlock();

  @override
  State<_OptionsBlock> createState() => _OptionsBlockState();
}

class _OptionsBlockState extends State<_OptionsBlock> {
  final _thresholdController = TextEditingController();
  final _thresholdFocus = FocusNode();
  // -1 (not a valid threshold) so the very first build always seeds the
  // field's text, even when the real value already equals the default.
  int _lastKnownThreshold = -1;

  @override
  void initState() {
    super.initState();
    _thresholdFocus.addListener(() {
      if (!_thresholdFocus.hasFocus) _saveThreshold();
    });
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _thresholdFocus.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> changes) async {
    final user = context.read<AuthProvider>().user;
    final provider = context.read<AutoMessageProvider>();
    if (user == null) return;
    final ok = await provider.saveSettings(user.id, changes);
    if (!ok && mounted) {
      showAppSnack(
        context,
        provider.error ?? 'Não foi possível salvar. Tente de novo.',
        error: true,
      );
    }
  }

  void _saveThreshold() {
    final parsed = int.tryParse(_thresholdController.text.trim());
    final value =
        (parsed == null || parsed < BotSettings.minDiamondImmunityThreshold)
            ? BotSettings.minDiamondImmunityThreshold
            : parsed;
    _thresholdController.text = '$value';
    if (value == _lastKnownThreshold) return;
    _lastKnownThreshold = value;
    _save({'diamond_immunity_threshold': value});
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AutoMessageProvider>().settings;
    final enabled = settings?.moderationEnabled ?? true;
    final permanent = settings?.kickPermanent ?? false;
    final immunity = settings?.diamondImmunityEnabled ?? false;
    final threshold = settings?.diamondImmunityThreshold ??
        BotSettings.minDiamondImmunityThreshold;
    if (threshold != _lastKnownThreshold && !_thresholdFocus.hasFocus) {
      _lastKnownThreshold = threshold;
      _thresholdController.text = '$threshold';
    }

    return AppSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSwitchRow(
            title: 'Moderação automática',
            subtitle:
                'Desligada, o robô só observa o chat e não silencia nem bane ninguém.',
            value: enabled,
            onChanged: (v) => _save({'moderation_enabled': v}),
          ),
          const SizedBox(height: 8),
          AppSwitchRow(
            title: 'Banimento permanente',
            subtitle:
                'Ao banir, remove o usuário de forma permanente, e não só '
                'nesta live. Cuidado com palavras que peguem mensagens normais.',
            value: permanent,
            onChanged: (v) => _save({'kick_permanent': v}),
          ),
          const SizedBox(height: 8),
          AppSwitchRow(
            title: 'Imunidade por diamantes',
            subtitle: 'Quem já enviou diamantes suficientes nesta live não é '
                'silenciado nem banido, mesmo usando uma palavra da lista.',
            value: immunity,
            onChanged: (v) => _save({'diamond_immunity_enabled': v}),
          ),
          if (immunity) ...[
            const SizedBox(height: 16),
            AppTextField(
              controller: _thresholdController,
              focusNode: _thresholdFocus,
              label: 'Diamantes mínimos na live para ficar imune',
              helper: 'Mínimo: ${BotSettings.minDiamondImmunityThreshold}',
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _saveThreshold(),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Entry point to the phrase tester and the rules help. Both open over the
/// page so the list never resizes under the keyboard.
class _TesterBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Veja se uma mensagem de exemplo seria pega por alguma regra ativa, '
            'antes de confiar nela ao vivo.',
            style: AppType.body,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton.secondary(
                label: 'Testar uma frase',
                icon: Icons.science_outlined,
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: AppColors.surface,
                  shape: const RoundedRectangleBorder(),
                  builder: (_) => const _PhraseTesterSheet(),
                ),
              ),
              AppButton.text(
                label: 'Como as regras funcionam',
                icon: Icons.help_outline,
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _RulesHelpDialog(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhraseTesterSheet extends StatefulWidget {
  const _PhraseTesterSheet();

  @override
  State<_PhraseTesterSheet> createState() => _PhraseTesterSheetState();
}

class _PhraseTesterSheetState extends State<_PhraseTesterSheet> {
  final _textController = TextEditingController();
  bool _testing = false;
  PhraseTestResult? _result;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    final provider = context.read<ModerationProvider>();
    final result = await provider.testPhrase(userId: user.id, text: text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
    if (result == null) {
      showAppSnack(context,
          provider.error ?? 'Não foi possível testar a frase. Tente de novo.',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Testar uma frase', style: AppType.title),
          const SizedBox(height: 8),
          Text(
            'Digite uma mensagem de exemplo. O teste também pega número no '
            'lugar de letra e letra repetida.',
            style: AppType.meta,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _textController,
            label: 'Mensagem de exemplo',
            hint: 'Exemplo: g0z4 gostoso',
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _test(),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Testar frase',
            loading: _testing,
            expand: true,
            onPressed: _test,
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            _TestResult(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _TestResult extends StatelessWidget {
  final PhraseTestResult result;
  const _TestResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String text;
    if (!result.matched) {
      icon = Icons.check_circle_outline;
      color = AppColors.success;
      text = 'Nenhuma regra ativa pegaria essa frase.';
    } else if (result.action == 'kick') {
      icon = Icons.block;
      color = AppColors.danger;
      text = 'O robô baniria: bateu na regra "${result.keyword}".';
    } else {
      icon = Icons.volume_off_outlined;
      color = AppColors.warning;
      text = 'O robô silenciaria: bateu na regra "${result.keyword}".';
    }
    return AppSurface(
      raised: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppType.bodyStrong)),
        ],
      ),
    );
  }
}

class _RulesHelpDialog extends StatelessWidget {
  const _RulesHelpDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Como as regras funcionam', style: AppType.title),
              const SizedBox(height: 16),
              const Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HelpItem(
                        title: 'Asterisco no fim (ex.: puta*)',
                        body: 'Pega a palavra e qualquer coisa colada depois '
                            'dela ("putaria", "putasso"). Sem o *, só a '
                            'palavra inteira conta.',
                      ),
                      _HelpItem(
                        title: 'Palavras compostas',
                        body: 'Uma regra "passa zap" também pega "passazap", '
                            '"passa-zap", "passa_zap" e "passa.zap".',
                      ),
                      _HelpItem(
                        title: 'Número no lugar de letra',
                        body:
                            '0 vira o, 1 vira i, 3 vira e, 4 vira a, 5 vira s, '
                            '7 vira t, 8 vira b, 9 vira g, @ vira a, \$ vira s, '
                            '+ vira t e | vira i. "g0z4" é reconhecido como '
                            '"goza"; uma regra só cobre as grafias disfarçadas.',
                      ),
                      _HelpItem(
                        title: 'Letra esticada (ex.: gozzzaaa)',
                        body: 'Três ou mais letras iguais em sequência contam '
                            'como uma só antes de comparar. "goooza" também é '
                            'pego.',
                      ),
                      _HelpItem(
                        title: 'Regra com número (ex.: d4)',
                        body: 'Se a própria palavra tem número ou símbolo, só '
                            'pega quem digitar exatamente assim. Então "d4" '
                            'não pega quem escreve "amei da live".',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton.secondary(
                  label: 'Fechar',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  final String title;
  final String body;
  const _HelpItem({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppType.bodyStrong),
          const SizedBox(height: 4),
          Text(body, style: AppType.meta),
        ],
      ),
    );
  }
}

class _BulkImportDialog extends StatefulWidget {
  final String action;
  const _BulkImportDialog({required this.action});

  @override
  State<_BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<_BulkImportDialog> {
  final _textController = TextEditingController();
  bool _saving = false;
  BulkRuleResult? _result;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final keywords = _textController.text
        .split(RegExp(r'[\n,]'))
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
    if (keywords.isEmpty) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    setState(() => _saving = true);
    final provider = context.read<ModerationProvider>();
    final result = await provider.addRulesBulk(
      userId: user.id,
      action: widget.action,
      keywords: keywords,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _result = result;
    });
    if (result == null) {
      showAppSnack(
          context,
          provider.error ??
              'Não foi possível adicionar as palavras. Tente de novo.',
          error: true);
    }
  }

  String _summary(BulkRuleResult r) {
    final created = r.created.length;
    final skipped = r.skipped.length;
    final a = '$created ${created == 1 ? "adicionada" : "adicionadas"}';
    if (skipped == 0) return '$a.';
    return '$a, $skipped ${skipped == 1 ? "ignorada" : "ignoradas"}.';
  }

  @override
  Widget build(BuildContext context) {
    final isMute = widget.action == 'mute';
    final result = _result;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMute
                    ? 'Adicionar várias para silenciar'
                    : 'Adicionar várias para banir',
                style: AppType.title,
              ),
              const SizedBox(height: 8),
              Text(
                'Uma palavra por linha ou separadas por vírgula. Palavras já '
                'cadastradas e repetidas são ignoradas.',
                style: AppType.meta,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _textController,
                label: 'Palavras',
                hint: 'feia\nchata\nmal educada',
                minLines: 4,
                maxLines: 6,
              ),
              if (result != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      result.created.isNotEmpty
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 20,
                      color: result.created.isNotEmpty
                          ? AppColors.success
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_summary(result), style: AppType.bodyStrong),
                    ),
                  ],
                ),
                for (final s in result.skipped)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('"${s.keyword}": ${s.reason}',
                        style: AppType.meta),
                  ),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  AppButton.secondary(
                    label: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                  ),
                  AppButton(
                    label: 'Adicionar palavras',
                    loading: _saving,
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
