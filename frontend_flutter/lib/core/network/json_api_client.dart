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

  /// POST JSON. [timeout] overrides the client default for slow endpoints
  /// (the LLM-backed agent can legitimately take a minute).
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    Duration? timeout,
  }) {
    return _send(() async {
      final request = await _client.postUrl(_uri(path, query));
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(body ?? const <String, dynamic>{})));
      return request.close();
    }, timeout);
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

  Future<dynamic> _send(
    Future<HttpClientResponse> Function() run, [
    Duration? override,
  ]) async {
    try {
      final response = await run().timeout(override ?? timeout);
      final body = await utf8.decoder.bind(response).join();
      final decoded = body.isEmpty ? null : jsonDecode(body);

      switch (response.statusCode) {
        case >= 200 && < 300:
          return decoded;
        case 401 || 403:
          throw UnauthorizedException(
            serverMessage(decoded, 'You are not authorised for this action.'),
          );
        case 404:
          throw NotFoundException(
            serverMessage(decoded, 'The requested resource was not found.'),
          );
        case 422:
          throw ServerException(
            serverMessage(decoded, 'The request was rejected. Check your input.'),
            code: '422',
            cause: decoded,
          );
        default:
          throw ServerException(
            serverMessage(decoded, 'Request failed (${response.statusCode}).'),
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

  /// Extracts the most useful message from the backend's unified error shape:
  /// `{"error", "message", "details": [{"loc": [...], "msg": ...}]}`.
  ///
  /// Field-level validation messages win, then the top-level message/detail, so
  /// a 422 reads "password: String should have at least 8 characters" instead of
  /// a bare status code. Pure function, exposed for tests.
  static String serverMessage(dynamic decoded, String fallback) {
    if (decoded is! Map) return fallback;
    final details = decoded['details'];
    if (details is List && details.isNotEmpty && details.first is Map) {
      final first = (details.first as Map).cast<String, dynamic>();
      final msg = first['msg'];
      if (msg is String && msg.trim().isNotEmpty) {
        final field = _fieldName(first['loc']);
        return field == null ? msg.trim() : '$field: ${msg.trim()}';
      }
    }
    for (final key in const ['message', 'detail']) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return fallback;
  }

  /// Last meaningful segment of a validation `loc` (skips `body` / `query`).
  static String? _fieldName(dynamic loc) {
    if (loc is! List) return null;
    for (var i = loc.length - 1; i >= 0; i--) {
      final segment = loc[i];
      if (segment is String && segment != 'body' && segment != 'query') {
        return segment;
      }
    }
    return null;
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
