/// Persistent token store backed by `shared_preferences`.
///
/// Keeps the user logged in across cold starts. The session is automatically
/// invalidated if the user has been inactive for [_inactivityThreshold] — i.e.
/// they never opened the app for that entire period.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_service.dart';
import 'remote_auth_service.dart';

class SharedPrefsAuthTokenStore implements AuthTokenStore {
  static const _keyRefreshToken = 'localiq.auth.refresh_token';
  static const _keyLastActive = 'localiq.auth.last_active_ms';

  /// 7 days of inactivity → force re-login.
  static const _inactivityThreshold = Duration(days: 7);

  SharedPrefsAuthTokenStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPrefsAuthTokenStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsAuthTokenStore(prefs);
  }

  @override
  Future<void> write(AuthSession session) async {
    if (session.refreshToken.isNotEmpty) {
      await _prefs.setString(_keyRefreshToken, session.refreshToken);
    }
    // Stamp last-active on every successful write (= login or token refresh).
    await _prefs.setInt(_keyLastActive, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Future<String?> readRefreshToken() async {
    final lastActiveMs = _prefs.getInt(_keyLastActive);
    if (lastActiveMs == null) return null;

    final lastActive = DateTime.fromMillisecondsSinceEpoch(lastActiveMs);
    if (DateTime.now().difference(lastActive) >= _inactivityThreshold) {
      // User was away too long — expire the session.
      await clear();
      return null;
    }

    return _prefs.getString(_keyRefreshToken);
  }

  /// Call this every time the user actively opens the app so the inactivity
  /// clock resets. Safe to call even when no session is stored.
  Future<void> touchActivity() async {
    if (_prefs.containsKey(_keyRefreshToken)) {
      await _prefs.setInt(_keyLastActive, DateTime.now().millisecondsSinceEpoch);
    }
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_keyRefreshToken);
    await _prefs.remove(_keyLastActive);
  }
}
