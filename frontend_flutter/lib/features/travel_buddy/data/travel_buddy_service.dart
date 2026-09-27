import '../../../core/error/app_exception.dart';
import '../../../core/network/json_api_client.dart';
import '../domain/travel_buddy_reply.dart';

/// Talks to the agentic Travel Buddy on the backend.
///
///   POST /travel-buddy/chat  { message, conversation_id?, confirm? }
///
/// The endpoint runs the LLM plus real tool calls, so it gets a much longer
/// timeout than ordinary CRUD.
class TravelBuddyService {
  TravelBuddyService(this._client);

  final JsonApiClient _client;

  static const _agentTimeout = Duration(seconds: 90);

  Future<TravelBuddyReply> send(
    String message, {
    int? conversationId,
    bool confirm = false,
    double? lat,
    double? lng,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'conversation_id': ?conversationId,
      'confirm': confirm,
      'lat': lat,
      'lng': lng,
    };
    final data = await _client.post(
      '/travel-buddy/chat',
      body: body,
      timeout: _agentTimeout,
    );
    if (data is! Map) {
      throw const ParseException('The assistant returned an unexpected reply.');
    }
    return TravelBuddyReply.fromJson(data.cast<String, dynamic>());
  }
}
