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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final service = ref.watch(authServiceProvider);
    final savedCount = ref.watch(savedControllerProvider).value?.length ?? 0;
    final itinerary = ref.watch(itineraryControllerProvider).value;
    final chat = ref.watch(assistantThreadProvider).messages.length;
    final env = ref.watch(environmentProvider);
    final discovery = ref.watch(discoveryContextProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
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
                        user?.initials ?? 'G',
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
                            user?.displayName ?? 'Guest',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            user?.email ?? 'Not signed in — exploring as a guest',
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
                                label: (user?.tier ?? UserTier.guest).label
                                    .toUpperCase(),
                                color: user?.isGuest == true
                                    ? AppColors.warning
                                    : AppColors.success,
                                dense: true,
                              ),
                              AppBadge(
                                label: (user?.provider ?? AuthProvider.guest)
                                    .label
                                    .toUpperCase(),
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
              AppPanel(
                padding: EdgeInsets.zero,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: const Text('Starting point'),
                        subtitle: Text(discovery.locationLabel),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _locationSheet(context),
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
                        title: const Text('Assistant'),
                        subtitle: Text('$chat messages'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/assistant'),
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