import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/domain/chat_thread.dart';
import '../../../models/social.dart';
import '../../../shared/widgets/app_image.dart';
import '../application/meetup_controller.dart';
import '../application/notification_controller.dart';
import '../data/local_social.dart';
import '../data/social_repository.dart';

/// Phase 9: People / Matching Screen
///
/// Connects solo travelers and local explorers based on shared taste,
/// availability, and verified trust status.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = ref.watch(peopleMatchesProvider).value ?? kLocalPeopleMatches;
    final meetupState = ref.watch(meetupControllerProvider);
    final pendingCount = meetupState.pendingReceivedCount;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Your Matches'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: [
            const Tab(text: 'Matched Explorers'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Meetup Invitations'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _MatchesTab(
            matches: matches,
            onProposeMeetup: (match) => _showProposeSheet(context, match),
          ),
          _MeetupsTab(
            onFindAnotherMatch: () => _tabCtrl.animateTo(0),
          ),
        ],
      ),
    );
  }

  void _showProposeSheet(BuildContext context, PeopleMatch match) {
    final experienceCtrl = TextEditingController(text: 'Heritage & Art Deco Walk');
    final meetingPointCtrl = TextEditingController(text: 'Oval Maidan Promenade, Churchgate');
    final messageCtrl = TextEditingController(
      text: 'Hey ${match.displayName}! Would love to check out some local spots together.',
    );
    DateTime selectedTime = DateTime.now().add(const Duration(days: 1, hours: 2));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Invite ${match.displayName}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${match.compatibilityPercent}% taste compatibility · Verified Public Location required',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Experience / Outing Topic',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: experienceCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.explore_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Public Meeting Point',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: meetingPointCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Custom Message',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: messageCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 20),

                    FilledButton(
                      onPressed: () {
                        final currentUser = ref.read(currentUserProvider);
                        final currentUserId = currentUser?.id ?? 'guest-explorer';

                        ref.read(meetupControllerProvider.notifier).sendInvitation(
                              currentUserId: currentUserId,
                              toUserId: match.userId,
                              experienceId: 'exp-custom',
                              experienceTitle: experienceCtrl.text.trim(),
                              proposedDate: selectedTime,
                              message: messageCtrl.text.trim(),
                              meetingPoint: meetingPointCtrl.text.trim(),
                            );

                        ref.read(notificationControllerProvider.notifier).addNotification(
                              type: NotificationType.meetupUpdate,
                              title: 'Meetup Invitation Sent',
                              body: 'Waiting for ${match.displayName} to accept your invitation to "${experienceCtrl.text.trim()}".',
                              actionRoute: '/people/matches',
                            );

                        Navigator.pop(ctx);
                        _tabCtrl.animateTo(1);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Invitation sent! Waiting for ${match.displayName} to accept.'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: const Text('Send Meetup Invitation', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MatchesTab extends ConsumerWidget {
  const _MatchesTab({required this.matches, required this.onProposeMeetup});

  final List<PeopleMatch> matches;
  final void Function(PeopleMatch) onProposeMeetup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetupState = ref.watch(meetupControllerProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Safe Meetup Notice Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Community Safety: All matched explorers have verified identities. Meetups are designed for public cultural venues.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        for (final match in matches) ...[
          _MatchCard(
            match: match,
            isInvited: meetupState.sentRequests.any((r) => r.toUserId == match.userId),
            onPropose: () => onProposeMeetup(match),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.isInvited,
    required this.onPropose,
  });

  final PeopleMatch match;
  final bool isInvited;
  final VoidCallback onPropose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: AppImage(
                  url: match.photoUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '★ ${match.reputationScore.toStringAsFixed(1)} · Verified Explorer',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${match.compatibilityPercent}% Match',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Shared Explorations & Taste:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: match.sharedInterests.map((interest) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  interest,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          if (isInvited)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Invitation sent · Waiting for ${match.displayName.split(' ').first} to accept',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text('Chat'),
                    onPressed: () {
                      context.push(
                        '/chat/2',
                        extra: ChatThread(
                          id: 2,
                          kind: 'meetup',
                          otherUserId: int.tryParse(match.userId) ?? 202,
                          otherName: match.displayName,
                          otherAvatarUrl: match.photoUrl,
                          contextLabel: 'Matched Explorer · ${match.compatibilityPercent}% Match',
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 15),
                    label: const Text('Propose Meetup'),
                    onPressed: onPropose,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MeetupsTab extends ConsumerWidget {
  const _MeetupsTab({required this.onFindAnotherMatch});

  final VoidCallback onFindAnotherMatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetupState = ref.watch(meetupControllerProvider);
    final received = meetupState.receivedRequests;
    final sent = meetupState.sentRequests;

    final allConfirmed = [
      ...received.where((r) => r.status == MeetupStatus.accepted),
      ...sent.where((r) => r.status == MeetupStatus.accepted),
    ];

    final hasAny = received.isNotEmpty || sent.isNotEmpty;

    if (!hasAny) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline_rounded, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text(
                'No meetup invitations yet',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 6),
              const Text(
                'Match with explorers sharing your taste profile and propose an outing!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onFindAnotherMatch,
                child: const Text('Find Fellow Explorers'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 1. Received Invitations
        if (received.isNotEmpty) ...[
          const Text(
            'Received Invitations',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          for (final req in received) ...[
            _ReceivedInvitationCard(request: req),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 14),
        ],

        // ── 2. Sent Invitations
        if (sent.isNotEmpty) ...[
          const Text(
            'Sent Invitations',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          for (final req in sent) ...[
            _SentInvitationCard(request: req),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 14),
        ],

        // ── 3. Confirmed Meetups
        if (allConfirmed.isNotEmpty) ...[
          const Text(
            'Confirmed Meetups 🎉',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          for (final req in allConfirmed) ...[
            _ConfirmedMeetupCard(request: req),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _ReceivedInvitationCard extends ConsumerWidget {
  const _ReceivedInvitationCard({required this.request});

  final MeetupRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = request.status == MeetupStatus.pending;
    final isAccepted = request.status == MeetupStatus.accepted;
    final isDeclined = request.status == MeetupStatus.declined;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isAccepted ? AppColors.success.withValues(alpha: 0.5) : AppColors.border,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mail_outline_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.experienceTitle,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'From Elena Rostova · 91% Match',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: request.status),
            ],
          ),
          const SizedBox(height: 12),
          if (request.message != null && request.message!.isNotEmpty) ...[
            Text(
              '"${request.message}"',
              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.text),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  request.meetingPoint ?? 'Public meeting point',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          if (isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ref.read(meetupControllerProvider.notifier).declineInvitation(request.id);
                      ref.read(notificationControllerProvider.notifier).addNotification(
                            type: NotificationType.meetupUpdate,
                            title: 'Invitation Declined',
                            body: 'You declined the invitation to "${request.experienceTitle}".',
                            actionRoute: '/people/matches',
                          );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      ref.read(meetupControllerProvider.notifier).acceptInvitation(request.id);
                      ref.read(notificationControllerProvider.notifier).addNotification(
                            type: NotificationType.meetupUpdate,
                            title: 'Meetup Confirmed! 🎉',
                            body: 'Meetup confirmed with Elena Rostova for "${request.experienceTitle}".',
                            actionRoute: '/people/matches',
                          );
                    },
                    child: const Text('Accept Meetup'),
                  ),
                ),
              ],
            ),
          ],
          if (isAccepted) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: const Text('Chat with Elena'),
                onPressed: () {
                  context.push(
                    '/chat/2',
                    extra: const ChatThread(
                      id: 2,
                      kind: 'meetup',
                      otherUserId: 202,
                      otherName: 'Elena Rostova',
                      contextLabel: 'Random Meetup · Heritage & Art Deco Walk',
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          if (isDeclined) ...[
            const SizedBox(height: 10),
            const Text(
              'Invitation declined.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SentInvitationCard extends ConsumerWidget {
  const _SentInvitationCard({required this.request});

  final MeetupRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = request.status == MeetupStatus.pending;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.outgoing_mail, color: AppColors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.experienceTitle,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Meeting at: ${request.meetingPoint ?? 'Public Spot'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: request.status),
            ],
          ),
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Waiting for explorer to accept...',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(meetupControllerProvider.notifier).cancelSentInvitation(request.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation cancelled.')),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfirmedMeetupCard extends StatelessWidget {
  const _ConfirmedMeetupCard({required this.request});

  final MeetupRequest request;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: const Text(
                  'MEETUP CONFIRMED',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10),
                ),
              ),
              const Spacer(),
              const Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            request.experienceTitle,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  request.meetingPoint ?? 'Public location',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, size: 15, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Safety tip: Meet inside daylight public venue. Emergency SOS active in app.',
                    style: TextStyle(fontSize: 11, color: AppColors.primaryDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final MeetupStatus status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case MeetupStatus.pending:
        bg = AppColors.primary.withValues(alpha: 0.12);
        fg = AppColors.primary;
        label = 'Pending';
        break;
      case MeetupStatus.accepted:
        bg = AppColors.success.withValues(alpha: 0.15);
        fg = AppColors.success;
        label = 'Confirmed';
        break;
      case MeetupStatus.declined:
        bg = AppColors.danger.withValues(alpha: 0.12);
        fg = AppColors.danger;
        label = 'Declined';
        break;
      case MeetupStatus.expired:
        bg = AppColors.textMuted.withValues(alpha: 0.12);
        fg = AppColors.textMuted;
        label = 'Expired';
        break;
      case MeetupStatus.completed:
        bg = AppColors.primaryDark.withValues(alpha: 0.15);
        fg = AppColors.primaryDark;
        label = 'Completed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }
}
