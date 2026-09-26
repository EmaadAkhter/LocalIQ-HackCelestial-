import 'place.dart';

enum ChatRole { user, assistant }

/// A single turn in the assistant thread.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.placeChips = const <Place>[],
    this.suggestions = const <String>[],
    this.isTyping = false,
  });

  final ChatRole role;
  final String text;

  /// Optional visual cards (used for "3 recommendations" replies).
  final List<Place> placeChips;

  /// Quick-reply chips under an assistant message.
  final List<String> suggestions;

  final bool isTyping;

  ChatMessage copyWith({
    String? text,
    List<Place>? placeChips,
    bool? isTyping,
  }) {
    return ChatMessage(
      role: role,
      text: text ?? this.text,
      placeChips: placeChips ?? this.placeChips,
      suggestions: suggestions,
      isTyping: isTyping ?? this.isTyping,
    );
  }
}

/// Input for the assistant endpoint.
class ChatRequest {
  const ChatRequest({
    required this.message,
    this.experienceId,
    this.history = const <ChatMessage>[],
  });

  final String message;
  final String? experienceId;
  final List<ChatMessage> history;

  Map<String, dynamic> toApiJson() {
    return <String, dynamic>{
      'experience_id': experienceId,
      'message': message,
      'history': history
          .map(
            (ChatMessage m) => <String, dynamic>{
              'role': m.role.name,
              'content': m.text,
            },
          )
          .toList(),
    };
  }
}
