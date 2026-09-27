import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/network/json_api_client.dart';
import '../../../core/providers.dart';
import '../domain/chat_thread.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

abstract class ChatRepository {
  Future<List<ChatThread>> threads();
  Future<List<ChatMessage>> messages(int threadId);
  Future<ChatMessage> sendMessage(int threadId, String text);
  Future<void> markRead(int threadId);
}

// ---------------------------------------------------------------------------
// Remote (real API)
// ---------------------------------------------------------------------------

class RemoteChatRepository implements ChatRepository {
  RemoteChatRepository(this._api);
  final JsonApiClient _api;

  @override
  Future<List<ChatThread>> threads() async {
    final res = await _api.get('/chat/threads');
    final list = res as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ChatThread.fromJson)
        .toList();
  }

  @override
  Future<List<ChatMessage>> messages(int threadId) async {
    final res = await _api.get('/chat/threads/$threadId/messages');
    final list = res as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  @override
  Future<ChatMessage> sendMessage(int threadId, String text) async {
    final res = await _api.post(
      '/chat/threads/$threadId/messages',
      body: {'text': text},
    ) as Map<String, dynamic>;
    return ChatMessage.fromJson(res);
  }

  @override
  Future<void> markRead(int threadId) async {
    await _api.post('/chat/threads/$threadId/read', body: {});
  }
}

// ---------------------------------------------------------------------------
// Local stub (offline / dev)
// ---------------------------------------------------------------------------

class LocalChatRepository implements ChatRepository {
  final _threads = <ChatThread>[
    const ChatThread(
      id: 1,
      kind: 'guide_explorer',
      otherUserId: 101,
      otherName: 'Ravi Sharma',
      lastMessage: "I'll be at the Gateway by 9 AM.",
      unreadCount: 2,
      contextLabel: 'Mumbai Heritage Walk · Booking #42',
      contextId: 42,
    ),
    const ChatThread(
      id: 2,
      kind: 'meetup',
      otherUserId: 202,
      otherName: 'Ananya Krishnan',
      lastMessage: 'Sounds great, see you there!',
      unreadCount: 0,
      contextLabel: 'Random Meetup at Marine Drive',
      contextId: 7,
    ),
    const ChatThread(
      id: 3,
      kind: 'guide_explorer',
      otherUserId: 303,
      otherName: 'Farhan Qureshi',
      lastMessage: 'The mangrove trek is now confirmed.',
      unreadCount: 1,
      contextLabel: 'Dharavi Art Trail · Booking #51',
      contextId: 51,
    ),
  ];

  final _messages = <int, List<ChatMessage>>{
    1: [
      ChatMessage(
        id: 1, threadId: 1, senderId: 101, text: 'Hi! Looking forward to the walk.',
        sentAt: DateTime.now().subtract(const Duration(minutes: 30)), isMe: false,
      ),
      ChatMessage(
        id: 2, threadId: 1, senderId: 0, text: 'Me too! What time works for you?',
        sentAt: DateTime.now().subtract(const Duration(minutes: 28)), isMe: true,
      ),
      ChatMessage(
        id: 3, threadId: 1, senderId: 101, text: 'I\'ll be at the Gateway by 9 AM.',
        sentAt: DateTime.now().subtract(const Duration(minutes: 5)), isMe: false,
      ),
    ],
    2: [
      ChatMessage(
        id: 4, threadId: 2, senderId: 202, text: 'Hey! Are you still up for Marine Drive?',
        sentAt: DateTime.now().subtract(const Duration(hours: 1)), isMe: false,
      ),
      ChatMessage(
        id: 5, threadId: 2, senderId: 0, text: 'Absolutely, see you there!',
        sentAt: DateTime.now().subtract(const Duration(minutes: 50)), isMe: true,
      ),
      ChatMessage(
        id: 6, threadId: 2, senderId: 202, text: 'Sounds great, see you there!',
        sentAt: DateTime.now().subtract(const Duration(minutes: 45)), isMe: false,
      ),
    ],
    3: [
      ChatMessage(
        id: 7, threadId: 3, senderId: 303, text: 'The mangrove trek is now confirmed.',
        sentAt: DateTime.now().subtract(const Duration(hours: 2)), isMe: false,
      ),
    ],
  };

  int _nextId = 100;

  @override
  Future<List<ChatThread>> threads() async => List.unmodifiable(_threads);

  @override
  Future<List<ChatMessage>> messages(int threadId) async =>
      List.unmodifiable(_messages[threadId] ?? []);

  @override
  Future<ChatMessage> sendMessage(int threadId, String text) async {
    final msg = ChatMessage(
      id: _nextId++,
      threadId: threadId,
      senderId: 0, // current user
      text: text,
      sentAt: DateTime.now(),
      isMe: true,
    );
    _messages.putIfAbsent(threadId, () => []).add(msg);
    return msg;
  }

  @override
  Future<void> markRead(int threadId) async {}
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ref.watch(remoteDataEnabledProvider)
      ? RemoteChatRepository(ref.watch(apiClientProvider))
      : LocalChatRepository();
}, name: 'localiq.chatRepository');

final chatThreadsProvider = FutureProvider<List<ChatThread>>((ref) {
  return ref.read(chatRepositoryProvider).threads();
}, name: 'localiq.chatThreads');

// Notifier for live message list in a thread.
class ChatMessagesNotifier extends AsyncNotifier<List<ChatMessage>> {
  int? _threadId;

  void init(int threadId) {
    _threadId = threadId;
    ref.invalidateSelf();
  }

  @override
  Future<List<ChatMessage>> build() async {
    final id = _threadId;
    if (id == null) return [];
    await ref.read(chatRepositoryProvider).markRead(id);
    return ref.read(chatRepositoryProvider).messages(id);
  }

  Future<void> send(String text) async {
    final id = _threadId;
    if (id == null) return;
    final msg = await ref.read(chatRepositoryProvider).sendMessage(id, text);
    state = AsyncData([...?state.value, msg]);
  }
}

final chatMessagesProvider =
    AsyncNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
  ChatMessagesNotifier.new,
  name: 'localiq.chatMessages',
);
