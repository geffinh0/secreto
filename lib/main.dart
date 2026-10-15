import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'providers/auth_provider.dart';
import 'providers/bot_provider.dart';
import 'providers/moderation_provider.dart';
import 'providers/auto_message_provider.dart';
import 'providers/stats_provider.dart';
import 'providers/admin_provider.dart';
import 'router/app_router.dart';
import 'package:go_router/go_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The appearance choice is read before the first frame so the app never
  // flashes the wrong mood.
  final theme = ThemeController();
  await theme.load();
  final platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  AppColors.dark = theme.resolve(platform) == Brightness.dark;
  _applyStatusBar();
  runApp(SuperModeratorApp(theme: theme));
}

void _applyStatusBar() {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: AppColors.dark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness:
          AppColors.dark ? Brightness.light : Brightness.dark,
    ),
  );
}

class SuperModeratorApp extends StatelessWidget {
  final ThemeController theme;
  const SuperModeratorApp({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => BotProvider()),
        ChangeNotifierProvider(create: (_) => ModerationProvider()),
        ChangeNotifierProvider(create: (_) => AutoMessageProvider()),
        ChangeNotifierProvider(create: (_) => StatsProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
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

class _AppWithRouterState extends State<_AppWithRouter>
    with WidgetsBindingObserver {
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
    _themeController = context.read<ThemeController>();
    _themeController.addListener(_syncTheme);
    WidgetsBinding.instance.addObserver(this);
  }

  late final ThemeController _themeController;

  @override
  void didChangePlatformBrightness() => _syncTheme();

  /// Applies the chosen mood. The palette lives in static getters, so widgets
  /// that do not depend on Theme would keep their old colours: mark every
  /// element dirty so the whole tree repaints in one frame (State is kept).
  void _syncTheme() {
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final dark = _themeController.resolve(platform) == Brightness.dark;
    if (dark == AppColors.dark) return;
    AppColors.dark = dark;
    _applyStatusBar();
    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    (context as Element).visitChildren(markDirty);
    setState(() {});
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
    context.read<StatsProvider>().reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeController.removeListener(_syncTheme);
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: "Atila's Client",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppColors.dark ? Brightness.dark : Brightness.light),
      routerConfig: _router,
    );
  }
}
