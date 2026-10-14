import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/portal_api_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_message_provider.dart';
import '../../providers/moderation_provider.dart';
import '../../widgets/ui/ui.dart';

/// "Importar configurações": paste the contents of a backup file (.json, format
/// "atilas-config") and add its moderation words and auto messages to THIS account.
/// The server checks every item, skips what is already there (so importing twice is
/// harmless) and only ever writes to the logged-in user. Step 1 checks the file and
/// shows what would happen; step 2 imports it.
class ImportConfigCard extends StatefulWidget {
  const ImportConfigCard({super.key, this.api});

  final PortalApiService? api;

  @override
  State<ImportConfigCard> createState() => _ImportConfigCardState();
}

class _ImportConfigCardState extends State<ImportConfigCard> {
  late final PortalApiService _api = widget.api ?? PortalApiService();
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _preview; // server answer to the dry run
  Map<String, dynamic>? _done; // server answer to the real import

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The decoded file, or null (with [_error] set) when it is not valid JSON.
  Map<String, dynamic>? _parse() {
    var text = _controller.text.trim();
    if (text.startsWith('﻿')) text = text.substring(1);
    if (text.isEmpty) {
      _error = 'Cole aqui o conteúdo do arquivo de backup (.json).';
      return null;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    _error =
        'Isso não parece um arquivo de backup. Cole o conteúdo completo do .json, '
        'do primeiro "{" ao último "}".';
    return null;
  }

  Future<void> _run({required bool dryRun}) async {
    setState(() {
      _error = null;
      if (dryRun) {
        _preview = null;
        _done = null;
      }
    });
    final body = _parse();
    if (body == null) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    final result = await _api.post(
        '/config/import${dryRun ? '?dry_run=true' : ''}', body,
        timeout: const Duration(seconds: 60));
    if (!mounted) return;
    if (result['success'] == true && result['data'] is Map) {
      final data = (result['data'] as Map).cast<String, dynamic>();
      setState(() {
        _busy = false;
        if (dryRun) {
          _preview = data;
        } else {
          _done = data;
          _preview = null;
          _controller.clear();
        }
      });
      if (!dryRun) await _reloadLists();
    } else {
      setState(() {
        _busy = false;
        _error = PortalApiService.errorMessage(
            result, 'Não foi possível ler o arquivo.');
      });
    }
  }

  Future<void> _reloadLists() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    await context.read<ModerationProvider>().loadRules(user.id);
    if (!mounted) return;
    await context.read<AutoMessageProvider>().load(user.id);
  }

  int _n(Map<String, dynamic>? section, String key) =>
      (section?[key] as num?)?.toInt() ?? 0;

  Widget _summary(Map<String, dynamic> data, {required bool preview}) {
    final rules = (data['rules'] as Map?)?.cast<String, dynamic>();
    final messages = (data['messages'] as Map?)?.cast<String, dynamic>();
    String line(String what, Map<String, dynamic>? s) {
      final parts = <String>[
        '${_n(s, 'created')} ${preview ? 'serão adicionadas' : 'adicionadas'}',
        if (_n(s, 'skipped') > 0) '${_n(s, 'skipped')} já existiam',
        if (_n(s, 'invalid') > 0) '${_n(s, 'invalid')} inválidas',
      ];
      return '$what: ${parts.join(' · ')}';
    }

    final invalid = [
      ...((rules?['invalid_items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => 'Palavra #${(e['index'] as num) + 1}: ${e['reason']}'),
      ...((messages?['invalid_items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => 'Mensagem #${(e['index'] as num) + 1}: ${e['reason']}'),
    ];
    return AppSurface(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  preview
                      ? Icons.fact_check_outlined
                      : Icons.check_circle_outline,
                  size: 20,
                  color: preview ? AppColors.accent : AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                    preview ? 'O que vai acontecer' : 'Importação concluída',
                    style: AppType.bodyStrong),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(line('Palavras de moderação', rules),
              key: const ValueKey('import_rules_line'), style: AppType.body),
          Text(line('Mensagens automáticas', messages),
              key: const ValueKey('import_messages_line'), style: AppType.body),
          for (final text in invalid.take(8))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 16, color: AppColors.warning),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text(text,
                          style:
                              AppType.meta.copyWith(color: AppColors.warning))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final canImport = preview != null &&
        (_n((preview['rules'] as Map?)?.cast<String, dynamic>(), 'created') +
                _n((preview['messages'] as Map?)?.cast<String, dynamic>(),
                    'created')) >
            0;

    return AppSection(
      title: 'Importar configurações',
      subtitle:
          'Traga as palavras de moderação e as mensagens automáticas de um arquivo de backup para esta conta. '
          'Nada é apagado: o que já existe é mantido e repetidas são ignoradas. '
          'A conexão com o robô e as demais configurações não mudam.',
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              key: const ValueKey('import_config_field'),
              controller: _controller,
              label: 'Conteúdo do backup',
              hint: 'Cole aqui o conteúdo do arquivo .json de backup',
              minLines: 4,
              maxLines: 8,
              enabled: !_busy,
              onChanged: (_) {
                if (_preview != null || _done != null || _error != null) {
                  setState(() {
                    _preview = null;
                    _done = null;
                    _error = null;
                  });
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.error_outline,
                          size: 20, color: AppColors.danger),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(_error!, style: AppType.body),
                    ),
                  ],
                ),
              ),
            if (preview != null) ...[
              _summary(preview, preview: true),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_done != null) ...[
              _summary(_done!, preview: false),
              const SizedBox(height: AppSpacing.md),
            ],
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton.secondary(
                  key: const ValueKey('import_check_button'),
                  label: 'Conferir arquivo',
                  icon: Icons.fact_check_outlined,
                  onPressed: _busy ? null : () => _run(dryRun: true),
                ),
                AppButton(
                  key: const ValueKey('import_confirm_button'),
                  label: 'Importar',
                  icon: Icons.upload_outlined,
                  loading: _busy,
                  onPressed:
                      (_busy || !canImport) ? null : () => _run(dryRun: false),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
