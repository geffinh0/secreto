import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/gradient_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );
    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Row(
        children: [
          // Left hero panel (only on wide screens): Atila, front and centre.
          if (isWide)
            Expanded(
              child: Container(
                color: AppTheme.bgCard,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/images/fox_hero.webp', width: 260),
                      const SizedBox(height: 24),
                      const Text(
                        "Atila's Client",
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Moderação inteligente\npara suas lives SuperLive',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 40),
                      const _FeatureChip(icon: Icons.shield_rounded, label: 'Moderação automática'),
                      const SizedBox(height: 12),
                      const _FeatureChip(icon: Icons.chat_bubble_rounded, label: 'Mensagens recorrentes'),
                      const SizedBox(height: 12),
                      const _FeatureChip(icon: Icons.bolt_rounded, label: 'Conectado em tempo real'),
                    ],
                  ),
                ),
              ),
            ),

          // Right form panel: fixed width next to the hero on wide screens,
          // the whole row on narrow ones.
          _PanelSlot(
            isWide: isWide,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isWide) ...[
                            Center(
                              child: Image.asset('assets/images/fox_hero.webp', width: 120),
                            ),
                            const SizedBox(height: 20),
                          ],
                          const Text(
                            'Bem-vindo de volta!',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Entre na sua conta para gerenciar seu robô moderador.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Error message
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
                                  const Icon(Icons.error_rounded,
                                      color: AppTheme.error, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      auth.error!,
                                      style: const TextStyle(
                                          color: AppTheme.error, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                // Username field
                                TextFormField(
                                  controller: _usernameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Usuário',
                                    prefixIcon: Icon(Icons.person_rounded),
                                    hintText: 'Seu nome de usuário',
                                  ),
                                  validator: (v) => (v?.isEmpty ?? true)
                                      ? 'Campo obrigatório'
                                      : null,
                                  onFieldSubmitted: (_) => _login(),
                                ),
                                const SizedBox(height: 16),

                                // Password field
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Senha',
                                    prefixIcon: const Icon(Icons.lock_rounded),
                                    hintText: 'Sua senha',
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                      ),
                                      onPressed: () => setState(
                                          () => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  validator: (v) => (v?.isEmpty ?? true)
                                      ? 'Campo obrigatório'
                                      : null,
                                  onFieldSubmitted: (_) => _login(),
                                ),
                                const SizedBox(height: 28),

                                // Login button
                                GradientButton(
                                  id: 'login_submit_button',
                                  onPressed: auth.isLoading ? null : _login,
                                  isLoading: auth.isLoading,
                                  label: 'Entrar',
                                  icon: Icons.login_rounded,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Não tem conta? ',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                              ),
                              GestureDetector(
                                onTap: () => context.go('/register'),
                                child: const Text(
                                  'Criar agora',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A fixed-width column on wide screens, otherwise it fills the row. (A
/// `SizedBox(width: double.infinity)` inside a `Row` is an unbounded-width error.)
class _PanelSlot extends StatelessWidget {
  final bool isWide;
  final Widget child;

  const _PanelSlot({required this.isWide, required this.child});

  @override
  Widget build(BuildContext context) =>
      isWide ? SizedBox(width: 480, child: child) : Expanded(child: child);
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.primary, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

