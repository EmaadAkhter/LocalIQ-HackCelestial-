import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_state.dart';
import '../../../app/router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/place_image.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../../models/place.dart';
import '../../../models/recommendation.dart';
import '../../../models/search_params.dart';
import '../home/widgets/home_widgets.dart';

/// Recommendations list — third reference frame.
class RecommendationsScreen extends StatelessWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<Recommendation> items = state.recommendations;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _ResultsHeader(
              subtitle: _subtitle(state),
              sort: state.sort,
              onSort: () => _showSortSheet(context, state),
              onFilter: () => _showFilterSheet(context, state),
              filterCount: _activeFilterCount(state.filters),
              weather: state.weatherSummary,
            ),
            Expanded(
              child: items.isEmpty
                  ? _EmptyResults(
                      onReset: () {
                        state.clearFilters();
                        state.showHome();
                      },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.page,
                        Insets.md,
                        Insets.page,
                        Insets.xl,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Insets.md),
                      itemBuilder: (BuildContext context, int index) {
                        return RecommendationCard(recommendation: items[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitle(AppState state) {
    final String hours = state.params.timeHours.round() == 1
        ? '1 hour'
        : '${state.params.timeHours.round()} hours';
    return 'Based on your $hours · ${Fmt.inrExact(state.params.budgetInr)} · '
        '${state.params.groupType.label}';
  }

  static int _activeFilterCount(FilterOptions filters) {
    int count = 0;
    if (filters.maxCost != null) count++;
    if (filters.maxTravelMinutes != null) count++;
    if (filters.indoorOnly) count++;
    if (!filters.openOnly) count++;
    return count;
  }

  Future<void> _showSortSheet(BuildContext context, AppState state) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SheetTitle(title: 'Sort by'),
            for (final SortOption option in SortOption.values)
              ListTile(
                onTap: () {
                  state.setSort(option);
                  Navigator.of(sheetContext).pop();
                },
                leading: Icon(option.icon, size: 19, color: AppColors.primary),
                title: Text(option.label),
                trailing: state.sort == option
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
              ),
            const SizedBox(height: Insets.md),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilterSheet(BuildContext context, AppState state) async {
    FilterOptions draft = state.filters;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  0,
                  Insets.page,
                  Insets.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SheetTitle(title: 'Filters'),
                    _FilterLabel('Max spend per person'),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: <Widget>[
                        for (final int value in <int>[200, 500, 1000, 2000])
                          ChoiceChip(
                            label: Text(Fmt.inrExact(value)),
                            selected: draft.maxCost == value,
                            onSelected: (bool on) => setSheetState(() {
                              draft = on
                                  ? draft.copyWith(maxCost: value)
                                  : draft.copyWith(clearCost: true);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: Insets.lg),
                    _FilterLabel('Max travel time'),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: <Widget>[
                        for (final int value in <int>[10, 20, 30, 45])
                          ChoiceChip(
                            label: Text('$value min'),
                            selected: draft.maxTravelMinutes == value,
                            onSelected: (bool on) => setSheetState(() {
                              draft = on
                                  ? draft.copyWith(maxTravelMinutes: value)
                                  : draft.copyWith(clearTravel: true);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: Insets.lg),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: draft.indoorOnly,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.primary,
                      title: const Text(
                        'Indoor only',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onChanged: (bool v) => setSheetState(
                        () => draft = draft.copyWith(indoorOnly: v),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: draft.openOnly,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.primary,
                      title: const Text(
                        'Open right now',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onChanged: (bool v) => setSheetState(
                        () => draft = draft.copyWith(openOnly: v),
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              state.clearFilters();
                              Navigator.of(sheetContext).pop();
                            },
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              state.setFilters(draft);
                              Navigator.of(sheetContext).pop();
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.subtitle,
    required this.sort,
    required this.onSort,
    required this.onFilter,
    required this.filterCount,
    required this.weather,
  });

  final String subtitle;
  final SortOption sort;
  final VoidCallback onSort;
  final VoidCallback onFilter;
  final int filterCount;
  final String? weather;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, Insets.sm, Insets.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: 'Local'),
                    TextSpan(
                      text: 'IQ',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onSort,
                tooltip: 'Sort: ${sort.label}',
                icon: const Icon(Icons.swap_vert_rounded),
              ),
              Stack(
                children: <Widget>[
                  IconButton(
                    onPressed: onFilter,
                    tooltip: 'Filter',
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  if (filterCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$filterCount',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Top Experiences for You',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (weather != null) ...<Widget>[
                const SizedBox(width: 8),
                const Icon(
                  Icons.wb_cloudy_outlined,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    weather!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.lavender,
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: Insets.lg),
            const Text(
              'Nothing fits those constraints',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try adding more time, raising the budget, or clearing filters.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: Insets.xl),
            OutlinedButton(
              onPressed: onReset,
              child: const Text('Adjust search'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card used in the results list.
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({required this.recommendation, super.key});

  final Recommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final Place place = recommendation.place;
    final bool isOpen = place.isOpenAt(DateTime.now());
    final AppState state = context.read<AppState>();
    final bool saved = state.isInItinerary(place.id);

    return Material(
      color: AppColors.surface,
      borderRadius: Radii.cardRadius,
      child: InkWell(
        borderRadius: Radii.cardRadius,
        onTap: () => goToPlace(context, place),
        child: Container(
          padding: const EdgeInsets.all(Insets.md),
          decoration: BoxDecoration(
            borderRadius: Radii.cardRadius,
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PlaceThumb(
                imageUrl: place.imageUrl,
                seed: place.name,
                icon: place.category.icon,
                size: 84,
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            place.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            context.read<AppState>().toggleFavourite(place.id);
                          },
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              state.isFavourite(place.id)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 18,
                              color: state.isFavourite(place.id)
                                  ? AppColors.closed
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    RatingRow(
                      rating: place.rating,
                      reviewCount: place.reviewCount,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${place.category.label} · ${place.blurb}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: Insets.md,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        InfoPill.minutes('${recommendation.travelMinutes} min'),
                        InfoPill.cost(place.avgCost),
                        OpenStatusPill(isOpen: isOpen),
                        if (saved)
                          const InfoPill(
                            icon: Icons.check_circle_rounded,
                            text: 'In plan',
                            color: AppColors.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
