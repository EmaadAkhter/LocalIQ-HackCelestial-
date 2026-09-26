import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../routing/domain/routes_service.dart';

/// A pin placed on the map, positioned by real coordinates.
class PlacePin {
  const PlacePin({
    required this.id,
    required this.label,
    required this.position,
    this.tone = 'neutral',
    this.selected = false,
    this.onTap,
  });

  final String id;
  final String label;
  final ({double lat, double lng}) position;
  final String tone;
  final bool selected;
  final VoidCallback? onTap;
}

/// The map surface.
///
/// Renders a vector map today. A `google_maps_flutter` implementation slots in
/// behind the same [PlacePin] / [MapPolyline] contract via [MapService.hasTiles]
/// without any change to the call sites, so the map can be upgraded without
/// touching product code.
class LocalIqMapView extends StatefulWidget {
  const LocalIqMapView({
    super.key,
    this.pins = const [],
    this.route = const [],
    this.userLocation,
    this.height = 260,
    this.showLabels = true,
    this.interactive = true,
  });

  final List<PlacePin> pins;
  final List<({double lat, double lng})> route;
  final ({double lat, double lng})? userLocation;
  final double height;
  final bool showLabels;
  final bool interactive;

  @override
  State<LocalIqMapView> createState() => _LocalIqMapViewState();
}

