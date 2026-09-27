import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import 'router/app_router.dart';

class LocalIqApp extends ConsumerStatefulWidget {
  const LocalIqApp({super.key});

  @override
  ConsumerState<LocalIqApp> createState() => _LocalIqAppState();
}

class _LocalIqAppState extends ConsumerState<LocalIqApp> with WidgetsBindingObserver {
  final _router = createAppRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called every time the app comes to the foreground — resets the 7-day
  /// inactivity clock so only truly absent users are signed out.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(sharedPrefsTokenStoreProvider.future).then((store) {
        store.touchActivity();
      }).ignore();
    }
  }

  Future<void> _bootstrap() async {
    // Ensure SharedPreferences are loaded before anything else resolves.
    await ref.read(sharedPrefsTokenStoreProvider.future);

    // Check if the user has already completed onboarding (local flag).
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('localiq.onboarding.completed') ?? false;

    // Try to restore a persisted session.
    final session = await ref.read(authServiceProvider).restore();
    if (!mounted) return;

    if (session != null && !onboardingDone && !session.user.isGuest) {
      // Registered user who hasn't finished onboarding yet.
      _router.go('/onboarding');
    } else if (session != null) {
      // Already logged in — go straight home.
      _router.go('/home');
    }
    // Otherwise, stay on /welcome (the initial location).
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
