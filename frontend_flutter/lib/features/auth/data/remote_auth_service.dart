import 'dart:async';

import '../../../core/error/app_exception.dart';
import '../../../core/network/json_api_client.dart';
import '../../../core/utils/json_map_x.dart';
import '../../context/domain/discovery_context.dart';
import '../domain/auth_service.dart';

/// REST implementation of [AuthService].
///
/// Endpoints expected from the backend:
///   POST /auth/login           { email, password }
///   POST /auth/register        { name, email, password, terms_accepted }
///   POST /auth/google          { id_token }
///   POST /auth/guest
///   POST /auth/forgot-password { email }
///   POST /auth/refresh         { refresh_token }
///
/// Tokens are held in memory here. A production build should persist the
/// refresh token with `flutter_secure_storage` and call /auth/refresh on
/// cold start; `restore()` is the seam for that.
class RemoteAuthService implements AuthService {
  RemoteAuthService(this._client, {AuthTokenStore? tokenStore})
      : _tokenStore = tokenStore ?? InMemoryAuthTokenStore();

  final JsonApiClient _client;

  final _controller = StreamController<AuthSession?>.broadcast();
  AuthSession? _session;

  /// Token persistence seam. Defaults to in-memory; a production build
  /// injects a `flutter_secure_storage` implementation.
  final AuthTokenStore _tokenStore;

  @override
  Stream<AuthSession?> authStateChanges() => _controller.stream;

  @override
  AuthSession? get currentSession => _session;

  @override
  LocalIqUser? get currentUser => _session?.user;

  @override
  Future<AuthSession?> restore() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final data = await _client.post(
        '/auth/refresh',
        body: {'refresh_token': refreshToken},
      );
      final session = _decode((data as Map).cast<String, dynamic>());
      await _tokenStore.write(session);
      _emit(session);
      return session;
    } on AppException {
      await _tokenStore.clear();
      return null;
    }
  }

  @override
  Future<AuthSession> signInWithPassword(AuthCredentials credentials) {
    return _post('/auth/login', {
      'email': credentials.email,
      'password': credentials.password,
    });
  }

  @override
  Future<AuthSession> signUp(SignUpRequest request) {
    return _post('/auth/register', {
      'name': request.name,
      'email': request.email,
      'password': request.password,
      'terms_accepted': request.termsAccepted,
    });
  }

  @override
  Future<AuthSession> signInWithGoogle({String? idToken}) {
    if (idToken == null || idToken.isEmpty) {
      throw const ConfigurationException(
        'Google sign-in requires an ID token from google_sign_in.',
      );
    }
    return _post('/auth/google', {'id_token': idToken});
  }

  @override
  Future<AuthSession> continueAsGuest() => _post('/auth/guest', const {});

  @override
  Future<void> signOut() async {
    await _tokenStore.clear();
    _emit(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _client.post('/auth/forgot-password', body: {'email': email});
  }

  @override
  Future<void> applyContext(DiscoveryContext context) async {
    // The active context lives client-side. This seam exists so the backend
    // can mirror it for cross-device continuity (PUT /users/me/context).
  }

  @override
  List<({String label, String description})> valuePropositions() =>
      LocalAuthValueProps.items;

  Future<AuthSession> _post(String path, Map<String, dynamic> body) async {
    final data = await _client.post(path, body: body);
    if (data is! Map) throw const ParseException('Unexpected auth payload.');
    final session = _decode(data.cast<String, dynamic>());
    await _tokenStore.write(session);
    _emit(session);
    return session;
  }

  AuthSession _decode(Map<String, dynamic> json) {
    final user = LocalIqUser.fromJson(json.mapOrEmpty('user'));
    final expiresIn = json.intValue('expiresIn', fallback: 3600);
    return AuthSession(
      user: user,
      accessToken: json.string('accessToken') ?? '',
      refreshToken: json.string('refreshToken') ?? '',
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  void _emit(AuthSession? session) {
    _session = session;
    if (!_controller.isClosed) _controller.add(session);
  }

  void dispose() => _controller.close();
}

/// Persistence seam for tokens. The default is in-memory, which is correct for
/// development and for web; swap for a secure-storage implementation in a
/// production build.
abstract interface class AuthTokenStore {
  Future<void> write(AuthSession session);
  Future<String?> readRefreshToken();
  Future<void> clear();
}

class InMemoryAuthTokenStore implements AuthTokenStore {
  String? _refreshToken;

  @override
  Future<void> write(AuthSession session) async {
    _refreshToken = session.refreshToken.isEmpty ? null : session.refreshToken;
  }

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clear() async => _refreshToken = null;
}

/// Marketing points rendered on the auth screens.
abstract final class LocalAuthValueProps {
  static const items = <({String label, String description})>[
    (
      label: 'Time-aware',
      description: 'Every option is checked against the window you actually have.',
    ),
    (
      label: 'Budget-fit',
      description: 'Nothing over your spend appears above the fold.',
    ),
    (
      label: 'Weather-aware',
      description: 'Rain reranks the list toward covered places automatically.',
    ),
    (
      label: 'Plan-ready',
      description: 'Save anything you can finish into a timed itinerary.',
    ),
  ];
}
