import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../widgets/ui/ui.dart';

class AutoMessagesScreen extends StatefulWidget {
  const AutoMessagesScreen({super.key});

  @override
  State<AutoMessagesScreen> createState() => _AutoMessagesScreenState();
}

class _AutoMessagesScreenState extends State<AutoMessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user != null) context.read<AutoMessageProvider>().load(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AutoMessageProvider>();
    final userId = context.watch<AuthProvider>().user?.id ?? 0;

    final settings = _SendSettings(settings: provider.settings, userId: userId);
    final queue = _Queue(userId: userId, provider: provider);

    // Phone: settings first, then the queue. Desktop: queue left, settings right.
    final body = AppSpacing.isWide(context)
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: queue),
              const SizedBox(width: AppSpacing.xl),
              Expanded(flex: 2, child: settings),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              settings,
              SizedBox(height: AppSpacing.section(context)),
              queue,
            ],
          );

    return AppPage(
      children: [
        const Reveal(
          child: PageHeader(
            title: 'Mensagens automáticas',
            subtitle:
                'O robô envia as mensagens da fila em ordem, em repetição, durante a live.',
          ),
        ),
        Reveal(index: 1, child: body),
      ],
    );
  }
}

class _SendSettings extends StatefulWidget {
  final BotSettings? settings;
  final int userId;

  const _SendSettings({required this.settings, required this.userId});

  @override
  State<_SendSettings> createState() => _SendSettingsState();
}

