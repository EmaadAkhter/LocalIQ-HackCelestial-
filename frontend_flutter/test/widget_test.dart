import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localiq/app/app.dart';
import 'package:localiq/app/app_state.dart';
import 'package:localiq/core/constants/app_constants.dart';
import 'package:localiq/models/place.dart';
import 'package:localiq/models/recommendation.dart';
import 'package:localiq/models/search_params.dart';
import 'package:localiq/services/mock_api_service.dart';
import 'package:provider/provider.dart';

/// Builds the app with a zero-latency service so tests stay fast/deterministic.
Widget _app({MockApiService? service}) {
  return LocalIQApp(
    api: service ?? MockApiService(latency: Duration.zero),
  );
}

/// Pumps the app and walks past onboarding so the bottom-nav shell is mounted.
Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
  // First two slides advance with "Next"; the last one says "Get Started".
  for (var i = 0; i < 3; i++) {
    final Finder next = find.text('Next');
    if (next.evaluate().isEmpty) break;
    await tester.tap(next);
    await tester.pumpAndSettle();
  }
  final Finder start = find.text('Get Started');
  if (start.evaluate().isNotEmpty) {
    await tester.tap(start);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    // Keep widget tests offline and free of platform image loading.
    AppConfig.enableRemoteImages = false;
  });

  group('feasibility engine', () {
    final MockApiService api = MockApiService(latency: Duration.zero);

    test('respects budget', () {
      final List<Recommendation> cheap = api.rank(
        const SearchParams(budgetInr: 300, timeHours: 6),
      );
      expect(cheap, isNotEmpty);
      expect(
        cheap.every((Recommendation r) => r.place.avgCost <= 300),
        isTrue,
      );
    });

    test('respects time window', () {
      // A one-hour window can legitimately admit nothing; the invariant is what
      // matters: everything returned must fit the window.
      for (final double hours in <double>[1, 2, 4]) {
        final List<Recommendation> results = api.rank(
          SearchParams(budgetInr: 5000, timeHours: hours),
        );
        expect(
          results.every(
            (Recommendation r) => r.totalMinutes <= (hours * 60).round(),
          ),
          isTrue,
          reason: 'result exceeded ${hours}h window',
        );
      }
      // And a generous window does produce results.
      expect(
        api.rank(const SearchParams(budgetInr: 5000, timeHours: 6)),
        isNotEmpty,
      );
    });

    test('filters inaccessible places when required', () {
      final List<Recommendation> accessible = api.rank(
        const SearchParams(
          budgetInr: 5000,
          timeHours: 12,
          accessibility: true,
        ),
      );
      expect(accessible, isNotEmpty);
      expect(
        accessible.every((Recommendation r) => r.place.isWheelchairFriendly),
        isTrue,
      );
    });

    test('ranks matching interests first and stays deterministic', () {
      final List<Recommendation> first = api.rank(
        const SearchParams(
          budgetInr: 5000,
          timeHours: 12,
          interests: <PlaceCategory>{PlaceCategory.food},
        ),
      );
      final List<Recommendation> second = api.rank(
        const SearchParams(
          budgetInr: 5000,
          timeHours: 12,
          interests: <PlaceCategory>{PlaceCategory.food},
        ),
      );
      expect(first.first.place.category, PlaceCategory.food);
      expect(
        first.map((Recommendation r) => r.place.id).toList(),
        second.map((Recommendation r) => r.place.id).toList(),
      );
    });

    test('every recommendation explains itself', () {
      final List<Recommendation> all = api.rank(
        const SearchParams(budgetInr: 5000, timeHours: 12),
      );
      expect(all, isNotEmpty);
      for (final Recommendation r in all) {
        expect(r.whyItFits, isNotEmpty);
        expect(r.reasons, isNotEmpty);
      }
    });
  });

  group('itinerary maths', () {
    test('totals add up and start times are labelled', () async {
      final MockApiService api = MockApiService(latency: Duration.zero);
      final SearchParams params = const SearchParams(
        budgetInr: 2000,
        timeHours: 6,
      );
      final List<Recommendation> ranked = api.rank(params);
      final plan = await api.buildItinerary(
        recommendations: ranked,
        params: params,
      );
      expect(plan.stopCount, greaterThan(0));
      expect(plan.totalMinutes, plan.travelMinutes + plan.visitMinutes);
      expect(plan.totalCost, greaterThan(0));
      expect(plan.stops.first.startTimeLabel, isNotNull);
    });
  });

  group('AppState', () {
    testWidgets('search populates recommendations and marks them visited',
        (WidgetTester tester) async {
      await _pumpShell(tester);

      final BuildContext context = tester.element(find.byType(NavigationBar));
      final AppState state = Provider.of<AppState>(context, listen: false);
      expect(state.hasSearched, isFalse);

      // Mirrors HomeScreen: switch to the results view, then search.
      state.showResults();
      await state.findExperiences();
      await tester.pumpAndSettle();

      expect(state.hasSearched, isTrue);
      expect(state.recommendations, isNotEmpty);
      expect(state.exploreIndex, 1);
      expect(find.text('Top Experiences for You'), findsOneWidget);
    });

    testWidgets('add to itinerary then remove', (WidgetTester tester) async {
      await _pumpShell(tester);

      final BuildContext context = tester.element(find.byType(NavigationBar));
      final AppState state = Provider.of<AppState>(context, listen: false);
      await state.findExperiences();
      await tester.pumpAndSettle();

      final String placeId = state.recommendations.first.place.id;
      state.addTopRecommendation();
      await tester.pumpAndSettle();
      expect(state.isInItinerary(placeId), isTrue);
      expect(state.itineraryStops.length, 1);

      state.removeFromItinerary(placeId);
      await tester.pumpAndSettle();
      expect(state.isInItinerary(placeId), isFalse);
    });

    testWidgets('builds and saves a plan', (WidgetTester tester) async {
      await _pumpShell(tester);

      final BuildContext context = tester.element(find.byType(NavigationBar));
      final AppState state = Provider.of<AppState>(context, listen: false);
      await state.findExperiences();
      await tester.pumpAndSettle();

      state.addTopRecommendation();
      await state.buildPlan();
      await tester.pumpAndSettle();

      final plan = state.plan;
      expect(plan, isNotNull);
      expect(plan!.stopCount, 1);
      expect(plan.isSaved, isFalse);

      state.savePlan();
      await tester.pumpAndSettle();
      expect(state.plan!.isSaved, isTrue);
    });
  });

  group('navigation', () {
    testWidgets('onboarding reaches the shell with all four tabs',
        (WidgetTester tester) async {
      await _pumpShell(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      for (final String label in <String>[
        'Explore',
        'Map',
        'Itinerary',
        'Profile',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('bottom navigation switches tabs', (WidgetTester tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      // No search yet, so the map shows the empty hint.
      expect(find.textContaining('Find experiences'), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Guest mode'), findsOneWidget);

      await tester.tap(find.text('Itinerary'));
      await tester.pumpAndSettle();
      expect(find.text('No plan yet'), findsOneWidget);

      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      // The Home form is long; assert on content that is built without scrolling.
      expect(find.text('What would you like to do?'), findsOneWidget);

      // The primary CTA lives at the bottom of the scroll view.
      await tester.scrollUntilVisible(
        find.text('Find Experiences'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Find Experiences'), findsOneWidget);
    });

    testWidgets('guest button also reaches the shell',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'll explore as Guest"));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}
