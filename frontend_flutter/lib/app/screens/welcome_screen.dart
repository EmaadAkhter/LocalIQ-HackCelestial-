import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data_providers.dart';
import '../../core/role/user_role.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/brand.dart';

/// ENTRY SCREEN: Role selection before authentication.
///
/// This is the FIRST screen the user sees. It clearly separates
/// the two product roles — Explorer and Guide — before any auth.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _continueAsExplorer() {
    ref.read(userRoleProvider.notifier).setRole(UserRole.explorer);
    context.go('/login');
  }

  void _continueAsGuide() {
    ref.read(userRoleProvider.notifier).setRole(UserRole.guide);
    context.go('/guide-login');
  }

  void _continueAsGuest() async {
    ref.read(userRoleProvider.notifier).setRole(UserRole.explorer);
    await ref.read(authServiceProvider).continueAsGuest();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.sandGradient),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Brand Header
                      const Column(
                        children: [
                          BrandMark(height: 64),
                          SizedBox(height: 14),
                          Text(
                            'LocalIQ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Discover local. Smarter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFBCC9E4),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),

                      // ── Role selection heading
                      const Text(
                        'How will you use LocalIQ?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Pick your role to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFBCC9E4),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Explorer Card
                      _RoleCard(
                        icon: Icons.explore_rounded,
                        title: 'Explorer / Traveler',
                        accent: AppColors.blue,
                        bullets: const [
                          'Discover experiences',
                          'Meet people nearby',
                          'Build plans & itineraries',
                          'Find local guides',
                        ],
                        ctaLabel: 'Continue as Explorer',
                        onCta: _continueAsExplorer,
                      ),
                      const SizedBox(height: 14),

                      // ── Guide Card
                      _RoleCard(
                        icon: Icons.person_pin_circle_rounded,
                        title: 'Local Guide / Provider',
                        accent: AppColors.violet,
                        bullets: const [
                          'Offer experiences',
                          'Manage bookings',
                          'Set your availability',
                          'Earn from tours',
                        ],
                        ctaLabel: 'Continue as Guide',
                        onCta: _continueAsGuide,
                      ),

                      const SizedBox(height: 22),

                      // ── Guest access
                      Row(
                        children: const [
                          Expanded(child: Divider(color: Color(0x33FFFFFF))),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(
                                color: Color(0xFF8FA3C4),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Color(0x33FFFFFF))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _continueAsGuest,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          minimumSize: const Size(double.infinity, 46),
                        ),
                        icon: const Icon(Icons.person_outline_rounded, size: 18),
                        label: const Text('Continue as Guest'),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Guest mode: full explore experience. Nothing saved to an account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8FA3C4),
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.bullets,
    required this.ctaLabel,
    required this.onCta,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final List<String> bullets;
  final String ctaLabel;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, size: 13, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        color: Color(0xFFD3DFF5),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onCta,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: Text(
                ctaLabel,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
