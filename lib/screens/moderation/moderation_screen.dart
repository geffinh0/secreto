import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../providers/moderation_provider.dart';

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRules());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      context.read<ModerationProvider>().loadRules(user.id);
      context.read<AutoMessageProvider>().load(user.id); // moderation options
    }
  }

  @override
  Widget build(BuildContext context) {
    final mod = context.watch<ModerationProvider>();

    return Column(
      children: [
        // Tab bar
        Container(
          color: AppTheme.bgCard,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.primary,
            indicatorWeight: 2,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [
              Tab(
                icon: const Icon(Icons.volume_off_rounded, size: 18),
                text: 'Silenciar (${mod.muteRules.length})',
              ),
              Tab(
                icon: const Icon(Icons.block_rounded, size: 18),
                text: 'Banir (${mod.kickRules.length})',
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RulesTab(action: 'mute', rules: mod.muteRules),
              _RulesTab(action: 'kick', rules: mod.kickRules),
            ],
          ),
        ),
      ],
    );
  }
}

class _RulesTab extends StatefulWidget {
  final String action;
  final List<ModerationRule> rules;

  const _RulesTab({required this.action, required this.rules});

  @override
  State<_RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends State<_RulesTab> {
  final _keywordController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
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
      action: widget.action,
    );
    if (!mounted) return;
    setState(() => _isAdding = false);

