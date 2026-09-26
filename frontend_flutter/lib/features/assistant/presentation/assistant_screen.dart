import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../context/application/discovery_context_controller.dart';
import '../../itinerary/application/itinerary_controller.dart';
import '../../recommendations/application/recommendation_controller.dart';
import '../../recommendations/presentation/widgets/recommendation_card.dart';
import '../application/assistant_controller.dart';
import '../domain/chat_message.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(assistantControllerProvider.notifier).initialise();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    ref.read(assistantControllerProvider.notifier).send(text);
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppMotion.medium,
        curve: AppMotion.curve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(assistantControllerProvider);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 1120;

    final transcript = ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        Breakpoints.gutter(width),
        16,
        Breakpoints.gutter(width),
        12,
      ),
      itemCount: thread.messages.length,
      itemBuilder: (context, index) {
        return _MessageBlock(
          message: thread.messages[index],
          onOpen: (id) => context.push('/place/$id'),
          onPrompt: _send,
        );
      },
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppColors.brandWash,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ask LocalIQ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Answers from the same live ranking',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New conversation',
            onPressed: () =>
                ref.read(assistantControllerProvider.notifier).reset(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: desktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: transcript),
                const SizedBox(width: 1),
                SizedBox(width: 330, child: _ContextPanel(onPrompt: _send)),
              ],
            )
          : transcript,
      bottomNavigationBar: _Composer(
        controller: _controller,
        onSend: _send,
        starters: ref.read(assistantControllerProvider.notifier).starters,
      ),
    );
  }
}

class _MessageBlock extends ConsumerWidget {
  const _MessageBlock({
    required this.message,
    required this.onOpen,
    required this.onPrompt,
  });

  final ChatMessage message;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(messageRecommendationsProvider(message.recommendationIds));
    final width = MediaQuery.sizeOf(context).width;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment:
            message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width < 560 ? width * 0.9 : 580),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight:
                      message.isUser ? const Radius.circular(5) : null,
                  bottomLeft: message.isUser ? null : const Radius.circular(5),
                ),
                border: message.isUser
                    ? null
                    : Border.all(color: AppColors.border),
                boxShadow: message.isUser ? null : AppShadows.card,
              ),
              child: message.text.isEmpty && message.isStreaming
                  ? const SizedBox(
                      height: 3,
                      width: 90,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: AppColors.border,
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.violet),
                      ),
                    )
                  : Text(
                      message.text,
                      style: TextStyle(
                        color: message.isUser ? Colors.white : AppColors.text,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
            ),
          ),
          if (cards.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < cards.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RecommendationCard(recommendation: cards[i]),
              ),
          ],
          if (message.followUps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final followUp in message.followUps)
                  SelectChip(
                    label: followUp,
                    selected: false,
                    compact: true,
                    tone: AppColors.violet,
                    onTap: () => onPrompt(followUp),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContextPanel extends ConsumerWidget {
  const _ContextPanel({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryContextProvider);
    final counts = ref.watch(recommendationCountsProvider);
    final live = ref.watch(liveContextProvider).value;
    final itinerary = ref.watch(itineraryControllerProvider).value;
    final top = ref.watch(feasibleRecommendationsProvider).take(4).toList();

    return Container(
      color: AppColors.surfaceMuted,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assistant context',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Every answer respects these. The assistant can only cite options '
              'that are currently in your ranking.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),
            AppPanel(
              child: Column(
                children: [
                  _line('Location', discovery.locationLabel),
                  _line('Window', discovery.timeLabel),
                  _line('Budget', discovery.budgetLabel),
                  _line('Group', discovery.groupType.label),
                  _line('Access', discovery.accessibility.label),
                  _line('Conditions', live?.weather.condition.label ?? '—'),
                  _line(
                    'Ranking',
                    '${counts.feasible} / ${counts.total} feasible',
                  ),
                  _line(
                    'Plan',
                    itinerary == null || itinerary.isEmpty
                        ? 'Empty'
                        : '${itinerary.stopCount} stops · ${itinerary.costLabel}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Try asking'),
            const SizedBox(height: 9),
            for (final suggestion in const [
              'I have 2 hours and ₹800',
              'Give me indoor options',
              'Make the plan cheaper',
              'I want more local experiences',
              'What fits in one hour?',
              'What is in my plan?',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppPanel(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  onTap: () => onPrompt(suggestion),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tips_and_updates_outlined,
                        size: 15,
                        color: AppColors.violet,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          suggestion,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (top.isNotEmpty) ...[
              const SizedBox(height: 16),
              const FieldLabel('Currently on top'),
              const SizedBox(height: 9),
              for (var i = 0; i < top.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppPanel(
                    padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                    onTap: () => context.push(
                      '/place/${top[i].experience.id}?place=${top[i].place.id}',
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                top[i].experience.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                              Text(
                                '${top[i].completableMinutes} min · '
                                '${top[i].experience.priceLabel}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.starters,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final List<String> starters;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: starters.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) => SelectChip(
                      label: starters[index],
                      selected: false,
                      compact: true,
                      tone: AppColors.violet,
                      icon: Icons.auto_awesome_rounded,
                      onTap: () => onSend(starters[index]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(controller.text),
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Ask for anything you can actually do…',
                          prefixIcon: Icon(
                            Icons.auto_awesome_rounded,
                            size: 19,
                            color: AppColors.violet,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: () => onSend(controller.text),
                      style: IconButton.styleFrom(minimumSize: const Size(46, 46)),
                      icon: const Icon(Icons.send_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
