// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

/// Loads the Maps JavaScript API in the browser with the key supplied by the
/// backend. `google_maps_flutter_web` requires `google.maps` to exist before
/// the first `GoogleMap` widget is created.
Future<void> loadMapsJs(String apiKey) async {
  final String key = apiKey.trim();
  if (key.isEmpty) return;
  if (html.document.querySelector('script[data-localiq-maps]') != null) return;

  final Completer<void> completer = Completer<void>();
  final html.ScriptElement script = html.ScriptElement()
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=$key&loading=async&libraries=marker'
    ..async = true
    ..dataset['localiqMaps'] = 'true';
  script.onLoad.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  script.onError.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  html.document.head?.children.add(script);

  await completer.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {},
  );
}
