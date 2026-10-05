import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/bot_provider.dart';
import 'providers/moderation_provider.dart';
import 'providers/auto_message_provider.dart';
import 'router/app_router.dart';
import 'package:go_router/go_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const SuperModeratorApp());
}

class SuperModeratorApp extends StatelessWidget {
  const SuperModeratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => BotProvider()),
        ChangeNotifierProvider(create: (_) => ModerationProvider()),
        ChangeNotifierProvider(create: (_) => AutoMessageProvider()),
      ],
      child: const _AppWithRouter(),
    );
  }
}

class _AppWithRouter extends StatefulWidget {
  const _AppWithRouter();

  @override
  State<_AppWithRouter> createState() => _AppWithRouterState();
}

class _AppWithRouterState extends State<_AppWithRouter> {
  late final GoRouter _router;
  late final AuthProvider _auth;
  int? _lastUserId;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _lastUserId = _auth.user?.id;
    _router = createRouter(_auth);
    _auth.addListener(_onAuthChanged);
  }

  /// When the logged user changes (login, logout, session expiry) drop everything
  /// loaded for the previous user so nothing leaks between accounts.
  void _onAuthChanged() {
    final id = _auth.user?.id;
    if (id == _lastUserId) return;
    _lastUserId = id;
    context.read<BotProvider>().reset();
    context.read<ModerationProvider>().reset();
    context.read<AutoMessageProvider>().reset();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Super Moderator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: _router,
    );
  }
}
