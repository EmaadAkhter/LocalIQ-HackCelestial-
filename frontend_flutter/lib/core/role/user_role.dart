import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two distinct product roles in LocalIQ.
///
/// Explorer: discovers experiences, plans outings, meets people.
/// Guide:    offers experiences, manages availability, accepts bookings.
enum UserRole { explorer, guide }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.explorer => 'Explorer',
        UserRole.guide => 'Guide',
      };

  String get tagline => switch (this) {
        UserRole.explorer => 'Discover experiences, meet people, build plans.',
        UserRole.guide => 'Offer experiences, manage availability, earn.',
      };

  bool get isExplorer => this == UserRole.explorer;
  bool get isGuide => this == UserRole.guide;
}

/// Notifier for the user's selected role.
///
/// Null means the role has not been selected yet (role selection screen shown).
class UserRoleNotifier extends Notifier<UserRole?> {
  @override
  UserRole? build() => null;

  void setRole(UserRole role) => state = role;
  void clear() => state = null;
}

/// Persists the user's selected role for the current session.
final userRoleProvider =
    NotifierProvider<UserRoleNotifier, UserRole?>(UserRoleNotifier.new);

/// Convenience: resolves role, defaulting to explorer if somehow null.
final resolvedRoleProvider = Provider<UserRole>((ref) {
  return ref.watch(userRoleProvider) ?? UserRole.explorer;
});
