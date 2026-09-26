import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_image.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../context/application/discovery_context_controller.dart';
import '../../../context/domain/discovery_context.dart';
import '../../../itinerary/application/itinerary_controller.dart';
import '../../../places/domain/place.dart';
import '../../../recommendations/domain/recommendation.dart';
import '../../../saved/application/saved_controller.dart';

/// The recommendation card.
///
/// Renders the three feasibility tiers with the exact reason behind them, and
/// exposes the two explanation surfaces ("why this fits" / "why this ranked")
/// that make the engine's reasoning inspectable.
class RecommendationCard extends ConsumerWidget {
  const RecommendationCard({
    super.key,
    required this.recommendation,
    this.compact = false,
  });

  final Recommendation recommendation;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 620 && !compact;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(
          '/place/${rec.experience.id}?place=${rec.place.id}',
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: rec.tier == FeasibilityTier.notFeasible
                  ? AppColors.danger.withValues(alpha: 0.28)
                  : rec.tier == FeasibilityTier.partial
                      ? AppColors.warning.withValues(alpha: 0.30)
                      : AppColors.border,
            ),
            boxShadow: AppShadows.card,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg - 1),
            child: wide ? _wideLayout(context, ref) : _stackedLayout(context, ref),
          ),
        ),
      ),
    );
  }

  Widget _wideLayout(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(1),
          child: AppImage(
            url: rec.experience.imageUrl,
            width: 132,
            height: 156,
            tint: categoryColor(rec.experience.category),
            borderRadius: BorderRadius.zero,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: _Body(recommendation: rec, showSave: true),
          ),
        ),
      ],
    );
  }

  Widget _stackedLayout(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AppImage(
              url: rec.experience.imageUrl,
              height: 148,
              tint: categoryColor(rec.experience.category),
              borderRadius: BorderRadius.zero,
            ),
            Positioned(left: 10, top: 10, child: _RankChip(rec)),
            Positioned(
              right: 8,
              top: 8,
              child: _SaveButton(recommendation: rec),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: _Body(recommendation: rec, showSave: false),
        ),
      ],
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip(this.rec);

  final Recommendation rec;

  @override
  Widget build(BuildContext context) {
    final feasible = rec.tier == FeasibilityTier.feasible;
    final label = feasible ? '#${rec.rank}' : rec.tier.label;
    final color = rec.tier.color;
    return Container(
      height: 26,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!feasible) ...[
            Icon(rec.tier.icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.recommendation});

  final Recommendation recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      isSavedProvider(recommendation.experience.id),
    );
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          ref.read(savedControllerProvider.notifier).toggle(recommendation);
          showAppToast(
            context,
            saved ? 'Removed from saved' : 'Saved for later',
            icon: saved ? Icons.heart_broken_rounded : Icons.favorite_rounded,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: AnimatedSwitcher(
            duration: AppMotion.fast,
            child: Icon(
              saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(saved),
              size: 16,
              color: saved ? AppColors.danger : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.recommendation, required this.showSave});

  final Recommendation recommendation;
  final bool showSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    final place = rec.place;
    final experience = rec.experience;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSave)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  experience.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16.5,
                    height: 1.2,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SaveButton(recommendation: rec),
            ],
          )
        else
          Text(
            experience.title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16.5,
              height: 1.2,
              letterSpacing: -0.2,
            ),
          ),
        const SizedBox(height: 3),
        Text(
          experience.tagline,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.star_rounded, size: 16, color: AppColors.star),
            Text(
              place.rating.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
            Text(
              '(${_compact(place.reviewCount)})',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 2),
            AppBadge(
              label: experience.category.label,
              color: categoryColor(experience.category),
              dense: true,
            ),
            if (place.localFavourite)
              const AppBadge(
                label: 'LOCAL FAVOURITE',
                color: AppColors.violet,
                icon: Icons.diamond_rounded,
                dense: true,
              ),
            AppBadge(
              label: place.openingHours.isOpenAt(
                ref.watch(discoveryContextProvider).startTime,
              )
                  ? 'Open now'
                  : 'Closed',
              icon: place.openingHours.isOpenAt(
                ref.watch(discoveryContextProvider).startTime,
              )
                  ? Icons.check_circle_outline
                  : Icons.do_not_disturb_on_outlined,
              color: place.openingHours.isOpenAt(
                ref.watch(discoveryContextProvider).startTime,
              )
                  ? AppColors.success
                  : AppColors.danger,
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            MetaItem(icon: Icons.place_outlined, text: place.area),
            MetaItem(
              icon: Icons.directions_walk_rounded,
              text: '${rec.outboundTravel.minutes} min · '
                  '${rec.outboundTravel.mode.label}',
            ),
            MetaItem(
              icon: Icons.schedule_rounded,
              text: '${experience.activityMinutes} min there',
            ),
            MetaItem(
              icon: Icons.payments_outlined,
              text: experience.priceLabel,
              color: experience.typicalSpend == 0
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
            MetaItem(
              icon: experience.toleratesRain
                  ? Icons.umbrella_rounded
                  : Icons.wb_sunny_outlined,
              text: experience.weatherSuitability.label,
              color: experience.toleratesRain
                  ? AppColors.success
                  : AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          experience.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(height: 1.4, fontSize: 13),
        ),
        const SizedBox(height: 11),
        FeasibilityStrip(recommendation: rec),
        const SizedBox(height: 11),
        // A Wrap lays these out in flow order and wraps them onto new lines on
        // narrow screens. Do not add a Spacer/Expanded here: a Wrap accepts
        // WrapParentData only, so a Flex child throws a ParentDataWidget
        // assertion.
        Wrap(
          spacing: 6,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ExplanationButton(
              label: 'Why this fits',
              icon: Icons.checklist_rounded,
              onTap: () => showWhySheet(context, rec, WhyPanel.fits),
            ),
            _ExplanationButton(
              label: 'Why ranked here',
              icon: Icons.insights_rounded,
              onTap: () => showWhySheet(context, rec, WhyPanel.ranked),
            ),
            PlanToggleButton(recommendation: rec),
          ],
        ),
      ],
    );
  }

  static String _compact(int value) {
    if (value >= 1000) {
      final k = value / 1000;
      return '${k >= 10 || k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
    }
    return '$value';
  }
}

