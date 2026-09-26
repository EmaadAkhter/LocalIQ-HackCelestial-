/// No-op Maps JavaScript loader for Android and iOS.
///
/// The native SDKs read the key from the platform configuration
/// (`AndroidManifest.xml` / `Info.plist`), injected from the backend env at
/// build time, so nothing has to be loaded here.
Future<void> loadMapsJs(String apiKey) async {}
