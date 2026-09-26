import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../context/application/discovery_context_controller.dart';
import '../../../recommendations/application/recommendation_controller.dart';

/// Natural-language search entry point.
class DiscoverySearch extends ConsumerStatefulWidget {
  const DiscoverySearch({super.key});

  @override
  ConsumerState<DiscoverySearch> createState() => _DiscoverySearchState();
}

class _DiscoverySearchState extends ConsumerState<DiscoverySearch> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search() {
    final controller = ref.read(discoveryContextProvider.notifier);
    controller.setQuery(_controller.text);
    _focus.unfocus();
    showAppToast(
      context,
      'Re-ranked against your constraints',
      icon: Icons.manage_search_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final stacked = width < 640;

    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText:
            'e.g. indoor places near Fort under ₹800, or something local…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: IconButton(
          tooltip: 'Voice search',
          onPressed: () {
            const sample = 'Something indoor and cheap near Fort';
            _controller.text = sample;
            ref.read(discoveryContextProvider.notifier).setQuery(sample);
          },
          icon: const Icon(Icons.mic_none_rounded, size: 20),
        ),
      ),
    );

    return AppPanel(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No wrapping Row: AppBadge ellipsises internally when it is given a
          // bounded width, but a Row would force it to its intrinsic width and
          // overflow the panel on narrow screens.
          const AppBadge(
            label: 'FEASIBILITY-FIRST DISCOVERY',
            color: AppColors.violet,
            icon: Icons.auto_awesome_rounded,
          ),
          const SizedBox(height: 12),
          Text(
            'What do you want to experience?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              'Tell us where you are and what you can give it. You get the '
              'experiences you can realistically finish — not everything nearby.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          if (stacked)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field,
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Find experiences'),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Find experiences'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Entry point to the assistant, used on the Explore surface.
class AssistantEntryCard extends ConsumerWidget {
  const AssistantEntryCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(recommendationCountsProvider);
    final discovery = ref.watch(discoveryContextProvider);

    return AppPanel(
      padding: EdgeInsets.zero,
      color: AppColors.navy,
      elevated: false,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          gradient: AppColors.brandWash,
        ),
        child: Stack(
          children: [
            Positioned(
              right: -34,
              top: -34,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Ask LocalIQ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'It works from the same ranking as this page — '
                    '${counts.feasible} feasible, ${counts.partial} partial, '
                    '${counts.blocked} blocked for your '
                    '${discovery.timeLabel} window. Ask for indoor, cheaper, '
                    'local gems or a one-hour plan.',
                    style: const TextStyle(
                      color: Color(0xFFCFDCF4),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => context.push('/travel-buddy'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      minimumSize: const Size(0, 40),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: const Text('Open assistant'),
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
