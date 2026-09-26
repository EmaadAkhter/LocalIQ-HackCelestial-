import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// What a pin represents. Drives its icon and colour.
enum PinKind { place, gem, user, pickup, drop, stop, driver }

/// A pin placed on the map, positioned by real coordinates.
class PlacePin {
  const PlacePin({
    required this.id,
    required this.label,
    required this.position,
    this.tone = 'neutral',
    this.selected = false,
    this.onTap,
    this.kind = PinKind.place,
    this.number,
  });

  final String id;
  final String label;
  final ({double lat, double lng}) position;
  final String tone;
  final bool selected;
  final VoidCallback? onTap;
  final PinKind kind;

  /// Order label for a stop pin (1, 2, 3...).
  final int? number;
}

/// The map surface.
///
/// A self-hosted vector map: real coordinates, real Mumbai geography, no API
/// key and no network — so the same widget powers discovery, the trip map and
/// the offline demo. A `google_maps_flutter` / tile implementation slots in
/// behind the same [PlacePin] contract when a key is provisioned.
///
/// The camera fits every pin and route point on first build, then pans and
/// zooms freely; [MapCameraController] lets a parent recentre it (e.g. to keep
/// the driver in view).
class LocalIqMapView extends StatefulWidget {
  const LocalIqMapView({
    super.key,
    this.pins = const [],
    this.route = const [],
    this.userLocation,
    this.height = 260,
    this.showLabels = true,
    this.interactive = true,
    this.showControls = false,
    this.controller,
    this.padding = 0.35,
  });

  final List<PlacePin> pins;
  final List<({double lat, double lng})> route;
  final ({double lat, double lng})? userLocation;
  final double height;
  final bool showLabels;
  final bool interactive;
  final bool showControls;
  final MapCameraController? controller;

  /// Extra fraction of the fitted span left as margin (0..1).
  final double padding;

  @override
  State<LocalIqMapView> createState() => _LocalIqMapViewState();
}

/// Lets a parent move the camera (recentre, zoom) without rebuilding the map.
class MapCameraController extends ChangeNotifier {
  _MapCameraRequest? _pending;

  void moveTo({
    required double lat,
    required double lng,
    double? zoom,
  }) {
    _pending = _MapCameraRequest(lat: lat, lng: lng, zoom: zoom);
    notifyListeners();
  }

  void _consume() => _pending = null;
}

class _MapCameraRequest {
  const _MapCameraRequest({required this.lat, required this.lng, this.zoom});
  final double lat;
  final double lng;
  final double? zoom;
}

class _MapCamera {
  const _MapCamera({required this.lat, required this.lng, required this.zoom});

  final double lat;
  final double lng;
  final double zoom;

  _MapCamera copyWith({double? lat, double? lng, double? zoom}) => _MapCamera(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        zoom: zoom ?? this.zoom,
      );
}

class _Fit {
  const _Fit({
    required this.lat,
    required this.lng,
    required this.latSpan,
    required this.lngSpan,
  });

  final double lat;
  final double lng;
  final double latSpan;
  final double lngSpan;
}

class _Projection {
  _Projection({
    required this.fit,
    required this.camera,
    required this.size,
  });

  final _Fit fit;
  final _MapCamera camera;
  final Size size;

  double get _cosLat => math.cos(camera.lat * math.pi / 180).clamp(0.2, 1.0);

  /// Pixels per degree of latitude.
  double get scale {
    final latFit = size.height / fit.latSpan;
    final lngFit = size.width / (fit.lngSpan * _cosLat);
    return math.min(latFit, lngFit) * camera.zoom;
  }

  Offset project(double lat, double lng) {
    final s = scale;
    return Offset(
      size.width / 2 + (lng - camera.lng) * _cosLat * s,
      size.height / 2 - (lat - camera.lat) * s,
    );
  }

  /// Convert a screen delta into a camera delta.
  _MapCamera panBy(Offset delta) => camera.copyWith(
        lat: camera.lat + delta.dy / scale,
        lng: camera.lng - delta.dx / (_cosLat * scale),
      );
}

