import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_image.dart';
import '../../domain/place.dart';
import '../../../routing/presentation/localiq_map_view.dart';

/// Map view of the current search results.
///
/// Pins are coloured by category and, when the place is a local favourite, get
/// a distinct tone. Tapping a pin raises a compact card that opens the detail
/// screen, so the map is a first-class way to browse — not decoration.
class SearchMapView extends StatefulWidget {
  const SearchMapView({
    super.key,
    required this.places,
    this.userLocation,
    this.height,
  });

  final List<Place> places;
  final ({double lat, double lng})? userLocation;
  final double? height;

  @override
  State<SearchMapView> createState() => _SearchMapViewState();
}

class _SearchMapViewState extends State<SearchMapView> {
  final _camera = MapCameraController();
  Place? _selected;

  @override
  void didUpdateWidget(covariant SearchMapView old) {
    super.didUpdateWidget(old);
    if (old.places.length != widget.places.length) {
      if (_selected != null && !widget.places.any((p) => p.id == _selected!.id)) {
        _selected = null;
      }
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height ?? MediaQuery.sizeOf(context).height;
    final pins = [
      for (final place in widget.places)
        PlacePin(
          id: place.id,
          label: place.name,
          position: (lat: place.centre.latitude, lng: place.centre.longitude),
          kind: place.localFavourite ? PinKind.gem : PinKind.place,
          selected: _selected?.id == place.id,
          tone: place.localFavourite ? 'gem' : 'place',
          onTap: () {
            setState(() => _selected = place);
            _camera.moveTo(
              lat: place.centre.latitude,
              lng: place.centre.longitude,
              zoom: 2.4,
            );
          },
        ),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: LocalIqMapView(
            pins: pins,
            userLocation: widget.userLocation,
            height: height,
            showControls: true,
            padding: 0.3,
            controller: _camera,
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.place_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.places.length} on map',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selected != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _MapPlaceCard(
              place: _selected!,
              onClose: () => setState(() => _selected = null),
              onDetails: () => context.push('/place/${_selected!.id}?place=${_selected!.id}'),
            ),
          ),
      ],
    );
  }
}

class _MapPlaceCard extends StatelessWidget {
  const _MapPlaceCard({
    required this.place,
    required this.onClose,
    required this.onDetails,
  });

  final Place place;
  final VoidCallback onClose;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.raised,
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              width: 68,
              height: 68,
              child: AppImage(
                url: place.heroImageUrl,
                fit: BoxFit.cover,
                tint: categoryColor(place.category),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        place.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.textMuted,
                      onPressed: onClose,
                    ),
                  ],
                ),
                Text(
                  '${place.area} · ${place.category.label}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: AppColors.star),
                    const SizedBox(width: 3),
                    Text(
                      place.rating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      place.priceLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: onDetails,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Details', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