class _SendSettingsState extends State<_SendSettings> {
  late TextEditingController _intervalController;
  late bool _autoEnabled;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _autoEnabled = widget.settings?.autoMessagesEnabled ?? false;
    _intervalController = TextEditingController(
      text: (widget.settings?.messageIntervalSeconds ?? 120).toString(),
    );
  }

  @override
  void didUpdateWidget(_SendSettings old) {
    super.didUpdateWidget(old);
    if (widget.settings != old.settings && widget.settings != null) {
      _autoEnabled = widget.settings!.autoMessagesEnabled;
      _intervalController.text =
          widget.settings!.messageIntervalSeconds.toString();
    }
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final interval = int.tryParse(_intervalController.text.trim());
    if (interval == null ||
        interval < BotSettings.minIntervalSeconds ||
        interval > BotSettings.maxIntervalSeconds) {
      showAppSnack(
        context,
        'O intervalo deve ficar entre ${BotSettings.minIntervalSeconds} '
        'e ${BotSettings.maxIntervalSeconds} segundos.',
        error: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    final provider = context.read<AutoMessageProvider>();
    final ok = await provider.saveSettings(widget.userId, {
      'auto_messages_enabled': _autoEnabled,
      'message_interval_seconds': interval,
    });
    if (!mounted) return;
    setState(() => _isSaving = false);

    showAppSnack(
      context,
      ok
          ? 'Configurações salvas.'
          : provider.error ??
              'Não foi possível salvar as configurações. Tente de novo.',
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: 'Envio automático',
      last: true,
      child: AppSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSwitchRow(
              title: 'Enviar mensagens automáticas',
              subtitle: 'O robô envia a fila em repetição durante a live.',
              value: _autoEnabled,
              onChanged: (v) => setState(() => _autoEnabled = v),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: AppTextField(
                  controller: _intervalController,
                  label: 'Intervalo entre mensagens (mínimo 10 segundos)',
                  enabled: _autoEnabled,
                  keyboardType: TextInputType.number,
                  suffix: Center(
                    widthFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text('s', style: AppType.meta),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final v in const [30, 60, 120, 300])
                  AppChip(
                    label: v >= 60 ? '${v ~/ 60} min' : '$v s',
                    selected: _intervalController.text == v.toString(),
                    onTap: _autoEnabled
                        ? () => setState(
                            () => _intervalController.text = v.toString())
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.secondary(
              key: const ValueKey('save_settings_button'),
              label: 'Salvar configurações',
              icon: Icons.save_outlined,
              loading: _isSaving,
              onPressed: _isSaving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Queue extends StatelessWidget {
  final int userId;
  final AutoMessageProvider provider;

  const _Queue({required this.userId, required this.provider});

  @override
  Widget build(BuildContext context) {
    final count = provider.messages.length;
    final Widget content;
    if (provider.isLoading) {
      content = const AppStateView.loading(message: 'Carregando mensagens');
    } else if (provider.messages.isEmpty) {
      content = const AppStateView(
        pose: FoxPose.sleeping,
        title: 'Nenhuma mensagem na fila',
        message: 'Escreva a primeira mensagem acima para o robô enviar.',
      );
    } else {
      content = _MessageList(messages: provider.messages);
    }

    return AppSection(
      title: 'Fila de mensagens',
      subtitle:
          'Arraste para reordenar. Toque numa mensagem para editar ou excluir.',
      trailing: AppChip(label: count == 1 ? '1 mensagem' : '$count mensagens'),
      last: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AddMessageForm(userId: userId),
          const SizedBox(height: AppSpacing.lg),
          content,
        ],
      ),
    );
  }
}

class _AddMessageForm extends StatefulWidget {
  final int userId;
  const _AddMessageForm({required this.userId});

  @override
  State<_AddMessageForm> createState() => _AddMessageFormState();
}

class _AddMessageFormState extends State<_AddMessageForm> {
  final _controller = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _isAdding = true);
    final provider = context.read<AutoMessageProvider>();
    final success =
        await provider.addMessage(userId: widget.userId, content: text);
    if (success) _controller.clear();
    if (!mounted) return;
    setState(() => _isAdding = false);
    if (!success) {
      showAppSnack(
          context,
          provider.error ??
              'Não foi possível adicionar a mensagem. Tente de novo.',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _controller,
            label: 'Nova mensagem',
            hint: 'Exemplo: Obrigada por acompanharem a live.',
            minLines: 2,
            maxLines: 4,
            maxLength: 280,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('add_message_button'),
            label: 'Adicionar à fila',
            icon: Icons.add,
            loading: _isAdding,
            onPressed: _isAdding ? null : _add,
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<AutoMessage> messages;
  const _MessageList({required this.messages});

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, _, __) => Material(
        color: Colors.transparent,
        child: child,
      ),
      onReorder: (oldIndex, newIndex) {
        context.read<AutoMessageProvider>().reorderMessages(oldIndex, newIndex);
      },
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return Padding(
          key: ValueKey(msg.id ?? index),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: AppListRow(
            leading: ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: AppSpacing.touch,
                height: AppSpacing.touch,
                child: Icon(Icons.drag_indicator,
                    color: AppColors.muted, semanticLabel: 'Reordenar'),
              ),
            ),
            title: msg.content,
            subtitle: msg.isActive
                ? 'Ativa'
                : 'Desativada: o robô pula esta mensagem',
            trailing: AppSwitch(
              value: msg.isActive,
              semanticLabel: 'Mensagem ativa',
              onChanged: (_) async {
                final provider = context.read<AutoMessageProvider>();
                final ok = await provider.toggleMessage(msg);
                if (!ok && context.mounted) {
                  showAppSnack(
                      context,
                      provider.error ??
                          'Não foi possível alterar a mensagem. Tente de novo.',
                      error: true);
                }
              },
            ),
            onTap: () => _edit(context, msg),
          ),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, AutoMessage message) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditMessageDialog(initial: message.content),
    );
    if (result == null || !context.mounted) return;
    final provider = context.read<AutoMessageProvider>();

    if (result.delete) {
      final confirmed = await showAppConfirm(
        context,
        title: 'Excluir mensagem',
        message: 'A mensagem sai da fila e o robô deixa de enviá-la. '
            'Essa ação não pode ser desfeita.',
        confirmLabel: 'Excluir mensagem',
        destructive: true,
      );
      if (confirmed && message.id != null) {
        final ok = await provider.deleteMessage(message.id!);
        if (!ok && context.mounted) {
          showAppSnack(
              context,
              provider.error ??
                  'Não foi possível excluir a mensagem. Tente de novo.',
              error: true);
        }
      }
      return;
    }

    final text = result.text.trim();
    if (text.isNotEmpty) {
      final ok = await provider.updateMessage(message.copyWith(content: text));
      if (!ok && context.mounted) {
        showAppSnack(
            context,
            provider.error ??
                'Não foi possível salvar a mensagem. Tente de novo.',
            error: true);
      }
    }
  }
}

class _EditResult {
  final String text;
  final bool delete;
  const _EditResult(this.text, {this.delete = false});
}

class _EditMessageDialog extends StatefulWidget {
  final String initial;
  const _EditMessageDialog({required this.initial});

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Editar mensagem', style: AppType.title),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _controller,
                label: 'Mensagem',
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 280,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton.danger(
                    label: 'Excluir mensagem',
                    icon: Icons.delete_outline,
                    onPressed: () => Navigator.pop(
                        context, const _EditResult('', delete: true)),
                  ),
                  AppButton.secondary(
                    label: 'Cancelar',
                    onPressed: () => Navigator.pop(context),
                  ),
                  AppButton(
                    label: 'Salvar mensagem',
                    onPressed: () =>
                        Navigator.pop(context, _EditResult(_controller.text)),
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
