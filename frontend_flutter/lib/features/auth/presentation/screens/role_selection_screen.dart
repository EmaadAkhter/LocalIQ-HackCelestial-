import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/role/user_role.dart';
import '../../../../core/theme/app_theme.dart';

/// Role selection screen — shown once after first login.
///
/// The user picks whether they are an Explorer (discover & plan)
/// or a Guide (offer experiences, manage bookings).
///
/// This is a one-time flow; the selection is persisted via [userRoleProvider].
class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  UserRole? _selected;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_selected == null) return;
    ref.read(userRoleProvider.notifier).setRole(_selected!);
    final dest = _selected == UserRole.explorer ? '/home' : '/guide/dashboard';
    context.go(dest);
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header
                  const Text(
                    'How will you use\nLocalIQ?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Pick a mode to start. You can switch anytime from your profile.',
                    style: TextStyle(
                      color: Color(0xFFBCC9E4),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Role cards
                  _RoleCard(
                    role: UserRole.explorer,
                    selected: _selected == UserRole.explorer,
                    onTap: () => setState(() => _selected = UserRole.explorer),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    role: UserRole.guide,
                    selected: _selected == UserRole.guide,
                    onTap: () => setState(() => _selected = UserRole.guide),
                  ),

                  const Spacer(),

                  // ── CTA
                  AnimatedOpacity(
                    opacity: _selected != null ? 1.0 : 0.35,
                    duration: AppMotion.base,
                    child: FilledButton(
                      onPressed: _selected != null ? _confirm : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: Text(
                        _selected != null
                            ? 'Continue as ${_selected!.label}'
                            : 'Select a mode to continue',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
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
                      'Skip for now (Explorer mode)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
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
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isExplorer = role == UserRole.explorer;

    final accent = isExplorer ? AppColors.blue : AppColors.violet;
    final icon = isExplorer
        ? Icons.explore_rounded
        : Icons.person_pin_circle_rounded;
    final title = isExplorer ? 'Explorer' : 'Guide';
    final tagline = isExplorer
        ? 'Discover experiences, plan outings, meet local guides.'
        : 'Offer experiences, manage your availability, earn from your knowledge.';

    final bullets = isExplorer
        ? [
            'Personalised discovery feed',
            'Smart itinerary planning',
            'Connect with local guides',
            'Quests & hidden gems',
          ]
        : [
            'List and manage your experiences',
            'Availability calendar',
            'Receive and confirm bookings',
            'Earn from your local expertise',
          ];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.base,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.70)
                : Colors.white.withValues(alpha: 0.12),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon pill
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Text(
                            'Selected',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tagline,
                    style: const TextStyle(
                      color: Color(0xFFBCC9E4),
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...bullets.map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 13, color: accent),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              b,
                              style: const TextStyle(
                                color: Color(0xFFD3DFF5),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
