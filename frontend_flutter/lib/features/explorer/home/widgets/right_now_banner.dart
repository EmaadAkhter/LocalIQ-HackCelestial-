import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/right_now_context.dart';

/// Compact Right Now banner shown on the home feed and discover screens.
///
/// Summarizes the live contextual state in a single dismissible strip.
class RightNowBanner extends StatelessWidget {
  const RightNowBanner({super.key, required this.context});

  final RightNowContext context;

  @override
  Widget build(BuildContext ctxt) {
    final isPositive = !context.isRaining && context.crowdLevel.index <= 2;
    final accent = isPositive ? AppColors.success : AppColors.warning;
    final surfaceColor = isPositive ? AppColors.successSurface : AppColors.warningSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            isPositive ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.statusLabel,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${context.weatherLabel} · ${context.crowdLevel.label}',
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.80),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            context.weatherCondition.icon,
            size: 20,
            color: accent.withValues(alpha: 0.70),
          ),
        ],
      ),
    );
  }
}
