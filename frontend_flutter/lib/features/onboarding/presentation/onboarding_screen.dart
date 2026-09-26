import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/onboarding_providers.dart';
import '../domain/onboarding.dart';

/// The taste conversation: a short, warm exchange in the voice of a seasoned
/// maître d'. Every answer teaches the recommender something, and the last
/// screen shows the taste profile it built.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _messages = <_Message>[];
  final _selections = <String>{};

  OnboardingStep? _step;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Frictionless: a guest session is enough to learn the taste profile.
      final auth = ref.read(authServiceProvider);
      if (auth.currentUser == null) {
        await auth.continueAsGuest();
      }
      final step = await ref.read(onboardingRepositoryProvider).start();
      _applyStep(step, opening: true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyStep(OnboardingStep step, {bool opening = false}) {
    setState(() {
      _step = step;
      _selections.clear();
      if (step.ack != null && !opening) {
        _messages.add(_Message(step.ack!, fromHost: true));
      }
      if (step.prompt != null) {
        _messages.add(_Message(step.prompt!, fromHost: true));
      }
    });
    _autoScroll();
  }

  Future<void> _submit({String? message, List<String> selections = const []}) async {
    final step = _step;
    if (step?.sessionId == null || step!.done) return;
    final label = message ?? selections.join(', ');
    if (label.trim().isNotEmpty) {
      setState(() => _messages.add(_Message(label, fromHost: false)));
    }
    setState(() => _busy = true);
    try {
      final next = await ref.read(onboardingRepositoryProvider).answer(
            step.sessionId!,
            message: message,
            selections: selections,
          );
      _input.clear();
      _applyStep(next);
    } catch (error) {
      if (mounted) {
        showAppToast(context, '$error', icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onOption(String option) {
    final step = _step;
    if (step == null) return;
    if (step.multi) {
      setState(() {
        if (!_selections.add(option)) _selections.remove(option);
      });
      return;
    }
    _submit(selections: [option]);
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('A word before we begin'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/explore'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              if (step != null && !step.done) _ProgressBar(step: step),
              Expanded(
                child: _error != null
                    ? _ErrorState(message: _error!, onRetry: _begin)
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                        children: [
                          const _MaitreCard(),
                          const SizedBox(height: 16),
                          for (final message in _messages) _Bubble(message: message),
                          if (_busy)
                            const Padding(
                              padding: EdgeInsets.only(left: 8, top: 6),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                        ],
                      ),
              ),
              if (step != null && step.done)
                _TasteSummary(taste: step.taste)
              else if (step != null && !_busy)
                _Composer(
                  step: step,
                  controller: _input,
                  selections: _selections,
                  onOption: _onOption,
                  onSubmitText: () => _submit(message: _input.text),
                  onSubmitMulti: () => _submit(selections: _selections.toList()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message {
  const _Message(this.text, {required this.fromHost});
  final String text;
  final bool fromHost;
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: step.progress.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.violet),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${step.step} / ${step.totalSteps}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MaitreCard extends StatelessWidget {
  const _MaitreCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.violet.withValues(alpha: 0.14),
            AppColors.blue.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant_menu_rounded, color: AppColors.violet),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your table is ready',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                SizedBox(height: 2),
                Text(
                  'A few questions and I will remember your taste for every '
                  'recommendation that follows.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final host = message.fromHost;
    return Align(
      alignment: host ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: host ? AppColors.surface : AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.lg),
            topRight: const Radius.circular(AppRadius.lg),
            bottomLeft: Radius.circular(host ? 4 : AppRadius.lg),
            bottomRight: Radius.circular(host ? AppRadius.lg : 4),
          ),
          border: host ? Border.all(color: AppColors.border) : null,
          boxShadow: AppShadows.card,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: host ? AppColors.text : Colors.white,
            fontWeight: host ? FontWeight.w500 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.step,
    required this.controller,
    required this.selections,
    required this.onOption,
    required this.onSubmitText,
    required this.onSubmitMulti,
  });

  final OnboardingStep step;
  final TextEditingController controller;
  final Set<String> selections;
  final ValueChanged<String> onOption;
  final VoidCallback onSubmitText;
  final VoidCallback onSubmitMulti;

  @override
  Widget build(BuildContext context) {
    final hasOptions = step.options.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasOptions)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in step.options)
                  GestureDetector(
                    onTap: () => onOption(option),
                    child: AnimatedContainer(
                      duration: AppMotion.fast,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: selections.contains(option)
                            ? AppColors.primary
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: selections.contains(option)
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selections.contains(option)
                              ? Colors.white
                              : AppColors.text,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          if (hasOptions && step.multi) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: selections.isEmpty ? null : onSubmitMulti,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                child: const Text('Continue'),
              ),
            ),
          ],
          if (step.freeText) ...[
            if (hasOptions) const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmitText(),
                    decoration: const InputDecoration(
                      hintText: 'Type your answer...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onSubmitText,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TasteSummary extends StatelessWidget {
  const _TasteSummary({required this.taste});

  final TasteSnapshot? taste;

  @override
  Widget build(BuildContext context) {
    final snapshot = taste;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Your taste is set',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              if (snapshot != null)
                AppBadge(
                  label: '${snapshot.tagCount} SIGNALS',
                  color: AppColors.violet,
                  dense: true,
                ),
            ],
          ),
          if (snapshot != null && snapshot.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              snapshot.text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (snapshot != null && snapshot.likes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in snapshot.likes.take(10))
                  AppBadge(label: tag.replaceAll('_', ' '), color: AppColors.primary, dense: true),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/explore'),
              icon: const Icon(Icons.explore_rounded, size: 18),
              label: const Text('See what I recommend'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
