/// Holds the signed-in user's access token for [JsonApiClient] to attach to
/// requests.
///
/// The dependency graph is intentionally one-way: the API client *reads* the
/// token, the auth service *writes* it. Neither depends on the other, so there
/// is no provider cycle (the client is built before the auth service exists).
class AuthTokenHolder {
  String? _accessToken;

  String? get accessToken => _accessToken;

  bool get hasToken => (_accessToken ?? '').isNotEmpty;

  void set(String? token) {
    _accessToken = (token ?? '').isEmpty ? null : token;
  }

  void clear() => _accessToken = null;
}
