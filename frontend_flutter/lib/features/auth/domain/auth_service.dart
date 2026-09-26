import '../../context/domain/discovery_context.dart';
import 'user.dart';

export 'user.dart';

class AuthCredentials {
  const AuthCredentials({required this.email, required this.password});

  final String email;
  final String password;
}

class SignUpRequest {
  const SignUpRequest({
    required this.name,
    required this.email,
    required this.password,
    this.termsAccepted = false,
  });

  final String name;
  final String email;
  final String password;
  final bool termsAccepted;
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final LocalIqUser user;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeToExpiry => expiresAt.difference(DateTime.now());
}

/// Authentication contract. `AuthApi` implements this over the backend;
/// `OfflineAuthService` provides a local implementation with identical
/// semantics so the app is fully usable without a server.
abstract interface class AuthService {
  /// Emits the current session, or null when signed out.
  Stream<AuthSession?> authStateChanges();

  AuthSession? get currentSession;

  LocalIqUser? get currentUser;

  /// Restores a persisted session on cold start.
  Future<AuthSession?> restore();

  Future<AuthSession> signInWithPassword(AuthCredentials credentials);

  Future<AuthSession> signUp(SignUpRequest request);

  Future<AuthSession> signInWithGoogle({String? idToken});

  /// Anonymous access: full product, nothing persisted to an account.
  Future<AuthSession> continueAsGuest();

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);

  /// Called after sign-in so per-account state (saved, itinerary) can load.
  Future<void> applyContext(DiscoveryContext context);

  /// Ready-to-use constraint presets surfaced on the sign-in screens.
  List<({String label, String description})> valuePropositions();
}
