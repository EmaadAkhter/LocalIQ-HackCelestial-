import 'package:flutter/material.dart';

import '../../app/router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/place_image.dart';

/// Splash / onboarding, matching the first reference frame.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_Slide> _slides = <_Slide>[
    _Slide(
      title: 'Discover Local\nSmarter',
      body: 'Feasible Mumbai plans built around your time, budget and mood.',
      imageUrl: 'https://picsum.photos/seed/localiq-onboard-1/900/1100',
      icon: Icons.account_balance_rounded,
    ),
    _Slide(
      title: 'Plans that\nactually fit',
      body: 'We filter by opening hours, travel time and cost before ranking.',
      imageUrl: 'https://picsum.photos/seed/localiq-onboard-2/900/1100',
      icon: Icons.route_rounded,
    ),
    _Slide(
      title: 'Ask, tweak,\ngo further',
      body: 'Change time or budget and your itinerary reshuffles instantly.',
      imageUrl: 'https://picsum.photos/seed/localiq-onboard-3/900/1100',
      icon: Icons.auto_awesome_rounded,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    Navigator.of(context).pushReplacementNamed(Routes.shell);
  }

  void _next() {
    if (_page == _slides.length - 1) {
      _start();
      return;
    }
    _controller.nextPage(duration: Motion.medium, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deep,
      body: Stack(
        children: <Widget>[
          // Ambient brand glow.
          Positioned(
            top: -120,
            right: -80,
            child: _Glow(
              size: 280,
              color: AppColors.primary.withValues(alpha: 0.55),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -100,
            child: _Glow(
              size: 240,
              color: AppColors.indigo.withValues(alpha: 0.4),
            ),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                const _BrandLockup(),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (int index) => setState(() => _page = index),
                    itemBuilder: (BuildContext context, int index) {
                      final _Slide item = _slides[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Expanded(
                              child: PlaceImage(
                                imageUrl: item.imageUrl,
                                seed: 'onboard-$index',
                                icon: item.icon,
                                width: double.infinity,
                                borderRadius: BorderRadius.circular(Radii.xl),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              item.body,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 14.5,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _Dots(count: _slides.length, index: _page),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
                  child: Column(
                    children: <Widget>[
                      FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(54),
                        ),
                        child: Text(
                          _page == _slides.length - 1 ? 'Get Started' : 'Next',
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _start,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1.4,
                          ),
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: const Text("I'll explore as Guest"),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.icon,
  });

  final String title;
  final String body;
  final String imageUrl;
  final IconData icon;
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[AppColors.primary, AppColors.indigo],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.explore_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: 'Local'),
                TextSpan(
                  text: 'IQ',
                  style: TextStyle(color: AppColors.star),
                ),
              ],
            ),
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (int i) {
        final bool active = i == index;
        return AnimatedContainer(
          duration: Motion.medium,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
        );
      }),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
