import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_image.dart';
import '../../places/domain/place.dart';
import 'localiq_map_view.dart';

/// Phase 8: Map Screen — interactive map of Mumbai experiences.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  String? _selectedCategory;
  Place? _selectedPlace;
  bool _showRoute = false;

  final _categories = const [
    'All',
    'Food',
    'Heritage',
    'Art',
    'Nature',
    'Shopping',
    'Nightlife',
  ];

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(allPlacesProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Explore Mumbai Map'),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        actions: [
          IconButton(
            tooltip: _showRoute ? 'Hide Route' : 'Show Route',
            icon: Icon(
              _showRoute ? Icons.route_rounded : Icons.alt_route_rounded,
              color: _showRoute ? AppColors.primary : AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _showRoute = !_showRoute),
          ),
        ],
      ),
      body: placesAsync.when(
        data: (places) {
          final filtered = _filterPlaces(places);
          final pins = filtered.map((place) {
            final isSelected = _selectedPlace?.id == place.id;
            return PlacePin(
              id: place.id,
              label: place.name,
              position: (
                lat: place.centre.latitude,
                lng: place.centre.longitude,
              ),
              tone: place.localFavourite ? 'gem' : 'primary',
              selected: isSelected,
              onTap: () {
                setState(() => _selectedPlace = place);
              },
            );
          }).toList();

          final sampleRoute = _showRoute && filtered.length >= 3
              ? filtered.take(4).map((p) => (
                    lat: p.centre.latitude,
                    lng: p.centre.longitude,
                  )).toList()
              : const <({double lat, double lng})>[];

          return Stack(
            children: [
              // Full interactive vector map
              Positioned.fill(
                child: LocalIqMapView(
                  pins: pins,
                  route: sampleRoute,
                  userLocation: const (lat: 18.9322, lng: 72.8316),
                  height: MediaQuery.sizeOf(context).height,
                  showLabels: true,
                  interactive: true,
                ),
              ),

              // Top category filter bar
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final cat = _categories[i];
                      final isSelected = (_selectedCategory == null && cat == 'All') ||
                          _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.surface,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppColors.primary : AppColors.border,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedCategory = cat == 'All' ? null : cat;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),

              // Selected place bottom card
              if (_selectedPlace != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: _MapPlaceCard(
                    place: _selectedPlace!,
                    onClose: () => setState(() => _selectedPlace = null),
                    onDetails: () => context.push(
                      '/place/${_selectedPlace!.id}',
                      extra: _selectedPlace,
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (e, _) => Center(
          child: Text('Error loading map: $e'),
        ),
      ),
    );
  }

  List<Place> _filterPlaces(List<Place> places) {
    if (_selectedCategory == null) return places;
    return places.where((p) {
      return p.category.label.toLowerCase() == _selectedCategory!.toLowerCase();
    }).toList();
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: 76,
                    height: 76,
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
                      const SizedBox(height: 3),
                      Text(
                        '${place.area} · ${place.category.label}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: AppColors.star),
                          const SizedBox(width: 3),
                          Text(
                            place.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
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
                            child: const Text('View Details', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
