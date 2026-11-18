import 'package:flutter/foundation.dart';

/// Which appearance the user picked. `system` follows the device setting.
enum AppearanceMode { light, dark, system }

/// Small, dependency-free holder for the chosen appearance.
///
/// It deliberately lives outside the auth session: appearance is a device
/// preference, not identity data, and it must never be written next to tokens.
class AppearanceController extends ChangeNotifier {
  AppearanceController._();

  static final AppearanceController instance = AppearanceController._();

  AppearanceMode _mode = AppearanceMode.system;
  AppearanceMode get mode => _mode;

  /// Platform brightness, kept in sync by [BrandGuardApp].
  bool _systemIsDark = false;
  bool get systemIsDark => _systemIsDark;

  /// Human label used by the profile selector.
  String get label => switch (_mode) {
    AppearanceMode.light => 'Light',
    AppearanceMode.dark => 'Dark',
    AppearanceMode.system => 'System',
  };

  /// Final brightness the UI must use right now.
  bool get isDark => switch (_mode) {
    AppearanceMode.light => false,
    AppearanceMode.dark => true,
    AppearanceMode.system => _systemIsDark,
  };

  void setMode(AppearanceMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Called from `didChangePlatformBrightness` so `system` reacts live.
  void updateSystemBrightness(bool isDark) {
    if (_systemIsDark == isDark) return;
    _systemIsDark = isDark;
    if (_mode == AppearanceMode.system) notifyListeners();
  }

  /// Parses a stored preference value; unknown input falls back to `system`.
  static AppearanceMode parse(String? raw) {
    return switch (raw) {
      'light' => AppearanceMode.light,
      'dark' => AppearanceMode.dark,
      _ => AppearanceMode.system,
    };
  }

  /// Stable storage key/value for the preference.
  String get storageValue => switch (_mode) {
    AppearanceMode.light => 'light',
    AppearanceMode.dark => 'dark',
    AppearanceMode.system => 'system',
  };
}
