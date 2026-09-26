import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The mark. Prefers the bundled asset and falls back to a painted version so
/// the header is never empty.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.height = 32});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      height: height,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, _, _) => _PaintedMark(height: height),
    );
  }
}

class _PaintedMark extends StatelessWidget {
  const _PaintedMark({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height,
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide * 0.26;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      Paint()..color = AppColors.navy,
    );
    final pin = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.40),
          radius: size.shortestSide * 0.19,
        ),
      )
      ..moveTo(size.width * 0.30, size.height * 0.50)
      ..lineTo(size.width * 0.5, size.height * 0.80)
      ..lineTo(size.width * 0.70, size.height * 0.50)
      ..close();
    canvas.drawPath(pin, Paint()..color = const Color(0xFF8B7BFF));
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.40),
      size.shortestSide * 0.075,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mark plus the product name.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.height = 32, this.showTagline = true});

  final double height;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(height: height),
        if (showTagline) ...[
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LocalIQ',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: height * 0.5,
                  color: AppColors.primary,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              Text(
                'Discover local. Smarter.',
                style: TextStyle(
                  fontSize: height * 0.32,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Wordmark only, for the wide app bar where the mark already sits beside it.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'LocalIQ',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16.5,
            color: AppColors.primary,
            letterSpacing: -0.3,
            height: 1.1,
          ),
        ),
        Text(
          'Discover local. Smarter.',
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
