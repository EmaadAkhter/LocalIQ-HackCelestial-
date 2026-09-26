import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/top_app_bar.dart';
import '../../../core/config/environment.dart';
import '../../../core/config/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../context/application/discovery_context_controller.dart';
import '../../itinerary/application/itinerary_controller.dart';
import '../../recommendations/application/recommendation_controller.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final twoCol = width >= 1060;

    return PageBody(
      maxWidth: 1160,
      slivers: [
        const _Hero(),
        if (twoCol)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Expanded(flex: 7, child: _Explainer()),
                SizedBox(width: 18),
                SizedBox(width: 320, child: _SideColumn()),
              ],
            ),
          )
        else
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Explainer(),
              SizedBox(height: 18),
              _SideColumn(),
            ],
          ),
        const _ArchitectureNote(),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: EdgeInsets.zero,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          gradient: AppColors.brandWash,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppBadge(
                label: 'HOW IT WORKS',
                color: Color(0xFFB9C7E8),
                icon: Icons.info_outline_rounded,
              ),
              const SizedBox(height: 12),
              const Text(
                'From what’s nearby\nto what you can actually do.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: const Text(
                  'Most maps answer "what is around me?". LocalIQ answers "what '
                  'can I genuinely finish in the next two hours, in this '
                  'weather, on this budget?" — and says so honestly when the '
                  'answer is nothing.',
                  style: TextStyle(
                    color: Color(0xFFD3DFF5),
                    fontSize: 14.5,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeroStat(value: '3', label: 'Feasibility tiers'),
                  _HeroStat(value: '10', label: 'Hard constraints'),
                  _HeroStat(value: '0', label: 'Popularity-led rankings'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFBCC9E4),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    const blocks = <({IconData icon, String title, String body})>[
      (
        icon: Icons.bolt_rounded,
        title: 'The problem',
        body:
            'Search results tell you what exists. They rarely tell you what you '
            'can finish. A two-hour window in monsoon-season Mumbai collapses '
            'the moment a 40-minute transit and an exposed walk are involved.',
      ),
      (
        icon: Icons.fact_check_outlined,
        title: 'The feasibility engine',
        body:
            'Every candidate is evaluated against ten named constraints: time, '
            'budget, opening hours, weather, accessibility, travel time, group '
            'fit, interest match, crowd level and booking. Each one produces a '
            'pass, a caveat or a failure, and the failures are shown to you '
            'verbatim rather than hidden.',
      ),
      (
        icon: Icons.looks_one_rounded,
        title: 'Three tiers, not two',
        body:
            'Feasible means you can complete it end to end. Partially suitable '
            'means a trade-off is available — trim the visit, or accept a '
            'caveat. Not feasible means a hard constraint fails, and the card '
            'tells you exactly which one and why.',
      ),
      (
        icon: Icons.tune_rounded,
        title: 'What-if, not search',
        body:
            'There is no "search" in the traditional sense. You change a '
            'variable — time, budget, weather, group, access, or the local ↔ '
            'tourist dial — and the entire surface re-evaluates: cards, counts, '
            'map pins and your plan.',
      ),
      (
        icon: Icons.leaderboard_rounded,
        title: 'Ranked on fit, not fame',
        body:
            'Ratings and footfall are weak priors, deliberately capped. The '
            'score is dominated by how well the option uses your window, '
            'matches your interests, respects your budget and tolerates the '
            'weather. A famous landmark with a 90-minute transit will rank below '
            'a neighbourhood café that actually fits.',
      ),
      (
        icon: Icons.auto_awesome_rounded,
        title: 'One assistant, one source of truth',
        body:
            'The assistant does not generate a second, looser answer. It reads '
            'the same live ranking you are looking at, so it can only suggest '
            'options that are genuinely on your list — and it can only cite '
            'options that currently exist.',
      ),
      (
        icon: Icons.route_rounded,
        title: 'Plans that hold up',
        body:
            'My Plan sequences your stops with real clock times, travel legs, a '
            'return buffer, a running cost and a plan-level verdict. Re-check '
            're-runs the engine against current traffic, opening hours and '
            'conditions, and flags anything that no longer works.',
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < blocks.length; i += 2)
          if (i + 1 < blocks.length) ...[
            _Block(icon: blocks[i].icon, title: blocks[i].title, body: blocks[i].body),
            const SizedBox(height: 14),
            _Block(
              icon: blocks[i + 1].icon,
              title: blocks[i + 1].title,
              body: blocks[i + 1].body,
            ),
            const SizedBox(height: 14),
          ] else ...[
            _Block(icon: blocks[i].icon, title: blocks[i].title, body: blocks[i].body),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.lavender,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: AppColors.violet),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(height: 1.5, fontSize: 14)),
        ],
      ),
    );
  }
}

