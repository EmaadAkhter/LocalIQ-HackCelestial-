import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/social.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../places/domain/place.dart';
import '../application/meetup_controller.dart';
import '../data/local_social.dart';
import '../data/social_repository.dart';

/// Random Meetup — spontaneous, activity-driven connection.
///
/// Screen 16 in the design language: pick *when* you are free and *where*, and
/// LocalIQ matches you with verified locals/travellers on the same vibe. No
/// swiping, no profiles parade — the match is derived from overlapping intent
/// and pinned to a curated public anchor.
class RandomMeetupScreen extends ConsumerStatefulWidget {
  const RandomMeetupScreen({super.key});

  @override
  ConsumerState<RandomMeetupScreen> createState() => _RandomMeetupScreenState();
}

class _RandomMeetupScreenState extends ConsumerState<RandomMeetupScreen> {
  int _timeIndex = 1;
  int _hubIndex = 0;
  bool _matching = false;

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(meetupControllerProvider).pendingReceivedCount;
    final places = ref.watch(allPlacesProvider).value ?? const [];
    final hubs = _resolveHubs(places);
    final safeHubIndex = _hubIndex.clamp(0, hubs.isNotEmpty ? hubs.length - 1 : 0);
    final hub = hubs.isNotEmpty ? hubs[safeHubIndex] : _defaultHubs.first;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Invitations',
            onPressed: () => context.push('/people/matches'),
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.mark_email_unread_outlined),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              const _Eyebrow(),
              const SizedBox(height: 12),
              Text(
                'Random Meetup',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.05,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Explore with someone who gets your vibe.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              const Text(
                'LocalIQ pairs you with verified locals or travellers seeking a '
                'similar Mumbai experience at the exact same time. Zero swiping. '
                '100% activity-driven.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // ── How it works
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeading(
                      title: 'How Meetup Matching Works',
                      subtitle: 'A three-step protocol',
                      icon: Icons.auto_awesome_rounded,
                    ),
                    const SizedBox(height: 14),
                    for (final step in _steps) ...[
                      _StepRow(step: step),
                      if (step != _steps.last) const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              const _GhostModeCard(),
              const SizedBox(height: 20),

              // ── When
              const FieldLabel('When do you want to go?'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _times.length; i++)
                    SelectChip(
                      label: _times[i].label,
                      icon: _times[i].icon,
                      selected: i == _timeIndex,
                      onTap: () => setState(() => _timeIndex = i),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 14, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Text(
                    '${_times[_timeIndex].label} · ${_times[_timeIndex].window}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // ── Where
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(child: FieldLabel('Target neighborhood / hub')),
                  Text(
                    'Radius: ${hub.radiusKm.toStringAsFixed(1)} KM',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < hubs.length; i++) ...[
                _HubCard(
                  hub: hubs[i],
                  selected: i == safeHubIndex,
                  onTap: () => setState(() => _hubIndex = i),
                ),
                if (i != hubs.length - 1) const SizedBox(height: 10),
              ],
              const SizedBox(height: 22),

              // ── CTA
              FilledButton.icon(
                onPressed: _matching ? null : () => _findMatch(hub),
                icon: _matching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.bolt_rounded, size: 18),
                label: Text(
                  _matching ? 'Scanning for your vibe…' : 'Find My Match',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ghost Mode is on by default. Your exact location and identity '
                'stay hidden until a mutual double opt-in at the anchor.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.textFaint, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _findMatch(_Hub hub) async {
    setState(() => _matching = true);
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;
    setState(() => _matching = false);
    _showMatchesSheet(hub);
  }

  void _showMatchesSheet(_Hub hub) {
    final matches = ref.read(peopleMatchesProvider).value ?? kLocalPeopleMatches;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.bolt_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${matches.length} explorers near ${hub.name}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const Text(
                            'Matching your vibe, budget and timing',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final match in matches.take(3)) ...[
                  _MatchPreviewTile(match: match),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/people/matches');
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text(
                    'See all matches & invitations',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Static content
// ---------------------------------------------------------------------------

class _Step {
  const _Step(this.index, this.title, this.body, this.icon);
  final String index;
  final String title;
  final String body;
  final IconData icon;
}

const _steps = [
  _Step(
    '01',
    'Vibe & Budget',
    'Choose your timing, vibe and taste profile.',
    Icons.tune_rounded,
  ),
  _Step(
    '02',
    'Synapse AI',
    'Dynamic indexing of overlapping high-intent interests.',
    Icons.hub_rounded,
  ),
  _Step(
    '03',
    'Public Anchor',
    'Auto-route to a curated no-pressure public cafe.',
    Icons.storefront_rounded,
  ),
];

class _TimeOption {
  const _TimeOption(this.label, this.window, this.icon);
  final String label;
  final String window;
  final IconData icon;
}

const _times = [
  _TimeOption('Peak hours', '19:00 – 23:00', Icons.groups_rounded),
  _TimeOption('Today daytime', 'Till 18:30', Icons.wb_sunny_outlined),
  _TimeOption('Tonight', '19:00 – 23:00', Icons.nightlight_outlined),
  _TimeOption('This weekend', 'Sat & Sun slots', Icons.weekend_outlined),
  _TimeOption('Custom window', 'Pick a slot', Icons.event_outlined),
];

class _Hub {
  const _Hub({
    required this.name,
    required this.blurb,
    required this.requests,
    required this.radiusKm,
    required this.image,
  });
  final String name;
  final String blurb;
  final String requests;
  final double radiusKm;
  final String image;
}

List<_Hub> _resolveHubs(List<Place> places) {
  if (places.isEmpty) return _defaultHubs;
  final Map<String, List<Place>> byArea = {};
  for (final p in places) {
    final area = p.area.trim().isNotEmpty ? p.area.trim() : 'Mumbai Central';
    byArea.putIfAbsent(area, () => []).add(p);
  }
  final hubs = byArea.entries.take(5).map((entry) {
    final areaPlaces = entry.value;
    final first = areaPlaces.first;
    final highlights = areaPlaces.take(2).map((p) => p.name).join(' · ');
    return _Hub(
      name: entry.key,
      blurb: '$highlights & local culture',
      requests: '${areaPlaces.length * 8 + 14} active explorers nearby',
      radiusKm: (entry.key.toLowerCase().contains('colaba') || entry.key.toLowerCase().contains('fort')) ? 3.2 : 4.5,
      image: first.heroImageUrl.isNotEmpty
          ? first.heroImageUrl
          : 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=900&q=80',
    );
  }).toList();
  return hubs.isNotEmpty ? hubs : _defaultHubs;
}

const _defaultHubs = [
  _Hub(
    name: 'Bandra West',
    blurb: 'Cafes, live gigs & Carter Road promenade',
    requests: '48 active match requests',
    radiusKm: 4.2,
    image:
        'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=900&q=80',
  ),
  _Hub(
    name: 'South Mumbai / Colaba',
    blurb: 'Heritage walks, art deco & old Irani cafes',
    requests: '31 active match requests',
    radiusKm: 3.6,
    image:
        'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?auto=format&fit=crop&w=900&q=80',
  ),
  _Hub(
    name: 'Juhu & Versova',
    blurb: 'Beach sunsets, shacks & street food',
    requests: '26 active match requests',
    radiusKm: 5.0,
    image:
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=900&q=80',
  ),
];

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _Eyebrow extends StatelessWidget {
  const _Eyebrow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: const Text(
            'SPONTANEOUS CONNECTION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.primaryDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: Text(
            step.index,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(step.icon, size: 15, color: AppColors.violet),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      step.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                step.body,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
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

class _GhostModeCard extends StatelessWidget {
  const _GhostModeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.violet.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.visibility_off_rounded, color: AppColors.violet, size: 19),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Ghost Mode Active',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    SizedBox(width: 8),
                    AppBadge(label: 'DEFAULT', color: AppColors.violet, dense: true),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Exact GPS coordinates & identity are concealed until mutual '
                  'double opt-in at the anchor destination.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.hub, required this.selected, required this.onTap});

  final _Hub hub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySurface : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected ? AppShadows.card : null,
          ),
          child: Row(
            children: [
              AppImage(
                url: hub.image,
                width: 64,
                height: 64,
                borderRadius: BorderRadius.circular(AppRadius.md),
                fallbackLabel: hub.name,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            hub.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          const AppBadge(
                            label: 'SELECTED',
                            color: AppColors.primary,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hub.blurb,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 12,
                          color: selected ? AppColors.primary : AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hub.requests,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: selected ? AppColors.primary : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.primary : AppColors.borderStrong,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchPreviewTile extends StatelessWidget {
  const _MatchPreviewTile({required this.match});

  final PeopleMatch match;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          AppImage(
            url: match.photoUrl,
            width: 44,
            height: 44,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            fallbackLabel: match.displayName,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '★ ${match.reputationScore.toStringAsFixed(1)} · ${match.sharedInterests.take(2).join(' · ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '${match.compatibilityPercent}%',
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
