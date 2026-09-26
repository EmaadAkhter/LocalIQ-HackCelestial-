import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import 'router/app_router.dart';

class LocalIqApp extends ConsumerStatefulWidget {
  const LocalIqApp({super.key});

  @override
  ConsumerState<LocalIqApp> createState() => _LocalIqAppState();
}

class _LocalIqAppState extends ConsumerState<LocalIqApp> {
  final _router = createAppRouter();

  @override
  void initState() {
    super.initState();
    // Cold start: try to restore a persisted session via /auth/refresh. A no-op
    // for the offline service and when there is nothing to restore.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = await ref.read(authServiceProvider).restore();
      if (!mounted) return;
      if (session != null && !session.user.onboardingCompleted) {
        _router.go('/onboarding');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LocalIQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
      builder: (context, child) {
        // Clamp text scaling so dense layouts stay intact.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.25),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Exposed so screens can build links without importing the router file.
extension GoRouterBuildContext on BuildContext {
  GoRouter get router => GoRouter.of(this);
}

extension ThemeContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get text => Theme.of(this).textTheme;
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isMobile => Breakpoints.isMobile(screenWidth);
  bool get isDesktop => Breakpoints.isDesktop(screenWidth);
}
