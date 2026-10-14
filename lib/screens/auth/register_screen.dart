import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/ui/ui.dart';
import 'change_password_screen.dart' show passwordRuleError;
import 'login_screen.dart' show AuthShell, AuthErrorBanner;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _agencyCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _agencyCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      _usernameController.text.trim(),
      _passwordController.text,
      _displayNameController.text.trim(),
      _agencyCodeController.text.trim(),
    );
    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  Widget _visibilityToggle(bool obscured, VoidCallback onToggle) => IconButton(
        tooltip: obscured ? 'Mostrar senha' : 'Ocultar senha',
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: AppColors.muted,
        ),
        onPressed: onToggle,
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AuthShell(
      title: 'Criar conta',
      subtitle:
          'Use o código da sua agência para configurar o portal de moderação.',
      footerNote: 'Já tem conta?',
      footer: AppButton.text(
        label: 'Entrar',
        onPressed: () => context.go('/login'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (auth.error != null) AuthErrorBanner(message: auth.error!),
            AppTextField(
              controller: _agencyCodeController,
              label: 'Código da agência',
              hint: 'Peça o código à sua agência',
              inputFormatters: [
                TextInputFormatter.withFunction(
                    (old, v) => v.copyWith(text: v.text.toUpperCase())),
              ],
              textInputAction: TextInputAction.next,
              validator: (v) => (v?.trim().isEmpty ?? true)
                  ? 'Informe o código da sua agência'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _displayNameController,
              label: 'Nome de exibição',
              hint: 'Como você quer aparecer',
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v?.isEmpty ?? true) ? 'Preencha este campo' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _usernameController,
              label: 'Usuário',
              hint: 'Sem espaços ou caracteres especiais',
              autofillHints: const [AutofillHints.newUsername],
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v?.isEmpty ?? true) return 'Preencha este campo';
                if (v!.contains(' ')) return 'Sem espaços';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _passwordController,
              label: 'Senha',
              helper:
                  'Mínimo de 8 caracteres, com uma letra maiúscula e um caractere especial',
              obscureText: _obscurePass,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              suffix: _visibilityToggle(_obscurePass,
                  () => setState(() => _obscurePass = !_obscurePass)),
              validator: (v) {
                if (v?.isEmpty ?? true) return 'Preencha este campo';
                return passwordRuleError(v!);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _confirmPasswordController,
              label: 'Confirmar senha',
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _register(),
              suffix: _visibilityToggle(_obscureConfirm,
                  () => setState(() => _obscureConfirm = !_obscureConfirm)),
              validator: (v) => v != _passwordController.text
                  ? 'As senhas não coincidem'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const ValueKey('register_submit_button'),
              label: 'Criar conta',
              icon: Icons.person_add_alt,
              expand: true,
              loading: auth.isLoading,
              onPressed: auth.isLoading ? null : _register,
            ),
          ],
        ),
      ),
    );
  }
}