class _LocalIqMapViewState extends State<LocalIqMapView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  // South Mumbai bounds used for the linear projection.
  static const _latMin = 18.88;
  static const _latMax = 19.09;
  static const _lngMin = 72.78;
  static const _lngMax = 72.86;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => GestureDetector(
                    onTap: () => setState(() {}),
                    child: CustomPaint(
                      painter: _VectorMapPainter(
                        pins: widget.pins,
                        route: widget.route,
                        userLocation: widget.userLocation,
                        showLabels: widget.showLabels,
                        pulse: _pulse.value,
                        project: (point) => _project(point, size),
                      ),
                    ),
                  ),
                ),
              ),
              for (final pin in widget.pins)
                _PinOverlay(
                  pin: pin,
                  position: _project(pin.position, size),
                ),
            ],
          );
        },
      ),
    );
  }

  Offset _project(({double lat, double lng}) point, Size size) {
    final x = ((point.lng - _lngMin) / (_lngMax - _lngMin)).clamp(0.0, 1.0);
    final y = 1 - ((point.lat - _latMin) / (_latMax - _latMin)).clamp(0.0, 1.0);
    return Offset(x * size.width, y * size.height);
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
        _ => AppColors.violet,
      };

  @override
  Widget build(BuildContext context) {
    final size = pin.selected ? 30.0 : 24.0;
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size - 6,
      child: Tooltip(
        message: pin.label,
        child: GestureDetector(
          onTap: pin.onTap,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _tone,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: _tone.withValues(alpha: 0.42),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.place_rounded,
              size: 12,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _VectorMapPainter extends CustomPainter {
  _VectorMapPainter({
    required this.pins,
    required this.route,
    required this.userLocation,
    required this.showLabels,
    required this.pulse,
    required this.project,
  });

  final List<PlacePin> pins;
  final List<({double lat, double lng})> route;
  final ({double lat, double lng})? userLocation;
  final bool showLabels;
  final double pulse;
  final Offset Function(({double lat, double lng})) project;

  static const _sea = Color(0xFFBCD9F0);
  static const _seaDeep = Color(0xFFA7CBE8);
  static const _land = Color(0xFFEDF1F7);
  static const _block = Color(0xFFDDE4EE);
  static const _park = Color(0xFFD3E3CE);
  static const _arterial = Color(0xFFFBF0D8);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _land);

    // Arabian Sea, west.
    final sea = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.30, 0)
      ..quadraticBezierTo(
        size.width * 0.20,
        size.height * 0.34,
        size.width * 0.27,
        size.height * 0.58,
      )
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.80,
        size.width * 0.46,
        size.height,
      )
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(sea, Paint()..color = _sea);

    // Back Bay, south.
    final backBay = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.90)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.86,
        size.width * 0.72,
        size.height * 0.96,
      )
      ..quadraticBezierTo(
        size.width * 0.86,
        size.height,
        size.width,
        size.height * 0.97,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(backBay, Paint()..color = _seaDeep);

    // Green pockets.
    final park = Paint()..color = _park;
    canvas.drawOval(
      Rect.fromLTWH(size.width * 0.40, size.height * 0.08, 60, 34),
      park,
    );
    canvas.drawOval(
      Rect.fromLTWH(size.width * 0.52, size.height * 0.30, 44, 26),
      park,
    );
    canvas.drawOval(
      Rect.fromLTWH(size.width * 0.74, size.height * 0.52, 70, 40),
      park,
    );

    // Street grid.
    final block = Paint()..color = _block;
    for (var r = 0; r < 7; r++) {
      for (var c = 0; c < 9; c++) {
        final x = size.width * 0.32 + c * (size.width * 0.075);
        final y = size.height * 0.06 + r * (size.height * 0.13);
        if (x > size.width - 8) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, size.width * 0.055, size.height * 0.085),
            const Radius.circular(3),
          ),
          block,
        );
      }
    }

    // Arterials.
    final arterial = Paint()
      ..color = _arterial
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.34, size.height * 0.86)
        ..quadraticBezierTo(
          size.width * 0.46,
          size.height * 0.60,
          size.width * 0.50,
          size.height * 0.40,
        )
        ..quadraticBezierTo(
          size.width * 0.56,
          size.height * 0.20,
          size.width * 0.54,
          0,
        ),
      arterial,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.30, size.height * 0.42)
        ..quadraticBezierTo(
          size.width * 0.55,
          size.height * 0.36,
          size.width,
          size.height * 0.30,
        ),
      arterial,
    );

    // Minor streets.
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.16 + i * 0.16);
      canvas.drawLine(
        Offset(size.width * 0.33, y),
        Offset(size.width, y + size.height * 0.02),
        road,
      );
    }
    for (var i = 0; i < 4; i++) {
      final x = size.width * (0.40 + i * 0.16);
      canvas.drawLine(
        Offset(x, size.height * 0.02),
        Offset(x - size.width * 0.03, size.height * 0.95),
        road,
      );
    }

    // Sea-link bridges.
    final bridge = Paint()
      ..color = const Color(0xFFC7B9A4)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 2; i++) {
      final y = size.height * (0.62 + i * 0.16);
      canvas.drawLine(
        Offset(0, y + size.height * 0.10),
        Offset(size.width * (0.30 - i * 0.10), y),
        bridge,
      );
    }

    // Route through the pins, in order.
    if (route.length > 1) {
      final points = route.map(project).toList();
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.violet.withValues(alpha: 0.32)
          ..strokeWidth = 6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.violet
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else if (pins.length > 1) {
      final points = pins.map((p) => project(p.position)).toList();
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.violet
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // User location with a breathing halo.
    final user = userLocation;
    if (user != null) {
      final at = project(user);
      final halo = math.sin(pulse * math.pi) * 0.5 + 0.5;
      canvas.drawCircle(
        at,
        18 + halo * 14,
        Paint()..color = AppColors.blue.withValues(alpha: 0.08 + halo * 0.10),
      );
      canvas.drawCircle(at, 6, Paint()..color = AppColors.blue);
      canvas.drawCircle(
        at,
        6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    if (showLabels) {
      _label(canvas, 'ARABIAN SEA', Offset(size.width * 0.03, size.height * 0.42));
      _label(canvas, 'FORT', Offset(size.width * 0.46, size.height * 0.36));
      _label(canvas, 'COLABA', Offset(size.width * 0.33, size.height * 0.70));
      _label(canvas, 'BANDRA', Offset(size.width * 0.74, size.height * 0.14));
      _label(canvas, 'WORLI', Offset(size.width * 0.12, size.height * 0.34));
      _label(canvas, 'BACK BAY', Offset(size.width * 0.60, size.height * 0.93));
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
      old.pins.length != pins.length ||
      old.route.length != route.length ||
      old.pulse != pulse ||
      old.showLabels != showLabels ||
      old.userLocation != userLocation;
}

/// Legend explaining the pin tones.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key, this.showRoute = true});

  final bool showRoute;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        const _LegendDot(color: AppColors.blue, label: 'You'),
        const _LegendDot(color: AppColors.success, label: 'Feasible'),
        const _LegendDot(color: AppColors.warning, label: 'Partial'),
        const _LegendDot(color: AppColors.danger, label: 'Blocked'),
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
