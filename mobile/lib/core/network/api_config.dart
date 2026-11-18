/// Public endpoint selection only. Never add credentials to this file.
///
/// Native builds use the hosted HTTPS API without requiring a dart-define.
/// Web stays same-origin so the optional local browser demo still works.
/// Local/emulator development is an explicit API_BASE build-time override.
class ApiConfig {
  ApiConfig._();

  static const hostedBaseUrl = 'https://brandguard-app.antideploy.app';

  static String resolveBaseUrl({
    String configuredBase = '',
    required bool isWeb,
    String? webOrigin,
  }) {
    final configured = configuredBase.trim().replaceFirst(RegExp(r'/+$'), '');
    final selected = configured.isNotEmpty
        ? configured
        : isWeb
        ? (webOrigin ?? '')
        : hostedBaseUrl;
    final uri = Uri.tryParse(selected);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiConfigurationException();
    }
    return selected.replaceFirst(RegExp(r'/+$'), '');
  }
}

class ApiConfigurationException implements Exception {
  const ApiConfigurationException();

  @override
  String toString() =>
      'The server address is invalid. Rebuild with a valid API_BASE URL.';
}
