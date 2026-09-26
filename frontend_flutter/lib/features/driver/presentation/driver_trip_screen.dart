import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../routing/presentation/localiq_map_view.dart';
import '../application/driver_providers.dart';
import '../domain/driver_trip.dart';

/// The live trip map for a driver: pickup, ordered stops, drop-off and the
/// driver's own position, with the route drawn between them.
class DriverTripScreen extends ConsumerStatefulWidget {
  const DriverTripScreen({super.key, required this.bookingId});

  final int bookingId;

  @override
  ConsumerState<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends ConsumerState<DriverTripScreen> {
  final _camera = MapCameraController();
  int _routeCursor = 0;
  bool _busy = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(driverTripProvider(widget.bookingId));
    } catch (error) {
      if (mounted) {
        showAppToast(context, '$error', icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(DriverTrip trip, String status) => _run(() async {
        await ref.read(driverRepositoryProvider).setStatus(trip.id, status);
      });

  /// Walk the driver along the route so the map demonstrates live tracking
  /// without a physical device moving.
  Future<void> _simulateMove(DriverTrip trip) async {
    if (trip.route.isEmpty) return;
    await _run(() async {
      _routeCursor = (_routeCursor + 6) % trip.route.length;
      final point = trip.route[_routeCursor];
      await ref
          .read(driverRepositoryProvider)
          .reportLocation(trip.id, lat: point.lat, lng: point.lng);
      _camera.moveTo(lat: point.lat, lng: point.lng, zoom: 2.2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(driverTripProvider(widget.bookingId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Trip map'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/driver'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(driverTripProvider(widget.bookingId)),
          ),
        ],
      ),
      body: tripAsync.when(
        data: (trip) => _TripBody(
          trip: trip,
          camera: _camera,
          busy: _busy,
          onAdvance: (status) => _advance(trip, status),
          onSimulate: () => _simulateMove(trip),
        ),
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Could not load trip: $error', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _TripBody extends StatelessWidget {
  const _TripBody({
    required this.trip,
    required this.camera,
    required this.busy,
    required this.onAdvance,
    required this.onSimulate,
  });

  final DriverTrip trip;
  final MapCameraController camera;
  final bool busy;
  final ValueChanged<String> onAdvance;
  final VoidCallback onSimulate;

  @override
  Widget build(BuildContext context) {
    final pins = <PlacePin>[
      if (trip.pickup != null)
        PlacePin(
          id: 'pickup',
          label: trip.pickup!.address ?? 'Pickup',
          position: trip.pickup!.position,
          kind: PinKind.pickup,
          tone: 'pickup',
        ),
      for (final stop in trip.stops)
        if (stop.position != null)
          PlacePin(
            id: 'stop-${stop.sequence}',
            label: stop.name ?? 'Stop ${stop.sequence}',
            position: stop.position!,
            kind: PinKind.stop,
            tone: 'gem',
            number: stop.sequence,
          ),
      if (trip.drop != null)
        PlacePin(
          id: 'drop',
          label: trip.drop!.address ?? 'Drop-off',
          position: trip.drop!.position,
          kind: PinKind.drop,
          tone: 'drop',
        ),
      if (trip.driverLocation != null)
        PlacePin(
          id: 'driver',
          label: 'You',
          position: trip.driverLocation!.position,
          kind: PinKind.driver,
          tone: 'driver',
        ),
    ];

    final drop = trip.drop;
    // Before the driver reports a position, show the origin as "you".
    final fallbackOrigin = trip.driverLocation?.position ?? trip.pickup?.position;

    return ListView(
      children: [
        Stack(
          children: [
            LocalIqMapView(
              pins: pins,
              route: trip.route,
              userLocation: fallbackOrigin,
              height: 380,
              controller: camera,
              showControls: true,
              padding: 0.5,
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _StatusChip(trip: trip),
            ),
            if (trip.remaining != null)
              Positioned(
                right: 12,
                top: 12,
                child: AppBadge(
                  label: trip.remaining!.label,
                  color: AppColors.blue,
                  icon: Icons.navigation_rounded,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: MapLegend(showTrip: true, showRoute: true),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onSimulate,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Simulate movement'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                ),
              ),
              const SizedBox(width: 10),
              if (trip.primaryAction != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => onAdvance(trip.primaryAction!),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(trip.primaryActionLabel),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SummaryRow(trip: trip, drop: drop),
        const SizedBox(height: 8),
        _StopsPanel(trip: trip),
        const SizedBox(height: 20),
        _GuestPanel(trip: trip),
        const SizedBox(height: 30),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    final color = switch (trip.status) {
      'in_progress' => AppColors.blue,
      'confirmed' || 'accepted' => AppColors.success,
      'completed' => AppColors.textMuted,
      'cancelled' => AppColors.danger,
      _ => AppColors.warning,
    };
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              trip.statusLabel,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.trip, required this.drop});

  final DriverTrip trip;
  final TripPoint? drop;

  @override
  Widget build(BuildContext context) {
    final start = trip.pickup?.address ?? 'Pickup';
    final end = drop?.address ?? 'Drop-off';
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Endpoint(icon: Icons.trip_origin_rounded, color: AppColors.success, label: 'Pick up', value: start),
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Container(width: 2, height: 16, color: AppColors.border),
          ),
          _Endpoint(icon: Icons.flag_rounded, color: AppColors.danger, label: 'Drop', value: end),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _Metric(icon: Icons.straighten_rounded, label: '${trip.distanceKm.toStringAsFixed(1)} km'),
              _Metric(icon: Icons.schedule_rounded, label: '${trip.durationMin} min'),
              _Metric(icon: Icons.place_rounded, label: '${trip.stops.length} stops'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({required this.icon, required this.color, required this.label, required this.value});

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted,
                ),
              ),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _StopsPanel extends StatelessWidget {
  const _StopsPanel({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    if (trip.stops.isEmpty) return const SizedBox.shrink();
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            title: 'Route stops',
            subtitle: 'In order, with dwell time',
            icon: Icons.route_rounded,
          ),
          const SizedBox(height: 8),
          for (final stop in trip.stops)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.lavender,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${stop.sequence}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        color: AppColors.violet,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.name ?? 'Stop ${stop.sequence}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        Text(
                          '${stop.durationMin} min'
                          '${stop.travelTimeMin > 0 ? ' · ${stop.travelTimeMin} min travel' : ''}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                        ),
                      ],
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

class _GuestPanel extends StatelessWidget {
  const _GuestPanel({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            title: 'Guest',
            subtitle: 'Who you are collecting',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 8),
          _kv('Name', trip.guestName ?? 'Demo Guest'),
          _kv('Phone', trip.guestPhone ?? '—'),
          _kv('Group size', '${trip.groupSize}'),
          _kv('When', '${trip.date ?? ''} ${trip.startTime ?? ''}'.trim()),
          if ((trip.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              trip.note!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                key,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}
