/// Chat thread domain models.
///
/// A [ChatThread] represents a persistent conversation between two users
/// (guide↔explorer after a booking, or matched meetup users). Messages are
/// stored on the backend and polled on screen entry.
library;

class ChatThread {
  const ChatThread({
    required this.id,
    required this.kind,
    required this.otherUserId,
    required this.otherName,
    this.otherAvatarUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.contextLabel,
    this.contextId,
  });

  /// 'guide_explorer' | 'meetup'
  final String kind;
  final int id;
  final int otherUserId;
  final String otherName;
  final String? otherAvatarUrl;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// e.g. "Mumbai Heritage Walk · Booking #42"
  final String? contextLabel;
  final int? contextId;

  bool get hasUnread => unreadCount > 0;

  String get kindLabel => switch (kind) {
        'guide_explorer' => 'Booking',
        'meetup' => 'Meetup',
        _ => kind,
      };

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
        id: (json['id'] as num?)?.toInt() ?? 0,
        kind: json['kind'] as String? ?? 'guide_explorer',
        otherUserId: (json['otherUserId'] as num?)?.toInt() ?? 0,
        otherName: json['otherName'] as String? ?? 'User',
        otherAvatarUrl: json['otherAvatarUrl'] as String?,
        lastMessage: json['lastMessage'] as String?,
        lastMessageAt: json['lastMessageAt'] != null
            ? DateTime.tryParse(json['lastMessageAt'] as String)
            : null,
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
        contextLabel: json['contextLabel'] as String?,
        contextId: (json['contextId'] as num?)?.toInt(),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.isMe = false,
    this.read = false,
  });

  final int id;
  final int threadId;
  final int senderId;
  final String text;
  final DateTime sentAt;
  final bool isMe;
  final bool read;

  factory ChatMessage.fromJson(Map<String, dynamic> json, {int? myId}) =>
      ChatMessage(
        id: (json['id'] as num?)?.toInt() ?? 0,
        threadId: (json['threadId'] as num?)?.toInt() ?? 0,
        senderId: (json['senderId'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
        sentAt: json['sentAt'] != null
            ? DateTime.tryParse(json['sentAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        isMe: myId != null &&
            (json['senderId'] as num?)?.toInt() == myId,
        read: json['read'] as bool? ?? false,
      );
}
