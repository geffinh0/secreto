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

/// Shared frame of the signed-out screens, the one place the garden scene
/// appears. Phone: the title on the left and the sitting fox on the right,
/// then the gold vine, then the form (one scrolling column, max 520). From
/// 900px: an asymmetric split - brand and title top left, the fox standing
/// large at the bottom of the left half - and the form on a lighter-paper
/// panel on the right, separated by a hairline.
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

  Widget _titleBlock({required bool compact}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title,
                style: compact
                    ? AppType.display.copyWith(fontSize: 34)
                    : AppType.display,
                maxLines: 3,
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
              flex: 6,
              child: LayoutBuilder(builder: (context, c) {
                // The fox stands in the lower right of the left half; its
                // height follows the window but never past its native
                // resolution, so the engraving stays crisp.
                final foxHeight = (c.maxHeight - 260).clamp(260.0, 560.0);
                return Stack(
                  children: [
                    Positioned(
                      left: AppSpacing.xxl,
                      top: AppSpacing.xxl,
                      right: AppSpacing.xxl,
                      child: Reveal(
                        child: Row(
                          children: [
                            const FoxIcon(size: 44),
                            const SizedBox(width: 12),
                            Text('Super Moderator', style: AppType.heading),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: AppSpacing.xxl,
                      bottom: AppSpacing.lg,
                      child: Reveal(
                        index: 2,
                        child: FoxArt(FoxPose.gardenSitting, height: foxHeight),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.xxl,
                      top: 148,
                      width:
                          (c.maxWidth - AppSpacing.xxl * 2).clamp(240.0, 440.0),
                      child: Reveal(
                        index: 1,
                        child: _titleBlock(compact: false),
                      ),
                    ),
                  ],
                );
              }),
            ),
            Expanded(
              flex: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(left: AppShape.hairline),
                ),
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
                  Reveal(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: _titleBlock(compact: true)),
                        const SizedBox(width: AppSpacing.md),
                        const FoxArt(FoxPose.gardenSitting, height: 190),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Reveal(index: 1, child: OrnamentDivider()),
                  const SizedBox(height: AppSpacing.lg),
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
            Icon(Icons.error_outline, color: AppColors.danger, size: 20),
            const SizedBox(width: AppSpacing.sm + 4),
            Expanded(child: Text(message, style: AppType.body)),
          ],
        ),
      ),
    );
  }
}
