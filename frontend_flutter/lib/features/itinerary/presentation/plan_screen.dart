import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../context/application/discovery_context_controller.dart';
import '../../context/domain/discovery_context.dart';
import '../../places/domain/place.dart';
import '../../places/presentation/widgets/constraint_panel.dart';
import '../../routing/presentation/localiq_map_view.dart';
import '../application/itinerary_controller.dart';
import '../domain/itinerary.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = Breakpoints.isDesktop(width);
    final gutter = Breakpoints.gutter(width);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = width >= 900 ? 4 : 2;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.maxContent),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header(),
                  const SizedBox(height: 18),
                  _StatsRow(columns: columns),
                  const SizedBox(height: 16),
                  const StartTimeField(),
                  const SizedBox(height: 18),
                  if (desktop)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(flex: 13, child: _Timeline()),
                          const SizedBox(width: 18),
                          SizedBox(width: 330, child: _SummaryRail()),
                        ],
                      ),
                    )
                  else
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Timeline(),
                        SizedBox(height: 18),
                        _SummaryRail(),
                      ],
                    ),
                  const SizedBox(height: 18),
                  const _TimeBreakdown(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Plan', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'A sequenced, feasibility-checked plan for ${discovery.locationLabel}, '
                'starting at ${_clock(discovery.startTime)}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add stops'),
        ),
      ],
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itinerary = ref.watch(itineraryControllerProvider).value;
    final discovery = ref.watch(discoveryContextProvider);
    final status = itinerary?.statusFor(discovery.timeBudgetMinutes) ??
        ItineraryStatus.empty;

    final tiles = <Widget>[
      StatTile(
        label: 'Total time',
        value: itinerary == null || itinerary.isEmpty
            ? '—'
            : itinerary.totalLabel,
        detail: 'of ${discovery.timeLabel} window',
        icon: Icons.schedule_rounded,
        tone: status.color,
      ),
      StatTile(
        label: 'Travel time',
        value: itinerary == null || itinerary.isEmpty
            ? '—'
            : '${itinerary.travelMinutes} min',
        detail: 'including the return leg',
        icon: Icons.directions_walk_rounded,
        tone: AppColors.blue,
      ),
      StatTile(
        label: 'Cost',
        value: itinerary?.costLabel ?? '—',
        detail: 'of ${discovery.budgetLabel} budget',
        icon: Icons.payments_outlined,
        tone: (itinerary?.totalCost ?? 0) <= discovery.budget
            ? AppColors.violet
            : AppColors.danger,
      ),
      StatTile(
        label: 'Return buffer',
        value: '${itinerary?.returnBufferMinutes ?? 12} min',
        detail: itinerary?.endAt != null
            ? 'back by ${_clock(itinerary!.endAt!)}'
            : 'reserved for delays',
        icon: Icons.flag_outlined,
        tone: AppColors.primary,
      ),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += columns) {
      final slice = tiles.sublist(i, (i + columns).clamp(0, tiles.length));
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: 10),
                Expanded(
                  child: c < slice.length ? slice[c] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(resolvedStopsProvider);
    final discovery = ref.watch(discoveryContextProvider);
    final itinerary = ref.watch(itineraryControllerProvider).value;

    if (stops.isEmpty) {
      return AppEmptyState(
        icon: Icons.route_outlined,
        title: 'Your plan is empty',
        message:
            'Add any achievable experience and the timeline, travel legs, cost '
            'and feasibility check are built automatically.',
        action: FilledButton.icon(
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.explore_rounded, size: 17),
          label: const Text('Browse experiences'),
        ),
      );
    }

    final route = <({double lat, double lng})>[
      (lat: discovery.centre.latitude, lng: discovery.centre.longitude),
      for (final stop in stops)
        (lat: stop.place.centre.latitude, lng: stop.place.centre.longitude),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPanel(
          child: LocalIqMapView(
            route: route,
            userLocation: (
              lat: discovery.centre.latitude,
              lng: discovery.centre.longitude,
            ),
            height: 190,
            showLabels: false,
          ),
        ),
        const SizedBox(height: 14),
        AppPanel(
          child: Column(
            children: [
              _OriginNode(
                time: _clock(discovery.startTime),
                title: 'Start · ${discovery.locationLabel}',
                subtitle: 'Depart ${_clock(discovery.startTime)}',
                color: AppColors.blue,
              ),
              for (var i = 0; i < stops.length; i++) ...[
                _StopCard(
                  stop: stops[i],
                  index: i,
                  travelMinutes: stops[i].stop.travelInMinutes,
                ),
                _OriginNode(
                  time: i == stops.length - 1
                      ? _clock(
                          stops[i].stop.departAt.add(
                            Duration(minutes: stops[i].stop.travelToMinutes),
                          ),
                        )
                      : _clock(stops[i].stop.departAt),
                  title: i == stops.length - 1
                      ? 'Return · ${discovery.locationLabel}'
                      : 'Next stop',
                  subtitle: i == stops.length - 1
                      ? '${stops[i].stop.travelToMinutes} min back + '
                          '${itinerary?.returnBufferMinutes ?? 12} min buffer'
                      : 'Depart ${_clock(stops[i].stop.departAt)}',
                  color: AppColors.primary,
                  isLast: i == stops.length - 1,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OriginNode extends StatelessWidget {
  const _OriginNode({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.color,
    this.isLast = false,
  });

  final String time;
  final String title;
  final String subtitle;
  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              time,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: color,
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopCard extends ConsumerWidget {
  const _StopCard({required this.stop, required this.index, required this.travelMinutes});

  final ResolvedStop stop;
  final int index;
  final int travelMinutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(itineraryControllerProvider.notifier);
    final notes = stop.stop.notes;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _clock(stop.stop.arriveAt),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 16),
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(child: Container(width: 2, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: AppPanel(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                onTap: () => context.push(
                  '/place/${stop.experience.id}?place=${stop.place.id}',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: AppImage(
                            url: stop.experience.imageUrl,
                            width: 62,
                            height: 62,
                            tint: categoryColor(stop.experience.category),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stop.experience.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${stop.place.area} · ${stop.timeLabel}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: stop.stop.locked
                                  ? 'Unlock this stop'
                                  : 'Keep this stop when re-checking',
                              onPressed: () => controller.toggleLock(stop.stop.id),
                              icon: Icon(
                                stop.stop.locked
                                    ? Icons.lock_rounded
                                    : Icons.lock_open_rounded,
                                size: 16,
                                color: stop.stop.locked
                                    ? AppColors.violet
                                    : AppColors.textMuted,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Move up',
                              onPressed: index == 0
                                  ? null
                                  : () => controller.move(index, index - 1),
                              icon: const Icon(
                                Icons.arrow_upward_rounded,
                                size: 16,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Move down',
                              onPressed: () =>
                                  controller.move(index, index + 2),
                              icon: const Icon(
                                Icons.arrow_downward_rounded,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        AppBadge(
                          label: '${stop.stop.activityMinutes} min',
                          icon: Icons.schedule_rounded,
                          color: AppColors.primary,
                          dense: true,
                        ),
                        AppBadge(
                          label: '$travelMinutes min travel',
                          icon: Icons.directions_walk_rounded,
                          color: AppColors.blue,
                          dense: true,
                        ),
                        AppBadge(
                          label: stop.stop.cost == 0
                              ? 'Free'
                              : '₹${stop.stop.cost}',
                          icon: Icons.payments_outlined,
                          color: stop.stop.cost == 0
                              ? AppColors.success
                              : AppColors.violet,
                          dense: true,
                        ),
                        AppBadge(
                          label: stop.experience.toleratesRain
                              ? 'Rain-safe'
                              : 'Exposed',
                          icon: stop.experience.toleratesRain
                              ? Icons.umbrella_rounded
                              : Icons.wb_sunny_outlined,
                          color: stop.experience.toleratesRain
                              ? AppColors.success
                              : AppColors.warning,
                          dense: true,
                        ),
                      ],
                    ),
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppColors.warningSurface,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          notes,
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await controller.remove(stop.stop.id);
                              if (!context.mounted) return;
                              showAppToast(
                                context,
                                '${stop.experience.title} removed',
                                icon: Icons.playlist_remove_rounded,
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 15),
                            label: const Text('Remove'),
                          ),
                          TextButton.icon(
                            onPressed: () => context.go('/home'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                            label: const Text('Swap'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRail extends ConsumerWidget {
  const _SummaryRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itinerary = ref.watch(itineraryControllerProvider).value;
    final discovery = ref.watch(discoveryContextProvider);
    final controller = ref.read(itineraryControllerProvider.notifier);
    final status = itinerary?.statusFor(discovery.timeBudgetMinutes) ??
        ItineraryStatus.empty;
    final slack = (itinerary?.slackAgainst(discovery.timeBudgetMinutes)) ?? 0;

    return Column(
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Plan summary',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _row('Stops', '${itinerary?.stopCount ?? 0}'),
              _row('Activity', '${itinerary?.activityMinutes ?? 0} min'),
              _row('Travel', '${itinerary?.travelMinutes ?? 0} min'),
              _row(
                'Return buffer',
                '${itinerary?.returnBufferMinutes ?? 12} min',
              ),
              _row('Total', itinerary?.totalLabel ?? '—'),
              _row('Cost', itinerary?.costLabel ?? '—'),
              if (itinerary?.endAt != null)
                _row('Wrap up', _clock(itinerary!.endAt!)),
              const Divider(height: 22),
              Row(
                children: [
                  Icon(status.icon, size: 16, color: status.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      switch (status) {
                        ItineraryStatus.onTrack =>
                          'Fits with $slack min to spare',
                        ItineraryStatus.tight =>
                          'Fits, but only $slack min of slack',
                        ItineraryStatus.overrunning =>
                          '${slack.abs()} min over your window',
                        ItineraryStatus.empty => 'Nothing planned yet',
                      },
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: status.color,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: itinerary == null || itinerary.isEmpty
                    ? null
                    : () async {
                        await controller.save();
                        if (!context.mounted) return;
                        showAppToast(
                          context,
                          'Plan saved',
                          icon: Icons.save_rounded,
                        );
                      },
                icon: Icon(
                  itinerary?.isSaved == true
                      ? Icons.check_rounded
                      : Icons.save_outlined,
                  size: 17,
                ),
                label: Text(
                  itinerary?.isSaved == true ? 'Plan saved' : 'Save plan',
                ),
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: itinerary == null || itinerary.isEmpty
                    ? null
                    : () async {
                        await controller.recheck();
                        if (!context.mounted) return;
                        showAppToast(
                          context,
                          'Re-checked against live traffic, hours and conditions',
                          icon: Icons.fact_check_outlined,
                        );
                      },
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Re-check'),
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('Modify'),
              ),
              if (itinerary != null && !itinerary.isEmpty) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () async {
                    await controller.clear();
                    if (!context.mounted) return;
                    showAppToast(
                      context,
                      'Plan cleared',
                      icon: Icons.delete_outline_rounded,
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Clear plan'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            v,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

class _TimeBreakdown extends ConsumerWidget {
  const _TimeBreakdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itinerary = ref.watch(itineraryControllerProvider).value;
    final discovery = ref.watch(discoveryContextProvider);
    if (itinerary == null || itinerary.isEmpty) return const SizedBox.shrink();

    final segments = <({String label, int minutes, Color color})>[
      (
        label: 'Travel',
        minutes: itinerary.travelMinutes,
        color: AppColors.blue,
      ),
      (
        label: 'Experiences',
        minutes: itinerary.activityMinutes,
        color: AppColors.violet,
      ),
      (
        label: 'Buffer',
        minutes: itinerary.returnBufferMinutes,
        color: AppColors.success,
      ),
    ];
    final total = itinerary.totalMinutes;
    final window = discovery.timeBudgetMinutes;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.donut_small_rounded,
                size: 17,
                color: AppColors.violet,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Where the time goes',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Text(
                '$total / $window min',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final segment in segments)
                    if (segment.minutes > 0)
                      Expanded(
                        flex: segment.minutes,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: AppMotion.slow,
                          builder: (context, value, _) => Opacity(
                            opacity: value,
                            child: Container(color: segment.color),
                          ),
                        ),
                      ),
                  if (total < window)
                    Expanded(
                      flex: window - total,
                      child: Container(color: AppColors.border),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final segment in segments)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: segment.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${segment.label} · ${segment.minutes}m',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _clock(DateTime time) {
  final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m ${time.hour >= 12 ? 'PM' : 'AM'}';
}

/// Convenience for the summary rail.
String durationLabel(int minutes) => DiscoveryContext.formatMinutes(minutes);
