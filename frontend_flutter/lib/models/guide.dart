import 'package:flutter/material.dart';

/// Immutable typed model for a LocalIQ Guide.
///
/// This is the marketplace profile — separate from the auth user model.
/// A guide is a verified, verified, or unverified provider on the platform.
@immutable
class Guide {
  const Guide({
    required this.id,
    required this.userId,
    required this.name,
    required this.bio,
    required this.photoUrl,
    required this.languages,
    required this.specialties,
    required this.preferredAreas,
    required this.hourlyRateInr,
    required this.rating,
    required this.reviewCount,
    required this.verification,
    required this.isAvailableNow,
    this.yearsExperience = 0,
    this.sampleItineraries = const [],
    this.badges = const [],
    this.responseTimeMinutes = 30,
  });

  final String id;
  final String userId;
  final String name;
  final String bio;
  final String photoUrl;
  final List<String> languages;
  final List<String> specialties;
  final List<String> preferredAreas;
  final int hourlyRateInr;
  final double rating;
  final int reviewCount;
  final GuideVerification verification;
  final bool isAvailableNow;
  final int yearsExperience;
  final List<String> sampleItineraries;
  final List<String> badges;
  final int responseTimeMinutes;

  String get rateLabel => '₹$hourlyRateInr/hr';
  String get reviewLabel => '$reviewCount review${reviewCount == 1 ? '' : 's'}';
  String get languageLabel => languages.join(' · ');

  factory Guide.fromJson(Map<String, dynamic> json) {
    return Guide(
      id: (json['id'] as String?) ?? '',
      userId: (json['userId'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Guide',
      bio: (json['bio'] as String?) ?? '',
      photoUrl: (json['photoUrl'] as String?) ?? '',
      languages: List<String>.from(json['languages'] as List? ?? []),
      specialties: List<String>.from(json['specialties'] as List? ?? []),
      preferredAreas: List<String>.from(json['preferredAreas'] as List? ?? []),
      hourlyRateInr: (json['hourlyRateInr'] as int?) ?? 500,
      rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
      reviewCount: (json['reviewCount'] as int?) ?? 0,
      verification: GuideVerificationX.parse(json['verification'] as String?),
      isAvailableNow: (json['isAvailableNow'] as bool?) ?? false,
      yearsExperience: (json['yearsExperience'] as int?) ?? 0,
      sampleItineraries:
          List<String>.from(json['sampleItineraries'] as List? ?? []),
      badges: List<String>.from(json['badges'] as List? ?? []),
      responseTimeMinutes: (json['responseTimeMinutes'] as int?) ?? 30,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'name': name,
        'bio': bio,
        'photoUrl': photoUrl,
        'languages': languages,
        'specialties': specialties,
        'preferredAreas': preferredAreas,
        'hourlyRateInr': hourlyRateInr,
        'rating': rating,
        'reviewCount': reviewCount,
        'verification': verification.name,
        'isAvailableNow': isAvailableNow,
        'yearsExperience': yearsExperience,
        'sampleItineraries': sampleItineraries,
        'badges': badges,
        'responseTimeMinutes': responseTimeMinutes,
      };
}

enum GuideVerification { notStarted, pending, verified, enhanced }

extension GuideVerificationX on GuideVerification {
  String get label => switch (this) {
        GuideVerification.notStarted => 'Unverified',
        GuideVerification.pending => 'Verification Pending',
        GuideVerification.verified => 'ID Verified',
        GuideVerification.enhanced => 'Enhanced Trust',
      };

  bool get isVerified =>
      this == GuideVerification.verified || this == GuideVerification.enhanced;

  static GuideVerification parse(String? value) {
    if (value == null) return GuideVerification.notStarted;
    return GuideVerification.values.firstWhere(
      (v) => v.name.toLowerCase() == value.toLowerCase(),
      orElse: () => GuideVerification.notStarted,
    );
  }
}

/// A booking request from an explorer to a guide.
@immutable
class GuideBooking {
  const GuideBooking({
    required this.id,
    required this.guideId,
    required this.explorerId,
    required this.guideName,
    required this.guidePhotoUrl,
    required this.date,
    required this.startTime,
    required this.durationHours,
    required this.groupSize,
    required this.status,
    required this.totalCostInr,
    this.notes,
    this.meetingPoint,
    this.cancelledReason,
  });

  final String id;
  final String guideId;
  final String explorerId;
  final String guideName;
  final String guidePhotoUrl;
  final DateTime date;
  final TimeOfDay startTime;
  final int durationHours;
  final int groupSize;
  final BookingStatus status;
  final int totalCostInr;
  final String? notes;
  final String? meetingPoint;
  final String? cancelledReason;

  String get costLabel => '₹$totalCostInr';
  String get durationLabel => '$durationHours hr${durationHours == 1 ? '' : 's'}';
}

enum BookingStatus { requested, accepted, declined, cancelled, completed }

extension BookingStatusX on BookingStatus {
  String get label => switch (this) {
        BookingStatus.requested => 'Requested',
        BookingStatus.accepted => 'Confirmed',
        BookingStatus.declined => 'Declined',
        BookingStatus.cancelled => 'Cancelled',
        BookingStatus.completed => 'Completed',
      };

  bool get isActive =>
      this == BookingStatus.requested || this == BookingStatus.accepted;
}

/// An availability slot on a guide's calendar.
@immutable
class GuideAvailabilitySlot {
  const GuideAvailabilitySlot({
    required this.date,
    required this.startHour,
    required this.endHour,
    required this.state,
    this.maxGroupSize = 6,
  });

  final DateTime date;
  final int startHour;
  final int endHour;
  final SlotState state;
  final int maxGroupSize;
}

enum SlotState { available, unavailable, booked }
