import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_image.dart';
import '../../data/local_social.dart';
import '../../data/social_repository.dart';

/// Home-feed entry point for Random Meetup.
///
/// Surfaces the human-to-human side of LocalIQ on Home, where it was previously
/// buried, without stealing a bottom-nav slot from the AI Travel Buddy.
class RandomMeetupBanner extends ConsumerWidget {
  const RandomMeetupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(peopleMatchesProvider).value ?? kLocalPeopleMatches;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'SPONTANEOUS',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.visibility_off_rounded, size: 14, color: Colors.white70),
              const SizedBox(width: 4),
              const Text(
                'Ghost Mode',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Random Meetup',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Find someone who gets your vibe, right now.',
            style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 24.0 + (matches.take(4).length - 1) * 18.0,
                height: 32,
                child: Stack(
                  children: [
                    for (var i = 0; i < matches.take(4).length; i++)
                      Positioned(
                        left: i * 18.0,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: AppImage(
                            url: matches[i].photoUrl,
                            width: 29,
                            height: 29,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            fallbackLabel: matches[i].displayName,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${matches.length} explorers nearby',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => context.push('/people'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primaryDark,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text(
                  'Find a buddy',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
