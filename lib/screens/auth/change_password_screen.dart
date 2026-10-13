import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/gradient_button.dart';

/// Same rules the server enforces (backend/security.py password_problems); the server
/// stays the authority, this only saves a round trip for the obvious mistakes.
String? passwordRuleError(String password) {
  if (password.length < 10) return 'Use pelo menos 10 caracteres';
  final hasLetter = password.runes.any((r) => String.fromCharCode(r).toLowerCase() != String.fromCharCode(r).toUpperCase());
  final hasDigit = password.runes.any((r) => r >= 0x30 && r <= 0x39);
  if (!hasLetter || !hasDigit) return 'Misture letras e números';
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
    final ok = await auth.changePassword(_currentController.text, _newController.text);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada')));
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final forced = auth.mustChangePassword;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: forced
          ? null
          : AppBar(
              backgroundColor: AppTheme.bgDark,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
              ),
            ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal(context),
            vertical: 32,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forced ? 'Escolha a sua senha' : 'Alterar senha',
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  forced
                      ? 'Você entrou com uma senha provisória. Ela só vale uma vez: '
                          'crie agora uma senha só sua para continuar.'
                      : 'Por segurança, as suas outras sessões serão encerradas.',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                ),
                const SizedBox(height: 24),
                if (auth.error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(14),
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
                          child: Text(auth.error!,
                              style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _currentController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: forced ? 'Senha provisória' : 'Senha atual',
                          prefixIcon: const Icon(Icons.lock_clock_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v?.isEmpty ?? true) ? 'Campo obrigatório' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _newController,
                        obscureText: _obscure,
                        decoration: const InputDecoration(
                          labelText: 'Nova senha',
                          prefixIcon: Icon(Icons.lock_rounded),
                          helperText: 'Mínimo 10 caracteres, com letras e números. '
                              'Não use seu usuário, nome ou senhas comuns.',
                          helperMaxLines: 3,
                        ),
                        validator: (v) {
                          if (v?.isEmpty ?? true) return 'Campo obrigatório';
                          if (v == _currentController.text) return 'Use uma senha diferente da atual';
                          return passwordRuleError(v!);
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscure,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar nova senha',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                        validator: (v) =>
                            v != _newController.text ? 'As senhas não coincidem' : null,
                      ),
                      const SizedBox(height: 28),
                      GradientButton(
                        id: 'change_password_submit_button',
                        onPressed: auth.isLoading ? null : _submit,
                        isLoading: auth.isLoading,
                        label: 'Salvar nova senha',
                        icon: Icons.check_rounded,
                      ),
                      if (forced) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => context.read<AuthProvider>().logout(),
                          child: const Text('Sair'),
                        ),
                      ],
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
