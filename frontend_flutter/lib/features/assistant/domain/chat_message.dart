import 'package:flutter/foundation.dart';

import '../../../core/utils/json_map_x.dart';

enum ChatRole { user, assistant, system }

/// Who authored a turn, plus how it should be rendered.
enum MessageIntent {
  general,
  clarifyTime,
  clarifyBudget,
  showOptions,
  addToPlan,
  refinePlan,
  planStatus,
  noResults,
  error;

  static MessageIntent parse(String? value) {
    if (value == null) return MessageIntent.general;
    final needle = value.toLowerCase();
    return MessageIntent.values.firstWhere(
      (i) => i.name.toLowerCase().replaceAll('_', '') == needle,
      orElse: () => MessageIntent.general,
    );
  }
}

/// A single assistant turn. Recommendation cards are referenced by
/// recommendation id so the UI always renders the *current* ranking rather
/// than a stale snapshot.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.intent = MessageIntent.general,
    this.recommendationIds = const [],
    this.suggestedContext,
    this.followUps = const [],
    this.isStreaming = false,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final MessageIntent intent;

  /// Ids of recommendations rendered as cards beneath this message.
  final List<String> recommendationIds;

  /// When set, the assistant proposes a context change the user can apply
  /// with one tap (e.g. "give me 3 hours instead").
  final ({String label, int? minutes, int? budget})? suggestedContext;

  final List<String> followUps;
  final bool isStreaming;

  bool get hasCards => recommendationIds.isNotEmpty;

  bool get isUser => role == ChatRole.user;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json.string('id') ?? '',
      role: json.string('role') == 'user' ? ChatRole.user : ChatRole.assistant,
      text: json.string('text') ?? '',
      createdAt:
          DateTime.tryParse(json.stringOrNull('createdAt') ?? '') ?? DateTime.now(),
      intent: MessageIntent.parse(json.string('intent')),
      recommendationIds: json.stringList('recommendationIds'),
      followUps: json.stringList('followUps'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'created_at': createdAt.toIso8601String(),
        'intent': intent.name,
        'recommendation_ids': recommendationIds,
        'follow_ups': followUps,
      };

  ChatMessage copyWith({
    String? text,
    List<String>? recommendationIds,
    List<String>? followUps,
    bool? isStreaming,
    MessageIntent? intent,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      createdAt: createdAt,
      intent: intent ?? this.intent,
      recommendationIds: recommendationIds ?? this.recommendationIds,
      suggestedContext: suggestedContext,
      followUps: followUps ?? this.followUps,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

/// A conversation thread. `threadId` maps 1:1 to a backend conversation.
@immutable
class ChatThread {
  const ChatThread({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEmpty => messages.isEmpty;

  ChatThread copyWith({
    List<ChatMessage>? messages,
    String? title,
    DateTime? updatedAt,
  }) {
    return ChatThread(
      id: id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return ChatThread(
      id: json.string('id') ?? '',
      title: json.string('title') ?? 'New conversation',
      messages: json.mapList('messages').map(ChatMessage.fromJson).toList(),
      createdAt:
          DateTime.tryParse(json.stringOrNull('createdAt') ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json.stringOrNull('updatedAt') ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': [for (final m in messages) m.toJson()],
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
