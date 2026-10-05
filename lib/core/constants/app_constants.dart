class AppConstants {
  // Backend (FastAPI). Override at run/build time:
  //   flutter run ... --dart-define=API_URL=http://192.168.0.10:8000
  static const String localBackendUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8000',
  );

  // Storage keys
  static const String keyPortalToken = 'portal_token';
  static const String keyPortalUser = 'portal_user';

  // Remembers the robot login mode/identifier last used, purely for a faster
  // reconnect form (never a credential - no password or token is stored here).
  static const String keyLastRobotLoginMode = 'last_robot_login_mode';
  static const String keyLastRobotEmail = 'last_robot_email';
  static const String keyLastRobotPhone = 'last_robot_phone';

  // App info
  static const String appName = 'Super Moderator';
  static const String appVersion = '2.0.0';
  static const String appTagline = 'Moderação inteligente para suas lives';
}
