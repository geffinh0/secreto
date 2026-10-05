import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bot_provider.dart';
import '../../widgets/common/gradient_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final bot = context.watch<BotProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile section
          _SectionCard(
            title: 'Sua conta',
            icon: Icons.person_rounded,
            iconColor: AppTheme.primary,
            children: [
              _InfoRow(label: 'Nome', value: user?.displayName ?? 'N/A'),
              const SizedBox(height: 12),
              _InfoRow(label: 'Usuário', value: '@${user?.username ?? 'N/A'}'),
              const SizedBox(height: 12),
              _InfoRow(label: 'E-mail', value: user?.email ?? 'N/A'),
              const SizedBox(height: 12),
              _InfoRow(
                  label: 'Tipo',
                  value: (user?.isAdmin ?? false) ? 'Administrador' : 'Criadora'),
              const SizedBox(height: 20),
              GradientButton(
                id: 'logout_button',
                onPressed: () => context.read<AuthProvider>().logout(),
                label: 'Sair da conta',
                icon: Icons.logout_rounded,
                startColor: AppTheme.error,
                endColor: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Robot account section
          _SectionCard(
            title: 'Conta do Robô (SuperLive)',
            icon: Icons.smart_toy_rounded,
            iconColor: AppTheme.accent,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bot.isConnected
                            ? AppTheme.success
                            : AppTheme.error,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      bot.isConnected
                          ? 'Conectado como: ${bot.botProfile?.nickname ?? "Robô"}'
                          : 'Robô desconectado',
                      style: TextStyle(
                        color: bot.isConnected
                            ? AppTheme.textPrimary
                            : AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Para conectar o robô, vá até a aba "Robô" e informe as credenciais da conta oficial.',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // About section
          const _SectionCard(
            title: 'Sobre o Super Moderator',
            icon: Icons.info_rounded,
            iconColor: AppTheme.textMuted,
            children: [
              _InfoRow(label: 'Versão', value: AppConstants.appVersion),
              SizedBox(height: 12),
              _InfoRow(label: 'Plataforma', value: 'SuperLive v2.31.0'),
              SizedBox(height: 12),
              _InfoRow(label: 'Backend', value: 'FastAPI + SQLite'),
              SizedBox(height: 12),
              _InfoRow(label: 'Frontend', value: 'Flutter Web'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

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
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
