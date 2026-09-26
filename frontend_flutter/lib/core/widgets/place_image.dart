import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

/// Image with a deterministic branded gradient fallback.
///
/// Remote placeholder photos are used when [AppConfig.enableRemoteImages] is
/// true; otherwise (and on any network error) the gradient + category glyph is
/// rendered so the UI never shows a broken image.
class PlaceImage extends StatelessWidget {
  const PlaceImage({
    required this.imageUrl,
    required this.seed,
    required this.icon,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String? imageUrl;
  final String seed;
  final IconData icon;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  /// Backend-relative image paths (e.g. the photo proxy
  /// `/api/v1/images/place?name=...`) become absolute LocalIQ URLs.
  /// Absolute URLs are passed through untouched.
  static String? _resolve(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('/')) return '${AppConfig.apiBaseUrl}$value';
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = borderRadius ?? BorderRadius.circular(Radii.md);
    final String? url = _resolve(imageUrl);
    final bool remoteEnabled = AppConfig.enableRemoteImages;

    Widget child;
    // Inline condition so `url` is promoted to non-null inside the branch.
    if (remoteEnabled && url != null && url.trim().isNotEmpty) {
      child = Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            _Placeholder(seed: seed, icon: icon, width: width, height: height),
        loadingBuilder:
            (BuildContext context, Widget child, ImageChunkEvent? progress) {
              if (progress == null) return child;
              return _Placeholder(
                seed: seed,
                icon: icon,
                width: width,
                height: height,
                showIcon: false,
              );
            },
      );
    } else {
      child = _Placeholder(
        seed: seed,
        icon: icon,
        width: width,
        height: height,
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(width: width, height: height, child: child),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.seed,
    required this.icon,
    required this.width,
    required this.height,
    this.showIcon = true,
  });

  final String seed;
  final IconData icon;
  final double? width;
  final double? height;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final pair =
        AppColors.placeholderGradients[seed.hashCode.abs() %
            AppColors.placeholderGradients.length];
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: pair,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: showIcon
          ? Center(
              child: FractionallySizedBox(
                widthFactor: 0.42,
                child: FittedBox(
                  child: Icon(icon, color: Colors.white.withValues(alpha: 0.9)),
                ),
              ),
            )
          : null,
    );
  }
}

/// Square thumbnail used in the itinerary route strip.
class PlaceThumb extends StatelessWidget {
  const PlaceThumb({
    required this.imageUrl,
    required this.seed,
    required this.icon,
    this.size = 56,
    super.key,
  });

  final String? imageUrl;
  final String seed;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PlaceImage(
      imageUrl: imageUrl,
      seed: seed,
      icon: icon,
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(Radii.sm),
    );
  }
}
