/// Contract tests for the remote repositories.
///
/// These exist because the app and backend drifted apart once already: the
/// repositories were only ever exercised against the bundled offline dataset,
/// so a shape change on the server went unnoticed until the demo. Every fixture
/// below is a real response captured from the running backend — if the backend
/// renames a field, these fail.
///
/// A loopback `HttpServer` is used rather than a mocked `HttpClient`: the
/// transport, the JSON decoding and the repository mapping are all exercised,
/// and no dependency is added. `HttpOverrides` is cleared first because
/// `flutter_test` installs one that answers every request with a 400.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localiq/core/network/json_api_client.dart';
import 'package:localiq/features/context/data/remote_context_repository.dart';
import 'package:localiq/features/places/data/remote_place_repository.dart';
import 'package:localiq/features/context/domain/context_models.dart';
import 'package:localiq/features/auth/data/remote_auth_service.dart';
import 'package:localiq/features/auth/domain/auth_service.dart';
import 'package:localiq/features/places/domain/place_repository.dart';

/// One real `GET /places` row, captured from the tunnel.
const Map<String, dynamic> _place = {
  'id': '15',
  'name': 'Banganga & Walkeshwar Walk',
  'category': 'culture',
  'address': 'Walkeshwar, Mumbai',
  'area': 'Walkeshwar',
  'centre': {'latitude': 18.9451, 'longitude': 72.7922},
  'heroImageUrl':
      'https://localiq.tavesglobal.com/static/images/banganga-walkeshwar-walk.jpg',
  'imageUrls': [
    'https://localiq.tavesglobal.com/static/images/banganga-walkeshwar-walk.jpg',
  ],
  'openingHours': {
    'weekly': {
      '1': '06:00-19:00',
      '2': '06:00-19:00',
      '3': '06:00-19:00',
      '4': '06:00-19:00',
      '5': '06:00-19:00',
      '6': '06:00-19:00',
      '7': '06:00-19:00',
    },
  },
  'accessibility': {
    'stepFree': true,
    'wheelchairAccessible': true,
    'restrooms': true,
    'seatingAvailable': true,
    'maxWalkingMinutes': 15,
  },
  'rating': 4.7,
  'reviewCount': 416,
  'priceLevel': 1,
  'typicalSpend': 150,
  'crowdLevel': 'moderate',
  'indoor': false,
  'localFavourite': true,
  'bookingRequired': false,
  'phone': null,
  'website': null,
  'summary': 'Ancient tank, Banganga, and Walkeshwar temples in Malabar Hill.',
};

/// One real `GET /context/live` payload.
const Map<String, dynamic> _liveContext = {
  'weather': {
    'temperatureC': 26.3,
    'condition': 'cloudy',
    'apparentTemperatureC': 31.7,
    'humidity': 86,
    'precipitationChance': 29,
    'windKph': 3.7,
    'uvIndex': 7.4,
    'observedAt': '2026-09-26T22:01:27.978780+00:00',
    'sunrise': '2026-09-27T06:28',
    'sunset': '2026-09-27T18:30',
  },
  'traffic': {
    'level': 'light',
    'speedMultiplier': 0.95,
    'updatedAt': '2026-09-27T03:31:27.978930+05:30',
  },
};

