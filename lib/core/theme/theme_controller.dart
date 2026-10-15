import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which mood the user picked. [system] follows the device.
enum AppThemeMode { system, light, dark }

/// Remembers the appearance choice (Configurações > Aparência). Purely a
/// display preference: it is stored on this device only.
class ThemeController extends ChangeNotifier {
  static const String storageKey = 'theme_mode';

  AppThemeMode _mode = AppThemeMode.system;
  AppThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      _mode = AppThemeMode.values
          .firstWhere((m) => m.name == saved, orElse: () => AppThemeMode.system);
    } catch (_) {
      _mode = AppThemeMode.system;
    }
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, mode.name);
    } catch (_) {
      // not saving only means the choice is forgotten on the next visit
    }
  }

  /// The brightness to paint with, given what the device reports.
  Brightness resolve(Brightness platform) => switch (_mode) {
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
        AppThemeMode.system => platform,
      };
}
