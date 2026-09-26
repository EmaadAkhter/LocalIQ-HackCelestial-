import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data_providers.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/brand.dart';

/// Entry screen. Route to sign-in, sign-up or guest.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.navyWash),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Column(
                      children: [
                        BrandMark(height: 68),
                        SizedBox(height: 18),
                        Text(
                          'LocalIQ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
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
                    const SizedBox(height: 26),
                    const Text(
                      'From what’s nearby\nto what you can actually do.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Location, time, budget, interests, group and weather in — '
                      'a plan you can finish out.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFBCC9E4),
                        fontSize: 13.5,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 16,
                            color: Color(0xFFBCC9E4),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Nothing is hidden. If an option does not fit '
                              'your window, we say so and explain why.',
                              style: TextStyle(
                                color: Color(0xFFD3DFF5),
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    FilledButton(
                      onPressed: () => context.go('/login'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: const Text('Get started'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(authServiceProvider)
                            .continueAsGuest();
                        if (context.mounted) context.go('/explore');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.30),
                        ),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                      label: const Text('Continue as guest'),
                    ),
                    if (wide) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Explore · My Plan · Saved · About',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8FA3C4),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
