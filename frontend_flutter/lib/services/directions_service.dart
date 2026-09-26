import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Google Maps directions for a coordinate.
///
/// Kept behind a service so tests can stub it and so the URL scheme can change
/// in one place. Falls back to a `maps` web URL which works on every platform.
class DirectionsService {
  const DirectionsService();

  /// [lat]/[lng] are the destination, [originLat]/[originLng] optional.
  Future<bool> openDirections({
    required double lat,
    required double lng,
    double? originLat,
    double? originLng,
    String? label,
  }) async {
    final String destination = '$lat,$lng';
    final String origin = (originLat != null && originLng != null)
        ? '?origin=$originLat,$originLng&'
        : '';
    final Uri web = Uri.parse(
      'https://www.google.com/maps/dir/$origin'
      'api=1&destination=$destination&travelmode=walking',
    );
    final Uri native = Uri.parse('google.navigation:q=$lat,$lng');

    if (await canLaunchUrl(native)) {
      return launchUrl(native, mode: LaunchMode.externalApplication);
    }
    return launchUrl(web, mode: LaunchMode.externalApplication);
  }
}

/// Minimal logging helper so services never print raw payloads.
abstract final class AppLog {
  AppLog._();

  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('[LocalIQ] $message');
    }
  }
}
