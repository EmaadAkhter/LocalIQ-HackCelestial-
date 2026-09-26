import 'package:flutter/material.dart';

/// Trust tier for a LocalIQ user (Explorer or Guide).
///
/// Stranger-related functionality must visibly depend on trust status.
@immutable
class TrustStatus {
  const TrustStatus({
    required this.tier,
    required this.verificationState,
    required this.badges,
    this.idVerifiedAt,
    this.backgroundCheckedAt,
  });

  final TrustTier tier;
  final VerificationState verificationState;
  final List<TrustBadge> badges;
  final DateTime? idVerifiedAt;
  final DateTime? backgroundCheckedAt;

  bool get isVerified => tier.index >= TrustTier.idVerified.index;
  bool get canMeetStrangers => tier.index >= TrustTier.basic.index;
  bool get hasEnhancedTrust => tier == TrustTier.enhanced;

  static const TrustStatus unverified = TrustStatus(
    tier: TrustTier.none,
    verificationState: VerificationState.notStarted,
    badges: [],
  );
}

enum TrustTier {
  none,
  basic,    // Email verified
  idVerified, // Government ID
  enhanced,   // Background check
}

extension TrustTierX on TrustTier {
  String get label => switch (this) {
        TrustTier.none => 'Not Verified',
        TrustTier.basic => 'Basic Verification',
        TrustTier.idVerified => 'ID Verified',
        TrustTier.enhanced => 'Enhanced Trust',
      };

  String get description => switch (this) {
        TrustTier.none => 'Complete basic verification to unlock social features.',
        TrustTier.basic => 'Email verified. Complete ID verification for more.',
        TrustTier.idVerified => 'Identity confirmed. You can meet and plan with others.',
        TrustTier.enhanced => 'Background checked. Full access to social features.',
      };

  Color get color => switch (this) {
        TrustTier.none => const Color(0xFF8590A6),
        TrustTier.basic => const Color(0xFF2F5BFF),
        TrustTier.idVerified => const Color(0xFF0E7C5A),
        TrustTier.enhanced => const Color(0xFF6C55E8),
      };

  IconData get icon => switch (this) {
        TrustTier.none => Icons.shield_outlined,
        TrustTier.basic => Icons.verified_outlined,
        TrustTier.idVerified => Icons.verified_user_outlined,
        TrustTier.enhanced => Icons.security_rounded,
      };
}

enum VerificationState { notStarted, pending, verified, needsAttention }

extension VerificationStateX on VerificationState {
  String get label => switch (this) {
        VerificationState.notStarted => 'Not started',
        VerificationState.pending => 'In review',
        VerificationState.verified => 'Verified',
        VerificationState.needsAttention => 'Needs attention',
      };
}

enum TrustBadge {
  emailVerified,
  phoneVerified,
  idVerified,
  backgroundChecked,
  communityTrusted,
}

extension TrustBadgeX on TrustBadge {
  String get label => switch (this) {
        TrustBadge.emailVerified => 'Email Verified',
        TrustBadge.phoneVerified => 'Phone Verified',
        TrustBadge.idVerified => 'ID Verified',
        TrustBadge.backgroundChecked => 'Background Checked',
        TrustBadge.communityTrusted => 'Community Trusted',
      };
}
