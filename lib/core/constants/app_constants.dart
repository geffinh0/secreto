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

  // App info
  static const String appName = 'Super Moderator';
  static const String appVersion = '2.0.0';
  static const String appTagline = 'Moderação inteligente para suas lives';
}
