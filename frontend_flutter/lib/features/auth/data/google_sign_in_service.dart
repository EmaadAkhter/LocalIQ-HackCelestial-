/// Google Sign-In, wrapped so every auth screen shares one flow.
///
/// The plugin needs an explicit client id. On Android the **web** client id is
/// passed as `serverClientId`, which makes Google issue an idToken whose
/// audience is the web client — the audience the backend validates against
/// `GOOGLE_OAUTH_CLIENT_ID`. Passing the Android client id instead yields a
/// token the backend rejects.
library;

import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/environment.dart';
import '../../../core/error/app_exception.dart';

class GoogleSignInService {
  GoogleSignInService({GoogleSignIn? plugin})
      : _plugin = plugin ?? GoogleSignIn.instance;

  final GoogleSignIn _plugin;

  /// `initialize` may only be called once per process.
  bool _ready = false;

  /// True when the build supplied a client id.
  bool get isConfigured => Environment.fromEnvironment.hasGoogleSignIn;

  /// Returns a Google idToken for the backend to verify.
  ///
  /// Throws [ConfigurationException] when the build has no client id, when the
  /// user dismisses the sheet, or when Google returns no idToken.
  Future<String> idToken() async {
    final clientId = Environment.fromEnvironment.googleServerClientId?.trim();
    if (clientId == null || clientId.isEmpty) {
      throw const ConfigurationException(
        'Google sign-in is not configured for this build. Rebuild with '
        '--dart-define=LOCALIQ_GOOGLE_SERVER_CLIENT_ID=<web client id>.',
      );
    }

    if (!_ready) {
      await _plugin.initialize(serverClientId: clientId);
      _ready = true;
    }

    final GoogleSignInAccount account = await _plugin.authenticate();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw const ConfigurationException('Google did not return an ID token.');
    }
    return token;
  }
}
