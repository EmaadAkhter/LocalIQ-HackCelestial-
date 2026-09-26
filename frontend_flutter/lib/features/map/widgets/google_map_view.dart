import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/place.dart';

/// Real Google Maps view, enabled only when a key is available.
///
/// The key is never committed: `RuntimeConfig` fetches it from the backend
/// (`GET /api/v1/config`) at startup and applies it to `AppConfig`. On web the
/// Maps JavaScript API is loaded with that same key; on Android and iOS the
/// native SDKs read the key from the platform configuration, which the release
/// scripts fill in from the backend env. [MapScreen] falls back to the offline
/// canvas when no key is present, so the app always renders something useful.
class GoogleMapView extends StatelessWidget {
  const GoogleMapView({
    required this.places,
    required this.userLat,
    required this.userLng,
    super.key,
  });

  final List<Place> places;
  final double userLat;
  final double userLng;

  @override
  Widget build(BuildContext context) {
    final Set<Marker> markers = <Marker>{
      Marker(
        markerId: const MarkerId('me'),
        position: LatLng(userLat, userLng),
        infoWindow: const InfoWindow(title: 'You are here'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      for (int i = 0; i < places.length; i++)
        Marker(
          markerId: MarkerId(places[i].id),
          position: LatLng(places[i].lat, places[i].lng),
          infoWindow: InfoWindow(
            title: places[i].name,
            snippet:
                '${places[i].category.label} · '
                '${places[i].indoorOutdoor.label}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
        ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(userLat, userLng),
        zoom: 13.5,
      ),
      markers: markers,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (GoogleMapController controller) {
        // Route hook: ready for the Directions / Routes API.
        if (places.length > 1) {
          final double minLat = places
              .map((Place p) => p.lat)
              .reduce((a, b) => a < b ? a : b);
          final double maxLat = places
              .map((Place p) => p.lat)
              .reduce((a, b) => a > b ? a : b);
          final double minLng = places
              .map((Place p) => p.lng)
              .reduce((a, b) => a < b ? a : b);
          final double maxLng = places
              .map((Place p) => p.lng)
              .reduce((a, b) => a > b ? a : b);
          controller.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat, minLng),
                northeast: LatLng(maxLat, maxLng),
              ),
              80,
            ),
          );
        }
      },
    );
  }
}

/// Legend explaining the marker colours used by the offline canvas.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'Your route',
          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
