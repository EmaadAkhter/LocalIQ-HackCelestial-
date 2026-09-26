import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/quest.dart';
import '../../../shared/widgets/app_image.dart';
import '../application/quest_controller.dart';
import '../data/local_quests.dart';
import '../data/quest_repository.dart';

/// Phase 15: City Quests Screen
class QuestsScreen extends ConsumerStatefulWidget {
  const QuestsScreen({super.key});

  @override
  ConsumerState<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends ConsumerState<QuestsScreen> {
  @override
  Widget build(BuildContext context) {
    final quests = ref.watch(allQuestsProvider).value ?? kLocalQuests;
    final questSessionState = ref.watch(questControllerProvider);

    // Calculate level based on XP
    final totalXp = questSessionState.totalXp;
    final badgesCount = questSessionState.earnedBadges.length;
    final level = (totalXp / 300).floor() + 1;

    // Active in-progress quest (if any)
    ActiveQuestState? activeSession;
    for (final s in questSessionState.sessions.values) {
      if (!s.isCompleted) {
        activeSession = s;
        break;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('City Quests & Expeditions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.wallet_rounded),
            tooltip: 'Experience Wallet & Badges',
            onPressed: () => context.push('/wallet'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── XP & Progress Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C55E8), Color(0xFF4A34BE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.raised,
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🏆', style: TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quest Explorer · Level $level',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$totalXp XP Earned · $badgesCount Badges Unlocked',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/wallet'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: const Text('Passport →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          if (activeSession != null) ...[
            const SizedBox(height: 18),
            _ActiveQuestBanner(
              session: activeSession,
              onContinue: () => _showQuestDetails(context, activeSession!.quest),
            ),
          ],

          const SizedBox(height: 20),

          const Text(
            'Featured Mumbai Quests',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 12),

          for (final quest in quests) ...[
            _QuestCard(
              quest: quest,
              session: questSessionState.getSession(quest.id),
              isCompleted: questSessionState.isCompleted(quest.id),
              onTap: () => _showQuestDetails(context, quest),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  void _showQuestDetails(BuildContext context, Quest quest) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _QuestDetailSheet(
          quest: quest,
          onCompletedCelebration: (reward) {
            _showCompletionDialog(context, quest, reward);
          },
        );
      },
    );
  }

  void _showCompletionDialog(BuildContext context, Quest quest, QuestReward? reward) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Row(
            children: const [
              Text('🎉 ', style: TextStyle(fontSize: 26)),
              Expanded(
                child: Text(
                  'Quest Completed!',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Congratulations! You successfully completed "${quest.title}".',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Text('🏅', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reward?.badgeLabel ?? 'Explorer Badge',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          Text(
                            '+${reward?.xpPoints ?? 250} XP added to your Passport',
                            style: const TextStyle(fontSize: 12, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/wallet');
              },
              child: const Text('View in Passport'),
            ),
          ],
        );
      },
    );
  }
}

class _ActiveQuestBanner extends StatelessWidget {
  const _ActiveQuestBanner({required this.session, required this.onContinue});

  final ActiveQuestState session;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: const Text(
                  'IN PROGRESS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.quest.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Current Stop: Stop ${session.currentStopIndex + 1} of ${session.totalStops} · ${session.currentStop.placeName}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text('Continue Quest (Stop ${session.currentStopIndex + 1}/${session.totalStops})'),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestDetailSheet extends ConsumerWidget {
  const _QuestDetailSheet({
    required this.quest,
    required this.onCompletedCelebration,
  });

  final Quest quest;
  final void Function(QuestReward?) onCompletedCelebration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questSessionState = ref.watch(questControllerProvider);
    final session = questSessionState.getSession(quest.id);
    final isCompleted = questSessionState.isCompleted(quest.id);
    final isStarted = session != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    quest.title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              quest.description,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _MetaBadge(icon: Icons.timer_outlined, label: quest.durationLabel),
                const SizedBox(width: 8),
                _MetaBadge(icon: Icons.currency_rupee_rounded, label: quest.costLabel),
                const SizedBox(width: 8),
                _MetaBadge(icon: Icons.flag_outlined, label: '${quest.stopCount} Stops'),
                const SizedBox(width: 8),
                if (quest.reward != null)
                  _MetaBadge(
                    icon: Icons.bolt_rounded,
                    label: '+${quest.reward!.xpPoints} XP',
                    color: AppColors.primary,
                  ),
              ],
            ),

            if (isCompleted) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Quest Completed! Badge "${quest.reward?.badgeLabel}" added to your Wallet.',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Divider(height: 28),
            const Text('Quest Checkpoints:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 12),

            for (int i = 0; i < quest.stops.length; i++) ...[
              _buildStopRow(i, quest.stops[i], session, isCompleted),
            ],

            const SizedBox(height: 20),

            // ── Primary Functional Action
            if (isCompleted) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ref.read(questControllerProvider.notifier).abandonQuest(quest.id);
                        ref.read(questControllerProvider.notifier).startQuest(quest);
                      },
                      child: const Text('Replay Quest'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/wallet');
                      },
                      child: const Text('View in Passport'),
                    ),
                  ),
                ],
              ),
            ] else if (isStarted) ...[
              FilledButton(
                onPressed: () {
                  final isDone = ref.read(questControllerProvider.notifier).completeCurrentStop(quest.id);
                  if (isDone) {
                    Navigator.pop(context);
                    onCompletedCelebration(quest.reward);
                  }
                },
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: Text(
                  session.isOnLastStop
                      ? 'Complete Final Stop & Claim Rewards 🎉'
                      : 'Complete Stop ${session.currentStopIndex + 1} & Advance',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              const SizedBox(height: 8),
              if (session.nextStop != null)
                Center(
                  child: Text(
                    'Next stop up: ${session.nextStop!.placeName}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
            ] else ...[
              FilledButton(
                onPressed: () {
                  ref.read(questControllerProvider.notifier).startQuest(quest);
                },
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text(
                  'Start This Quest',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildStopRow(int index, QuestStop stop, ActiveQuestState? session, bool isCompleted) {
    final isDone = isCompleted || (session != null && session.progress.stopsCompleted.contains(index));
    final isCurrent = session != null && !isCompleted && session.currentStopIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: isCurrent ? const EdgeInsets.all(10) : EdgeInsets.zero,
        decoration: isCurrent
            ? BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: isDone
                  ? AppColors.success
                  : isCurrent
                      ? AppColors.primary
                      : AppColors.surfaceSecondary,
              child: isDone
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                      '${stop.stopNumber}',
                      style: TextStyle(
                        color: isCurrent ? Colors.white : AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stop.placeName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: isDone ? AppColors.textMuted : AppColors.text,
                            decoration: isDone ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: const Text(
                            'CURRENT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stop.task,
                    style: TextStyle(
                      fontSize: 12,
                      color: isCurrent ? AppColors.text : AppColors.textMuted,
                      fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({
    required this.quest,
    required this.session,
    required this.isCompleted,
    required this.onTap,
  });

  final Quest quest;
  final ActiveQuestState? session;
  final bool isCompleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: session != null && !isCompleted
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.border,
            width: session != null && !isCompleted ? 1.5 : 1.0,
          ),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              child: Stack(
                children: [
                  AppImage(
                    url: quest.coverImageUrl,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        quest.difficulty.label,
                        style: TextStyle(
                          color: quest.difficulty.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: isCompleted
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: const Text(
                              'COMPLETED 🏆',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          )
                        : session != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Text(
                                  'STOP ${session!.currentStopIndex + 1} OF ${session!.totalStops}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Text(
                                  '+${quest.reward?.xpPoints ?? 250} XP',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quest.title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    quest.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(quest.durationLabel, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      const SizedBox(width: 12),
                      const Icon(Icons.place_outlined, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('${quest.stopCount} stops', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      const Spacer(),
                      Text(
                        isCompleted
                            ? 'Completed ✓'
                            : session != null
                                ? 'Continue Quest →'
                                : 'Start Quest →',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: isCompleted ? AppColors.success : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }
}
