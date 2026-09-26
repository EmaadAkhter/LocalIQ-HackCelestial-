import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/driver_providers.dart';
import '../domain/driver_trip.dart';

/// The driver's trip list. Tapping a trip opens the live trip map.
class DriverTripsScreen extends ConsumerWidget {
  const DriverTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(driverTripsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My trips'),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(driverTripsProvider),
          ),
        ],
      ),
      body: trips.when(
        data: (rows) {
          if (rows.isEmpty) {
            return const _Empty('No trips assigned yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _TripCard(trip: rows[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (error, _) => _DriverError(error: error),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final DriverTripSummary trip;

  Color get _statusColor => switch (trip.status) {
        'in_progress' => AppColors.blue,
        'confirmed' || 'accepted' => AppColors.success,
        'completed' => AppColors.textMuted,
        'cancelled' => AppColors.danger,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/driver/trip/${trip.id}'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trip.title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                AppBadge(
                  label: trip.status.replaceAll('_', ' ').toUpperCase(),
                  color: _statusColor,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  trip.whenLabel,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 14),
                const Icon(Icons.group_rounded, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${trip.groupSize}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
            if (trip.pickupAddress != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.trip_origin_rounded, size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trip.pickupAddress!,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (trip.guestName != null)
                  Expanded(
                    child: Text(
                      'Guest · ${trip.guestName}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/driver/trip/${trip.id}'),
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: const Text('Open map'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route_rounded, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _DriverError extends ConsumerWidget {
  const _DriverError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = error.toString();
    final notAGuide = text.contains('not_a_guide') ||
        text.contains('not authorised') ||
        text.contains('Forbidden');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notAGuide ? Icons.badge_outlined : Icons.error_outline_rounded,
              size: 44,
              color: notAGuide ? AppColors.violet : AppColors.danger,
            ),
            const SizedBox(height: 14),
            Text(
              notAGuide
                  ? 'You are not set up as a guide yet'
                  : 'Could not load your trips',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              notAGuide
                  ? 'Complete guide onboarding to see and run trips.'
                  : text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            if (notAGuide)
              FilledButton.icon(
                onPressed: () => context.push('/guide-onboarding'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Start guide onboarding'),
              )
            else
              OutlinedButton(
                onPressed: () => ref.invalidate(driverTripsProvider),
                child: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}
