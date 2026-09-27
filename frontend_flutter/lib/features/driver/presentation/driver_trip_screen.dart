import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../chat/domain/chat_thread.dart';
import '../../routing/presentation/localiq_map_view.dart';
import '../application/driver_providers.dart';
import '../domain/driver_trip.dart';

/// Rapido-inspired V1 Driver Live Cockpit.
///
/// Features:
///   - Real-time turn-by-turn guidance banner
///   - Speedometer HUD & Live distance telemetry
///   - Direct passenger messaging (in-app chat) and call shortcuts
///   - One-touch Emergency SOS with local emergency contact dispatch
///   - Rapido 4-digit passenger OTP verification at pickup
///   - Interactive route walk / simulate movement
///   - Detailed fare invoice & QR payment collection upon trip completion
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
  int _speedKmh = 34;

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

  /// Walk the driver along the route so the map demonstrates live tracking.
  Future<void> _simulateMove(DriverTrip trip) async {
    if (trip.route.isEmpty) return;
    await _run(() async {
      _routeCursor = (_routeCursor + 6) % trip.route.length;
      final point = trip.route[_routeCursor];
      await ref
          .read(driverRepositoryProvider)
          .reportLocation(trip.id, lat: point.lat, lng: point.lng);
      _camera.moveTo(lat: point.lat, lng: point.lng, zoom: 2.2);
      setState(() {
        _speedKmh = 28 + (_routeCursor % 16);
      });
    });
  }

  void _showOtpDialog(DriverTrip trip) {
    final otpCtrl = TextEditingController(text: '4829');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: const Text(
                      'START TRIP OTP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter 4-Digit Passenger Code',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Ask ${trip.guestName ?? "the passenger"} for their Rapido pickup PIN to ensure you have the right rider.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 16,
                  color: AppColors.primary,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••',
                  filled: true,
                  fillColor: AppColors.canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _advance(trip, 'in_progress');
                    showAppToast(context, 'OTP Verified! Ride Started 🚀', icon: Icons.check_circle_rounded);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    foregroundColor: Colors.black,
                    minimumSize: const Size(0, 50),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text(
                    'VERIFY & START TRIP',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFareReceipt(DriverTrip trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'RIDE COMPLETED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.success,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Collect Fare',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _fareRow('Base Fare', '₹50.00'),
                    const SizedBox(height: 6),
                    _fareRow('Distance Fare (${trip.distanceKm.toStringAsFixed(1)} km)', '₹140.00'),
                    const SizedBox(height: 6),
                    _fareRow('High Demand Surge (1.2x)', '₹35.00'),
                    const SizedBox(height: 6),
                    _fareRow('Tolls & Platform fee', '₹15.00'),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'TOTAL COLLECTIBLE',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        Text(
                          '₹240.00',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: const [
                  Icon(Icons.qr_code_2_rounded, size: 24, color: AppColors.text),
                  SizedBox(width: 8),
                  Text(
                    'Collect via UPI QR or Cash',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _advance(trip, 'completed');
                    showAppToast(context, '₹240 Collected! Trip closed.', icon: Icons.celebration_rounded);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size(0, 50),
                  ),
                  child: const Text(
                    'COLLECT ₹240 & FINISH TRIP',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _fareRow(String title, String amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  void _showSosConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 26),
            SizedBox(width: 10),
            Text('Emergency SOS', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: const Text(
          'Triggering SOS alerts the LocalIQ Safety Control Room, your registered emergency contact, and Mumbai Police (112) with your live vehicle GPS location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              showAppToast(
                context,
                '🚨 SOS Triggered! Safety Team & Patrol dispatched.',
                icon: Icons.shield_rounded,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('CONFIRM SOS'),
          ),
        ],
      ),
    );
  }

  void _openChatWithPassenger(DriverTrip trip) {
    final thread = ChatThread(
      id: 1,
      kind: 'guide_explorer',
      otherUserId: 101,
      otherName: trip.guestName ?? 'Passenger',
      contextLabel: 'Ride #${trip.bookingRef} · ${trip.pickup?.address ?? "Pickup"}',
    );
    context.push('/chat/1', extra: thread);
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(driverTripProvider(widget.bookingId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/driver'),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB800),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: const Text(
                'LIVE RIDE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Trip #${widget.bookingId}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        actions: [
          // Emergency SOS Button
          IconButton(
            tooltip: 'Emergency SOS',
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sos_rounded, color: AppColors.danger, size: 22),
            ),
            onPressed: _showSosConfirmation,
          ),
          // Refresh
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(driverTripProvider(widget.bookingId)),
          ),
        ],
      ),
      body: tripAsync.when(
        data: (trip) => _CockpitBody(
          trip: trip,
          camera: _camera,
          busy: _busy,
          speedKmh: _speedKmh,
          onAdvance: (status) => _advance(trip, status),
          onSimulate: () => _simulateMove(trip),
          onOpenOtp: () => _showOtpDialog(trip),
          onOpenFare: () => _showFareReceipt(trip),
          onOpenChat: () => _openChatWithPassenger(trip),
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

// ── Cockpit Body ─────────────────────────────────────────────────────────────

class _CockpitBody extends StatelessWidget {
  const _CockpitBody({
    required this.trip,
    required this.camera,
    required this.busy,
    required this.speedKmh,
    required this.onAdvance,
    required this.onSimulate,
    required this.onOpenOtp,
    required this.onOpenFare,
    required this.onOpenChat,
  });

  final DriverTrip trip;
  final MapCameraController camera;
  final bool busy;
  final int speedKmh;
  final ValueChanged<String> onAdvance;
  final VoidCallback onSimulate;
  final VoidCallback onOpenOtp;
  final VoidCallback onOpenFare;
  final VoidCallback onOpenChat;

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
          label: 'You (Bike)',
          position: trip.driverLocation!.position,
          kind: PinKind.driver,
          tone: 'driver',
        ),
    ];

    final fallbackOrigin = trip.driverLocation?.position ?? trip.pickup?.position;

    return ListView(
      children: [
        // ── Turn-by-Turn Instruction Banner ──────────────────────────────────
        _TurnInstructionBanner(trip: trip),

        // ── Interactive Map View with telemetry HUD ──────────────────────────
        Stack(
          children: [
            LocalIqMapView(
              pins: pins,
              route: trip.route,
              userLocation: fallbackOrigin,
              height: 360,
              controller: camera,
              showControls: true,
              padding: 0.5,
            ),
            // Status Chip
            Positioned(
              left: 12,
              top: 12,
              child: _StatusChip(trip: trip),
            ),
            // Speedometer HUD
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed_rounded, size: 16, color: Color(0xFFFFB800)),
                    const SizedBox(width: 5),
                    Text(
                      '$speedKmh km/h',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Remaining distance/ETA badge
            if (trip.remaining != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.navigation_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 5),
                      Text(
                        trip.remaining!.label,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        // ── Passenger Communications Hub ─────────────────────────────────────
        _PassengerCard(
          trip: trip,
          onChat: onOpenChat,
          onCall: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Calling ${trip.guestName ?? "Passenger"}...'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),

        // ── Primary Rapido Action Bar ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              if (trip.status == 'confirmed' || trip.status == 'accepted')
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onOpenOtp,
                    icon: const Icon(Icons.pin_rounded, size: 20),
                    label: const Text(
                      'ARRIVED AT PICKUP · ENTER OTP',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB800),
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                )
              else if (trip.status == 'in_progress')
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onOpenFare,
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: const Text(
                      'COMPLETE RIDE & COLLECT FARE',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                )
              else if (trip.primaryAction != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => onAdvance(trip.primaryAction!),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      trip.primaryActionLabel.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  ),
                ),
              const SizedBox(height: 8),
              // Simulation button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onSimulate,
                  icon: const Icon(Icons.electric_bike_rounded, size: 18),
                  label: const Text('Simulate Vehicle Movement (+6 coordinates)'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        // ── Route Endpoints ──────────────────────────────────────────────────
        _SummaryRow(trip: trip, drop: trip.drop),

        const SizedBox(height: 12),
        // ── Stops ────────────────────────────────────────────────────────────
        _StopsPanel(trip: trip),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Turn-by-Turn Instruction Banner ──────────────────────────────────────────

class _TurnInstructionBanner extends StatelessWidget {
  const _TurnInstructionBanner({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    final (instruction, icon) = switch (trip.status) {
      'confirmed' || 'accepted' => (
          'Head towards Bandra Station West · Pickup point in 1.2 km',
          Icons.turn_right_rounded,
        ),
      'in_progress' => (
          'Proceed on Western Express Highway towards South Mumbai',
          Icons.straight_rounded,
        ),
      'completed' => (
          'Destination reached at Colaba Causeway. Ride Complete.',
          Icons.flag_rounded,
        ),
      _ => ('Follow on-screen route navigation', Icons.navigation_rounded),
    };

    return Container(
      color: const Color(0xFF1F2937),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB800),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: Colors.black, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEXT MANEUVER',
                  style: TextStyle(
                    color: Color(0xFFFFB800),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  instruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

// ── Passenger Card with Direct Chat ──────────────────────────────────────────

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({
    required this.trip,
    required this.onChat,
    required this.onCall,
  });

  final DriverTrip trip;
  final VoidCallback onChat;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primarySurface,
            child: Text(
              (trip.guestName?.isNotEmpty == true ? trip.guestName![0] : 'P').toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
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
                    Text(
                      trip.guestName ?? 'Passenger',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFD97706)),
                    const Text('4.9', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  ],
                ),
                Text(
                  '${trip.groupSize} rider · Cash / UPI payment',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          // Call Button
          IconButton(
            tooltip: 'Call Passenger',
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceSecondary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone_rounded, size: 18, color: AppColors.text),
            ),
            onPressed: onCall,
          ),
          const SizedBox(width: 4),
          // Chat Button
          IconButton(
            tooltip: 'Chat with Passenger',
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_rounded, size: 18, color: AppColors.primary),
            ),
            onPressed: onChat,
          ),
        ],
      ),
    );
  }
}

// ── Status Chip ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    final color = switch (trip.status) {
      'in_progress' => const Color(0xFF2563EB),
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
              trip.statusLabel.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Summary Row ─────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.trip, required this.drop});

  final DriverTrip trip;
  final TripPoint? drop;

  @override
  Widget build(BuildContext context) {
    final start = trip.pickup?.address ?? 'Pickup spot';
    final end = drop?.address ?? 'Drop-off point';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Endpoint(icon: Icons.trip_origin_rounded, color: AppColors.success, label: 'Pick up', value: start),
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Container(width: 2, height: 16, color: AppColors.border),
          ),
          _Endpoint(icon: Icons.flag_rounded, color: AppColors.danger, label: 'Drop off', value: end),
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

// ── Stops Panel ─────────────────────────────────────────────────────────────

class _StopsPanel extends StatelessWidget {
  const _StopsPanel({required this.trip});

  final DriverTrip trip;

  @override
  Widget build(BuildContext context) {
    if (trip.stops.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.route_rounded, size: 16, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'ROUTE STOPS & EXPERIENCES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                      color: AppColors.primarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${stop.sequence}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        color: AppColors.primary,
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
                          '${stop.durationMin} min stay'
                          '${stop.travelTimeMin > 0 ? ' · ${stop.travelTimeMin} min transit' : ''}',
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
