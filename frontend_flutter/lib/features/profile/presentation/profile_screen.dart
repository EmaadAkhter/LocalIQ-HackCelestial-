import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/top_app_bar.dart';
import '../../../core/config/environment.dart';
import '../../../core/providers.dart';
import '../../../core/config/providers.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../assistant/application/assistant_controller.dart';
import '../../auth/domain/auth_service.dart';
import '../../context/domain/context_models.dart';
import '../../context/application/discovery_context_controller.dart';
import '../../itinerary/application/itinerary_controller.dart';
import '../../saved/application/saved_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signOut();
      if (!mounted) return;
      context.go('/login');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  void _showAccountRequiredDialog(BuildContext context, String featureName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Account Required', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Create an account to unlock $featureName.\n\nSign in or register to sync your saved places, itineraries, and trusted identity across devices.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/signup');
            },
            child: const Text('Create Account'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final service = ref.watch(authServiceProvider);
    final savedCount = ref.watch(savedControllerProvider).value?.length ?? 0;
    final itinerary = ref.watch(itineraryControllerProvider).value;
    final chat = ref.watch(assistantThreadProvider).messages.length;
    final env = ref.watch(environmentProvider);
    final discovery = ref.watch(discoveryContextProvider);

    final isGuest = user == null || user.isGuest;
    final displayName = isGuest ? 'Guest Explorer' : (user.displayName.isEmpty ? 'Explorer' : user.displayName);
    final subtitle = isGuest ? 'LocalIQ Guest Profile' : (user.email ?? 'Verified Account');

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Profile')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Breakpoints.gutter(MediaQuery.sizeOf(context).width),
              12,
              Breakpoints.gutter(MediaQuery.sizeOf(context).width),
              32,
            ),
            children: [
              AppPanel(
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.violet.withValues(alpha: 0.22),
                            AppColors.blue.withValues(alpha: 0.22),
                          ],
                        ),
                      ),
                      child: Text(
                        isGuest ? 'GE' : user.initials,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.violet,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              AppBadge(
                                label: isGuest
                                    ? 'GUEST EXPLORER'
                                    : (user.tier.label).toUpperCase(),
                                color: isGuest ? AppColors.warning : AppColors.success,
                                dense: true,
                              ),
                              AppBadge(
                                label: isGuest
                                    ? 'SESSION ACTIVE'
                                    : (user.provider.label).toUpperCase(),
                                color: AppColors.violet,
                                dense: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (isGuest) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'LocalIQ Guest Profile Active',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primaryDark),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Your preferences, plans, and wallet are saved for this session. Create an account to sync across devices.',
                              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => context.push('/signup'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Text('Sign Up', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                AppPanel(
                  color: AppColors.dangerSurface,
                  borderColor: AppColors.danger.withValues(alpha: 0.25),
                  elevated: false,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.danger,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // ── Five Distinct Primary Sections (Req 3 & 10)
              AppPanel(
                padding: EdgeInsets.zero,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      // Section 1: Preferences
                      ListTile(
                        leading: const Icon(Icons.tune_rounded, color: AppColors.primary),
                        title: const Text('Preferences', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'Time: ${discovery.timeLabel} · Budget: ${discovery.budgetLabel} · Group: ${discovery.groupType.label}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/taste-profile'),
                      ),
                      const Divider(height: 1),

                      // Section 2: Current Area
                      ListTile(
                        leading: const Icon(Icons.location_on_outlined, color: AppColors.blue),
                        title: const Text('Current Area', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(discovery.locationLabel),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _locationSheet(context),
                      ),
                      const Divider(height: 1),

                      // Section 3: Saved Experiences
                      ListTile(
                        leading: const Icon(Icons.favorite_outline, color: AppColors.danger),
                        title: const Text('Saved Experiences', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('$savedCount saved places and experiences'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.go('/saved'),
                      ),
                      const Divider(height: 1),

                      // Section 4: My Plans
                      ListTile(
                        leading: const Icon(Icons.playlist_add_check_outlined, color: Color(0xFF0E7C5A)),
                        title: const Text('My Plans', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          itinerary == null || itinerary.isEmpty
                              ? 'No stops planned yet'
                              : '${itinerary.stopCount} stops · ${itinerary.costLabel} · ${itinerary.totalLabel}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.go('/plan'),
                      ),
                      const Divider(height: 1),

                      // Section 5: Taste Profile
                      ListTile(
                        leading: const Icon(Icons.fingerprint_rounded, color: AppColors.violet),
                        title: const Text('Taste Profile & DNA', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('Architecture, cafes, heritage & hidden gems'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/taste-profile'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Navigation & Tools
              AppPanel(
                padding: EdgeInsets.zero,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.bolt_rounded, color: AppColors.primary),
                        title: const Text('Random Meetup', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('Meet verified locals & travellers on your vibe'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/people'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.wallet_rounded),
                        title: const Text('Experience Wallet & Passport'),
                        subtitle: const Text('Offline passes, stamps & quest badges'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/wallet'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.explore_rounded),
                        title: const Text('City Quests & Expeditions'),
                        subtitle: const Text('Curated challenges and XP rewards'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/quests'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.map_outlined),
                        title: const Text('Interactive Map'),
                        subtitle: const Text('View experiences on vector map'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/map'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.security_rounded),
                        title: const Text('Safety & Trust Center'),
                        subtitle: const Text('ID verification, trusted contacts & SOS'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          if (isGuest) {
                            _showAccountRequiredDialog(context, 'Safety & ID Verification');
                          } else {
                            context.push('/safety');
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.person_search_rounded),
                        title: const Text('Local Guides Marketplace'),
                        subtitle: const Text('Book verified guides & custom tours'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/guides'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.psychology_rounded),
                        title: const Text('AI Experience Director'),
                        subtitle: const Text('Autonomous real-time trip orchestrator'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/director'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.work_outline_rounded),
                        title: const Text('Guide Workspace'),
                        subtitle: const Text('Switch to guide role & manage bookings'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          if (isGuest) {
                            _showAccountRequiredDialog(context, 'Guide Workspace');
                          } else {
                            context.push('/guide/dashboard');
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.local_taxi_rounded, color: AppColors.blue),
                        title: const Text('Driver trips & live map'),
                        subtitle: const Text('Pickup, stops and drop-off for your trips'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          if (isGuest) {
                            _showAccountRequiredDialog(context, 'Driver trips');
                          } else {
                            context.push('/driver');
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.badge_outlined, color: AppColors.success),
                        title: const Text('Become a guide'),
                        subtitle: const Text('Upload licences, pick areas & start earning'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/guide-onboarding'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.restaurant_menu_rounded, color: AppColors.violet),
                        title: const Text('Taste onboarding'),
                        subtitle: const Text('Let us learn what you love, in a minute'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/onboarding'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('Companion'),
                        subtitle: Text('$chat messages'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/travel-buddy'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.favorite_outline),
                        title: const Text('Saved experiences'),
                        subtitle: Text('$savedCount saved'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.go('/saved'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.playlist_add_check_outlined),
                        title: const Text('My plan'),
                        subtitle: Text(
                          itinerary == null || itinerary.isEmpty
                              ? 'No stops yet'
                              : '${itinerary.stopCount} stops · '
                                  '${itinerary.costLabel} · ${itinerary.totalLabel}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.go('/plan'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('Companion'),
                        subtitle: Text('$chat messages'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/travel-buddy'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.developer_mode_rounded,
                          size: 17,
                          color: AppColors.violet,
                        ),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'Build configuration',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const DataSourceChip(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _kv('Environment', env.name.label),
                    _kv('API base URL', env.hasBackend ? env.apiBaseUrl : 'not set'),
                    _kv('Google Maps key', env.hasGoogleMaps ? 'configured' : 'not set'),
                    _kv(
                      'Places key',
                      env.hasGooglePlaces ? 'configured' : 'not set',
                    ),
                    _kv('Map surface', ref.watch(mapServiceProvider).providerLabel),
                    _kv('Request timeout', '${env.requestTimeout.inSeconds}s'),
                    const SizedBox(height: 10),
                    const Text(
                      'All values are supplied at build time via --dart-define. '
                      'No secret is committed to the repository.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (user == null || user.isGuest)
                OutlinedButton.icon(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.login_rounded, size: 17),
                  label: const Text('Sign in to sync across devices'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _busy ? null : _signOut,
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: const Text('Sign out'),
                ),
              const SizedBox(height: 10),
              Text(
                'Signed in as ${user?.email ?? 'guest'} · ${user?.homeCity ?? 'Mumbai'}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              // Exposed for debugging without a separate settings screen.
              TextButton(
                onPressed: () async {
                  await service.sendPasswordReset('user@example.com');
                  if (!context.mounted) return;
                  showAppToast(
                    context,
                    'Password reset requested',
                    icon: Icons.mark_email_read_outlined,
                  );
                },
                child: const Text('Request a password reset email'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
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
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _locationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Starting point',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Changing this re-runs the ranking, the map and the plan.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                for (final place in LocationSelector.locations)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place_outlined, size: 20),
                    title: Text(place.label),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                    onTap: () {
                      ref
                          .read(discoveryContextProvider.notifier)
                          .setLocation(
                            place.label,
                            GeoPoint(latitude: place.lat, longitude: place.lng),
                          );
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}