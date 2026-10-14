import 'dart:js_interop';

// Bridge to the update helpers in web/index.html. The page polls /build.json
// (every 5 minutes and whenever the tab becomes visible) and raises a flag when
// the server runs a newer build than the one this tab loaded. Applying the
// update clears the old service worker and caches, then reloads.
@JS('appUpdateAvailable')
external bool _updateAvailable();

@JS('appApplyUpdate')
external void _applyUpdate();

class AppUpdateService {
  AppUpdateService._();

  /// True once a newer build is live. False off the web and in local dev,
  /// where index.html is not stamped with a build id.
  static bool get available {
    try {
      return _updateAvailable();
    } catch (_) {
      return false;
    }
  }

  static void apply() {
    try {
      _applyUpdate();
    } catch (_) {
      // best-effort: a failed update must never crash the app
    }
  }
}
