import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/fox_icon.dart';
import '../../widgets/ui/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
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

    return AuthShell(
      title: 'Entre na sua conta',
      subtitle: 'Gerencie o robô que modera as suas lives.',
      footer: AppButton.text(
        label: 'Criar conta',
        onPressed: () => context.go('/register'),
      ),
      footerNote: 'Ainda não tem conta?',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (auth.error != null) AuthErrorBanner(message: auth.error!),
            AppTextField(
              controller: _usernameController,
              label: 'Usuário',
              hint: 'Seu nome de usuário',
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v?.isEmpty ?? true) ? 'Preencha este campo' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _passwordController,
              label: 'Senha',
              hint: 'Sua senha',
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
              suffix: IconButton(
                tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.muted,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) =>
                  (v?.isEmpty ?? true) ? 'Preencha este campo' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const ValueKey('login_submit_button'),
              label: 'Entrar',
              icon: Icons.login,
              expand: true,
              loading: auth.isLoading,
              onPressed: auth.isLoading ? null : _login,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared frame of the signed-out screens. Phone: one scrolling column, fox on
/// top, left-aligned display title, form below (max 520). From 900px: an
/// asymmetric split with the brand and title large on the left and the form on
/// a surface block on the right.
class AuthShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final String? footerNote;
  final Widget? footer;

  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footerNote,
    this.footer,
  });

  Widget _titleBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title,
                style: AppType.display,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(subtitle, style: AppType.body.copyWith(color: AppColors.muted)),
        ],
      );

  Widget _formBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                if (footerNote != null) Text(footerNote!, style: AppType.meta),
                footer!,
              ],
            ),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final wide = AppSpacing.isWide(context);

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Row(
          children: [
            Expanded(
              flex: 7,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Reveal(child: FoxIcon(size: 64)),
                    Reveal(
                      index: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _titleBlock(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: ColoredBox(
                color: AppColors.surface,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Reveal(index: 2, child: _formBlock()),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.pageHorizontal(context),
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Reveal(child: FoxIcon(size: 48)),
                  const SizedBox(height: AppSpacing.xl),
                  Reveal(index: 1, child: _titleBlock()),
                  const SizedBox(height: AppSpacing.xl),
                  Reveal(index: 2, child: _formBlock()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error from the auth provider: icon + text on a raised block, never colour alone.
class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppSurface(
        raised: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
            const SizedBox(width: AppSpacing.sm + 4),
            Expanded(child: Text(message, style: AppType.body)),
          ],
        ),
      ),
    );
  }
}
