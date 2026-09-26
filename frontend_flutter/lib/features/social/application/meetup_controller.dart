import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/social.dart';

/// The full meetup session state: all sent/received invitations.
class MeetupState {
  const MeetupState({
    this.sentRequests = const [],
    this.receivedRequests = const [],
  });

  final List<MeetupRequest> sentRequests;
  final List<MeetupRequest> receivedRequests;

  /// All requests (sent + received) deduplicated by id.
  List<MeetupRequest> get allRequests {
    final map = <String, MeetupRequest>{};
    for (final r in sentRequests) {
      map[r.id] = r;
    }
    for (final r in receivedRequests) {
      map[r.id] = r;
    }
    return map.values.toList();
  }

  int get pendingSentCount =>
      sentRequests.where((r) => r.status == MeetupStatus.pending).length;

  int get pendingReceivedCount =>
      receivedRequests.where((r) => r.status == MeetupStatus.pending).length;

  MeetupState copyWith({
    List<MeetupRequest>? sentRequests,
    List<MeetupRequest>? receivedRequests,
  }) {
    return MeetupState(
      sentRequests: sentRequests ?? this.sentRequests,
      receivedRequests: receivedRequests ?? this.receivedRequests,
    );
  }
}

class MeetupController extends Notifier<MeetupState> {
  @override
  MeetupState build() {
    // Seed with a sample received invitation so the UI has something to show.
    return MeetupState(
      receivedRequests: [
        MeetupRequest(
          id: 'invite-seed-1',
          fromUserId: 'u2',
          toUserId: 'current-user',
          experienceId: 'exp-irani-trail',
          experienceTitle: 'Irani Café Trail',
          proposedDate: DateTime.now().add(const Duration(days: 1, hours: 3)),
          status: MeetupStatus.pending,
          safetyStatus: MeetupSafetyStatus.publicPlace,
          message: 'Hey! Want to check out the Irani Cafe Trail tomorrow?',
          meetingPoint: 'Bastion Cafe, Colaba, Mumbai',
        ),
      ],
    );
  }

  /// Send a meetup invitation to another user.
  MeetupRequest sendInvitation({
    required String currentUserId,
    required String toUserId,
    required String experienceId,
    required String experienceTitle,
    required DateTime proposedDate,
    String? message,
    String? meetingPoint,
  }) {
    final id = 'invite-${math.Random().nextInt(0xFFFFFF).toRadixString(16)}';
    final request = MeetupRequest(
      id: id,
      fromUserId: currentUserId,
      toUserId: toUserId,
      experienceId: experienceId,
      experienceTitle: experienceTitle,
      proposedDate: proposedDate,
      status: MeetupStatus.pending,
      safetyStatus: MeetupSafetyStatus.publicPlace,
      message: message,
      meetingPoint: meetingPoint ?? 'Public meeting point (to be confirmed)',
    );

    state = state.copyWith(
      sentRequests: [...state.sentRequests, request],
    );
    return request;
  }

  /// Accept a received invitation.
  void acceptInvitation(String invitationId) {
    final updated = state.receivedRequests.map((r) {
      if (r.id == invitationId) {
        return MeetupRequest(
          id: r.id,
          fromUserId: r.fromUserId,
          toUserId: r.toUserId,
          experienceId: r.experienceId,
          experienceTitle: r.experienceTitle,
          proposedDate: r.proposedDate,
          status: MeetupStatus.accepted,
          safetyStatus: MeetupSafetyStatus.safetyConfirmed,
          message: r.message,
          meetingPoint: r.meetingPoint,
        );
      }
      return r;
    }).toList();

    state = state.copyWith(receivedRequests: updated);
  }

  /// Decline a received invitation.
  void declineInvitation(String invitationId) {
    final updated = state.receivedRequests.map((r) {
      if (r.id == invitationId) {
        return MeetupRequest(
          id: r.id,
          fromUserId: r.fromUserId,
          toUserId: r.toUserId,
          experienceId: r.experienceId,
          experienceTitle: r.experienceTitle,
          proposedDate: r.proposedDate,
          status: MeetupStatus.declined,
          safetyStatus: r.safetyStatus,
          message: r.message,
          meetingPoint: r.meetingPoint,
        );
      }
      return r;
    }).toList();

    state = state.copyWith(receivedRequests: updated);
  }

  /// Cancel a sent invitation.
  void cancelSentInvitation(String invitationId) {
    final updated = state.sentRequests
        .where((r) => r.id != invitationId)
        .toList();
    state = state.copyWith(sentRequests: updated);
  }
}

final meetupControllerProvider =
    NotifierProvider<MeetupController, MeetupState>(
  MeetupController.new,
  name: 'localiq.meetupController',
);

/// Pending received invitations count — used for notification badges.
final pendingInvitationsCountProvider = Provider<int>((ref) {
  return ref.watch(meetupControllerProvider).pendingReceivedCount;
}, name: 'localiq.pendingInvitations');
