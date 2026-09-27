import 'package:flutter_test/flutter_test.dart';
import 'package:localiq/core/network/json_api_client.dart';
import 'package:localiq/features/auth/domain/auth_service.dart';

/// Locks the client-side password policy to the backend's `RegisterRequest`
/// rule (min 8, upper + lower + digit) so the app never sends a password the
/// server answers with a 422.
void main() {
  group('passwordProblem', () {
    test('accepts a password meeting the backend policy', () {
      expect(passwordProblem('Secret123'), isNull);
      expect(passwordProblem('aB3defgh'), isNull);
    });

    test('rejects fewer than 8 characters', () {
      expect(passwordProblem('Abc123'), 'Password must be at least 8 characters');
      expect(passwordProblem(''), 'Password must be at least 8 characters');
      expect(passwordProblem(null), 'Password must be at least 8 characters');
    });

    test('rejects a missing uppercase letter', () {
      expect(
        passwordProblem('secret123'),
        'Password must include an uppercase letter',
      );
    });

    test('rejects a missing lowercase letter', () {
      expect(
        passwordProblem('SECRET123'),
        'Password must include a lowercase letter',
      );
    });

    test('rejects a missing digit', () {
      expect(passwordProblem('SecretAbc'), 'Password must include a number');
    });
  });

  group('JsonApiClient.serverMessage', () {
    test('prefers the field-level validation message from details', () {
      final body = {
        'error': 'ValidationError',
        'message': 'Request validation failed',
        'details': [
          {
            'loc': ['body', 'password'],
            'msg': 'String should have at least 8 characters',
            'type': 'string_too_short',
          },
        ],
      };
      expect(
        JsonApiClient.serverMessage(body, 'fallback'),
        'password: String should have at least 8 characters',
      );
    });

    test('handles a non-body loc (query parameter)', () {
      final body = {
        'details': [
          {'loc': ['query', 'radius_km'], 'msg': 'Input should be less than or equal to 50'},
        ],
      };
      expect(
        JsonApiClient.serverMessage(body, 'fallback'),
        'radius_km: Input should be less than or equal to 50',
      );
    });

    test('uses the message when loc carries no field name', () {
      final body = {
        'details': [
          {'loc': ['body'], 'msg': 'Invalid payload'},
        ],
      };
      expect(JsonApiClient.serverMessage(body, 'fallback'), 'Invalid payload');
    });

    test('falls back to the top-level message for plain HTTP errors', () {
      final body = {
        'error': 'HTTPException',
        'message': 'An account with this email already exists',
        'status_code': 409,
      };
      expect(
        JsonApiClient.serverMessage(body, 'fallback'),
        'An account with this email already exists',
      );
    });

    test('falls back to detail when message is absent', () {
      expect(
        JsonApiClient.serverMessage({'detail': 'Not found'}, 'fallback'),
        'Not found',
      );
    });

    test('returns the fallback for unknown or empty bodies', () {
      expect(JsonApiClient.serverMessage(null, 'fallback'), 'fallback');
      expect(JsonApiClient.serverMessage('nope', 'fallback'), 'fallback');
      expect(JsonApiClient.serverMessage(const {}, 'fallback'), 'fallback');
      expect(
        JsonApiClient.serverMessage(const {'details': []}, 'fallback'),
        'fallback',
      );
    });
  });
}
