import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../../app/widgets/brand.dart';

/// Split auth layout: navy brand panel on the left, form on the right.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showBrand = width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          if (showBrand)
            const Expanded(flex: 5, child: _BrandPanel())
          else
            const SizedBox.shrink(),
          Expanded(
            flex: showBrand ? 6 : 1,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!showBrand) ...[
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            BrandMark(height: 40),
                            SizedBox(width: 10),
                            Text(
                              'LocalIQ',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                letterSpacing: -0.5,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 22),
                      ...children,
                      if (footer != null) ...[
                        const SizedBox(height: 18),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandWash),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'LocalIQ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Discover local. Smarter.',
                style: TextStyle(
                  color: Color(0xFFBCC9E4),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Location + time + budget + interests + group + weather\n'
                '→ experiences you can actually finish.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _Feature(icon: Icons.schedule_rounded, label: 'Time-aware'),
                  _Feature(icon: Icons.payments_outlined, label: 'Budget-fit'),
                  _Feature(
                    icon: Icons.water_drop_outlined,
                    label: 'Weather-aware',
                  ),
                  _Feature(icon: Icons.route_rounded, label: 'Plan-ready'),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: Color(0xFFBCC9E4),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your plans, saved places and preferences stay yours. '
                        'Guest access works without an account.',
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
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed, this.label});

  final VoidCallback onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      icon: const _GoogleMark(),
      label: Text(label ?? 'Continue with Google'),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width / 5.2
      ..strokeCap = StrokeCap.round;
    final centre = Offset(size.width * 0.5, size.height * 0.5);
    final radius = size.width * 0.34;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -1.4,
      1.7,
      false,
      stroke..color = const Color(0xFFEA4335),
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      0.5,
      1.8,
      false,
      stroke..color = const Color(0xFFFBBC05),
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      2.2,
      1.8,
      false,
      stroke..color = const Color(0xFF34A853),
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.5),
      Offset(size.width * 0.9, size.height * 0.5),
      stroke..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key, this.message, this.tone});

  final String? message;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? AppColors.blue;
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      elevated: false,
      color: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message ?? '',
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthError extends StatelessWidget {
  const AuthError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AuthNotice(
      message: message,
      tone: AppColors.danger,
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class AuthBackLink extends StatelessWidget {
  const AuthBackLink({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/welcome'),
        icon: const Icon(Icons.arrow_back_rounded, size: 16),
        label: const Text('Back'),
      ),
    );
  }
}
