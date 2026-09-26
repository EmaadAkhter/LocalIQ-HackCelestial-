import 'dart:async';
import 'dart:math' as math;

import '../../../core/error/app_exception.dart';
import '../../context/domain/discovery_context.dart';
import '../domain/auth_service.dart';
import 'remote_auth_service.dart';

/// Offline implementation of [AuthService].
///
/// Credentials are validated locally so the auth screens behave exactly as
/// they will against the backend — including error copy — and a guest session
/// is always available with no network at all.
class LocalAuthService implements AuthService {
  LocalAuthService({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final _controller = StreamController<AuthSession?>.broadcast();
  AuthSession? _session;

  @override
  Stream<AuthSession?> authStateChanges() => _controller.stream;

  @override
  AuthSession? get currentSession => _session;

  @override
  LocalIqUser? get currentUser => _session?.user;

  @override
  Future<AuthSession?> restore() async => _session;

  @override
  Future<AuthSession> signInWithPassword(AuthCredentials credentials) async {
    await _networkDelay();
    final email = credentials.email.trim();
    if (!_isEmail(email)) {
      throw const ConfigurationException('Enter a valid email address.');
    }
    if (credentials.password.length < 4) {
      throw const ConfigurationException(
        'Password must be at least 4 characters.',
      );
    }
    return _emit(
      LocalIqUser(
        id: 'user-$email',
        displayName: _nameFromEmail(email),
        email: email,
        avatarUrl: null,
        provider: AuthProvider.email,
        tier: UserTier.free,
        homeCity: 'Mumbai',
        createdAt: _clock(),
      ),
      AuthProvider.email,
    );
  }

  @override
  Future<AuthSession> signUp(SignUpRequest request) async {
    await _networkDelay();
    final email = request.email.trim();
    if (request.name.trim().length < 2) {
      throw const ConfigurationException('Enter your full name.');
    }
    if (!_isEmail(email)) {
      throw const ConfigurationException('Enter a valid email address.');
    }
    if (request.password.length < 6) {
      throw const ConfigurationException(
        'Use at least 6 characters for your password.',
      );
    }
    if (!request.termsAccepted) {
      throw const ConfigurationException(
        'Please accept the terms to create an account.',
      );
    }
    return _emit(
      LocalIqUser(
        id: 'user-$email',
        displayName: request.name.trim(),
        email: email,
        avatarUrl: null,
        provider: AuthProvider.email,
        tier: UserTier.free,
        homeCity: 'Mumbai',
        createdAt: _clock(),
      ),
      AuthProvider.email,
    );
  }

  @override
  Future<AuthSession> signInWithGoogle({String? idToken}) async {
    await _networkDelay();
    return _emit(
      LocalIqUser(
        id: 'user-google',
        displayName: 'Aanya Shah',
        email: 'aanya.shah@gmail.com',
        avatarUrl: null,
        provider: AuthProvider.google,
        tier: UserTier.free,
        homeCity: 'Mumbai',
        createdAt: _clock(),
      ),
      AuthProvider.google,
    );
  }

  @override
  Future<AuthSession> continueAsGuest() async {
    await _networkDelay();
    return _emit(
      LocalIqUser(
        id: 'guest',
        displayName: 'Guest',
        email: null,
        avatarUrl: null,
        provider: AuthProvider.guest,
        tier: UserTier.guest,
        homeCity: 'Mumbai',
        createdAt: _clock(),
        isAnonymous: true,
      ),
      AuthProvider.guest,
    );
  }

  @override
  Future<void> signOut() async {
    _session = null;
    if (!_controller.isClosed) _controller.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _networkDelay();
    if (!_isEmail(email.trim())) {
      throw const ConfigurationException('Enter a valid email address.');
    }
  }

  @override
  Future<void> applyContext(DiscoveryContext context) async {}

  @override
  List<({String label, String description})> valuePropositions() =>
      LocalAuthValueProps.items;

  Future<AuthSession> _emit(LocalIqUser user, AuthProvider provider) async {
    final session = AuthSession(
      user: user,
      accessToken: 'local-${math.Random().nextInt(1 << 32)}',
      refreshToken: 'local-refresh-${user.id}',
      expiresAt: _clock().add(const Duration(days: 7)),
    );
    _session = session;
    if (!_controller.isClosed) _controller.add(session);
    return session;
  }

  static bool _isEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  static String _nameFromEmail(String email) {
    final local = email.split('@').first;
    final parts = local
        .split(RegExp(r'[._-]'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Traveller';
    return parts
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  /// Keeps the async surface honest without a real socket.
  Future<void> _networkDelay() =>
      Future<void>.delayed(const Duration(milliseconds: 260));

  void dispose() => _controller.close();
}
