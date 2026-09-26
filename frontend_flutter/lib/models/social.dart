import 'package:flutter/material.dart';

/// The user's experience history and passport.
///
/// Shows completed experiences, visited places, badges, and stats.
@immutable
class ExperienceWallet {
  const ExperienceWallet({
    required this.userId,
    required this.logs,
    required this.badges,
    required this.questsCompleted,
    this.totalXp = 0,
    this.citiesVisited = const [],
    this.hiddenGemsFound = 0,
    this.sunriseWalks = 0,
    this.foodTrailsCompleted = 0,
    this.monsoonAdventures = 0,
  });

  final String userId;
  final List<ExperienceLog> logs;
  final List<String> badges; // badge IDs
  final List<String> questsCompleted;
  final int totalXp;
  final List<String> citiesVisited;
  final int hiddenGemsFound;
  final int sunriseWalks;
  final int foodTrailsCompleted;
  final int monsoonAdventures;

  int get experiencesCompleted => logs.length;
  int get placesVisited => logs.map((l) => l.placeId).toSet().length;

  static ExperienceWallet empty(String userId) => ExperienceWallet(
        userId: userId,
        logs: const [],
        badges: const [],
        questsCompleted: const [],
      );
}

/// A single completed or in-progress experience entry.
@immutable
class ExperienceLog {
  const ExperienceLog({
    required this.id,
    required this.experienceId,
    required this.placeId,
    required this.placeTitle,
    required this.imageUrl,
    required this.completedAt,
    required this.durationMinutes,
    required this.spentInr,
    this.rating,
    this.note,
    this.isHiddenGem = false,
  });

  final String id;
  final String experienceId;
  final String placeId;
  final String placeTitle;
  final String imageUrl;
  final DateTime completedAt;
  final int durationMinutes;
  final int spentInr;
  final int? rating; // 1–5
  final String? note;
  final bool isHiddenGem;

  String get costLabel => spentInr == 0 ? 'Free' : '₹$spentInr';
}

/// A meetup request from one user to another around an experience.
@immutable
class MeetupRequest {
  const MeetupRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.experienceId,
    required this.experienceTitle,
    required this.proposedDate,
    required this.status,
    required this.safetyStatus,
    this.message,
    this.meetingPoint,
    this.trustedContact,
  });

  final String id;
  final String fromUserId;
  final String toUserId;
  final String experienceId;
  final String experienceTitle;
  final DateTime proposedDate;
  final MeetupStatus status;
  final MeetupSafetyStatus safetyStatus;
  final String? message;
  final String? meetingPoint;
  final String? trustedContact;
}

enum MeetupStatus { pending, accepted, declined, expired, completed }

enum MeetupSafetyStatus { publicPlace, trustedContactShared, safetyConfirmed }

/// A person profile shown in the People / social matching UI.
///
/// Not a dating profile — experience-specific compatibility only.
@immutable
class PeopleMatch {
  const PeopleMatch({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.compatibilityPercent,
    required this.sharedInterests,
    required this.verificationTier,
    required this.reputationScore,
    this.badges = const [],
    this.mutualFriendCount = 0,
  });

  final String userId;
  final String displayName;
  final String photoUrl;
  final int compatibilityPercent;
  final List<String> sharedInterests;
  final int verificationTier; // 0–3 maps to TrustTier
  final double reputationScore;
  final List<String> badges;
  final int mutualFriendCount;

  String get compatLabel => '$compatibilityPercent% match';
}

/// In-app notification.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.isRead = false,
    this.actionRoute,
    this.imageUrl,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime receivedAt;
  final bool isRead;
  final String? actionRoute;
  final String? imageUrl;
}

enum NotificationType {
  bookingUpdate,
  meetupUpdate,
  planChange,
  weatherAlert,
  rightNowChange,
  guideRequest,
  questProgress,
  priceDeal,
  safetyAlert,
  general,
}

extension NotificationTypeX on NotificationType {
  IconData get icon => switch (this) {
        NotificationType.bookingUpdate => Icons.calendar_month_outlined,
        NotificationType.meetupUpdate => Icons.people_outline_rounded,
        NotificationType.planChange => Icons.route_outlined,
        NotificationType.weatherAlert => Icons.umbrella_outlined,
        NotificationType.rightNowChange => Icons.bolt_rounded,
        NotificationType.guideRequest => Icons.person_search_outlined,
        NotificationType.questProgress => Icons.explore_outlined,
        NotificationType.priceDeal => Icons.local_offer_outlined,
        NotificationType.safetyAlert => Icons.security_outlined,
        NotificationType.general => Icons.notifications_outlined,
      };

  Color get color => switch (this) {
        NotificationType.weatherAlert => const Color(0xFF2F5BFF),
        NotificationType.safetyAlert => const Color(0xFFC93B3B),
        NotificationType.rightNowChange => const Color(0xFF6C55E8),
        NotificationType.priceDeal => const Color(0xFF0E7C5A),
        _ => const Color(0xFF123A6B),
      };
}
