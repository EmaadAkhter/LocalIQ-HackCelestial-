import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/place_image.dart';
import '../../models/place.dart';
import '../../models/recommendation.dart';
import 'widgets/google_map_view.dart';

/// Map view — fourth reference frame.
///
/// Renders an offline canvas by default (no API key needed) and swaps in a
/// real `GoogleMap` once the backend has supplied a Google Maps key.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<Recommendation> stops = state.itineraryStops.isEmpty
        ? state.recommendations.take(3).toList()
        : state.itineraryStops.take(3).toList();
    final int index = _selectedIndex != null && _selectedIndex! < stops.length
        ? _selectedIndex!
        : 0;
    final Recommendation? active = stops.isEmpty
        ? null
        : stops[index.clamp(0, stops.length - 1)];

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AppConfig.hasMapsApiKey
                ? GoogleMapView(
                    places: stops.map((Recommendation r) => r.place).toList(),
                    userLat: state.params.latitude,
                    userLng: state.params.longitude,
                  )
                : OfflineMapCanvas(
                    places: stops.map((Recommendation r) => r.place).toList(),
                    userLat: state.params.latitude,
                    userLng: state.params.longitude,
                    activeIndex: active == null ? -1 : index,
                    onMarkerTap: (int i) => setState(() => _selectedIndex = i),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.md,
                Insets.md,
                Insets.md,
                0,
              ),
              child: _MapSearchBar(location: state.params.location),
            ),
          ),
          if (active != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _RouteSheet(
                stops: stops,
                active: active,
                onSelect: (int i) => setState(() => _selectedIndex = i),
                onViewFull: () => _viewFullItinerary(context),
              ),
            )
          else
            const Align(
              alignment: Alignment.bottomCenter,
              child: _NoStopsHint(),
            ),
        ],
      ),
    );
  }

  void _viewFullItinerary(BuildContext context) {
    final AppState state = context.read<AppState>();
    if (state.itineraryStops.isEmpty && state.recommendations.isNotEmpty) {
      state.addTopRecommendation();
    }
    // Switch to the Itinerary tab via the shell's navigation bar.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    state.buildPlan();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Opening your plan — see the Itinerary tab.'),
      ),
    );
  }
}

