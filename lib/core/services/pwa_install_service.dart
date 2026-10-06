import 'dart:js_interop';

// Thin bridge to the JS helpers in web/index.html. Install prompting is a
// browser API with no Flutter equivalent, so this has to go through JS:
// Chrome/Android fire `beforeinstallprompt` (captured there, triggered here);
// iOS has no such event at all, only "Adicionar à Tela de Início" from
// Safari's own Share sheet, so [isIos] exists to switch the UI to static
// instructions instead of a button that would never do anything.
@JS('pwaCanPromptInstall')
external bool _canPromptInstall();

@JS('pwaTriggerInstall')
external void _triggerInstall();

@JS('pwaIsStandalone')
external bool _isStandalone();

@JS('pwaIsIos')
external bool _isIos();

class PwaInstallService {
  static bool get canPromptInstall => _tryBool(() => _canPromptInstall());
  static bool get isStandalone => _tryBool(() => _isStandalone());
  static bool get isIos => _tryBool(() => _isIos());

  static void triggerInstall() {
    try {
      _triggerInstall();
    } catch (_) {
      // no-op: the prompt helper is best-effort, never worth crashing over
    }
  }

  static bool _tryBool(bool Function() fn) {
    try {
      return fn();
    } catch (_) {
      return false;
    }
  }
}
