import 'package:flutter/foundation.dart';

import '../../../core/utils/json_map_x.dart';

/// A tool call the agent wants to make before it will answer.
///
/// The backend only pauses for actions that spend money or change state;
/// read-only lookups run inline.
@immutable
class TravelBuddyPendingAction {
  const TravelBuddyPendingAction({
    required this.id,
    required this.name,
    this.arguments = const {},
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  factory TravelBuddyPendingAction.fromJson(Map<String, dynamic> json) {
    return TravelBuddyPendingAction(
      id: json.string('id') ?? '',
      name: json.string('name') ?? 'action',
      arguments: json.mapOrEmpty('arguments'),
    );
  }

  /// Human-readable label for the confirmation button.
  String get label => switch (name) {
        'book_guide' => 'Confirm guide booking',
        'create_booking' => 'Confirm booking',
        _ => 'Confirm ${name.replaceAll('_', ' ')}',
      };
}

/// One turn of the Travel Buddy conversation.
@immutable
class TravelBuddyReply {
  const TravelBuddyReply({
    required this.conversationId,
    required this.status,
    required this.text,
    this.pendingActions = const [],
  });

  final int conversationId;

  /// `completed`, `pending_confirmation`, or `failed`.
  final String status;
  final String text;
  final List<TravelBuddyPendingAction> pendingActions;

  bool get needsConfirmation =>
      status == 'pending_confirmation' && pendingActions.isNotEmpty;

  factory TravelBuddyReply.fromJson(Map<String, dynamic> json) {
    final message = json.mapOrEmpty('message');
    return TravelBuddyReply(
      conversationId: json.intValue('conversation_id'),
      status: json.string('status') ?? 'completed',
      text: message.string('content') ?? '',
      pendingActions: json
          .mapOrEmptyList('pending_actions')
          .map(TravelBuddyPendingAction.fromJson)
          .toList(),
    );
  }
}
