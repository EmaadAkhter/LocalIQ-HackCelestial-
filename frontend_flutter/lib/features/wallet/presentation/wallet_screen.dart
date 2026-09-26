import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

/// Phase 16: Experience Wallet & Passport Screen
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Experience Wallet'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'Active Passes'),
            Tab(text: 'Explorer Passport'),
            Tab(text: 'Badges & XP'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _ActivePassesTab(),
          _PassportTab(),
          _BadgesTab(),
        ],
      ),
    );
  }
}

class _ActivePassesTab extends StatelessWidget {
  const _ActivePassesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Digital Pass Card
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.raised,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CONFIRMED PASS',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            fontSize: 10,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Kala Ghoda Art Deco Walk',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 36),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _PassDetailRow(label: 'Guide', value: 'Riya Patel (Verified Historian)'),
                    const SizedBox(height: 8),
                    _PassDetailRow(label: 'Date & Time', value: 'Today · 4:30 PM (2h)'),
                    const SizedBox(height: 8),
                    _PassDetailRow(label: 'Meeting Point', value: 'Keneseth Eliyahoo Synagogue'),
                    const SizedBox(height: 8),
                    _PassDetailRow(label: 'Booking ID', value: 'LIQ-MUM-8921'),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 14, color: Color(0xFF0E7C5A)),
                        const SizedBox(width: 6),
                        Text(
                          'Available offline · Valid for entry without mobile data',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0E7C5A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PassDetailRow extends StatelessWidget {
  const _PassDetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PassportTab extends StatelessWidget {
  const _PassportTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Passport Cover
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2E2724), Color(0xFF3D2F2B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.raised,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'LOCALIQ PASSPORT',
                    style: TextStyle(
                      color: Color(0xFFD4AF37),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      fontSize: 12,
                    ),
                  ),
                  Icon(Icons.public_rounded, color: Color(0xFFD4AF37), size: 24),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'MUMBAI EXPLORER',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Passport No: LIQ-IND-2026-042',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PassportStat(number: '14', label: 'Places Visited'),
                  _PassportStat(number: '6', label: 'Hidden Gems'),
                  _PassportStat(number: '3', label: 'Quests Done'),
                  _PassportStat(number: '1,030', label: 'Total XP'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        const Text('Passport Stamps Collected:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: const [
            _StampChip(city: 'COLABA', date: '22 SEP 2026', icon: Icons.castle_rounded),
            _StampChip(city: 'FORT', date: '23 SEP 2026', icon: Icons.museum_rounded),
            _StampChip(city: 'MARINE DRIVE', date: '24 SEP 2026', icon: Icons.waves_rounded),
            _StampChip(city: 'KALA GHODA', date: '25 SEP 2026', icon: Icons.palette_rounded),
            _StampChip(city: 'BANDRA', date: '26 SEP 2026', icon: Icons.coffee_rounded),
          ],
        ),
      ],
    );
  }
}

class _PassportStat extends StatelessWidget {
  const _PassportStat({required this.number, required this.label});
  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}

class _StampChip extends StatelessWidget {
  const _StampChip({required this.city, required this.date, required this.icon});
  final String city;
  final String date;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 20, color: const Color(0xFFD4AF37)),
              const Text('ENTRY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFD4AF37))),
            ],
          ),
          const SizedBox(height: 6),
          Text(city, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(date, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _BadgesTab extends StatelessWidget {
  const _BadgesTab();

  @override
  Widget build(BuildContext context) {
    final badges = [
      ('Art Deco Connoisseur', 'Visited 5+ heritage sites in Fort', Icons.architecture_rounded, const Color(0xFF6C55E8)),
      ('Irani Cafe Regular', 'Sampled chai & bun maska at 3 cafes', Icons.local_cafe_rounded, const Color(0xFFC75D2C)),
      ('Monsoon Wanderer', 'Completed an outing during Mumbai rains', Icons.umbrella_rounded, const Color(0xFF2F5BFF)),
      ('Hidden Gem Hunter', 'Discovered 5 uncrowded local spots', Icons.diamond_rounded, const Color(0xFF0E7C5A)),
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: badges.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final b = badges[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: b.$4.withValues(alpha: 0.15),
                child: Icon(b.$3, color: b.$4, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(b.$2, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: const Text('Unlocked', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0E7C5A))),
              ),
            ],
          ),
        );
      },
    );
  }
}
