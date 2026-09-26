import 'package:flutter/material.dart';

import '../features/chat/chat_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/place_details/place_details_screen.dart';
import '../features/shell/main_shell.dart';
import '../models/place.dart';

/// Named routes for the app.
abstract final class Routes {
  Routes._();

  static const String splash = '/';
  static const String shell = '/home';
  static const String placeDetails = '/place';
  static const String chat = '/chat';
}

/// Central route table — keeps navigation declarative and testable.
abstract final class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.splash:
        return _page(settings, const OnboardingScreen());

      case Routes.shell:
        return _page(settings, const MainShell());

      case Routes.placeDetails:
        final Place? place = settings.arguments is Place
            ? settings.arguments as Place
            : null;
        if (place == null) {
          // Defensive: a bad argument must not crash the app.
          return _page(
            settings,
            const Scaffold(body: Center(child: Text('Place not found'))),
          );
        }
        return _page(settings, PlaceDetailsScreen(place: place));

      case Routes.chat:
        final Place? place = settings.arguments is Place
            ? settings.arguments as Place
            : null;
        return _page(settings, ChatScreen(place: place));

      default:
        return _page(
          settings,
          Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Page not found'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pushReplacementNamed(Routes.shell),
                      child: const Text('Go to Explore'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    }
  }

  static MaterialPageRoute<dynamic> _page(
    RouteSettings settings,
    Widget child,
  ) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (BuildContext context) => child,
    );
  }
}

/// Convenience helper so screens do not import Material for a single call.
void goToPlace(BuildContext context, Place place) {
  Navigator.of(context).pushNamed(Routes.placeDetails, arguments: place);
}

void goToChat(BuildContext context, {Place? place}) {
  Navigator.of(context).pushNamed(Routes.chat, arguments: place);
}
