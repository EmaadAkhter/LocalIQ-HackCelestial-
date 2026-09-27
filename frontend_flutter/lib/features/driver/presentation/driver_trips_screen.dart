import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../application/driver_providers.dart';
import '../domain/driver_trip.dart';

/// Rapido-inspired Driver / Captain V1 Home Hub.
///
/// Features:
///   - Online / Offline duty status with live pulse indicator
///   - Today's earnings HUD & bonus target progress bar
///   - High demand / surge hotspot radar
///   - Simulated incoming ride dispatch with 15s countdown timer
///   - Active trip queue with instant navigation launch
///   - Direct passenger messaging shortcut
class DriverTripsScreen extends ConsumerStatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  ConsumerState<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends ConsumerState<DriverTripsScreen> {
  bool _isOnline = true;
  bool _showIncomingRequest = false;
  int _countdownSeconds = 15;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Simulate an incoming ride dispatch after 2 seconds if online
    if (_isOnline) {
      _scheduleIncomingRide();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _scheduleIncomingRide() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isOnline && !_showIncomingRequest) {
        setState(() {
          _showIncomingRequest = true;
          _countdownSeconds = 15;
        });
        _startTimer();
      }
    });
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdownSeconds <= 1) {
        t.cancel();
        setState(() => _showIncomingRequest = false);
      } else {
        setState(() => _countdownSeconds--);
      }
    });
  }

  void _toggleDuty() {
    setState(() {
      _isOnline = !_isOnline;
      if (!_isOnline) {
        _showIncomingRequest = false;
        _countdownTimer?.cancel();
      } else {
        _scheduleIncomingRide();
      }
    });
  }

  void _acceptRide(int tripId) {
    _countdownTimer?.cancel();
    setState(() => _showIncomingRequest = false);
    context.push('/driver/trip/$tripId');
  }

  void _declineRide() {
    _countdownTimer?.cancel();
    setState(() => _showIncomingRequest = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trip declined. Looking for next best match...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(driverTripsProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB800),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: const Text(
                'RAPIDO V1',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Captain Hub', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Passenger Messages',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () => context.push('/inbox'),
          ),
          IconButton(
            tooltip: 'Refresh Trips',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(driverTripsProvider),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── Duty Toggle Switch ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _DutySwitchBar(
              isOnline: _isOnline,
              onToggle: _toggleDuty,
            ),
          ),

          // ── Earnings HUD ───────────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: _EarningsHudCard(),
          ),

          // ── Surge / Hotspots Strip ─────────────────────────────────────────
          if (_isOnline)
            const SliverToBoxAdapter(
              child: _SurgeHotspotBanner(),
            ),

          // ── Incoming Ride Card (Rapido style dispatch) ─────────────────────
          if (_isOnline && _showIncomingRequest)
            SliverToBoxAdapter(
              child: _IncomingRideSheet(
                countdownSeconds: _countdownSeconds,
                onAccept: () => _acceptRide(1),
                onDecline: _declineRide,
              ),
            ),

          // ── Section Title ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'ASSIGNED TRIPS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Text(
                      'Live Queue',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Trips List ─────────────────────────────────────────────────────
          trips.when(
            data: (rows) {
              if (rows.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyTripsView(),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _TripCard(trip: rows[index]),
                    childCount: rows.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (err, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Duty Switch Bar ──────────────────────────────────────────────────────────

class _DutySwitchBar extends StatelessWidget {
  const _DutySwitchBar({required this.isOnline, required this.onToggle});

  final bool isOnline;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOnline ? const Color(0xFF10281E) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isOnline ? AppColors.success.withValues(alpha: 0.5) : AppColors.border,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOnline ? AppColors.success : Colors.black).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? AppColors.success : AppColors.danger,
              boxShadow: [
                if (isOnline)
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? "YOU'RE ONLINE" : "YOU'RE OFFLINE",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.5,
                    color: isOnline ? Colors.white : AppColors.text,
                  ),
                ),
                Text(
                  isOnline
                      ? 'Receiving ride requests nearby'
                      : 'Go online to start receiving bookings',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isOnline ? Colors.white.withValues(alpha: 0.7) : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isOnline,
            onChanged: (_) => onToggle(),
            activeThumbColor: AppColors.success,
            activeTrackColor: AppColors.success.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

// ── Earnings HUD Card ────────────────────────────────────────────────────────

class _EarningsHudCard extends StatelessWidget {
  const _EarningsHudCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "TODAY'S EARNINGS",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: const [
                      Text(
                        '₹1,480',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.text,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '+₹120 tips',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.star_rounded, size: 14, color: Color(0xFFD97706)),
                        SizedBox(width: 2),
                        Text(
                          '4.92',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      'Rating',
                      style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Metric chips
          Row(
            children: [
              _MetricItem(label: 'Rides', value: '6 done', icon: Icons.sports_motorsports_rounded),
              _MetricItem(label: 'Online', value: '4h 35m', icon: Icons.timer_outlined),
              _MetricItem(label: 'Acceptance', value: '98%', icon: Icons.thumb_up_alt_outlined),
            ],
          ),
          const SizedBox(height: 12),
          // Daily Target Goal Progress
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'Daily Goal: ₹1,480 / ₹2,000',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '74%',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: const LinearProgressIndicator(
                  value: 0.74,
                  minHeight: 7,
                  backgroundColor: AppColors.surfaceSecondary,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.bolt_rounded, size: 15, color: AppColors.primary),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '⚡ Complete 2 more trips to earn a ₹150 daily surge bonus!',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
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

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Icon(icon, size: 15, color: AppColors.textMuted),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Surge / Hotspots Banner ─────────────────────────────────────────────────

class _SurgeHotspotBanner extends StatelessWidget {
  const _SurgeHotspotBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0xFFFFD599)),
      ),
      child: Row(
        children: const [
          Icon(Icons.local_fire_department_rounded, size: 18, color: Color(0xFFE65100)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '🔥 Surge Alert: 1.4x in Bandra West & Colaba (+₹40 extra/trip)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A3B00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Incoming Ride Sheet (Rapido Dispatch) ───────────────────────────────────

class _IncomingRideSheet extends StatelessWidget {
  const _IncomingRideSheet({
    required this.countdownSeconds,
    required this.onAccept,
    required this.onDecline,
  });

  final int countdownSeconds;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B18),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: const Color(0xFFFFB800), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB800).withValues(alpha: 0.3),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with vehicle and timer
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.two_wheeler_rounded, size: 14, color: Colors.black),
                    SizedBox(width: 4),
                    Text(
                      'RAPIDO BIKE TAXI',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Countdown ring
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      value: countdownSeconds / 15.0,
                      strokeWidth: 3,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB800)),
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  Text(
                    '$countdownSeconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fare & Distance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'ESTIMATED FARE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white60,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '₹240.00',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF4ADE80),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text(
                    'TRIP LENGTH',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white60,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '21.4 km · 45m',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Pickup & Drop
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              children: [
                Row(
                  children: const [
                    Icon(Icons.trip_origin_rounded, size: 14, color: Color(0xFF4ADE80)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pickup: Bandra Station (West) · 1.2 km away',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(width: 2, height: 12, color: Colors.white24),
                  ),
                ),
                Row(
                  children: const [
                    Icon(Icons.flag_rounded, size: 14, color: Color(0xFFFF5A36)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Drop: Colaba Causeway, Mumbai',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Passenger info
          Row(
            children: const [
              CircleAvatar(
                radius: 14,
                backgroundColor: Color(0xFFFF5A36),
                child: Text('D', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              SizedBox(width: 8),
              Text(
                'Demo Guest · ★ 4.9',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Spacer(),
              Text(
                'Cash / UPI',
                style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Actions
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: FilledButton.icon(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    foregroundColor: Colors.black,
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 20),
                  label: const Text(
                    'ACCEPT RIDE',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Trip Card ───────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final DriverTripSummary trip;

  Color get _statusColor => switch (trip.status) {
        'in_progress' => const Color(0xFF2563EB),
        'confirmed' || 'accepted' => AppColors.success,
        'completed' => AppColors.textMuted,
        'cancelled' => AppColors.danger,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/driver/trip/${trip.id}'),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        trip.status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: _statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Booking #${trip.bookingRef}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '₹240',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  trip.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.trip_origin_rounded, size: 14, color: AppColors.success),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        trip.pickupAddress ?? 'Pickup spot',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      '${trip.guestName ?? "Passenger"} · ${trip.groupSize} guest(s)',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    Text(
                      trip.whenLabel,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/driver/trip/${trip.id}'),
                    icon: const Icon(Icons.navigation_rounded, size: 16),
                    label: const Text('Open Trip Cockpit'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty View ──────────────────────────────────────────────────────────────

class _EmptyTripsView extends StatelessWidget {
  const _EmptyTripsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.two_wheeler_outlined, size: 52, color: AppColors.textMuted),
            SizedBox(height: 14),
            Text(
              'No active trips right now',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            SizedBox(height: 6),
            Text(
              'Stay online to receive ride bookings in your zone.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
