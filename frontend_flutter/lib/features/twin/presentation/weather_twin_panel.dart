import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/twin_providers.dart';
import '../domain/twin_state.dart';

/// Weather Digital Twin control room.
///
/// Move the sliders and the whole ecosystem re-simulates: outdoor experiences
/// wash out, indoor demand spikes, flood risk spreads, and a concrete
/// alternative is proposed. This is the demo centrepiece.
class WeatherTwinPanel extends ConsumerWidget {
  const WeatherTwinPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenario = ref.watch(twinScenarioProvider);
    final twin = ref.watch(twinStateProvider);
    final notifier = ref.read(twinScenarioProvider.notifier);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: 'Weather Digital Twin',
            subtitle: 'Simulate how weather reshapes the city',
            icon: Icons.thunderstorm_outlined,
            trailing: TextButton.icon(
              onPressed: notifier.reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Reset'),
            ),
          ),
          const SizedBox(height: 12),
          _RainSelector(
            value: scenario.rainLevel,
            onChanged: notifier.setRain,
          ),
          const SizedBox(height: 6),
          _TwinSlider(
            label: 'Duration',
            value: scenario.durationHours,
            min: 0.5,
            max: 6,
            divisions: 11,
            display: '${scenario.durationHours.toStringAsFixed(1)} h',
            onChanged: notifier.setDuration,
          ),
          _TwinSlider(
            label: 'Flood multiplier',
            value: scenario.floodMultiplier,
            min: 0.5,
            max: 2,
            divisions: 6,
            display: '${scenario.floodMultiplier.toStringAsFixed(1)}x',
            onChanged: notifier.setFlood,
          ),
          const SizedBox(height: 14),
          twin.when(
            loading: () => const _TwinLoading(),
            error: (error, _) => _TwinMessage(
              icon: Icons.cloud_off_rounded,
              color: AppColors.danger,
              text: 'Twin unavailable: $error',
            ),
            data: (state) => _TwinResult(state: state),
          ),
        ],
      ),
    );
  }
}

class _RainSelector extends StatelessWidget {
  const _RainSelector({required this.value, required this.onChanged});

  final RainLevel value;
  final ValueChanged<RainLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RAIN INTENSITY',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppColors.textFaint,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final level in RainLevel.values)
              ChoiceChip(
                label: Text(level.label),
                selected: level == value,
                onSelected: (_) => onChanged(level),
                selectedColor: AppColors.primary.withValues(alpha: 0.14),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: level == value ? AppColors.primaryDark : AppColors.textMuted,
                ),
                side: BorderSide(
                  color: level == value ? AppColors.primary : AppColors.border,
                ),
                showCheckmark: false,
              ),
          ],
        ),
      ],
    );
  }
}

class _TwinSlider extends StatelessWidget {
  const _TwinSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textFaint,
                ),
              ),
            ),
            Text(
              display,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _TwinResult extends StatelessWidget {
  const _TwinResult({required this.state});

  final TwinState state;

  @override
  Widget build(BuildContext context) {
    final summary = state.summary;
    final outdoor = [...state.experiences.where((e) => e.indoorRatio < 0.5)]
      ..sort((a, b) => a.suitability.compareTo(b.suitability));
    final indoor = [...state.experiences.where((e) => e.indoorRatio >= 0.5)]
      ..sort((a, b) => b.suitability.compareTo(a.suitability));
    final flooding = state.areas.where((a) => a.isFlooding).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.narrative.isNotEmpty
                    ? summary.narrative.first
                    : 'Outdoor experiences stay feasible.',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              for (final line in summary.narrative.skip(1))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: AppColors.primary)),
                      Expanded(
                        child: Text(
                          line,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (summary.suggestedSwitch != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12.5, color: AppColors.text),
                      children: [
                        const TextSpan(text: 'Recommended switch: '),
                        TextSpan(
                          text: summary.suggestedSwitch!.from,
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: AppColors.textFaint,
                          ),
                        ),
                        const TextSpan(text: '  →  '),
                        TextSpan(
                          text: summary.suggestedSwitch!.to,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (flooding.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _MiniHeading('FLOOD RISK'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final area in flooding)
                AppBadge(
                  label: '${area.name} · ${area.floodRiskLevel}',
                  color: AppColors.danger,
                  icon: Icons.water_rounded,
                  dense: true,
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _ImpactList(
          heading: 'Washed out (outdoor)',
          experiences: outdoor.take(4).toList(),
          color: AppColors.danger,
        ),
        const SizedBox(height: 12),
        _ImpactList(
          heading: 'Best bets now (indoor)',
          experiences: indoor.take(4).toList(),
          color: AppColors.success,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.public_rounded, size: 13, color: AppColors.textFaint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Demo uses a curated social-signal feed; production streams live APIs.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ImpactList extends StatelessWidget {
  const _ImpactList({
    required this.heading,
    required this.experiences,
    required this.color,
  });

  final String heading;
  final List<TwinExperience> experiences;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (experiences.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MiniHeading(heading.toUpperCase()),
        const SizedBox(height: 6),
        for (final exp in experiences)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    exp.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Text(
                  exp.riskFlags.isNotEmpty ? exp.riskFlags.first : '',
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  exp.suitability.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniHeading extends StatelessWidget {
  const _MiniHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: AppColors.textFaint,
      ),
    );
  }
}

class _TwinLoading extends StatelessWidget {
  const _TwinLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _TwinMessage extends StatelessWidget {
  const _TwinMessage({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
