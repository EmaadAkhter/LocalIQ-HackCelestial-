import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/guide_onboarding_providers.dart';
import '../domain/guide_onboarding.dart';

/// Fast guide onboarding: three short steps, then a status card.
///
/// Speed is the point — no conversation, just the essentials a reviewer needs:
/// who you are, your two licences, and where/what you guide.
class GuideOnboardingScreen extends ConsumerStatefulWidget {
  const GuideOnboardingScreen({super.key});

  @override
  ConsumerState<GuideOnboardingScreen> createState() =>
      _GuideOnboardingScreenState();
}

class _GuideOnboardingScreenState
    extends ConsumerState<GuideOnboardingScreen> {
  static const _languages = ['en', 'hi', 'mr', 'ta', 'bn', 'gu'];

  // A valid 1x1 PNG used as the demo attachment until a camera/gallery picker
  // is wired in; the backend stores the real bytes either way.
  static final _samplePng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _rate = TextEditingController(text: '1000');

  final _selectedLanguages = <String>{'en'};
  final _areas = <String>{};
  final _niches = <String>{};

  GuideOnboardingStatus? _status;
  int _step = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(guideOnboardingRepositoryProvider);
      final auth = ref.read(authServiceProvider);
      if (auth.currentUser == null) await auth.continueAsGuest();
      final status = await repo.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _name.text = auth.currentUser?.displayName ?? _name.text;
        _areas.addAll(status.areas);
        _niches.addAll(status.niches);
        if (status.started) _step = status.isPending ? 3 : 1;
      });
    } catch (_) {
      // Offline repos never throw here; a remote failure just leaves step 0.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        showAppToast(context, '$error', icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run(() async {
        final status =
            await ref.read(guideOnboardingRepositoryProvider).start(
                  name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                  languages: _selectedLanguages.toList(),
                  bio: _bio.text.trim(),
                );
        if (mounted) {
          setState(() {
            _status = status;
            _step = 1;
          });
        }
      });

  Future<void> _upload(String kind) => _run(() async {
        await ref.read(guideOnboardingRepositoryProvider).uploadDocument(
              kind: kind,
              bytes: _samplePng,
              filename: '$kind.png',
              contentType: 'image/png',
            );
        final status = await ref.read(guideOnboardingRepositoryProvider).status();
        if (mounted) setState(() => _status = status);
      });

  Future<void> _submit() => _run(() async {
        final status = await ref.read(guideOnboardingRepositoryProvider).apply(
              areas: _areas.toList(),
              niches: _niches.toList(),
              ratePerHour: int.tryParse(_rate.text.trim()),
              bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
              languages: _selectedLanguages.toList(),
            );
        if (mounted) {
          setState(() {
            _status = status;
            _step = 3;
          });
        }
      });

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final options = ref.watch(guideOptionsProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Become a guide'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (status == null || !status.started)
                _IntroCard(onStart: _start, busy: _busy)
              else if (status.isPending || status.isVerified || status.isRejected)
                _StatusCard(status: status)
              else ...[
                _Stepper(step: _step),
                const SizedBox(height: 16),
                if (_step == 0)
                  _InfoStep(
                    name: _name,
                    bio: _bio,
                    languages: _languages,
                    selectedLanguages: _selectedLanguages,
                    onToggleLanguage: (value) => setState(() {
                      if (!_selectedLanguages.add(value)) {
                        _selectedLanguages.remove(value);
                      }
                    }),
                    onNext: _start,
                    busy: _busy,
                  )
                else if (_step == 1)
                  _DocumentsStep(
                    hasDriverLicense: status.hasDriverLicense,
                    hasGuideLicense: status.hasGuideLicense,
                    busy: _busy,
                    onUpload: _upload,
                    onNext: () => setState(() => _step = 2),
                  )
                else
                  options.when(
                    data: (data) => _AreasStep(
                      areas: data.areas,
                      niches: data.niches,
                      selectedAreas: _areas,
                      selectedNiches: _niches,
                      rate: _rate,
                      onToggleArea: (value) => setState(() {
                        if (!_areas.add(value)) _areas.remove(value);
                      }),
                      onToggleNiche: (value) => setState(() {
                        if (!_niches.add(value)) _niches.remove(value);
                      }),
                      onSubmit: _submit,
                      busy: _busy,
                      canSubmit: status.canSubmit,
                    ),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (error, _) => Text('Could not load options: $error'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.onStart, required this.busy});

  final VoidCallback onStart;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, color: AppColors.violet),
              SizedBox(width: 10),
              Text(
                'Start earning in three steps',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tell us who you are, attach your driver\u2019s licence and guide '
            'licence, then pick the areas and specialities you cover. Review is '
            'fast, and you can publish as soon as you are approved.',
            style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onStart,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Begin'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});

  final int step;

  static const _labels = ['Details', 'Documents', 'Areas'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: i <= step ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (i < _labels.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _InfoStep extends StatelessWidget {
  const _InfoStep({
    required this.name,
    required this.bio,
    required this.languages,
    required this.selectedLanguages,
    required this.onToggleLanguage,
    required this.onNext,
    required this.busy,
  });

  final TextEditingController name;
  final TextEditingController bio;
  final List<String> languages;
  final Set<String> selectedLanguages;
  final ValueChanged<String> onToggleLanguage;
  final VoidCallback onNext;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            title: 'Your details',
            subtitle: 'How guests will see you',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bio,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Short bio',
              hintText: 'A line about how you guide.',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Languages you guide in',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final language in languages)
                _Chip(
                  label: language.toUpperCase(),
                  selected: selectedLanguages.contains(language),
                  onTap: () => onToggleLanguage(language),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : onNext,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentsStep extends StatelessWidget {
  const _DocumentsStep({
    required this.hasDriverLicense,
    required this.hasGuideLicense,
    required this.busy,
    required this.onUpload,
    required this.onNext,
  });

  final bool hasDriverLicense;
  final bool hasGuideLicense;
  final bool busy;
  final ValueChanged<String> onUpload;
  final VoidCallback onNext;

  bool get _ready => hasDriverLicense && hasGuideLicense;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            title: 'Licences',
            subtitle: 'Two documents, then you are ready to submit',
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 14),
          _DocTile(
            label: "Driver's licence",
            uploaded: hasDriverLicense,
            busy: busy,
            onTap: () => onUpload('driver_license'),
          ),
          const SizedBox(height: 10),
          _DocTile(
            label: 'Guide licence',
            uploaded: hasGuideLicense,
            busy: busy,
            onTap: () => onUpload('guide_license'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Demo build attaches a placeholder image. The camera / gallery '
            'picker drops into the same upload call.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (!_ready || busy) ? null : onNext,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.label,
    required this.uploaded,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool uploaded;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = uploaded ? AppColors.success : AppColors.border;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: uploaded
              ? AppColors.success.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            Icon(
              uploaded ? Icons.check_circle_rounded : Icons.upload_file_rounded,
              color: uploaded ? AppColors.success : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ),
            Text(
              uploaded ? 'Uploaded' : 'Attach',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: uploaded ? AppColors.success : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreasStep extends StatelessWidget {
  const _AreasStep({
    required this.areas,
    required this.niches,
    required this.selectedAreas,
    required this.selectedNiches,
    required this.rate,
    required this.onToggleArea,
    required this.onToggleNiche,
    required this.onSubmit,
    required this.busy,
    required this.canSubmit,
  });

  final List<String> areas;
  final List<String> niches;
  final Set<String> selectedAreas;
  final Set<String> selectedNiches;
  final TextEditingController rate;
  final ValueChanged<String> onToggleArea;
  final ValueChanged<String> onToggleNiche;
  final VoidCallback onSubmit;
  final bool busy;
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            title: 'Where and what you guide',
            subtitle: 'Pick the areas and specialities you cover',
            icon: Icons.map_outlined,
          ),
          const SizedBox(height: 14),
          const Text('Areas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final area in areas)
                _Chip(
                  label: area,
                  selected: selectedAreas.contains(area),
                  onTap: () => onToggleArea(area),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Specialities', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final niche in niches)
                _Chip(
                  label: niche.replaceAll('_', ' '),
                  selected: selectedNiches.contains(niche),
                  onTap: () => onToggleNiche(niche),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: rate,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Hourly rate (INR)',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (busy || !canSubmit || selectedAreas.isEmpty) ? null : onSubmit,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Submit application'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final GuideOnboardingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.isVerified
        ? AppColors.success
        : status.isRejected
            ? AppColors.danger
            : AppColors.warning;
    final icon = status.isVerified
        ? Icons.verified_rounded
        : status.isRejected
            ? Icons.error_outline_rounded
            : Icons.hourglass_top_rounded;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.verificationLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                    Text(
                      status.isVerified
                          ? 'You are published and can accept trips.'
                          : status.isRejected
                              ? 'Please review the notes and resubmit.'
                              : 'Most applications are reviewed within a day.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (status.areas.isNotEmpty) ...[
            const Text('Areas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final area in status.areas)
                  AppBadge(label: area, color: AppColors.primary, dense: true),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (status.niches.isNotEmpty) ...[
            const Text('Specialities', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final niche in status.niches)
                  AppBadge(label: niche.replaceAll('_', ' '), color: AppColors.violet, dense: true),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (status.adminNotes != null && status.adminNotes!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerSurface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                status.adminNotes!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/driver'),
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text('Open my trips'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
          ),
        ],
      ),
    );
  }
}
