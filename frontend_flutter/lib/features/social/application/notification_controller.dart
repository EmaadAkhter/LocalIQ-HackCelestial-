import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/social.dart';

class NotificationState {
  const NotificationState({this.notifications = const []});

  final List<AppNotification> notifications;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  NotificationState copyWith({List<AppNotification>? notifications}) {
    return NotificationState(notifications: notifications ?? this.notifications);
  }
}

class NotificationController extends Notifier<NotificationState> {
  @override
  NotificationState build() {
    // Seed with initial notifications including the seeded meetup invitation.
    return NotificationState(
      notifications: [
        AppNotification(
          id: 'notif-1',
          type: NotificationType.meetupUpdate,
          title: 'New Meetup Invitation',
          body: 'Elena Rostova wants to explore the Irani Café Trail with you.',
          receivedAt: DateTime.now().subtract(const Duration(minutes: 15)),
          isRead: false,
          actionRoute: '/people/matches',
        ),
        AppNotification(
          id: 'notif-2',
          type: NotificationType.questProgress,
          title: 'Quest Available',
          body: 'The South Mumbai Art Deco circuit is perfect for today\'s weather.',
          receivedAt: DateTime.now().subtract(const Duration(hours: 2)),
          isRead: false,
          actionRoute: '/quests',
        ),
        AppNotification(
          id: 'notif-3',
          type: NotificationType.rightNowChange,
          title: 'Right Now Score Updated',
          body: 'Gateway of India is at peak atmosphere right now — 94/100.',
          receivedAt: DateTime.now().subtract(const Duration(hours: 4)),
          isRead: true,
          actionRoute: '/explore',
        ),
      ],
    );
  }

  void markRead(String id) {
    final updated = state.notifications.map((n) {
      if (n.id == id) {
        return AppNotification(
          id: n.id,
          type: n.type,
          title: n.title,
          body: n.body,
          receivedAt: n.receivedAt,
          isRead: true,
          actionRoute: n.actionRoute,
          imageUrl: n.imageUrl,
        );
      }
      return n;
    }).toList();
    state = state.copyWith(notifications: updated);
  }

  void markAllRead() {
    final updated = state.notifications.map((n) => AppNotification(
          id: n.id,
          type: n.type,
          title: n.title,
          body: n.body,
          receivedAt: n.receivedAt,
          isRead: true,
          actionRoute: n.actionRoute,
          imageUrl: n.imageUrl,
        )).toList();
    state = state.copyWith(notifications: updated);
  }

  void addNotification({
    required NotificationType type,
    required String title,
    required String body,
    String? actionRoute,
    String? imageUrl,
  }) {
    final notif = AppNotification(
      id: 'notif-${math.Random().nextInt(0xFFFFFF).toRadixString(16)}',
      type: type,
      title: title,
      body: body,
      receivedAt: DateTime.now(),
      isRead: false,
      actionRoute: actionRoute,
      imageUrl: imageUrl,
    );
    state = state.copyWith(notifications: [notif, ...state.notifications]);
  }
}

final notificationControllerProvider =
    NotifierProvider<NotificationController, NotificationState>(
  NotificationController.new,
  name: 'localiq.notificationController',
);

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationControllerProvider).unreadCount;
}, name: 'localiq.unreadNotifCount');
