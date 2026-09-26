import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

/// Phase 17: AI Experience Director Screen
///
/// Autonomous real-time orchestrator that detects weather, crowd,
/// and traffic conditions and dynamically recalculates the user's plan.
class DirectorScreen extends ConsumerStatefulWidget {
  const DirectorScreen({super.key});

  @override
  ConsumerState<DirectorScreen> createState() => _DirectorScreenState();
}

class _DirectorScreenState extends ConsumerState<DirectorScreen> {
  bool _rainSimulation = false;
  bool _rerouteAccepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.psychology_rounded, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('AI Experience Director'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Autonomous Director Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.raised,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'AUTONOMOUS SUPERVISOR ACTIVE',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const Text('v2.4 Live Engine', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Continuous Feasibility Monitoring',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Supervising transit times, live crowd levels, opening hours, and weather radar across South Mumbai.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Real-time Environmental Sensors
          Row(
            children: [
              Expanded(
                child: _SensorCard(
                  label: 'Weather Radar',
                  value: _rainSimulation ? 'Rain Cloud in 40m' : '29°C · Clear Sky',
                  status: _rainSimulation ? 'Alert Active' : 'Optimal',
                  icon: _rainSimulation ? Icons.umbrella_rounded : Icons.wb_sunny_rounded,
                  isWarning: _rainSimulation,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SensorCard(
                  label: 'Crowd Index',
                  value: 'Low (28% capacity)',
                  status: 'Great for walking',
                  icon: Icons.groups_rounded,
                  isWarning: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Active Intervention Card (When conditions change)
          if (_rainSimulation && !_rerouteAccepted)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: const Color(0xFFF59E0B)),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Color(0xFFD97706), size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Director Optimization Alert',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Coastal shower predicted at 5:15 PM during your planned Marine Drive Walk. The Director proposes swapping to the indoor National Gallery of Modern Art (NGMA) without altering your dinner reservation.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF78350F), height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            setState(() => _rerouteAccepted = true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Reroute accepted! Itinerary updated smoothly.'),
                                backgroundColor: Color(0xFF0E7C5A),
                              ),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Accept Smart Reroute'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // ── Supervised Dynamic Schedule
          Text(
            _rerouteAccepted ? 'Optimized Schedule (Weather-Adjusted)' : 'Current Active Timeline',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),

          _TimelineStop(
            time: '3:30 PM - 4:45 PM',
            title: 'Kala Ghoda Art Precinct & Cafe Heritage',
            subtitle: 'Confirmed · Walking 400m',
            isCurrent: true,
          ),
          const SizedBox(height: 10),

          _TimelineStop(
            time: '5:00 PM - 6:30 PM',
            title: _rerouteAccepted
                ? 'National Gallery of Modern Art (NGMA)'
                : 'Marine Drive Sunset Promenade',
            subtitle: _rerouteAccepted
                ? '⭐ Auto-substituted: Air conditioned, rain-proof'
                : 'Outdoor coastal walk · Weather monitoring active',
            isHighlighted: _rerouteAccepted,
          ),
          const SizedBox(height: 10),

          _TimelineStop(
            time: '7:00 PM - 8:30 PM',
            title: 'Trishna Seafood, Fort',
            subtitle: 'Dinner reservation held · 12m transit time',
            isCurrent: false,
          ),
          const SizedBox(height: 24),

          // ── Simulation Sandbox Controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Simulation Testing Sandbox',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Test how the AI Experience Director dynamically adapts to real-world disruptions:',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(
                          _rainSimulation ? Icons.cloud_off_rounded : Icons.grain_rounded,
                          size: 16,
                        ),
                        label: Text(_rainSimulation ? 'Clear Rain' : 'Simulate Rain'),
                        onPressed: () {
                          setState(() {
                            _rainSimulation = !_rainSimulation;
                            if (!_rainSimulation) _rerouteAccepted = false;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.label,
    required this.value,
    required this.status,
    required this.icon,
    required this.isWarning,
  });

  final String label;
  final String value;
  final String status;
  final IconData icon;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isWarning ? const Color(0xFFF59E0B) : AppColors.border,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Icon(icon, size: 18, color: isWarning ? const Color(0xFFD97706) : AppColors.primary),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 3),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isWarning ? const Color(0xFFD97706) : const Color(0xFF0E7C5A),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineStop extends StatelessWidget {
  const _TimelineStop({
    required this.time,
    required this.title,
    required this.subtitle,
    this.isCurrent = false,
    this.isHighlighted = false,
  });

  final String time;
  final String title;
  final String subtitle;
  final bool isCurrent;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFECFDF5)
            : isCurrent
                ? AppColors.primarySurface
                : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFF10B981)
              : isCurrent
                  ? AppColors.primary
                  : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isHighlighted
                ? Icons.check_circle_rounded
                : isCurrent
                    ? Icons.play_circle_filled_rounded
                    : Icons.schedule_rounded,
            size: 18,
            color: isHighlighted
                ? const Color(0xFF0E7C5A)
                : isCurrent
                    ? AppColors.primary
                    : AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