/// The headline verdict with the reason, plus a utilisation bar.
class FeasibilityStrip extends ConsumerWidget {
  const FeasibilityStrip({super.key, required this.recommendation});

  final Recommendation recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = recommendation;
    final available = ref.watch(
      discoveryContextProvider.select((c) => c.timeBudgetMinutes),
    );
    final color = rec.tier.color;
    final ratio = (rec.completableMinutes / available.clamp(1, 1000)).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(rec.tier.icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rec.tier == FeasibilityTier.notFeasible
                      ? rec.primaryBlocker
                      : rec.verdict,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${rec.completableMinutes} / $available min',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: AppMotion.medium,
              curve: AppMotion.curve,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: color.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${rec.outboundTravel.minutes} min out · '
            '${rec.experience.activityMinutes} min there · '
            '${rec.returnTravel.minutes} min back'
            '${rec.tier == FeasibilityTier.partial
                ? ' · trimmed to ${rec.experience.minimumMinutes} min it fits'
                : ''}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class PlanToggleButton extends ConsumerWidget {
  const PlanToggleButton({super.key, required this.recommendation});

  final Recommendation recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inPlan = ref.watch(
      itineraryControllerProvider
          .select((state) => state.value?.stops.any(
                (s) => s.experienceId == recommendation.experience.id,
              ) ??
              false),
    );
    final canAdd = recommendation.canAddToPlan;

    if (inPlan) {
      return OutlinedButton.icon(
        onPressed: () async {
          final controller = ref.read(itineraryControllerProvider.notifier);
          final itinerary = ref.read(itineraryControllerProvider).value;
          final stop = itinerary?.stops.where(
            (s) => s.experienceId == recommendation.experience.id,
          );
          if (stop != null && stop.isNotEmpty) {
            await controller.remove(stop.first.id);
            if (!context.mounted) return;
            showAppToast(
              context,
              'Removed from your plan',
              icon: Icons.playlist_remove_rounded,
            );
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: BorderSide(color: AppColors.danger.withValues(alpha: 0.35)),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: const Icon(Icons.playlist_remove_rounded, size: 16),
        label: const Text('In plan · Remove'),
      );
    }

    return FilledButton.icon(
      onPressed: canAdd
          ? () async {
              await ref
                  .read(itineraryControllerProvider.notifier)
                  .add(recommendation);
              if (!context.mounted) return;
              showAppToast(
                context,
                '${recommendation.experience.title} added to My Plan',
                icon: Icons.playlist_add_check_rounded,
              );
            }
          : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      icon: const Icon(Icons.add_rounded, size: 16),
      label: Text(canAdd ? 'Add to plan' : 'Cannot add'),
    );
  }
}

class _ExplanationButton extends StatelessWidget {
  const _ExplanationButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}

enum WhyPanel { fits, ranked }

/// Bottom sheet exposing the engine's reasoning verbatim.
void showWhySheet(
  BuildContext context,
  Recommendation rec,
  WhyPanel panel,
) {
  final title = panel == WhyPanel.fits ? 'Why this fits' : 'Why ranked here';
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (context) {
      final passes = rec.constraints
          .where((c) => c.status == ConstraintStatus.pass)
          .toList();
      final caveats = rec.constraints
          .where((c) => c.status == ConstraintStatus.warn)
          .toList();
      final blocks = rec.constraints.where((c) => c.isBlocking).toList();

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            rec.experience.title,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppBadge(
                      label: rec.tier.label.toUpperCase(),
                      color: rec.tier.color,
                      icon: rec.tier.icon,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (panel == WhyPanel.ranked) ...[
                  AppPanel(
                    color: AppColors.surfaceMuted,
                    elevated: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Ranking logic'),
                        const SizedBox(height: 6),
                        Text(
                          rec.whyRanked,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const FieldLabel('Relevance'),
                            const Spacer(),
                            Text(
                              rec.score.toStringAsFixed(0),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: rec.score / 100,
                            minHeight: 5,
                            backgroundColor: AppColors.border,
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.violet,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (blocks.isNotEmpty) ...[
                  _ConstraintSection(
                    title: 'What blocks it',
                    color: AppColors.danger,
                    results: blocks,
                  ),
                  const SizedBox(height: 14),
                ],
                if (caveats.isNotEmpty) ...[
                  _ConstraintSection(
                    title: 'Trade-offs',
                    color: AppColors.warning,
                    results: caveats,
                  ),
                  const SizedBox(height: 14),
                ],
                _ConstraintSection(
                  title: 'What works',
                  color: AppColors.success,
                  results: passes,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ConstraintSection extends StatelessWidget {
  const _ConstraintSection({
    required this.title,
    required this.color,
    required this.results,
  });

  final String title;
  final Color color;
  final List<ConstraintResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '$title (${results.length})',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final result in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    result.status == ConstraintStatus.pass
                        ? Icons.check_circle_rounded
                        : result.status == ConstraintStatus.warn
                            ? Icons.info_rounded
                            : Icons.block_rounded,
                    size: 16,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.detail,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Format helper reused by the mini-plan and detail screens.
String formatClock(DateTime time) {
  final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m ${time.hour >= 12 ? 'PM' : 'AM'}';
}

String formatDuration(int minutes) => DiscoveryContext.formatMinutes(minutes);