class _LocalIqMapViewState extends State<LocalIqMapView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  _MapCamera? _camera;
  double _gestureStartZoom = 1;
  int _fitSignature = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    widget.controller?.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant LocalIqMapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
    }
    final next = _signature(widget);
    if (next != _fitSignature) {
      _fitSignature = next;
      _camera = null;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _pulse.dispose();
    super.dispose();
  }

  void _onController() {
    final request = widget.controller?._pending;
    if (request == null) return;
    widget.controller?._consume();
    final camera = _camera ?? _fit(_points())._camera;
    setState(() {
      _camera = camera.copyWith(
        lat: request.lat,
        lng: request.lng,
        zoom: request.zoom,
      );
    });
  }

  int _signature(LocalIqMapView w) =>
      Object.hash(w.pins.length, w.route.length, w.userLocation);

  List<({double lat, double lng})> _points() => [
        for (final p in widget.pins) p.position,
        ...widget.route,
        if (widget.userLocation != null) widget.userLocation!,
      ];

  _Fit _fit(List<({double lat, double lng})> points) {
    if (points.isEmpty) {
      return const _Fit(lat: 19.00, lng: 72.845, latSpan: 0.22, lngSpan: 0.22);
    }
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLng = points.first.lng;
    var maxLng = points.first.lng;
    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final pad = 1 + widget.padding;
    return _Fit(
      lat: (minLat + maxLat) / 2,
      lng: (minLng + maxLng) / 2,
      latSpan: math.max(0.012, (maxLat - minLat) * pad),
      lngSpan: math.max(0.012, (maxLng - minLng) * pad),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final fit = _fit(_points());
          final camera = _camera ?? _MapCamera(lat: fit.lat, lng: fit.lng, zoom: 1);
          final projection = _Projection(fit: fit, camera: camera, size: size);

          final content = Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      painter: _VectorMapPainter(
                        projection: projection,
                        route: widget.route,
                        userLocation: widget.userLocation,
                        driverLocation: _driverLocation(),
                        showLabels: widget.showLabels,
                        pulse: _pulse.value,
                      ),
                    ),
                  ),
                ),
              ),
              for (final pin in widget.pins)
                _PinOverlay(
                  pin: pin,
                  position: projection.project(
                    pin.position.lat,
                    pin.position.lng,
                  ),
                ),
            ],
          );

          if (!widget.interactive) return content;

          return GestureDetector(
            onScaleStart: (_) => _gestureStartZoom = _camera?.zoom ?? 1,
            onScaleUpdate: (details) {
              setState(() {
                final base = _camera ?? _MapCamera(lat: fit.lat, lng: fit.lng, zoom: 1);
                final zoomed = details.scale == 1.0
                    ? base.zoom
                    : (_gestureStartZoom * details.scale).clamp(0.6, 16.0);
                final next = _Projection(
                  fit: fit,
                  camera: base.copyWith(zoom: zoomed),
                  size: size,
                );
                _camera = next.panBy(details.focalPointDelta);
              });
            },
            onDoubleTap: () {},
            onDoubleTapDown: (details) {
              setState(() {
                final base = _camera ?? _MapCamera(lat: fit.lat, lng: fit.lng, zoom: 1);
                final box = context.findRenderObject() as RenderBox?;
                final local = box?.globalToLocal(details.globalPosition) ??
                    Offset(size.width / 2, size.height / 2);
                final current = _Projection(fit: fit, camera: base, size: size);
                final target = current.panBy(Offset(
                  size.width / 2 - local.dx,
                  size.height / 2 - local.dy,
                ));
                _camera = target.copyWith(
                  zoom: (base.zoom * 1.8).clamp(0.6, 16.0),
                );
              });
            },
            child: Stack(
              children: [
                content,
                if (widget.showControls)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _MapControls(
                      onZoomIn: () => _zoomBy(size, fit, 1.5),
                      onZoomOut: () => _zoomBy(size, fit, 1 / 1.5),
                      onRecentre: () => setState(() {
                        _camera = _MapCamera(lat: fit.lat, lng: fit.lng, zoom: 1);
                      }),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  ({double lat, double lng})? _driverLocation() {
    for (final pin in widget.pins) {
      if (pin.kind == PinKind.driver) return pin.position;
    }
    return null;
  }

  void _zoomBy(Size size, _Fit fit, double factor) {
    setState(() {
      final base = _camera ?? _MapCamera(lat: fit.lat, lng: fit.lng, zoom: 1);
      _camera = base.copyWith(zoom: (base.zoom * factor).clamp(0.6, 16.0));
    });
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRecentre,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRecentre;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapButton(icon: Icons.add_rounded, onTap: onZoomIn, tooltip: 'Zoom in'),
        const SizedBox(height: 6),
        _MapButton(icon: Icons.remove_rounded, onTap: onZoomOut, tooltip: 'Zoom out'),
        const SizedBox(height: 6),
        _MapButton(
          icon: Icons.my_location_rounded,
          onTap: onRecentre,
          tooltip: 'Fit all',
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}

class _PinOverlay extends StatelessWidget {
  const _PinOverlay({required this.pin, required this.position});

  final PlacePin pin;
  final Offset position;

  Color get _tone => switch (pin.tone) {
        'feasible' => AppColors.success,
        'partial' => AppColors.warning,
        'blocked' => AppColors.danger,
        'user' => AppColors.blue,
        'pickup' => AppColors.success,
        'drop' => AppColors.danger,
        'driver' => AppColors.blue,
        'gem' => AppColors.violet,
        _ => AppColors.violet,
      };

  IconData get _icon => switch (pin.kind) {
        PinKind.user => Icons.person_pin_circle_rounded,
        PinKind.driver => Icons.local_taxi_rounded,
        PinKind.pickup => Icons.trip_origin_rounded,
        PinKind.drop => Icons.flag_rounded,
        PinKind.stop => Icons.circle,
        PinKind.gem => Icons.diamond_rounded,
        PinKind.place => Icons.place_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final isStop = pin.kind == PinKind.stop;
    final size = pin.selected ? 34.0 : (isStop ? 24.0 : 28.0);
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size,
      child: Tooltip(
        message: pin.label,
        child: GestureDetector(
          onTap: pin.onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tone,
                  shape: isStop ? BoxShape.circle : BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: _tone.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: isStop && pin.number != null
                    ? Text(
                        '${pin.number}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      )
                    : Icon(_icon, size: 14, color: Colors.white),
              ),
              // A small stem so the pin reads as anchored to the point.
              Container(width: 2, height: 5, color: _tone.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VectorMapPainter extends CustomPainter {
  _VectorMapPainter({
    required this.projection,
    required this.route,
    required this.userLocation,
    required this.driverLocation,
    required this.showLabels,
    required this.pulse,
  });

  final _Projection projection;
  final List<({double lat, double lng})> route;
  final ({double lat, double lng})? userLocation;
  final ({double lat, double lng})? driverLocation;
  final bool showLabels;
  final double pulse;

  static const _sea = Color(0xFFBCD9F0);
  static const _seaEdge = Color(0xFFA7CBE8);
  static const _land = Color(0xFFEDF1F7);
  static const _block = Color(0xFFDDE4EE);
  static const _park = Color(0xFFD3E3CE);
  static const _arterial = Color(0xFFFBF0D8);

  /// The west coast of Mumbai, north -> south, including the Back Bay bight.
  static const _coast = <(double, double)>[
    (19.34, 72.760),
    (19.24, 72.788),
    (19.14, 72.800),
    (19.06, 72.804),
    (19.00, 72.812),
    (18.96, 72.814),
    (18.93, 72.808),
    (18.905, 72.812),
    (18.885, 72.828),
    (18.905, 72.850),
    (18.935, 72.860),
    (18.965, 72.868),
    (19.00, 72.870),
  ];

  static const _areas = <(String, double, double)>[
    ('COLABA', 18.9067, 72.8147),
    ('FORT', 18.9338, 72.8355),
    ('CHURCHGATE', 18.9320, 72.8260),
    ('MARINE DRIVE', 18.9440, 72.8230),
    ('WORLI', 19.0176, 72.8160),
    ('BANDRA', 19.0596, 72.8295),
    ('JUHU', 19.1075, 72.8263),
    ('ANDHERI', 19.1197, 72.8464),
    ('DADAR', 19.0176, 72.8440),
    ('CHEMBUR', 19.0522, 72.9005),
    ('POWAI', 19.1176, 72.9060),
    ('THANE', 19.2183, 72.9781),
    ('BORIVALI', 19.2307, 72.8567),
  ];

  static const _parks = <(double, double, double, double)>[
    (18.9250, 72.8320, 0.006, 0.004), // Horniman Circle / Fort green
    (18.9600, 72.8100, 0.007, 0.004), // Hanging Gardens
    (19.0420, 72.9100, 0.010, 0.006), // Shivaji Park / central green
    (19.1170, 72.8420, 0.008, 0.005), // Aarey fringe
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _land);

    _paintSea(canvas, size);
    _paintParks(canvas);
    _paintGrid(canvas, size);
    _paintRoute(canvas);
    _paintPulse(canvas, userLocation, AppColors.blue);
    _paintPulse(canvas, driverLocation, AppColors.blue);
    if (showLabels) _paintLabels(canvas, size);
  }

  void _paintSea(Canvas canvas, Size size) {
    final points = [for (final c in _coast) projection.project(c.$1, c.$2)];
    if (points.isEmpty) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    // Close far to the west so the whole sea is filled.
    path
      ..lineTo(-size.width * 2, points.last.dy)
      ..lineTo(-size.width * 2, -size.height)
      ..lineTo(points.first.dx, -size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = _sea);
    final edge = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      edge.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      edge,
      Paint()
        ..color = _seaEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _paintParks(Canvas canvas) {
    final paint = Paint()..color = _park;
    for (final p in _parks) {
      final centre = projection.project(p.$1, p.$2);
      final latRadius = p.$3 * projection.scale;
      final lngRadius = p.$4 * projection.scale * projection._cosLat;
      canvas.drawOval(
        Rect.fromCenter(
          center: centre,
          width: lngRadius * 2,
          height: latRadius * 2,
        ),
        paint,
      );
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    // A road grid in real coordinate steps, so it scales with zoom naturally.
    final step = 0.006;
    final block = Paint()..color = _block;
    // Visible geographic window around the camera centre.
    final halfLat = size.height / (2 * projection.scale);
    final halfLng = size.width / (2 * projection.scale * projection._cosLat);
    final minLat = projection.camera.lat - halfLat;
    final maxLat = projection.camera.lat + halfLat;
    final minLng = projection.camera.lng - halfLng;
    final maxLng = projection.camera.lng + halfLng;

    var lat = (minLat / step).floor() * step;
    while (lat < maxLat) {
      var lng = (minLng / step).floor() * step;
      while (lng < maxLng) {
        final at = projection.project(lat, lng);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              at.dx,
              at.dy - step * projection.scale,
              step * projection.scale * projection._cosLat * 0.62,
              step * projection.scale * 0.6,
            ),
            const Radius.circular(2),
          ),
          block,
        );
        lng += step;
      }
      lat += step;
    }

    // Two arterials for texture.
    final arterial = Paint()
      ..color = _arterial
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final line in const [
      [(19.06, 72.80), (19.02, 72.84), (18.96, 72.87)],
      [(19.20, 72.86), (19.05, 72.85), (18.93, 72.83)],
    ]) {
      final pts = [for (final c in line) projection.project(c.$1, c.$2)];
      if (pts.length < 2) continue;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, arterial);
    }
  }

  void _paintRoute(Canvas canvas) {
    if (route.length < 2) return;
    final points = [for (final p in route) projection.project(p.lat, p.lng)];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.30)
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.violet
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintPulse(Canvas canvas, ({double lat, double lng})? point, Color color) {
    if (point == null) return;
    final at = projection.project(point.lat, point.lng);
    final halo = math.sin(pulse * math.pi) * 0.5 + 0.5;
    canvas.drawCircle(
      at,
      16 + halo * 14,
      Paint()..color = color.withValues(alpha: 0.10 + halo * 0.12),
    );
    canvas.drawCircle(at, 6, Paint()..color = color);
    canvas.drawCircle(
      at,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _paintLabels(Canvas canvas, Size size) {
    for (final area in _areas) {
      final at = projection.project(area.$2, area.$3);
      if (at.dx < -40 ||
          at.dx > size.width + 40 ||
          at.dy < -20 ||
          at.dy > size.height + 20) {
        continue;
      }
      _label(canvas, area.$1, at);
    }
  }

  void _label(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 8.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
          color: Color(0xFF8FA0B8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _VectorMapPainter old) =>
      old.route.length != route.length ||
      old.pulse != pulse ||
      old.showLabels != showLabels ||
      old.userLocation != userLocation ||
      old.driverLocation != driverLocation ||
      old.projection.camera.lat != projection.camera.lat ||
      old.projection.camera.lng != projection.camera.lng ||
      old.projection.camera.zoom != projection.camera.zoom ||
      old.projection.size != projection.size;
}

/// Legend explaining the pin tones.
class MapLegend extends StatelessWidget {
  const MapLegend({
    super.key,
    this.showRoute = true,
    this.showTrip = false,
  });

  final bool showRoute;
  final bool showTrip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        const _LegendDot(color: AppColors.blue, label: 'You'),
        if (showTrip) ...[
          const _LegendDot(color: AppColors.success, label: 'Pickup'),
          const _LegendDot(color: AppColors.danger, label: 'Drop-off'),
          const _LegendDot(color: AppColors.violet, label: 'Stops'),
        ] else ...[
          const _LegendDot(color: AppColors.success, label: 'Feasible'),
          const _LegendDot(color: AppColors.warning, label: 'Partial'),
          const _LegendDot(color: AppColors.danger, label: 'Blocked'),
        ],
        if (showRoute)
          const _LegendDot(color: AppColors.violet, label: 'Route'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
