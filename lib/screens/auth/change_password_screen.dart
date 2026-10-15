import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/ui/ui.dart';
import 'login_screen.dart' show AuthErrorBanner;

/// Same rules the server enforces (backend/security.py password_problems); the server
/// stays the authority, this only saves a round trip for the obvious mistakes.
String? passwordRuleError(String password) {
  if (password.length < 8) return 'Use pelo menos 8 caracteres';
  final hasUpper = password.runes.any((r) {
    final ch = String.fromCharCode(r);
    return ch != ch.toLowerCase() && ch == ch.toUpperCase();
  });
  if (!hasUpper) return 'Use pelo menos uma letra maiúscula';
  final hasSpecial = password.runes.any((r) {
    final ch = String.fromCharCode(r);
    final isLetterOrDigit =
        ch.toLowerCase() != ch.toUpperCase() || (r >= 0x30 && r <= 0x39);
    return !isLetterOrDigit && ch.trim().isNotEmpty;
  });
  if (!hasSpecial) {
    return r'Use pelo menos um caractere especial (como ! @ # $ % & *)';
  }
  return null;
}

/// Choose your own password. Shown as the ONLY reachable screen right after logging in
/// with a temporary password released by the admin (the router enforces that), and
/// also reachable voluntarily from Configurações.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok =
        await auth.changePassword(_currentController.text, _newController.text);
    if (ok && mounted) {
      showAppSnack(context, 'Senha alterada');
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final forced = auth.mustChangePassword;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: AppPage(
          maxWidth: 520,
          children: [
            Reveal(
              child: PageHeader(
                title: forced ? 'Escolha a sua senha' : 'Alterar senha',
                subtitle: forced
                    ? 'Você entrou com uma senha provisória. Ela só vale uma vez: '
                        'crie agora uma senha só sua para continuar.'
                    : 'Por segurança, as suas outras sessões serão encerradas.',
                leading: forced
                    ? null
                    : IconButton(
                        tooltip: 'Voltar',
                        icon:
                            Icon(Icons.arrow_back, color: AppColors.ink),
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/settings'),
                      ),
              ),
            ),
            Reveal(
              index: 1,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (auth.error != null)
                      AuthErrorBanner(message: auth.error!),
                    AppTextField(
                      controller: _currentController,
                      label: forced ? 'Senha provisória' : 'Senha atual',
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.next,
                      suffix: IconButton(
                        tooltip: _obscure ? 'Mostrar senhas' : 'Ocultar senhas',
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.muted,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) =>
                          (v?.isEmpty ?? true) ? 'Preencha este campo' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _newController,
                      label: 'Nova senha',
                      helper:
                          'Mínimo de 8 caracteres, com uma letra maiúscula e um '
                          'caractere especial. Não use seu usuário, nome ou senhas comuns.',
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v?.isEmpty ?? true) return 'Preencha este campo';
                        if (v == _currentController.text) {
                          return 'Use uma senha diferente da atual';
                        }
                        return passwordRuleError(v!);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _confirmController,
                      label: 'Confirmar nova senha',
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      validator: (v) => v != _newController.text
                          ? 'As senhas não coincidem'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      key: const ValueKey('change_password_submit_button'),
                      label: 'Salvar nova senha',
                      icon: Icons.check,
                      expand: true,
                      loading: auth.isLoading,
                      onPressed: auth.isLoading ? null : _submit,
                    ),
                    if (forced) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppButton.text(
                        label: 'Sair',
                        expand: true,
                        onPressed: () => context.read<AuthProvider>().logout(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
