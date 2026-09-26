import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Network image with a branded, category-tinted placeholder so layout never
/// collapses while loading, and a legible fallback when offline.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.borderRadius,
    this.tint,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;
  final Color? tint;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.md);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: url.isEmpty
            ? _Placeholder(tint: tint)
            : Image.network(
                url,
                fit: fit,
                gaplessPlayback: true,
                errorBuilder: (context, _, _) => _Placeholder(tint: tint),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _Placeholder(tint: tint, loading: true),
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.tint, this.loading = false});

  final Color? tint;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final base = tint ?? AppColors.primary;
    return Container(
      height: double.infinity,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: 0.10),
            base.withValues(alpha: 0.18),
          ],
        ),
      ),
      child: Icon(
        loading ? Icons.image_outlined : Icons.landscape_outlined,
        color: base.withValues(alpha: 0.45),
        size: 26,
      ),
    );
  }
}