    if (success) {
      _keywordController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mod.error ?? 'Erro ao adicionar regra'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mod = context.watch<ModerationProvider>();
    final isMute = widget.action == 'mute';
    final color = isMute ? AppTheme.warning : AppTheme.error;
    final actionLabel = isMute ? 'Silenciar' : 'Banir';
    final description = isMute
        ? 'Palavras que irão silenciar o usuário no chat da live.'
        : 'Palavras que irão banir o usuário da live.';

    return RefreshIndicator(
      onRefresh: () async {
        final user = context.read<AuthProvider>().user;
        if (user != null) context.read<ModerationProvider>().loadRules(user.id);
      },
      color: AppTheme.primary,
      backgroundColor: AppTheme.bgCard,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isMute
                              ? Icons.volume_off_rounded
                              : Icons.block_rounded,
                          color: color,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Palavras para $actionLabel',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                description,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'A palavra é comparada inteira, sem diferenciar maiúsculas '
                                'nem acentos. Use * no fim para pegar variações (ex.: puta*).',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const _ModerationOptionsCard(),
                  const SizedBox(height: 20),

                  // Add keyword form
                  _AddKeywordForm(
                    controller: _keywordController,
                    onAdd: _addRule,
                    isLoading: _isAdding,
                    action: widget.action,
                    color: color,
                  ),
                  const SizedBox(height: 24),

                  Text(
                    '${widget.rules.length} palavra${widget.rules.length != 1 ? "s" : ""} cadastrada${widget.rules.length != 1 ? "s" : ""}',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          if (mod.isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            )
          else if (widget.rules.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isMute ? Icons.volume_off_rounded : Icons.block_rounded,
                      color: AppTheme.textDisabled,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Nenhuma palavra cadastrada',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Adicione palavras acima para ativar a moderação',
                      style: TextStyle(
                          color: AppTheme.textDisabled, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final rule = widget.rules[index];
                    return _RuleItem(
                      rule: rule,
                      color: color,
                      onDelete: () =>
                          context.read<ModerationProvider>().deleteRule(rule.id!),
                      onToggle: () =>
                          context.read<ModerationProvider>().toggleRule(rule),
                    );
                  },
                  childCount: widget.rules.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddKeywordForm extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAdd;
  final bool isLoading;
  final String action;
  final Color color;

  const _AddKeywordForm({
    required this.controller,
    required this.onAdd,
    required this.isLoading,
    required this.action,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adicionar palavra',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText:
                        action == 'mute' ? 'Ex: xingamento' : 'Ex: spam',
                    prefixIcon: const Icon(Icons.add_rounded),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: AppTheme.bgSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: color),
                    ),
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: isLoading ? null : onAdd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Adicionar',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  final ModerationRule rule;
  final Color color;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _RuleItem({
    required this.rule,
    required this.color,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: rule.isActive ? color.withValues(alpha: 0.25) : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          // Keyword chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: rule.isActive
                  ? color.withValues(alpha: 0.12)
                  : AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rule.keyword,
              style: TextStyle(
                color: rule.isActive ? color : AppTheme.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),

          // Active toggle
          Switch(
            value: rule.isActive,
            onChanged: (_) => onToggle(),
            activeTrackColor: color,
          ),

          // Delete button
          IconButton(
            icon: const Icon(Icons.delete_rounded, size: 18),
            color: AppTheme.textMuted,
            tooltip: 'Remover',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remover palavra?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
        content: Text(
          'Deseja remover a palavra "${rule.keyword}" das regras de moderação?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: const Text('Remover',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

/// The switches that change how the robot applies the rules. They are saved
/// right away and picked up by a running live within a few seconds.
class _ModerationOptionsCard extends StatefulWidget {
  const _ModerationOptionsCard();

  @override
  State<_ModerationOptionsCard> createState() => _ModerationOptionsCardState();
}

class _ModerationOptionsCardState extends State<_ModerationOptionsCard> {
  final _thresholdController = TextEditingController();
  final _thresholdFocus = FocusNode();
  // -1 (not a valid threshold) so the very first build always seeds the
  // field's text, even when the real value already equals the default.
  int _lastKnownThreshold = -1;

  @override
  void dispose() {
    _thresholdController.dispose();
    _thresholdFocus.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext context, Map<String, dynamic> changes) async {
    final user = context.read<AuthProvider>().user;
    final provider = context.read<AutoMessageProvider>();
    if (user == null) return;
    final ok = await provider.saveSettings(user.id, changes);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Erro ao salvar'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _saveThreshold(BuildContext context) {
    final parsed = int.tryParse(_thresholdController.text.trim());
    final value = (parsed == null || parsed < BotSettings.minDiamondImmunityThreshold)
        ? BotSettings.minDiamondImmunityThreshold
        : parsed;
    _thresholdController.text = '$value';
    if (value == _lastKnownThreshold) return;
    _lastKnownThreshold = value;
    _save(context, {'diamond_immunity_threshold': value});
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AutoMessageProvider>().settings;
    final enabled = settings?.moderationEnabled ?? true;
    final permanent = settings?.kickPermanent ?? false;
    final diamondImmunity = settings?.diamondImmunityEnabled ?? false;
    final threshold =
        settings?.diamondImmunityThreshold ?? BotSettings.minDiamondImmunityThreshold;
    if (threshold != _lastKnownThreshold && !_thresholdFocus.hasFocus) {
      _lastKnownThreshold = threshold;
      _thresholdController.text = '$threshold';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: (v) => _save(context, {'moderation_enabled': v}),
            title: const Text('Moderação automática',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'Desligada, o robô só observa o chat e não silencia nem bane ninguém.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
          SwitchListTile(
            value: permanent,
            onChanged: (v) => _save(context, {'kick_permanent': v}),
            title: const Text('Banimento permanente',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'Ao banir, remove o usuário de forma permanente em vez de só nesta live. '
              'Cuidado com palavras que possam pegar mensagens normais.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
          SwitchListTile(
            value: diamondImmunity,
            onChanged: (v) => _save(context, {'diamond_immunity_enabled': v}),
            title: const Text('Imunidade por diamantes',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'Quem já enviou diamantes suficientes nesta live fica isento de '
              'silenciar/banir, mesmo usando uma palavra da lista.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
          if (diamondImmunity)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  const Icon(Icons.diamond_rounded, color: AppTheme.accent, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Diamantes mínimos na live para ficar imune',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _thresholdController,
                      focusNode: _thresholdFocus,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _saveThreshold(context),
                      onTapOutside: (_) => _saveThreshold(context),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        helperText: 'mín. ${BotSettings.minDiamondImmunityThreshold}',
                        helperStyle: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
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
