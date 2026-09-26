import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Network and asset image handler with category-tinted placeholder and resilient fallback.
///
/// Ensures images never collapse layout, supports both assets and remote URLs,
/// and handles CORS / offline environments gracefully.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.borderRadius,
    this.tint,
    this.fit = BoxFit.cover,
    this.fallbackLabel,
  });

  final String url;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;
  final Color? tint;
  final BoxFit fit;
  final String? fallbackLabel;

  bool get _isAsset =>
      url.startsWith('assets/') ||
      url.startsWith('asset:') ||
      url.startsWith('packages/');

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.md);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: _buildImage(context),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    if (url.isEmpty) {
      return _Placeholder(tint: tint, label: fallbackLabel);
    }

    if (_isAsset) {
      final cleanPath = url.replaceFirst('asset:', '');
      return Image.asset(
        cleanPath,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, _, _) =>
            _Placeholder(tint: tint, label: fallbackLabel),
      );
    }

    return Image.network(
      url,
      height: height,
      width: width,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) =>
          _Placeholder(tint: tint, label: fallbackLabel),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        final total = progress.expectedTotalBytes;
        final loaded = progress.cumulativeBytesLoaded;
        return _Placeholder(
          tint: tint,
          loading: true,
          progress: total != null && total > 0 ? loaded / total : null,
          label: fallbackLabel,
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    this.tint,
    this.loading = false,
    this.progress,
    this.label,
  });

  final Color? tint;
  final bool loading;
  final double? progress;
  final String? label;

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
            base.withValues(alpha: 0.12),
            base.withValues(alpha: 0.22),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                loading ? Icons.image_outlined : Icons.landscape_rounded,
                color: base.withValues(alpha: 0.55),
                size: 28,
              ),
              if (label != null && label!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: base.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (loading && progress != null)
            Positioned(
              bottom: 8,
              left: 16,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: base.withValues(alpha: 0.1),
                  color: base.withValues(alpha: 0.6),
                  minHeight: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
