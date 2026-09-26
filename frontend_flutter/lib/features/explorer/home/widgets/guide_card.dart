import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/guide.dart';

/// Compact guide card for home screen horizontal carousel.
class GuideCard extends StatelessWidget {
  const GuideCard({
    super.key,
    required this.guide,
    required this.onTap,
  });

  final dynamic guide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAvailable = guide is Guide
        ? (guide as Guide).isAvailableNow
        : (guide['available'] as bool? ?? false);
    final name = guide is Guide ? (guide as Guide).name : (guide['name'] as String? ?? '');
    final specialty = guide is Guide
        ? ((guide as Guide).specialties.isNotEmpty ? (guide as Guide).specialties.first : 'Local Guide')
        : (guide['specialty'] as String? ?? '');
    final rating = guide is Guide ? (guide as Guide).rating : (guide['rating'] ?? 4.8);
    final rate = guide is Guide ? (guide as Guide).hourlyRateInr : (guide['rate'] ?? 700);
    final initials = name.split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join();
    const color = AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, color.withValues(alpha: 0.60)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials.isEmpty ? 'G' : initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  if (isAvailable)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                specialty,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded,
                      size: 11, color: AppColors.star),
                  const SizedBox(width: 2),
                  Text(
                    '$rating',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '₹$rate/hr',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isAvailable ? '✓ Available today' : 'Unavailable',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isAvailable ? AppColors.success : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
