import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:localiq/app/app.dart';

/// Every location the router can produce, including a path-parameter route.
const _routes = <String>[
  '/welcome',
  '/login',
  '/signup',
  '/forgot-password',
  '/explore',
  '/plan',
  '/saved',
  '/about',
  '/recommendations',
  '/what-if',
  '/assistant',
  '/profile',
  '/place/exp-irani-trail?place=exp-irani-trail',
];

/// One representative size per responsive breakpoint in `AppTheme`.
const _sizes = <String, Size>{
  'desktop': Size(1600, 1000),
  'laptop': Size(1280, 860),
  'tablet': Size(900, 1100),
  'tablet-sm': Size(768, 1024),
  'mobile': Size(400, 860),
  'mobile-sm': Size(320, 700),
};

/// Reads the live router from a context *below* the `Router` widget, which is
/// where go_router installs its inherited handle. Navigating through this
/// exercises the real stack rather than a test-only shortcut.
GoRouter _routerOf(WidgetTester tester) {
  return GoRouter.of(tester.element(find.byType(Overlay).first));
}

/// Pumps until the local data source and the entrance animations have settled.
/// The bundled repository simulates network latency, so a single `pump` is
/// not enough and leaves timers pending at teardown.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('every route renders cleanly at every breakpoint', () {
    for (final route in _routes) {
      for (final size in _sizes.entries) {
        testWidgets('$route @ ${size.key}', (tester) async {
          // Collect build/layout errors. Restored via addTearDown so a failure
          // part-way through cannot leak the override into the next test.
          final problems = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = problems.add;
          addTearDown(() => FlutterError.onError = previous);

          tester.view.physicalSize = size.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(const ProviderScope(child: LocalIqApp()));
          await _settle(tester);

          _routerOf(tester).go(route);
          await _settle(tester);

          expect(
            problems,
            isEmpty,
            reason: '$route @ ${size.key} reported: '
                '${problems.map((p) => p.exceptionAsString()).join(' ;; ')}',
          );
          // Guard against silently landing on the router error screen.
          expect(find.text('That page does not exist'), findsNothing);
        });
      }
    }
  });
}
