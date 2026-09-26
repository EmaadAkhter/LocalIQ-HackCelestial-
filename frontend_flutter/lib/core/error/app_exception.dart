import 'package:flutter/foundation.dart';

/// Base failure type. Repositories translate transport, parsing and domain
/// problems into one of these so the UI never has to know about HTTP.
@immutable
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.code});

  final String message;
  final Object? cause;
  final String? code;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause, super.code});
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = 'Your session has expired.']);
}

class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

class ServerException extends AppException {
  const ServerException(super.message, {super.cause, super.code});
}

class ParseException extends AppException {
  const ParseException(super.message, {super.cause});
}

class ConfigurationException extends AppException {
  const ConfigurationException(super.message);
}

class CacheException extends AppException {
  const CacheException(super.message, {super.cause});
}

/// Normalises any thrown object into an [AppException].
AppException toAppException(Object error) {
  if (error is AppException) return error;
  return UnknownException(error.toString(), cause: error);
}

/// Concrete fallback for errors that arrive untyped from a dependency.
class UnknownException extends AppException {
  const UnknownException(super.message, {super.cause});
}
