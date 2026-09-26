import 'package:flutter_test/flutter_test.dart';
import 'package:localiq/features/driver/domain/driver_trip.dart';
import 'package:localiq/features/guides/domain/guide_onboarding.dart';
import 'package:localiq/features/onboarding/domain/onboarding.dart';

/// The backend ships snake_case; the app's `JsonMapX.pick` resolves camelCase.
/// These pin the contract for the new models.
void main() {
  group('DriverTrip', () {
    final json = <String, dynamic>{
      'id': 7,
      'booking_ref': 'DEMO0001',
      'status': 'confirmed',
      'allowed_transitions': ['in_progress', 'cancelled'],
      'date': '2026-09-27',
      'start_time': '10:00',
      'hours': 3,
      'group_size': 2,
      'guest_name': 'Demo Guest',
      'package_title': 'South Mumbai Walk',
      'guide_id': 1,
      'pickup': {'lat': 19.05, 'lng': 72.83, 'label': 'Pickup', 'address': 'Bandra'},
      'drop': {'lat': 18.90, 'lng': 72.81, 'label': 'Drop-off'},
      'stops': [
        {
          'sequence': 1,
          'name': 'Dadar Market',
          'lat': 19.01,
          'lng': 72.84,
          'duration_min': 40,
          'travel_time_min': 12,
          'segment_type': 'experience',
        },
      ],
      'route': [
        {'lat': 19.05, 'lng': 72.83},
        {'lat': 19.01, 'lng': 72.84},
      ],
      'distance_km': 12.4,
      'duration_min': 41,
      'route_source': 'google_routes',
      'driver_location': {'lat': 19.04, 'lng': 72.83, 'label': 'Driver'},
      'remaining': {'distance_km': 8.2, 'duration_min': 22},
    };

    test('parses the snake_case payload', () {
      final trip = DriverTrip.fromJson(json);
      expect(trip.id, 7);
      expect(trip.bookingRef, 'DEMO0001');
      expect(trip.packageTitle, 'South Mumbai Walk');
      expect(trip.pickup?.address, 'Bandra');
      expect(trip.drop?.lat, 18.90);
      expect(trip.stops.single.name, 'Dadar Market');
      expect(trip.stops.single.travelTimeMin, 12);
      expect(trip.route.length, 2);
      expect(trip.distanceKm, 12.4);
      expect(trip.routeSource, 'google_routes');
      expect(trip.driverLocation?.lat, 19.04);
      expect(trip.remaining?.durationMin, 22);
    });

    test('drives the primary action from allowed_transitions', () {
      final trip = DriverTrip.fromJson(json);
      expect(trip.can('in_progress'), isTrue);
      expect(trip.can('completed'), isFalse);
      expect(trip.primaryAction, 'in_progress');
      expect(trip.primaryActionLabel, 'Start trip');
      expect(trip.isInProgress, isFalse);
    });

    test('TripRemaining renders a compact label', () {
      const remaining = TripRemaining(distanceKm: 8.2, durationMin: 22);
      expect(remaining.label, '22 min · 8.2 km left');
    });
  });

  group('OnboardingStep', () {
    test('parses options, multi and the taste snapshot', () {
      final step = OnboardingStep.fromJson({
        'session_id': 3,
        'status': 'completed',
        'step': 7,
        'total_steps': 7,
        'progress': 1.0,
        'ack': 'Splendid.',
        'prompt': null,
        'options': <String>[],
        'multi': false,
        'free_text': false,
        'done': true,
        'completed': true,
        'taste': {
          'likes': ['cafe', 'street_food'],
          'dislikes': ['nightlife'],
          'text': 'You lean toward cafe, street food.',
          'vector': {'cafe': 1.2, 'nightlife': -1.4},
        },
      });
      expect(step.sessionId, 3);
      expect(step.done, isTrue);
      expect(step.completed, isTrue);
      expect(step.taste?.likes, ['cafe', 'street_food']);
      expect(step.taste?.dislikes, ['nightlife']);
      expect(step.taste?.vector['nightlife'], -1.4);
      expect(step.taste?.tagCount, 2);
    });

    test('a mid-conversation step exposes quick replies', () {
      final step = OnboardingStep.fromJson({
        'session_id': 1,
        'step': 2,
        'total_steps': 7,
        'progress': 0.28,
        'prompt': 'What should be on the table?',
        'options': ['Street food', 'Fine dining'],
        'multi': true,
      });
      expect(step.done, isFalse);
      expect(step.multi, isTrue);
      expect(step.options, ['Street food', 'Fine dining']);
    });
  });

  group('GuideOnboardingStatus', () {
    test('reports submission readiness and verification state', () {
      final status = GuideOnboardingStatus.fromJson({
        'guide_id': 4,
        'state': 'id_uploaded',
        'verification_status': 'pending',
        'verification_tier': 'standard',
        'has_driver_license': true,
        'has_guide_license': true,
        'can_submit': true,
        'areas': ['Bandra'],
        'niches': ['street_food'],
      });
      expect(status.started, isTrue);
      expect(status.isPending, isTrue);
      expect(status.verificationLabel, 'Under review');
      expect(status.canSubmit, isTrue);
      expect(status.areas, ['Bandra']);
      expect(status.niches, ['street_food']);
    });

    test('a fresh guide is not started', () {
      const status = GuideOnboardingStatus();
      expect(status.started, isFalse);
      expect(status.verificationLabel, 'Not started');
      expect(status.requiredDocuments, ['driver_license', 'guide_license']);
    });
  });
}
