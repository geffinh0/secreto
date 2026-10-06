import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../widgets/common/gradient_button.dart';

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
    final user = context.watch<AuthProvider>().user;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Settings card
          _SettingsCard(
            settings: provider.settings,
            userId: user?.id ?? 0,
          ),
          const SizedBox(height: 24),

          // Messages list header
          Row(
            children: [
              const Icon(Icons.chat_bubble_rounded,
                  color: AppTheme.accent, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Fila de mensagens',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  provider.messages.length == 1
                      ? '1 mensagem'
                      : '${provider.messages.length} mensagens',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Arraste para reordenar. As mensagens são enviadas em ordem, em loop contínuo.',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          // Add message form
          _AddMessageForm(userId: user?.id ?? 0),
          const SizedBox(height: 20),

          // Draggable list
          if (provider.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            )
          else if (provider.messages.isEmpty)
            _EmptyState()
          else
            _DraggableMessageList(messages: provider.messages),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatefulWidget {
  final BotSettings? settings;
  final int userId;

  const _SettingsCard({required this.settings, required this.userId});

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
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
  void didUpdateWidget(_SettingsCard old) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'O intervalo deve ficar entre ${BotSettings.minIntervalSeconds} '
              'e ${BotSettings.maxIntervalSeconds} segundos.'),
          backgroundColor: AppTheme.warning,
        ),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Configurações salvas com sucesso!'
            : provider.error ?? 'Erro ao salvar configurações'),
        backgroundColor: ok ? AppTheme.success : AppTheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
              SizedBox(width: 10),
              Text(
                'Configurações de envio automático',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Toggle auto messages
          _ToggleRow(
            icon: Icons.send_rounded,
            label: 'Envio automático de mensagens',
            description: 'O robô enviará as mensagens em loop durante a live',
            value: _autoEnabled,
            onChanged: (v) => setState(() => _autoEnabled = v),
          ),
          const SizedBox(height: 16),

          // Interval
          AnimatedOpacity(
            opacity: _autoEnabled ? 1 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Intervalo entre mensagens (mínimo 10 segundos)',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _intervalController,
                        enabled: _autoEnabled,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          suffixText: 's',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          filled: true,
                          fillColor: AppTheme.bgSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppTheme.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppTheme.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppTheme.primary),
                          ),
                        ),
                      ),
                    ),
                    // Quick presets
                    ...[30, 60, 120, 300].map(
                      (v) => _PresetChip(
                        label: v >= 60 ? '${v ~/ 60}min' : '${v}s',
                        isSelected: _intervalController.text == v.toString(),
                        onTap: () => setState(
                            () => _intervalController.text = v.toString()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          GradientButton(
            id: 'save_settings_button',
            onPressed: _isSaving ? null : _save,
            isLoading: _isSaving,
            label: 'Salvar configurações',
            icon: Icons.save_rounded,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppTheme.textSecondary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  description,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetChip(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.15)
              : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primary : AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
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
    final success = await context.read<AutoMessageProvider>().addMessage(
          userId: widget.userId,
          content: text,
        );
    if (success) _controller.clear();
    setState(() => _isAdding = false);
  }

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
            'Adicionar mensagem à fila',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 2,
            maxLength: 280,
            decoration: const InputDecoration(
              hintText: 'Ex: Divulguem meu Instagram! Obrigada por acompanharem!',
              hintMaxLines: 2,
              counterStyle: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          GradientButton(
            id: 'add_message_button',
            onPressed: _isAdding ? null : _add,
            isLoading: _isAdding,
            label: 'Adicionar à fila',
            icon: Icons.add_rounded,
          ),
        ],
      ),
    );
  }
}

class _DraggableMessageList extends StatelessWidget {
  final List<AutoMessage> messages;
  const _DraggableMessageList({required this.messages});

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        context.read<AutoMessageProvider>().reorderMessages(oldIndex, newIndex);
      },
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return _MessageItem(
          key: ValueKey(msg.id ?? index),
          message: msg,
          index: index,
          onDelete: () =>
              context.read<AutoMessageProvider>().deleteMessage(msg.id!),
          onEdit: () => _showEditDialog(context, msg),
          onToggle: () =>
              context.read<AutoMessageProvider>().toggleMessage(msg),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, AutoMessage message) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Editar mensagem',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 280,
          decoration: const InputDecoration(
            hintText: 'Mensagem...',
            counterStyle: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty) {
                context
                    .read<AutoMessageProvider>()
                    .updateMessage(message.copyWith(content: newContent));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Salvar',
                style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  final AutoMessage message;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  const _MessageItem({
    super.key,
    required this.message,
    required this.index,
    required this.onDelete,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: message.isActive
              ? AppTheme.accent.withValues(alpha: 0.25)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          // Order number
          Container(
            width: 50,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                message.content,
                style: TextStyle(
                  color: message.isActive
                      ? AppTheme.textPrimary
                      : AppTheme.textMuted,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),

          // Actions
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Tooltip(
                message: message.isActive
                    ? 'Ativa: entra no envio automático'
                    : 'Desativada: o robô pula esta mensagem',
                child: Switch(
                  value: message.isActive,
                  onChanged: (_) => onToggle(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle_rounded,
                      color: AppTheme.textMuted, size: 20),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 16),
                color: AppTheme.textMuted,
                onPressed: onEdit,
                tooltip: 'Editar',
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded, size: 16),
                color: AppTheme.error.withValues(alpha: 0.7),
                onPressed: onDelete,
                tooltip: 'Remover',
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppTheme.textDisabled, size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nenhuma mensagem na fila',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Adicione mensagens acima para criar a\nfila de envio automático durante a live.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textDisabled,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
