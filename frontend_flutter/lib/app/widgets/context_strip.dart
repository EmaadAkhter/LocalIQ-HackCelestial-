import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/context/application/discovery_context_controller.dart';
import '../../features/context/domain/context_models.dart';
import '../../features/context/domain/discovery_context.dart';
import '../../shared/widgets/ui_kit.dart';

/// The dark strip under the header carrying live conditions: location, clock,
/// weather, traffic and the planning note that explains the current ranking.
class ContextStrip extends ConsumerWidget {
  const ContextStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final context_ = ref.watch(discoveryContextProvider);
    final live = ref.watch(liveContextProvider);
    final width = MediaQuery.sizeOf(context).width;
    final mobile = Breakpoints.isMobile(width);

    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.surfaceDeep),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Breakpoints.gutter(width),
          vertical: mobile ? 10 : 9,
        ),
        child: mobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Facts(context: context_, live: live),
                  const SizedBox(height: 9),
                  _PlanningNote(live: live, fallback: context_.locationLabel),
                ],
              )
            : Row(
                children: [
                  Flexible(child: _Facts(context: context_, live: live)),
                  const SizedBox(width: 20),
                  Expanded(child: _PlanningNote(live: live, fallback: context_.locationLabel)),
                ],
              ),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.context, required this.live});

  final DiscoveryContext context;
  final AsyncValue<({WeatherSnapshot weather, TrafficSnapshot traffic})> live;

  @override
  Widget build(BuildContext buildContext) {
    final data = live.value;
    final weather = data?.weather;
    final traffic = data?.traffic;

    final items = <({IconData icon, String text, Color color})>[
      (
        icon: Icons.location_on_rounded,
        text: context.locationLabel,
        color: AppColors.primary,
      ),
      (
        icon: Icons.event_rounded,
        text: _weekday(context.startTime),
        color: AppColors.textMuted,
      ),
      (
        icon: Icons.schedule_rounded,
        text: '${_clock(context.startTime)} · ${context.timeLabel}',
        color: AppColors.textMuted,
      ),
      (
        icon: weather == null
            ? Icons.cloud_outlined
            : _iconFor(weather.condition),
        text: weather == null
            ? 'Reading conditions…'
            : '${weather.summary} · ${weather.precipitationChance}% rain',
        color: AppColors.primary,
      ),
      (
        icon: Icons.traffic_rounded,
        text: traffic?.label ?? 'Reading traffic…',
        color: AppColors.textMuted,
      ),
    ];

    return Wrap(
      spacing: 18,
      runSpacing: 7,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 13.5, color: item.color),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  item.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  static IconData _iconFor(WeatherCondition condition) => switch (condition) {
        WeatherCondition.clear => Icons.wb_sunny_rounded,
        WeatherCondition.cloudy => Icons.cloud_rounded,
        WeatherCondition.rain => Icons.water_drop_rounded,
        WeatherCondition.storm => Icons.thunderstorm_rounded,
        WeatherCondition.hot => Icons.local_fire_department_rounded,
      };
}

class _PlanningNote extends StatelessWidget {
  const _PlanningNote({required this.live, required this.fallback});

  final AsyncValue<({WeatherSnapshot weather, TrafficSnapshot traffic})> live;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final data = live.value;
    final note = data?.weather.planningNote;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 13,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              note ?? 'Ranking against live conditions in $fallback.',
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact constraint summary, used on the standalone pages.
class ContextSummaryRow extends ConsumerWidget {
  const ContextSummaryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final live = ref.watch(liveContextProvider).value;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AppBadge(
          label: discovery.timeLabel,
          icon: Icons.schedule_rounded,
          color: AppColors.primary,
        ),
        AppBadge(
          label: discovery.budgetLabel,
          icon: Icons.payments_outlined,
          color: AppColors.warning,
        ),
        AppBadge(
          label: live?.weather.summary ?? 'Loading…',
          icon: Icons.cloud_outlined,
          color: AppColors.primary,
        ),
        AppBadge(
          label: discovery.groupType.label,
          icon: Icons.group_outlined,
          color: AppColors.primary,
        ),
        AppBadge(
          label: discovery.accessibility.label,
          icon: Icons.accessible_rounded,
          color: AppColors.success,
        ),
        AppBadge(
          label: _biasLabel(discovery.localBias),
          icon: Icons.diamond_outlined,
          color: AppColors.warning,
        ),
      ],
    );
  }

  static String _biasLabel(double bias) {
    if (bias < 0.2) return 'Local gems';
    if (bias < 0.45) return 'Leaning local';
    if (bias < 0.7) return 'Balanced';
    return 'Touristy';
  }
}

String _clock(DateTime time) {
  final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m ${time.hour >= 12 ? 'PM' : 'AM'}';
}

String _weekday(DateTime time) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${days[time.weekday - 1]}, ${time.day} ${months[time.month - 1]}';
}
