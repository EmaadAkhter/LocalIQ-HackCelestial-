import 'package:flutter/foundation.dart';

import '../../../core/utils/json_map_x.dart';

/// Re-export so callers only import one file for the auth feature.
typedef AppUser = LocalIqUser;

/// Authenticated or anonymous account.
@immutable
class LocalIqUser {
  const LocalIqUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.provider,
    required this.tier,
    required this.homeCity,
    required this.createdAt,
    this.isAnonymous = false,
  });

  final String id;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final AuthProvider provider;
  final UserTier tier;
  final String homeCity;
  final DateTime createdAt;
  final bool isAnonymous;

  bool get isGuest => isAnonymous || tier == UserTier.guest;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return displayName.isEmpty ? 'L' : displayName[0].toUpperCase();
  }

  factory LocalIqUser.fromJson(Map<String, dynamic> json) {
    return LocalIqUser(
      id: json.string('id') ?? 'unknown',
      displayName: json.string('displayName') ?? 'Traveller',
      email: json.stringOrNull('email'),
      avatarUrl: json.stringOrNull('avatarUrl'),
      provider: AuthProviderX.parse(json.string('provider')),
      tier: UserTier.values.firstWhere(
        (t) => t.name == json.string('tier'),
        orElse: () => UserTier.free,
      ),
      homeCity: json.string('homeCity') ?? 'Mumbai',
      createdAt:
          DateTime.tryParse(json.stringOrNull('createdAt') ?? '') ?? DateTime.now(),
      isAnonymous: json.boolValue('isAnonymous'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'email': email,
        'avatar_url': avatarUrl,
        'provider': provider.name,
        'tier': tier.name,
        'home_city': homeCity,
        'created_at': createdAt.toIso8601String(),
        'is_anonymous': isAnonymous,
      };
}

enum AuthProvider { email, google, guest }

extension AuthProviderX on AuthProvider {
  String get label => switch (this) {
        AuthProvider.email => 'Email',
        AuthProvider.google => 'Google',
        AuthProvider.guest => 'Guest',
      };

  static AuthProvider parse(String? value) {
    if (value == null) return AuthProvider.email;
    return AuthProvider.values.firstWhere(
      (p) => p.name.toLowerCase() == value.toLowerCase(),
      orElse: () => AuthProvider.email,
    );
  }
}

enum UserTier { guest, free, plus, pro }

extension UserTierX on UserTier {
  String get label => switch (this) {
        UserTier.guest => 'Guest',
        UserTier.free => 'Free',
        UserTier.plus => 'Plus',
        UserTier.pro => 'Pro',
      };
}
