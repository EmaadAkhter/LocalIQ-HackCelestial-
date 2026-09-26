import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/role/user_role.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/brand.dart';

/// Role selection screen — the first screen after splash/onboarding.
///
/// Shows two distinct product role cards: Explorer and Guide.
/// Persists the selected role in [userRoleProvider].
class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  UserRole? _hoveredRole;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _selectRole(UserRole role) {
    ref.read(userRoleProvider.notifier).setRole(role);
    if (role == UserRole.explorer) {
      context.go('/login');
    } else {
      context.go('/guide/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.sandGradient),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  const BrandMark(height: 60),
                  const SizedBox(height: 16),
                  const Text(
                    'LocalIQ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Discover Local. Smarter.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFBCC9E4),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    'Welcome to LocalIQ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'How would you like to use LocalIQ?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFBCC9E4),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _RoleCard(
                    role: UserRole.explorer,
                    emoji: '🧭',
                    title: 'Explorer',
                    subtitle: 'Discover experiences, meet people, build plans, find guides.',
                    features: const [
                      'Personalized discovery feed',
                      'Right Now recommendations',
                      'Find and book local guides',
                      'Build plans with friends',
                    ],
                    accent: AppColors.blue,
                    isHovered: _hoveredRole == UserRole.explorer,
                    onHover: (v) => setState(
                        () => _hoveredRole = v ? UserRole.explorer : null),
                    onTap: () => _selectRole(UserRole.explorer),
                    ctaLabel: 'Continue as Explorer',
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    role: UserRole.guide,
                    emoji: '🎙️',
                    title: 'Guide',
                    subtitle:
                        'Offer experiences, manage availability, accept bookings, earn.',
                    features: const [
                      'Create and manage experiences',
                      'Booking calendar & requests',
                      'Earnings dashboard',
                      'Guide verification & identity',
                    ],
                    accent: AppColors.violet,
                    isHovered: _hoveredRole == UserRole.guide,
                    onHover: (v) =>
                        setState(() => _hoveredRole = v ? UserRole.guide : null),
                    onTap: () => _selectRole(UserRole.guide),
                    ctaLabel: 'Continue as Guide',
                  ),
                  const SizedBox(height: 28),
                  TextButton(
                    onPressed: () {
                      ref.read(userRoleProvider.notifier).setRole(
                          UserRole.explorer);
                      context.go('/home');
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF8FA3C4),
                    ),
                    child: const Text(
                      'Browse as guest',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _RoleSelectionFooter(),
                ],
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
    required this.role,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.accent,
    required this.isHovered,
    required this.onHover,
    required this.onTap,
    required this.ctaLabel,
  });

  final UserRole role;
  final String emoji;
  final String title;
  final String subtitle;
  final List<String> features;
  final Color accent;
  final bool isHovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  final String ctaLabel;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: isHovered
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: isHovered
                ? accent.withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.12),
            width: isHovered ? 1.5 : 1.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          role == UserRole.explorer
                              ? 'Traveller'
                              : 'Provider',
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFFBCC9E4),
                  fontSize: 13.5,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 15, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          style: const TextStyle(
                            color: Color(0xFFD3DFF5),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: Text(
                    ctaLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleSelectionFooter extends StatelessWidget {
  const _RoleSelectionFooter();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'You can switch your role at any time from your profile.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Color(0xFF6B7FA0),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
