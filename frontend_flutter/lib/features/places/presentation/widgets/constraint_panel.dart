import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../context/application/discovery_context_controller.dart';
import '../../../context/domain/context_models.dart';
import '../../../context/domain/discovery_context.dart';

/// Live constraint controls. Every change re-runs the engine immediately.
class ConstraintPanel extends ConsumerStatefulWidget {
  const ConstraintPanel({super.key});

  @override
  ConsumerState<ConstraintPanel> createState() => _ConstraintPanelState();
}

class _ConstraintPanelState extends ConsumerState<ConstraintPanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(discoveryContextProvider);
    final controller = ref.read(discoveryContextProvider.notifier);
    final width = MediaQuery.sizeOf(context).width;
    final stacked = width < 820;

    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.sky,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Your constraints',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 17,
                  ),
                  label: Text(_expanded ? 'Collapse' : 'Edit'),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        const SizedBox(height: 14),
                        if (stacked)
                          Column(
                            children: [
                              _TimeControl(
                                discovery: discovery,
                                controller: controller,
                              ),
                              const SizedBox(height: 20),
                              _BudgetControl(
                                discovery: discovery,
                                controller: controller,
                              ),
                            ],
                          )
                        else
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _TimeControl(
                                    discovery: discovery,
                                    controller: controller,
                                  ),
                                ),
                                const SizedBox(width: 22),
                                Container(width: 1, color: AppColors.border),
                                const SizedBox(width: 22),
                                Expanded(
                                  child: _BudgetControl(
                                    discovery: discovery,
                                    controller: controller,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        const FieldLabel('Interests'),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final category in ExperienceCategory.values)
                              SelectChip(
                                label: category.label,
                                compact: true,
                                icon: _iconFor(category),
                                selected: discovery.interests.contains(category),
                                onTap: () => controller.toggleInterest(category),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const FieldLabel('Who is travelling'),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final group in GroupType.values)
                              SelectChip(
                                label: group.label,
                                compact: true,
                                icon: _groupIcon(group),
                                tone: AppColors.blue,
                                selected: discovery.groupType == group,
                                onTap: () => controller.setGroup(group),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const FieldLabel('Accessibility'),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final need in AccessibilityNeed.values)
                              SelectChip(
                                label: need.label,
                                compact: true,
                                icon: Icons.accessible_rounded,
                                tone: AppColors.primary,
                                selected: discovery.accessibility == need,
                                onTap: () => controller.setAccessibility(need),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const FieldLabel('Conditions to plan for'),
                        const SizedBox(height: 9),
                        _WeatherOverrideRow(controller: controller),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(ExperienceCategory category) => switch (category) {
        ExperienceCategory.food => Icons.ramen_dining_rounded,
        ExperienceCategory.culture => Icons.account_balance_rounded,
        ExperienceCategory.history => Icons.history_edu_rounded,
        ExperienceCategory.art => Icons.palette_rounded,
        ExperienceCategory.nature => Icons.park_rounded,
        ExperienceCategory.heritage => Icons.account_balance_rounded,
        ExperienceCategory.nightlife => Icons.nightlife_rounded,
        ExperienceCategory.shopping => Icons.shopping_bag_rounded,
        ExperienceCategory.wellness => Icons.self_improvement_rounded,
        ExperienceCategory.adventure => Icons.hiking_rounded,
        ExperienceCategory.localLife => Icons.people_alt_rounded,
      };

  static IconData _groupIcon(GroupType group) => switch (group) {
        GroupType.solo => Icons.person_rounded,
        GroupType.couple => Icons.favorite_outline_rounded,
        GroupType.friends => Icons.groups_rounded,
        GroupType.family => Icons.family_restroom_rounded,
        GroupType.team => Icons.groups_2_rounded,
      };
}

class _TimeControl extends StatelessWidget {
  const _TimeControl({required this.discovery, required this.controller});

  final DiscoveryContext discovery;
  final DiscoveryContextController controller;

  static const _marks = <int, String>{
    30: '30m',
    60: '1h',
    120: '2h',
    180: '3h',
    240: '4h',
    300: '5h',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 15, color: AppColors.blue),
            const SizedBox(width: 6),
            const Flexible(
              child: FieldLabel('Time available'),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                discovery.timeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.blue,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.blue,
            thumbColor: AppColors.blue,
          ),
          child: Slider(
            min: 30,
            max: 600,
            divisions: 38,
            value: discovery.timeBudgetMinutes.toDouble().clamp(30, 600),
            label: discovery.timeLabel,
            onChanged: (v) => controller.setTime(v.round()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final entry in _marks.entries)
                GestureDetector(
                  onTap: () => controller.setTime(entry.key),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: discovery.timeBudgetMinutes == entry.key
                          ? AppColors.blue
                          : AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BudgetControl extends StatelessWidget {
  const _BudgetControl({required this.discovery, required this.controller});

  final DiscoveryContext discovery;
  final DiscoveryContextController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.payments_outlined,
              size: 15,
              color: AppColors.violet,
            ),
            const SizedBox(width: 6),
            const Flexible(
              child: FieldLabel('Budget'),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                discovery.budgetLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.violet,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.violet,
            thumbColor: AppColors.violet,
          ),
          child: Slider(
            min: 200,
            max: 6000,
            divisions: 29,
            value: discovery.budget.toDouble().clamp(200, 6000),
            label: discovery.budgetLabel,
            onChanged: (v) => controller.setBudget(v.round()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final value in [200, 800, 1500, 3000, 6000])
                GestureDetector(
                  onTap: () => controller.setBudget(value),
                  child: Text(
                    value >= 1000 ? '${value ~/ 1000}k' : '$value',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: discovery.budget == value
                          ? AppColors.violet
                          : AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeatherOverrideRow extends ConsumerWidget {
  const _WeatherOverrideRow({required this.controller});

  final DiscoveryContextController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(weatherOverrideProvider);
    final live = ref.watch(liveContextProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_outlined, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            const Flexible(
              child: FieldLabel('Conditions'),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                override == null
                    ? 'Live · ${live?.weather.condition.label ?? '—'}'
                    : 'Exploring ${override.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SelectChip(
              label: 'Live',
              compact: true,
              icon: Icons.sensors_rounded,
              tone: AppColors.success,
              selected: override == null,
              onTap: () => controller.setWeatherReset(),
            ),
            for (final condition in WeatherCondition.values)
              SelectChip(
                label: condition.label,
                compact: true,
                tone: AppColors.blue,
                selected: override == condition,
                onTap: () => controller.setWeather(condition),
              ),
          ],
        ),
        if (override != null) ...[
          const SizedBox(height: 8),
          const Text(
            'You are previewing how the ranking would change under different '
            'conditions. Live data resumes when you pick "Live".',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ],
    );
  }
}

/// Start-time control used on the plan screen.
class StartTimeField extends ConsumerWidget {
  const StartTimeField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final controller = ref.read(discoveryContextProvider.notifier);
    final first = DateTime(
      discovery.startTime.year,
      discovery.startTime.month,
      discovery.startTime.day,
      8,
    );
    final last = DateTime(
      discovery.startTime.year,
      discovery.startTime.month,
      discovery.startTime.day,
      20,
    );

    return AppPanel(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.play_circle_outline_rounded,
                size: 17,
                color: AppColors.blue,
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: FieldLabel('You start at'),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _clock(discovery.startTime),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppColors.blue,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.blue,
              thumbColor: AppColors.blue,
            ),
            child: Slider(
              min: first.millisecondsSinceEpoch.toDouble(),
              max: last.millisecondsSinceEpoch.toDouble(),
              divisions: 24,
              value: discovery.startTime.millisecondsSinceEpoch
                  .toDouble()
                  .clamp(
                    first.millisecondsSinceEpoch.toDouble(),
                    last.millisecondsSinceEpoch.toDouble(),
                  ),
              label: _clock(discovery.startTime),
              onChanged: (v) => controller.setStartTime(
                DateTime.fromMillisecondsSinceEpoch(v.round()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime time) {
    final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m ${time.hour >= 12 ? 'PM' : 'AM'}';
  }
}

/// Local ↔ tourist control, shared by Explore and the what-if lab.
class BiasSlider extends ConsumerWidget {
  const BiasSlider({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final controller = ref.read(discoveryContextProvider.notifier);
    final bias = discovery.localBias;
    final label = bias < 0.2
        ? 'Local gems'
        : bias < 0.45
            ? 'Leaning local'
            : bias < 0.7
                ? 'Balanced'
                : 'Touristy';

    return AppPanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      elevated: !dense,
      color: dense ? AppColors.surface : AppColors.surfaceMuted,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.diamond_outlined,
                size: 15,
                color: AppColors.violet,
              ),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'Local gems',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(label: label, color: AppColors.violet, dense: true),
              const SizedBox(width: 8),
              const Icon(
                Icons.emoji_events_outlined,
                size: 15,
                color: AppColors.warning,
              ),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'Touristy',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.violet,
              thumbColor: AppColors.violet,
            ),
            child: Slider(
              min: 0,
              max: 1,
              value: bias,
              onChanged: controller.setLocalBias,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick scenario presets.
class ScenarioRow extends ConsumerWidget {
  const ScenarioRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(discoveryContextProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap, not Row: the label and the hint together exceed the panel
        // width on phones, and a Row would overflow instead of reflowing.
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const FieldLabel('Start from a scenario'),
            Text(
              'one tap re-runs the whole engine',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final scenario in discoveryScenarios)
              AppPanel(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onTap: () {
                  controller.applyScenario(scenario);
                  showAppToast(
                    context,
                    'Applied "${scenario.label}"',
                    icon: Icons.auto_awesome_rounded,
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.sky,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        size: 15,
                        color: AppColors.blue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Flexible so the caption can ellipsize. Without it the
                    // Row is sized to its intrinsic content and overflows the
                    // Wrap's per-child max width on narrow screens.
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            scenario.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            scenario.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// String helper reused in several places.
String minutesLabel(int minutes) => DiscoveryContext.formatMinutes(minutes);
