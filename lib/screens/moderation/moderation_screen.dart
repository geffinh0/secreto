import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_spacing.dart';
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
        const _ModerationToolsCard(),

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

/// Shared across both tabs (mute/kick) since it tests against every active
/// rule regardless of which list it belongs to. Fixed height on purpose: it
/// used to expand inline and fight the tab bar/list below for vertical
/// space (worst on mobile, where the keyboard eats the rest). It now just
/// opens a bottom sheet that owns its own scrolling and keyboard inset, so
/// the rest of the screen never resizes under it.
class _ModerationToolsCard extends StatelessWidget {
  const _ModerationToolsCard();

  @override
  Widget build(BuildContext context) {
    final h = AppSpacing.pageHorizontal(context);
    return Container(
      margin: EdgeInsets.fromLTRB(h, 16, h, 14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: InkWell(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _PhraseTesterSheet(),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.science_outlined, color: AppTheme.accent, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Testar uma frase',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline_rounded,
                    color: AppTheme.textMuted, size: 20),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _RulesHelpDialog(),
                ),
                tooltip: 'Como as regras funcionam',
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet content for the phrase tester. Owns its own text field,
/// request state and result banner - fully isolated from the rest of the
/// moderation screen's layout, and safe-area/keyboard aware on its own.
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
    final result =
        await context.read<ModerationProvider>().testPhrase(userId: user.id, text: text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: AppTheme.border),
              left: BorderSide(color: AppTheme.border),
              right: BorderSide(color: AppTheme.border),
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20, 12, 20, 20 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const Row(
                  children: [
                    Icon(Icons.science_outlined, color: AppTheme.accent, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Testar uma frase',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Digite uma mensagem de exemplo pra ver se alguma regra ativa pegaria ela '
                  '- inclusive com número no lugar de letra ou letra repetida.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _textController,
                  autofocus: true,
                  onSubmitted: (_) => _test(),
                  decoration: const InputDecoration(
                    hintText: 'ex: g0z4 gostoso',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _testing ? null : _test,
                    child: _testing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.onAccent),
                          )
                        : const Text('Testar'),
                  ),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 14),
                  _TestResultBanner(result: _result!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TestResultBanner extends StatelessWidget {
  final PhraseTestResult result;
  const _TestResultBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    if (!result.matched) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: AppTheme.success, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text('Nenhuma regra ativa pegaria essa frase.',
                  style: TextStyle(color: AppTheme.success, fontSize: 13)),
            ),
          ],
        ),
      );
    }
    final isKick = result.action == 'kick';
    final color = isKick ? AppTheme.error : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(isKick ? Icons.block_rounded : Icons.volume_off_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${isKick ? "Baniria" : "Silenciaria"} - bateu na regra "${result.keyword}"',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulesHelpDialog extends StatelessWidget {
  const _RulesHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('Como as regras funcionam',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      content: const SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HelpItem(
                icon: Icons.star_rounded,
                title: 'Asterisco no fim (ex: puta*)',
                body: 'Pega a palavra e qualquer coisa colada depois dela '
                    '("putaria", "putasso"...). Sem o *, só a palavra inteira conta.',
              ),
              _HelpItem(
                icon: Icons.link_rounded,
                title: 'Palavras compostas coladas ou separadas',
                body: 'Uma regra "passa zap" também pega "passazap", '
                    '"passa-zap", "passa_zap" e "passa.zap".',
              ),
              _HelpItem(
                icon: Icons.filter_1_rounded,
                title: 'Número no lugar de letra (leetspeak)',
                body: '0→o, 1→i, 3→e, 4→a, 5→s, 7→t, 8→b, 9→g, @→a, \$→s, +→t, |→i. '
                    '"g0z4" é reconhecido como "goza" automaticamente (uma regra só '
                    '"goza" já cobre essa e outras grafias disfarçadas).',
              ),
              _HelpItem(
                icon: Icons.format_underlined_rounded,
                title: 'Letra esticada (ex: gozzzaaa)',
                body: '3 ou mais da mesma letra em sequência colapsam pra 1 só '
                    'antes de comparar - "goooza" também é pego.',
              ),
              _HelpItem(
                icon: Icons.pin_rounded,
                title: 'Regra com número (ex: d4)',
                body: 'Se a PALAVRA-CHAVE em si tem número/símbolo, ela vira '
                    'literal: só pega quem digitar exatamente daquele jeito '
                    '("d4"), e não vira automaticamente a palavra comum '
                    'correspondente ("da"). Assim "d4" não baniria todo mundo '
                    'que escreve "amei da live".',
              ),
              _HelpItem(
                icon: Icons.science_outlined,
                title: 'Testar uma frase',
                body: 'Use o campo acima pra conferir ao vivo se uma mensagem '
                    'específica bateria em alguma regra, antes de confiar nela.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendi', style: TextStyle(color: AppTheme.primary)),
        ),
      ],
    );
  }
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _HelpItem({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
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
              padding: AppSpacing.page(context),
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _BulkImportDialog(action: widget.action, color: color),
                      ),
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('Adicionar várias de uma vez'),
                      style: TextButton.styleFrom(foregroundColor: color),
                    ),
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
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pageHorizontal(context), 0, AppSpacing.pageHorizontal(context), 24,
              ),
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

class _BulkImportDialog extends StatefulWidget {
  final String action;
  final Color color;
  const _BulkImportDialog({required this.action, required this.color});

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
    final result = await context.read<ModerationProvider>().addRulesBulk(
          userId: user.id,
          action: widget.action,
          keywords: keywords,
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMute = widget.action == 'mute';
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: Text(
        'Adicionar várias palavras — ${isMute ? "Silenciar" : "Banir"}',
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Uma palavra por linha (ou separadas por vírgula). Já cadastradas '
              'e repetidas no texto são ignoradas automaticamente.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'feia\nchata\nmal educada',
                isDense: true,
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 14),
              Text(
                '${_result!.created.length} adicionada${_result!.created.length != 1 ? "s" : ""}'
                '${_result!.skipped.isNotEmpty ? ", ${_result!.skipped.length} ignorada${_result!.skipped.length != 1 ? "s" : ""}" : ""}.',
                style: TextStyle(
                  color: _result!.created.isNotEmpty ? AppTheme.success : AppTheme.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_result!.skipped.isNotEmpty) ...[
                const SizedBox(height: 6),
                ..._result!.skipped.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• "${s.keyword}" — ${s.reason}',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5),
                      ),
                    )),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar', style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: widget.color),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onAccent),
                )
              : const Text('Adicionar', style: TextStyle(color: AppTheme.onAccent)),
        ),
      ],
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
                              strokeWidth: 2, color: AppTheme.onAccent),
                        )
                      : const Text(
                          'Adicionar',
                          style: TextStyle(
                              color: AppTheme.onAccent,
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