void main() {
  late HttpServer server;
  late JsonApiClient client;
  late List<HttpRequest> seen;
  var placeCalls = 0;

  setUpAll(() {
    // flutter_test blocks real sockets by default; these tests need them.
    HttpOverrides.global = null;
  });

  setUp(() async {
    placeCalls = 0;
    seen = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    server.listen((request) async {
      seen.add(request);
      final path = request.uri.path;
      Object? body;

      switch (path) {
        case '/api/v1/places':
          // Return a *full* page the first time, then an empty one. A full page
          // is what forces the repository to request the next offset; a short
          // page would end paging immediately and hide a regression.
          final requested =
              int.tryParse(request.uri.queryParameters['limit'] ?? '100') ?? 100;
          body = placeCalls++ == 0
              ? List<Object>.filled(requested.clamp(1, 100), _place)
              : <Object>[];
        case '/api/v1/context/live':
          body = _liveContext;
        case '/api/v1/traffic':
          body = _liveContext['traffic'];
        case '/api/v1/auth/login':
          body = {
            'access_token': 'access-token-123',
            'refresh_token': 'refresh-token-456',
            'expires_in': 3600,
            'user': {
              'id': 7,
              'name': 'Contract Tester',
              'email': 'contract@localiq.test',
              'provider': 'email',
              'tier': 'free',
              'home_city': 'Mumbai',
              'is_anonymous': false,
              'email_verified': true,
            },
          };
        default:
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'detail': 'no fixture for $path'}));
          await request.response.close();
          return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });

    client = JsonApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
      timeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  group('RemotePlaceRepository', () {
    test('parses a real /places row into a Place', () async {
      final places = await RemotePlaceRepository(client).search(
        const PlaceQuery(limit: 1),
      );

      expect(places, hasLength(1));
      final place = places.single;
      expect(place.id, '15');
      expect(place.name, 'Banganga & Walkeshwar Walk');
      expect(place.area, 'Walkeshwar');
      expect(place.rating, 4.7);
      expect(place.typicalSpend, 150);
      expect(place.localFavourite, isTrue);
      expect(place.centre.latitude, closeTo(18.9451, 1e-6));
      expect(place.centre.longitude, closeTo(72.7922, 1e-6));
      expect(place.heroImageUrl, contains('/static/images/'));
      expect(place.imageUrls, hasLength(1));
    });

    test('walks offset pages when the query is unbounded', () async {
      // `limit: 0` means "the whole catalogue": the repository walks 100-row
      // pages until one comes back short. The server returns a full first page,
      // so a second request is required.
      final places = await RemotePlaceRepository(client).search(
        const PlaceQuery(limit: 0),
      );
      expect(places, hasLength(100));
      expect(placeCalls, 2, reason: 'full page then empty page');

      final offsets = seen
          .where((r) => r.uri.path == '/api/v1/places')
          .map((r) => r.uri.queryParameters['offset'])
          .toList();
      expect(offsets, ['0', '100']);
    });

    test('stops as soon as a bounded limit is satisfied', () async {
      // A limit of 3 is filled by the first page, so there is no second call.
      final places = await RemotePlaceRepository(client).search(
        const PlaceQuery(limit: 3),
      );
      expect(places, hasLength(3));
      expect(placeCalls, 1);
    });

    test('sends the place query parameters the backend expects', () async {
      await RemotePlaceRepository(client).search(
        const PlaceQuery(limit: 1, text: 'heritage'),
      );
      final query = seen.first.uri.queryParameters;
      expect(query['limit'], '1');
      expect(query['offset'], '0');
      expect(query['text'], 'heritage');
    });
  });

  group('RemoteContextRepository', () {
    test('parses /context/live into weather and traffic', () async {
      final context = await RemoteContextRepository(client).liveContext(
        const GeoPoint(latitude: 19.06, longitude: 72.83),
      );

      expect(context.weather.temperatureC, closeTo(26.3, 1e-6));
      expect(context.weather.condition, WeatherCondition.cloudy);
      expect(context.weather.precipitationChance, 29);
      expect(context.weather.windKph, closeTo(3.7, 1e-6));
      expect(context.weather.uvIndex, closeTo(7.4, 1e-6));
      expect(context.traffic.level, TrafficLevel.light);
      expect(context.traffic.speedMultiplier, closeTo(0.95, 1e-6));
    });
  });

  group('RemoteAuthService', () {
    test('decodes the token envelope the backend actually returns', () async {
      final service = RemoteAuthService(client);
      addTearDown(service.dispose);

      final session = await service.signInWithPassword(
        const AuthCredentials(
          email: 'contract@localiq.test',
          password: 'Secret123',
        ),
      );

      // snake_case on the wire, camelCase in the app (JsonMapX bridges them).
      expect(session.accessToken, 'access-token-123');
      expect(session.refreshToken, 'refresh-token-456');
      expect(session.user.email, 'contract@localiq.test');
      expect(session.expiresAt.isAfter(DateTime.now()), isTrue);
    });

    test('attaches the bearer token when a token provider is set', () async {
      final authed = JsonApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
        timeout: const Duration(seconds: 5),
        tokenProvider: () => 'session-token',
      );
      final service = RemoteAuthService(authed);
      addTearDown(service.dispose);

      await service.signInWithPassword(
        const AuthCredentials(email: 'a@b.test', password: 'Secret123'),
      );

      expect(seen.last.headers.value(HttpHeaders.authorizationHeader),
          'Bearer session-token');
    });
  });
}
