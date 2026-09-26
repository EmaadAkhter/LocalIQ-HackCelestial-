import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';

/// Profile tab. Auth is intentionally not wired yet — entries that need an
/// account are marked "Soon".
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Insets.page,
            Insets.md,
            Insets.page,
            Insets.xl,
          ),
          children: <Widget>[
            _ProfileHeader(name: state.displayName, isGuest: state.isGuest),
            const SizedBox(height: Insets.xl),
            _StatsRow(
              plans: state.itineraryStops.isEmpty ? 0 : 1,
              places: state.visitCount,
              favourites: state.favourites.length,
            ),
            const SizedBox(height: Insets.xl),
            const _SectionLabel('My trip'),
            _Tile(
              icon: Icons.favorite_rounded,
              title: 'Saved places',
              subtitle: state.favourites.isEmpty
                  ? 'Tap the heart on any place'
                  : '${state.favourites.length} saved',
              onTap: () => _toast(context, 'Saved places are coming soon.'),
            ),
            _Tile(
              icon: Icons.route_rounded,
              title: 'My itineraries',
              subtitle: state.itineraryStops.isEmpty
                  ? 'No plans yet'
                  : '${state.itineraryStops.length} stops in your current plan',
              onTap: () => _toast(context, 'Itinerary library is coming soon.'),
            ),
            const SizedBox(height: Insets.lg),
            const _SectionLabel('Preferences'),
            _Tile(
              icon: Icons.accessible_rounded,
              title: 'Accessibility',
              subtitle: state.params.accessibility
                  ? 'Step-free places only'
                  : 'No filter applied',
              onTap: state.toggleAccessibility,
              trailing: Switch.adaptive(
                value: state.params.accessibility,
                onChanged: (_) => state.toggleAccessibility(),
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.primary,
              ),
            ),
            _Tile(
              icon: Icons.payments_outlined,
              title: 'Default budget',
              subtitle: '₹${state.params.budgetInr}',
              onTap: () => _toast(context, 'Budget presets live on Home.'),
            ),
            const SizedBox(height: Insets.lg),
            const _SectionLabel('Assistant'),
            _Tile(
              icon: Icons.auto_awesome_rounded,
              title: 'Ask the AI guide',
              subtitle: 'Mock replies from local data',
              onTap: () => goToChat(context),
            ),
            const SizedBox(height: Insets.lg),
            const _SectionLabel('Account'),
            _Tile(
              icon: Icons.login_rounded,
              title: 'Sign in',
              subtitle: 'Coming soon',
              badge: 'Soon',
              onTap: () =>
                  _toast(context, 'Accounts arrive in the next milestone.'),
            ),
            _Tile(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: 'Coming soon',
              badge: 'Soon',
              onTap: () => _toast(
                context,
                'Notifications arrive in the next milestone.',
              ),
            ),
            const SizedBox(height: Insets.xl),
            const _AboutCard(),
          ],
        ),
      ),
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.isGuest});

  final String name;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[AppColors.primary, AppColors.indigo],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: const Icon(
            Icons.person_rounded,
            size: 30,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: Insets.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isGuest
                          ? AppColors.lavender
                          : AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      isGuest ? 'Guest mode' : 'Member',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.plans,
    required this.places,
    required this.favourites,
  });

  final int plans;
  final int places;
  final int favourites;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Insets.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _Stat(value: '$plans', label: 'Plans'),
          ),
          const _VDivider(),
          Expanded(
            child: _Stat(value: '$places', label: 'Places seen'),
          ),
          const _VDivider(),
          Expanded(
            child: _Stat(value: '$favourites', label: 'Saved'),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
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

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: AppColors.divider);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: Radii.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.cardRadius,
          child: Container(
            padding: const EdgeInsets.all(Insets.md),
            decoration: BoxDecoration(
              borderRadius: Radii.cardRadius,
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.lavender,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (badge != null) ...<Widget>[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: AppColors.deep,
        borderRadius: Radii.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: 'Local'),
                TextSpan(
                  text: 'IQ',
                  style: TextStyle(color: AppColors.star),
                ),
              ],
            ),
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Version 1.0.0 · Mock data build.\n'
            'Connect the FastAPI backend by passing a FastApiService to '
            'LocalIQApp. Google Maps turns on automatically once the backend '
            'serves a key via /api/v1/config.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
