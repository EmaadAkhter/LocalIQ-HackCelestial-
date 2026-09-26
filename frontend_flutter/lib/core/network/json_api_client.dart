import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/providers.dart';
import '../error/app_exception.dart';

/// Minimal, dependency-free JSON transport used by the REST repositories.
///
/// Swapping this for `dio`/`http` later is a one-file change: repositories
/// only depend on [JsonApiClient], never on `dart:io` directly.
class JsonApiClient {
  JsonApiClient({
    required this.baseUrl,
    required this.timeout,
    this.apiKey,
    this.tokenProvider,
    HttpClient? httpClient,
  }) : _injected = httpClient;

  final String baseUrl;
  final Duration timeout;
  final String? apiKey;

  /// Supplies the signed-in user's access token per request. Takes precedence
  /// over [apiKey] when it returns a value, so a session token always wins over
  /// the static first-party key.
  final String? Function()? tokenProvider;

  /// Injected for tests; created lazily otherwise.
  final HttpClient? _injected;

  HttpClient? _owned;
  HttpClient get _client => _injected ?? (_owned ??= HttpClient());

  void _applyHeaders(HttpClientRequest request, {bool json = true}) {
    if (json) request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('X-Client', 'localiq-flutter');
    final sessionToken = tokenProvider?.call();
    final bearer = (sessionToken != null && sessionToken.isNotEmpty)
        ? sessionToken
        : apiKey;
    if (bearer != null && bearer.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalized');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value != null) entry.key: '${entry.value}',
      },
    );
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    return _send(() async {
      final request = await _client.getUrl(_uri(path, query));
      _applyHeaders(request, json: false);
      return request.close();
    });
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) {
    return _send(() async {
      final request = await _client.postUrl(_uri(path, query));
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(body ?? const <String, dynamic>{})));
      return request.close();
    });
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return _send(() async {
      final request = await _client.patchUrl(_uri(path));
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(body ?? const <String, dynamic>{})));
      return request.close();
    });
  }

  Future<dynamic> delete(String path) {
    return _send(() async {
      final request = await _client.deleteUrl(_uri(path));
      _applyHeaders(request, json: false);
      return request.close();
    });
  }

  /// Multipart form upload (a single file plus optional text fields).
  ///
  /// `dart:io` only, so this lives beside the JSON verbs rather than in a
  /// repository; callers stay transport-agnostic.
  Future<dynamic> postMultipart(
    String path, {
    required String fileField,
    required List<int> bytes,
    required String filename,
    String? contentType,
    Map<String, String> fields = const {},
  }) {
    return _send(() async {
      final boundary =
          '----localiq${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
      final request = await _client.postUrl(_uri(path));
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('X-Client', 'localiq-flutter');
      final sessionToken = tokenProvider?.call();
      final bearer = (sessionToken != null && sessionToken.isNotEmpty)
          ? sessionToken
          : apiKey;
      if (bearer != null && bearer.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }

      final body = <int>[];
      void write(String text) => body.addAll(utf8.encode(text));

      for (final entry in fields.entries) {
        write('--$boundary\r\n');
        write('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n');
        write('${entry.value}\r\n');
      }
      write('--$boundary\r\n');
      write(
        'Content-Disposition: form-data; name="$fileField"; filename="$filename"\r\n',
      );
      write('Content-Type: ${contentType ?? 'application/octet-stream'}\r\n\r\n');
      body.addAll(bytes);
      write('\r\n--$boundary--\r\n');

      request.add(body);
      return request.close();
    });
  }

  Future<dynamic> _send(Future<HttpClientResponse> Function() run) async {
    try {
      final response = await run().timeout(timeout);
      final body = await utf8.decoder.bind(response).join();
      final decoded = body.isEmpty ? null : jsonDecode(body);

      switch (response.statusCode) {
        case >= 200 && < 300:
          return decoded;
        case 401 || 403:
          throw UnauthorizedException(
            decoded is Map && decoded['detail'] != null
                ? '${decoded['detail']}'
                : 'You are not authorised for this action.',
          );
        case 404:
          throw NotFoundException(
            decoded is Map && decoded['detail'] != null
                ? '${decoded['detail']}'
                : 'The requested resource was not found.',
          );
        default:
          throw ServerException(
            'Request failed (${response.statusCode}).',
            code: '$response.statusCode',
            cause: decoded,
          );
      }
    } on TimeoutException catch (e) {
      throw NetworkException('The request timed out.', cause: e);
    } on SocketException catch (e) {
      throw NetworkException(
        'No connection to LocalIQ. Check your network and try again.',
        cause: e,
      );
    } on FormatException catch (e) {
      throw ParseException('The server returned an unexpected response.', cause: e);
    }
  }

  /// Closes the underlying connection pool. Does nothing for an injected
  /// client, which the caller owns.
  void dispose() {
    if (_injected == null) _owned?.close(force: true);
  }
}

final jsonApiClientProvider = Provider<JsonApiClient>((ref) {
  final env = ref.watch(environmentProvider);
  final client = JsonApiClient(
    baseUrl: env.apiBaseUrl,
    timeout: env.requestTimeout,
    apiKey: env.apiKey,
  );
  ref.onDispose(client.dispose);
  return client;
}, name: 'localiq.jsonApiClient');