class _SideColumn extends ConsumerWidget {
  const _SideColumn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final counts = ref.watch(recommendationCountsProvider);
    final live = ref.watch(liveContextProvider).value;
    final itinerary = ref.watch(itineraryControllerProvider).value;
    final remote = ref.watch(remoteDataEnabledProvider);
    final env = ref.watch(environmentProvider);

    return Column(
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your current context',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 12),
              _row('Location', discovery.locationLabel),
              _row('Starts', _clock(discovery.startTime)),
              _row('Window', discovery.timeLabel),
              _row('Budget', discovery.budgetLabel),
              _row('Group', discovery.groupType.label),
              _row('Access', discovery.accessibility.label),
              _row('Conditions', live?.weather.condition.label ?? '—'),
              _row('Traffic', live?.traffic.label ?? '—'),
              _row('Evaluated', '${counts.total}'),
              _row('Feasible', '${counts.feasible}'),
              _row('Plan', itinerary == null || itinerary.isEmpty
                  ? 'Empty'
                  : '${itinerary.stopCount} stops · ${itinerary.costLabel}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Data source',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const DataSourceChip(),
                  const SizedBox(width: 8),
                  AppBadge(
                    label: env.name.label.toUpperCase(),
                    color: AppColors.primary,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                remote
                    ? 'Connected to ${env.apiBaseUrl}. Places, weather, traffic '
                        'and ranking are fetched live.'
                    : 'Running on the bundled South Mumbai catalogue. Supply a '
                        'backend with LOCALIQ_API_BASE_URL and the same screens '
                        'switch over with no code changes.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (env.hasGoogleMaps) ...[
                const SizedBox(height: 10),
                const AppBadge(
                  label: 'GOOGLE MAPS CONFIGURED',
                  color: AppColors.success,
                  icon: Icons.map_rounded,
                  dense: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Try it',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'Change a constraint and watch the ranking react.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.push('/what-if'),
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('Open what-if lab'),
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: () => context.push('/assistant'),
                icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                label: const Text('Ask the assistant'),
              ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
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

/// Architecture transparency, so the team can see the seams for backend work.
class _ArchitectureNote extends ConsumerWidget {
  const _ArchitectureNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const layers = <({String title, String detail, IconData icon})>[
      (
        title: 'UI',
        detail: 'Screens and reusable widgets. No API logic.',
        icon: Icons.widgets_outlined,
      ),
      (
        title: 'State',
        detail: 'Riverpod providers and controllers per feature.',
        icon: Icons.account_tree_outlined,
      ),
      (
        title: 'Repositories',
        detail: 'Place, context, itinerary, saved and auth contracts.',
        icon: Icons.inventory_2_outlined,
      ),
      (
        title: 'Services',
        detail: 'Routes, map surface, assistant, JSON transport.',
        icon: Icons.settings_ethernet_rounded,
      ),
      (
        title: 'REST',
        detail: 'FastAPI. Swap a local repository for a remote one.',
        icon: Icons.cloud_outlined,
      ),
    ];

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            title: 'Architecture',
            subtitle:
                'Each layer is an interface. Swapping the data source does not '
                'touch a single widget.',
            icon: Icons.layers_rounded,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final layer in layers)
                Container(
                  width: 200,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(layer.icon, size: 15, color: AppColors.violet),
                          const SizedBox(width: 7),
                          Text(
                            layer.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        layer.detail,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          height: 1.4,
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
