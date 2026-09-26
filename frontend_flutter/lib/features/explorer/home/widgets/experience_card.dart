import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../features/context/domain/context_models.dart';
import '../../../../features/places/domain/place.dart';
import '../../../../shared/widgets/app_image.dart';

/// Rich experience card for horizontal carousels.
///
/// Used in home feed sections, discover results, and saved lists.
/// Answers: Can I do this? Is it good for me? Is it good RIGHT NOW?
class ExperienceCard extends StatelessWidget {
  const ExperienceCard({
    super.key,
    required this.place,
    required this.onTap,
    this.rightNowLabel,
    this.isLocalGem = false,
    this.isSaved = false,
    this.onSave,
  });

  final Place place;
  final VoidCallback onTap;
  final String? rightNowLabel;
  final bool isLocalGem;
  final bool isSaved;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final isOpen = place.openingHours.isOpenAt(DateTime.now());

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 180,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero image
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.lg),
                    ),
                    child: place.heroImageUrl.isNotEmpty
                        ? AppImage(
                            url: place.heroImageUrl,
                            height: 120,
                            width: 180,
                            tint: categoryColor(place.category),
                          )
                        : _PlaceholderImage(
                            category: place.category,
                            height: 120,
                          ),
                  ),

                  // Save button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: onSave,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isSaved
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 15,
                          color: isSaved ? Colors.red : Colors.white,
                        ),
                      ),
                    ),
                  ),

                  // Badges
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        if (isLocalGem)
                          _Badge(label: 'LOCAL GEM', color: AppColors.violet),
                        if (rightNowLabel != null)
                          _Badge(
                            label: '⚡ $rightNowLabel',
                            color: AppColors.success,
                          ),
                        if (!isOpen)
                          _Badge(label: 'CLOSED', color: AppColors.danger),
                      ],
                    ),
                  ),
                ],
              ),

              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          height: 1.3,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 12, color: AppColors.star),
                          const SizedBox(width: 3),
                          Text(
                            place.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '· ${place.area}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            place.priceLabel,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: categoryColor(place.category)
                                  .withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              place.category.label,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: categoryColor(place.category),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wide experience card for list views in Discover and Saved.
class ExperienceListCard extends StatelessWidget {
  const ExperienceListCard({
    super.key,
    required this.place,
    required this.onTap,
    this.rightNowLabel,
    this.isLocalGem = false,
    this.isSaved = false,
    this.onSave,
    this.feasibilityLabel,
  });

  final Place place;
  final VoidCallback onTap;
  final String? rightNowLabel;
  final bool isLocalGem;
  final bool isSaved;
  final VoidCallback? onSave;
  final String? feasibilityLabel;

  @override
  Widget build(BuildContext context) {
    final isOpen = place.openingHours.isOpenAt(DateTime.now());

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppRadius.lg),
              ),
              child: place.heroImageUrl.isNotEmpty
                  ? AppImage(
                      url: place.heroImageUrl,
                      height: 110,
                      width: 100,
                      tint: categoryColor(place.category),
                    )
                  : _PlaceholderImage(
                      category: place.category,
                      height: 110,
                      width: 100,
                    ),
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category + badges row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: categoryColor(place.category)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            place.category.label,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: categoryColor(place.category),
                            ),
                          ),
                        ),
                        if (isLocalGem) ...[
                          const SizedBox(width: 5),
                          _Badge(
                              label: '💎 LOCAL GEM',
                              color: AppColors.violet),
                        ],
                        if (!isOpen) ...[
                          const SizedBox(width: 5),
                          _Badge(label: 'CLOSED', color: AppColors.danger),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.3,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 12, color: AppColors.star),
                        const SizedBox(width: 3),
                        Text(
                          '${place.rating.toStringAsFixed(1)} · ${place.area}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          place.priceLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        if (rightNowLabel != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.successSurface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              '⚡ $rightNowLabel',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (feasibilityLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        feasibilityLabel!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Save button
            Padding(
              padding: const EdgeInsets.all(10),
              child: GestureDetector(
                onTap: onSave,
                child: Icon(
                  isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 20,
                  color: isSaved ? Colors.red : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Gradient placeholder for places that have no image URL.
class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage({
    required this.category,
    this.height = 160,
    this.width = double.infinity,
  });

  final ExperienceCategory category;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.70),
            color.withValues(alpha: 0.40),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          _categoryIcon(category),
          size: 32,
          color: Colors.white.withValues(alpha: 0.70),
        ),
      ),
    );
  }

  static IconData _categoryIcon(ExperienceCategory cat) => switch (cat) {
        ExperienceCategory.food => Icons.restaurant_outlined,
        ExperienceCategory.art => Icons.palette_outlined,
        ExperienceCategory.history => Icons.account_balance_outlined,
        ExperienceCategory.culture => Icons.theater_comedy_outlined,
        ExperienceCategory.nature => Icons.park_outlined,
        ExperienceCategory.heritage => Icons.fort_outlined,
        ExperienceCategory.nightlife => Icons.nightlife_outlined,
        ExperienceCategory.shopping => Icons.shopping_bag_outlined,
        ExperienceCategory.wellness => Icons.spa_outlined,
        ExperienceCategory.adventure => Icons.hiking_outlined,
        ExperienceCategory.localLife => Icons.home_outlined,
      };
}
