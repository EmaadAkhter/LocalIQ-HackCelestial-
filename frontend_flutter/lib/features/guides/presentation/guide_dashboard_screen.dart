import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/role/user_role.dart';
import '../../../core/theme/app_theme.dart';

/// Phase 12: Guide App Dashboard Screen
class GuideDashboardScreen extends ConsumerStatefulWidget {
  const GuideDashboardScreen({super.key});

  @override
  ConsumerState<GuideDashboardScreen> createState() => _GuideDashboardScreenState();
}

class _GuideDashboardScreenState extends ConsumerState<GuideDashboardScreen> {
  bool _isAvailableNow = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Guide Workspace'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Explorer Mode'),
            onPressed: () {
              ref.read(userRoleProvider.notifier).setRole(UserRole.explorer);
              context.go('/home');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Availability Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isAvailableNow ? const Color(0xFF0E7C5A) : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isAvailableNow ? 'Available for Tours Now' : 'Currently Offline',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      Text(
                        _isAvailableNow
                            ? 'Explorers in South Mumbai can request instant bookings'
                            : 'Toggle on to receive live tour requests',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isAvailableNow,
                  activeThumbColor: const Color(0xFF0E7C5A),
                  onChanged: (val) {
                    setState(() => _isAvailableNow = val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Earnings summary row
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: 'Week Earnings',
                  value: '₹6,400',
                  subtitle: '+24% from last week',
                  icon: Icons.currency_rupee_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  title: 'Completed Tours',
                  value: '18',
                  subtitle: '★ 4.9 Rating',
                  icon: Icons.tour_rounded,
                  color: const Color(0xFF0E7C5A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Incoming Booking Requests
          const Text(
            'Incoming Booking Requests',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          _BookingRequestCard(
            travelerName: 'Elena Rostova',
            experienceTitle: 'Art Deco & Hidden Courtyards',
            time: 'Today at 5:00 PM (2h)',
            partySize: 2,
            rate: '₹1,600',
            onAccept: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Booking accepted! Meeting point confirmed.')),
              );
            },
          ),
          const SizedBox(height: 20),

          // ── My Active Experience Listings
          const Text(
            'My Active Experience Listings',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          _ExperienceListingCard(
            title: 'Kala Ghoda Art Deco & Hidden Passages',
            ratePerHour: '₹800/hr',
            duration: '2 hours',
            totalBookings: 12,
            active: true,
          ),
          const SizedBox(height: 10),
          _ExperienceListingCard(
            title: 'Sassoon Docks Morning Heritage & Fish Auction Walk',
            ratePerHour: '₹750/hr',
            duration: '2.5 hours',
            totalBookings: 6,
            active: true,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _BookingRequestCard extends StatelessWidget {
  const _BookingRequestCard({
    required this.travelerName,
    required this.experienceTitle,
    required this.time,
    required this.partySize,
    required this.rate,
    required this.onAccept,
  });

  final String travelerName;
  final String experienceTitle;
  final String time;
  final int partySize;
  final String rate;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySurface,
                child: Text(travelerName[0], style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(travelerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text('$time · $partySize explorers', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Text(rate, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Row(
              children: [
                const Icon(Icons.explore_outlined, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(child: Text(experienceTitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Accept Booking'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExperienceListingCard extends StatelessWidget {
  const _ExperienceListingCard({
    required this.title,
    required this.ratePerHour,
    required this.duration,
    required this.totalBookings,
    required this.active,
  });

  final String title;
  final String ratePerHour;
  final String duration;
  final int totalBookings;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 4),
                Text('$ratePerHour · $duration · $totalBookings completed tours', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF0E7C5A).withValues(alpha: 0.12) : AppColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              active ? 'Active' : 'Paused',
              style: TextStyle(
                color: active ? const Color(0xFF0E7C5A) : AppColors.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