class _MapSearchBar extends StatelessWidget {
  const _MapSearchBar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
            Expanded(
              child: Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoStopsHint extends StatelessWidget {
  const _NoStopsHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Insets.page),
      child: Material(
        color: AppColors.surface,
        borderRadius: Radii.cardRadius,
        child: const Padding(
          padding: EdgeInsets.all(Insets.lg),
          child: Row(
            children: <Widget>[
              Icon(Icons.map_rounded, color: AppColors.primary),
              SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  'Find experiences to see them pinned on the map.',
                  style: TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteSheet extends StatelessWidget {
  const _RouteSheet({
    required this.stops,
    required this.active,
    required this.onSelect,
    required this.onViewFull,
  });

  final List<Recommendation> stops;
  final Recommendation active;
  final ValueChanged<int> onSelect;
  final VoidCallback onViewFull;

  @override
  Widget build(BuildContext context) {
    final int totalMinutes = stops.fold<int>(
      0,
      (int sum, Recommendation r) => sum + r.travelMinutes,
    );
    final int totalCost = stops.fold<int>(
      0,
      (int sum, Recommendation r) => sum + r.place.avgCost,
    );

    return Padding(
      padding: const EdgeInsets.all(Insets.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: Radii.cardRadius,
        elevation: 10,
        shadowColor: Colors.black26,
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Suggested Route',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lavender,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      '~${Fmt.duration(totalMinutes)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${stops.length} stops · ${Fmt.inrExact(totalCost)} est.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: Insets.md),
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stops.length,
                  separatorBuilder: (_, _) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final Place place = stops[index].place;
                    final bool isActive = place.id == active.place.id;
                    return GestureDetector(
                      onTap: () => onSelect(index),
                      child: SizedBox(
                        width: 66,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Stack(
                              children: <Widget>[
                                PlaceThumb(
                                  imageUrl: place.imageUrl,
                                  seed: place.name,
                                  icon: place.category.icon,
                                  size: 52,
                                ),
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  child: _MarkerIndex(index: index + 1),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              place.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isActive
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isActive
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: Insets.lg),
              FilledButton(
                onPressed: onViewFull,
                child: const Text('View Full Itinerary'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkerIndex extends StatelessWidget {
  const _MarkerIndex({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        '$index',
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Offline stylised map: water, roads, route and numbered pins.
///
/// Purely visual, so the demo works with no API key and no network.
class OfflineMapCanvas extends StatelessWidget {
  const OfflineMapCanvas({
    required this.places,
    required this.userLat,
    required this.userLng,
    required this.activeIndex,
    required this.onMarkerTap,
    super.key,
  });

  final List<Place> places;
  final double userLat;
  final double userLng;
  final int activeIndex;
  final ValueChanged<int> onMarkerTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEFF3F0),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final List<Offset> points = _project(constraints.biggest);
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _MapPainter(
                    points: points,
                    userPoint: points.isEmpty ? Offset.zero : points.first,
                    activeIndex: activeIndex,
                  ),
                ),
              ),
              for (int i = 0; i < points.length; i++)
                Positioned(
                  left: points[i].dx - 16,
                  top: points[i].dy - 34,
                  child: GestureDetector(
                    onTap: () => onMarkerTap(i),
                    child: _Pin(index: i + 1, active: i == activeIndex),
                  ),
                ),
              Positioned(
                right: 16,
                bottom: 190,
                child: Column(
                  children: <Widget>[
                    _MapControl(icon: Icons.add_rounded, onTap: () {}),
                    const SizedBox(height: 8),
                    _MapControl(icon: Icons.remove_rounded, onTap: () {}),
                    const SizedBox(height: 8),
                    _MapControl(icon: Icons.my_location_rounded, onTap: () {}),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Simple equirectangular projection into the canvas box with padding.
  List<Offset> _project(Size size) {
    final List<({double lat, double lng})> all = <({double lat, double lng})>[
      (lat: userLat, lng: userLng),
      ...places.map((Place p) => (lat: p.lat, lng: p.lng)),
    ];
    if (all.isEmpty) return <Offset>[];

    double minLat = all.first.lat, maxLat = all.first.lat;
    double minLng = all.first.lng, maxLng = all.first.lng;
    for (final ({double lat, double lng}) p in all) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    // Fallback span when all points coincide.
    if ((maxLat - minLat).abs() < 0.004) {
      minLat -= 0.02;
      maxLat += 0.02;
    }
    if ((maxLng - minLng).abs() < 0.004) {
      minLng -= 0.02;
      maxLng += 0.02;
    }

    const double padX = 56;
    const double padTop = 130;
    const double padBottom = 240;
    final double usableW = size.width - padX * 2;
    final double usableH = size.height - padTop - padBottom;
    if (usableW <= 0 || usableH <= 0) return <Offset>[];

    final List<Offset> result = <Offset>[];
    for (final ({double lat, double lng}) p in all) {
      final double x = padX + (p.lng - minLng) / (maxLng - minLng) * usableW;
      final double y =
          padTop + (1 - (p.lat - minLat) / (maxLat - minLat)) * usableH;
      result.add(Offset(x, y.clamp(padTop, size.height - padBottom)));
    }
    return result;
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.index, required this.active});

  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.primary : AppColors.mapRoute;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
        Icon(Icons.arrow_drop_down_rounded, color: color, size: 20),
      ],
    );
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.sm),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.points,
    required this.userPoint,
    required this.activeIndex,
  });

  final List<Offset> points;
  final Offset userPoint;
  final int activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWater(canvas, size);
    _paintBlocks(canvas, size);
    _paintRoads(canvas, size);
    if (points.length > 1) _paintRoute(canvas);
    _paintUserDot(canvas);
  }

  void _paintWater(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xFFBFE0F0);
    final Path path = Path()
      ..moveTo(size.width * 0.62, 0)
      ..quadraticBezierTo(
        size.width * 0.52,
        size.height * 0.35,
        size.width * 0.74,
        size.height * 0.62,
      )
      ..quadraticBezierTo(
        size.width * 0.86,
        size.height * 0.78,
        size.width * 0.8,
        size.height,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _paintBlocks(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xFFE4EDE4);
    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 7; col++) {
        final double x = col * (size.width / 7) + 6;
        final double y = row * (size.height / 9) + 10;
        if (x > size.width * 0.6 && y > size.height * 0.5) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, size.width / 9, size.height / 13),
            const Radius.circular(4),
          ),
          paint,
        );
      }
    }
  }

  void _paintRoads(Canvas canvas, Size size) {
    final Paint road = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final Paint major = Paint()
      ..color = const Color(0xFFFDF6E3)
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 1; i < 6; i++) {
      final double y = size.height * (i / 6);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
    for (int i = 1; i < 5; i++) {
      final double x = size.width * (i / 5);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }
    canvas.drawLine(
      Offset(0, size.height * 0.62),
      Offset(size.width * 0.6, size.height * 0.2),
      major,
    );
  }

  void _paintRoute(Canvas canvas) {
    final Paint shadow = Paint()
      ..color = Colors.black12
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final Paint route = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final List<Offset> stops = points.skip(1).toList();
    final Path path = Path()..moveTo(userPoint.dx, userPoint.dy);
    for (final Offset p in stops) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, shadow);
    canvas.drawPath(path, route);

    // Highlight the active leg.
    if (activeIndex >= 0 && activeIndex < stops.length) {
      final Offset target = stops[activeIndex];
      final Offset from = activeIndex == 0 ? userPoint : stops[activeIndex - 1];
      final Paint active = Paint()
        ..color = AppColors.mapRoute
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(from, target, active);
    }
  }

  void _paintUserDot(Canvas canvas) {
    canvas.drawCircle(
      userPoint,
      18,
      Paint()..color = AppColors.indigo.withValues(alpha: 0.18),
    );
    canvas.drawCircle(userPoint, 7, Paint()..color = AppColors.indigo);
    canvas.drawCircle(
      userPoint,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.activeIndex != activeIndex;
  }
}
