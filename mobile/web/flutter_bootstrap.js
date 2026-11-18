{{flutter_js}}
{{flutter_build_config}}

// Native mobile is the main app. The optional web bundle stays same-origin.
// No service worker: rebuilding must not leave an older login/API configuration cached.
_flutter.loader.load();
