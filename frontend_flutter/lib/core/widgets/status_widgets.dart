import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// Open/closed status pill. `null` openTime means unknown.
class OpenStatusPill extends StatelessWidget {
  const OpenStatusPill({required this.isOpen, this.label, super.key});

  final bool isOpen;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.open : AppColors.closed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label ?? (isOpen ? 'Open' : 'Closed'),
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small metadata pill: icon + text, e.g. `12 min`, `₹80`.
class InfoPill extends StatelessWidget {
  const InfoPill({
    required this.icon,
    required this.text,
    this.color,
    super.key,
  });

  const InfoPill.minutes(this.text, {super.key})
    : icon = Icons.schedule_rounded,
      color = null;

  InfoPill.cost(num value, {super.key})
    : icon = Icons.payments_outlined,
      color = null,
      text = Fmt.inr(value);

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: resolved),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: resolved,
          ),
        ),
      ],
    );
  }
}

/// Star + rating + review count.
class RatingRow extends StatelessWidget {
  const RatingRow({
    required this.rating,
    this.reviewCount,
    this.size = 14,
    this.showReviews = true,
    super.key,
  });

  final double rating;
  final num? reviewCount;
  final double size;
  final bool showReviews;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.star_rounded, size: size + 2, color: AppColors.star),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (showReviews && reviewCount != null) ...<Widget>[
          const SizedBox(width: 4),
          Text(
            '(${Fmt.compactCount(reviewCount!)})',
            style: TextStyle(
              fontSize: size - 1.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
