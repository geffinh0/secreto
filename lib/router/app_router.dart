import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/moderation/moderation_screen.dart';
import '../screens/messages/auto_messages_screen.dart';
import '../screens/bot/bot_control_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/stats/stats_screen.dart';
import '../widgets/shell/main_shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

const String _splashPath = '/splash';

GoRouter createRouter(AuthProvider authProvider) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final location = state.matchedLocation;

      // While the saved session is still being checked, show a loader instead of
      // flashing the login screen; remember where the user was heading.
      if (!authProvider.isInitialized) {
        if (location == _splashPath) return null;
        return '$_splashPath?from=${Uri.encodeComponent(state.uri.toString())}';
      }

      final isAuth = authProvider.isAuthenticated;
      final isAuthRoute =
          location.startsWith('/login') || location.startsWith('/register');

      if (location == _splashPath) {
        final from = state.uri.queryParameters['from'];
        final target = (from != null && from.startsWith('/')) ? from : '/dashboard';
        return isAuth ? target : '/login';
      }
      if (!isAuth && !isAuthRoute) return '/login';
      if (isAuth && isAuthRoute) return '/dashboard';
      return null;
    },
    refreshListenable: authProvider,
    routes: [
      GoRoute(
        path: _splashPath,
        builder: (context, state) => const Scaffold(
          backgroundColor: AppTheme.bgDark,
          body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/moderation',
            builder: (context, state) => const ModerationScreen(),
          ),
          GoRoute(
            path: '/messages',
            builder: (context, state) => const AutoMessagesScreen(),
          ),
          GoRoute(
            path: '/bot',
            builder: (context, state) => const BotControlScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/stats',
            builder: (context, state) => const StatsScreen(),
          ),
        ],
      ),
    ],
  );
}
