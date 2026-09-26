import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/place_image.dart';
import '../../models/itinerary.dart';
import '../../models/place.dart';
import '../../models/recommendation.dart';
import '../../models/search_params.dart';
import '../home/widgets/home_widgets.dart';

/// Itinerary / plan — sixth reference frame.
class ItineraryScreen extends StatelessWidget {
  const ItineraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final ItineraryPlan? plan = state.plan;
    final List<Recommendation> stops = state.itineraryStops;

    if (stops.isEmpty) {
      return const Scaffold(body: _EmptyItinerary());
    }

    final int totalMinutes =
        plan?.totalMinutes ??
        stops.fold<int>(0, (int sum, Recommendation r) => sum + r.totalMinutes);
    final int totalCost =
        plan?.totalCost ??
        stops.fold<int>(
          0,
          (int sum, Recommendation r) => sum + r.place.avgCost,
        );
    final int travelMinutes =
        plan?.travelMinutes ??
        stops.fold<int>(
          0,
          (int sum, Recommendation r) => sum + r.travelMinutes,
        );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _PlanHeader(
              title: plan?.title ?? 'Your Plan',
              stopCount: stops.length,
              totalMinutes: totalMinutes,
              totalCost: totalCost,
              saved: plan?.isSaved ?? false,
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.sm,
                  Insets.page,
                  Insets.lg,
                ),
                itemCount: stops.length,
                onReorderItem: state.moveStop,
                proxyDecorator:
                    (Widget child, int index, Animation<double> animation) {
                      return Material(
                        color: Colors.transparent,
                        elevation: 8,
                        borderRadius: Radii.cardRadius,
                        child: child,
                      );
                    },
                itemBuilder: (BuildContext context, int index) {
                  final Recommendation stop = stops[index];
                  return _StopTile(
                    key: ValueKey<String>('stop-${stop.place.id}'),
                    index: index,
                    stop: stop,
                    startLabel: plan?.stops[index].startTimeLabel,
                    isLast: index == stops.length - 1,
                    onRemove: () => state.removeFromItinerary(stop.place.id),
                  );
                },
              ),
            ),
            _PlanFooter(
              travelMinutes: travelMinutes,
              totalMinutes: totalMinutes,
              totalCost: totalCost,
              isSaved: plan?.isSaved ?? false,
              isBuilding: state.isBuildingPlan,
              onSave: () {
                if (plan == null) {
                  state.buildPlan();
                } else {
                  state.savePlan();
                }
              },
              onModify: () => _showWhatIf(context, state),
              onClear: state.clearItinerary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWhatIf(BuildContext context, AppState state) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => const _WhatIfSheet(),
    );
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({
    required this.title,
    required this.stopCount,
    required this.totalMinutes,
    required this.totalCost,
    required this.saved,
  });

  final String title;
  final int stopCount;
  final int totalMinutes;
  final int totalCost;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.md,
        Insets.page,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              if (saved)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.open.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: AppColors.open,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Saved',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.open,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$stopCount ${stopCount == 1 ? 'stop' : 'stops'} · '
            '~${Fmt.duration(totalMinutes)} · ${Fmt.inrExact(totalCost)} (est.)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required super.key,
    required this.index,
    required this.stop,
    required this.isLast,
    required this.onRemove,
    this.startLabel,
  });

  final int index;
  final Recommendation stop;
  final bool isLast;
  final VoidCallback onRemove;
  final String? startLabel;

  @override
  Widget build(BuildContext context) {
    final Place place = stop.place;
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(Insets.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.cardRadius,
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _NumberBadge(index: index + 1),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
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
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(
                            Icons.drag_handle_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Text(
                          '${Fmt.duration(stop.place.durationMin)} visit',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (startLabel != null) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.lavender,
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: Text(
                              startLabel!,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      place.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Insets.sm),
                    Row(
                      children: <Widget>[
                        PlaceThumb(
                          imageUrl: place.imageUrl,
                          seed: place.name,
                          icon: place.category.icon,
                          size: 40,
                        ),
                        const SizedBox(width: Insets.sm),
                        Expanded(
                          child: Text(
                            '${place.category.label} · '
                            '${Fmt.inrExact(place.avgCost)} · '
                            '${Fmt.duration(stop.travelMinutes)} away',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: onRemove,
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 17,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 26),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: const Icon(
                    Icons.directions_car_rounded,
                    size: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Text(
                  '${Fmt.duration(stop.travelMinutes)} travel',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$index',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PlanFooter extends StatelessWidget {
  const _PlanFooter({
    required this.travelMinutes,
    required this.totalMinutes,
    required this.totalCost,
    required this.isSaved,
    required this.isBuilding,
    required this.onSave,
    required this.onModify,
    required this.onClear,
  });

  final int travelMinutes;
  final int totalMinutes;
  final int totalCost;
  final bool isSaved;
  final bool isBuilding;
  final VoidCallback onSave;
  final VoidCallback onModify;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.md,
        Insets.page,
        Insets.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _TotalCell(
                    label: 'Total time',
                    value: Fmt.duration(totalMinutes),
                  ),
                ),
                Expanded(
                  child: _TotalCell(
                    label: 'In travel',
                    value: Fmt.duration(travelMinutes),
                  ),
                ),
                Expanded(
                  child: _TotalCell(
                    label: 'Est. cost',
                    value: Fmt.inrExact(totalCost),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            FilledButton(
              onPressed: isBuilding ? null : onSave,
              child: isBuilding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isSaved ? 'Plan saved' : 'Save Plan'),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onModify,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Modify Plan (What-if)'),
                  ),
                ),
                const SizedBox(width: Insets.md),
                OutlinedButton(
                  onPressed: onClear,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.delete_outline_rounded, size: 19),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalCell extends StatelessWidget {
  const _TotalCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _EmptyItinerary extends StatelessWidget {
  const _EmptyItinerary();

  @override
  Widget build(BuildContext context) {
    final AppState state = context.read<AppState>();
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[AppColors.primary, AppColors.indigo],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(Radii.xl),
                ),
                child: const Icon(
                  Icons.route_rounded,
                  size: 38,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: Insets.xl),
              const Text(
                'No plan yet',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Find experiences and add a few stops — LocalIQ will order them '
                'and estimate travel time for you.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: Insets.xl),
              FilledButton(
                onPressed: () {
                  if (state.recommendations.isNotEmpty) {
                    state.addTopRecommendation();
                  } else {
                    state.showHome();
                  }
                },
                child: Text(
                  state.recommendations.isEmpty
                      ? 'Find experiences'
                      : 'Add top recommendation',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "What-if" sheet: change one constraint and the plan adapts.
class _WhatIfSheet extends StatefulWidget {
  const _WhatIfSheet();

  @override
  State<_WhatIfSheet> createState() => _WhatIfSheetState();
}

class _WhatIfSheetState extends State<_WhatIfSheet> {
  late double _hours;
  late int _budget;
  String _focus = 'Balanced';

  @override
  void initState() {
    super.initState();
    final SearchParams params = context.read<AppState>().params;
    _hours = params.timeHours;
    _budget = params.budgetInr;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        0,
        Insets.page,
        Insets.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SheetTitle(title: 'Modify your plan'),
          const Text(
            'Change a constraint and LocalIQ re-ranks the stops that still fit.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: Insets.lg),
          Text(
            'More time: ${_hours.round()}h',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Slider(
            value: _hours.clamp(1, 12),
            min: 1,
            max: 12,
            divisions: 11,
            label: '${_hours.round()}h',
            onChanged: (double v) => setState(() => _hours = v),
          ),
          Text(
            'Budget: ${Fmt.inrExact(_budget)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Slider(
            value: _budget.clamp(200, 5000).toDouble(),
            min: 200,
            max: 5000,
            divisions: 24,
            label: Fmt.inrExact(_budget),
            onChanged: (double v) => setState(() => _budget = v.round()),
          ),
          const Text(
            'Focus',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.sm,
            children: <Widget>[
              for (final String option in <String>[
                'Balanced',
                'Indoor only',
                'Cheapest',
                'Only food',
              ])
                ChoiceChip(
                  label: Text(option),
                  selected: _focus == option,
                  onSelected: (_) => setState(() => _focus = option),
                ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          FilledButton(
            onPressed: () async {
              final AppState state = context.read<AppState>();
              state.setTimeHours(_hours);
              state.setBudget(_budget);
              if (_focus == 'Only food') {
                state.setInterests(<PlaceCategory>{PlaceCategory.food});
              } else if (_focus == 'Indoor only') {
                state.setInterests(<PlaceCategory>{...state.params.interests});
                state.setFilters(const FilterOptions(indoorOnly: true));
              } else if (_focus == 'Cheapest') {
                state.setSort(SortOption.costLowToHigh);
              } else {
                state.setSort(SortOption.recommended);
              }
              await state.findExperiences();
              if (!context.mounted) return;
              await state.buildPlan();
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Plan updated for $_focus · ${_hours.round()}h',
                  ),
                ),
              );
            },
            child: const Text('Apply changes'),
          ),
        ],
      ),
    );
  }
}
