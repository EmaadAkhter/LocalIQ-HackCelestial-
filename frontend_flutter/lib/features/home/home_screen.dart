import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import 'widgets/home_widgets.dart';

/// Home / Search — the second reference frame.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _findExperiences(BuildContext context) async {
    final AppState state = context.read<AppState>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    state.showResults();
    await state.findExperiences();
    if (!context.mounted) return;
    final int count = context.read<AppState>().recommendations.length;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'No feasible places for that plan — try more time or budget.'
              : '$count feasible ${count == 1 ? 'place' : 'places'} found.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.md,
                  Insets.page,
                  0,
                ),
                child: const HomeHeader(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.lg,
                  Insets.page,
                  0,
                ),
                child: NaturalLanguageSearchField(
                  value: state.queryDraft,
                  onChanged: state.setQueryDraft,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.md,
                  Insets.page,
                  0,
                ),
                child: LocationCard(
                  location: state.params.location,
                  subtitle: 'Current Location',
                  onTap: () => _showAreaPicker(context),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.md,
                  Insets.page,
                  0,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: StatCard(
                        icon: Icons.schedule_rounded,
                        label: 'Time Available',
                        value: _hoursLabel(state.params.timeHours),
                        onTap: () => _showTimePicker(context, state),
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: StatCard(
                        icon: Icons.account_balance_wallet_rounded,
                        label: 'Budget',
                        value: Fmt.inrExact(state.params.budgetInr),
                        onTap: () => _showBudgetPicker(context, state),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.xl,
                  Insets.page,
                  0,
                ),
                child: InterestSelector(
                  selected: state.params.interests,
                  onToggle: state.toggleInterest,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.xl,
                  Insets.page,
                  0,
                ),
                child: GroupTypeSelector(
                  selected: state.params.groupType,
                  onChanged: state.setGroupType,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.lg,
                  Insets.page,
                  0,
                ),
                child: AccessibilityToggle(
                  value: state.params.accessibility,
                  onChanged: (_) => state.toggleAccessibility(),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.xl,
                  Insets.page,
                  Insets.lg,
                ),
                child: FilledButton(
                  onPressed: state.isSearching
                      ? null
                      : () => _findExperiences(context),
                  child: state.isSearching
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Find Experiences'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _hoursLabel(double hours) {
    final int h = hours.round();
    return h == 1 ? '1 hour' : '$h hours';
  }

  Future<void> _showAreaPicker(BuildContext context) async {
    final AppState state = context.read<AppState>();
    const Map<String, ({double lat, double lng})> areas =
        <String, ({double lat, double lng})>{
          'Bandra, Mumbai': (lat: 19.0596, lng: 72.8295),
          'Andheri, Mumbai': (lat: 19.1197, lng: 72.8464),
          'Colaba, Mumbai': (lat: 18.9067, lng: 72.8147),
          'Juhu, Mumbai': (lat: 19.1075, lng: 72.8263),
          'Powai, Mumbai': (lat: 19.121, lng: 72.9055),
          'Fort, Mumbai': (lat: 18.9328, lng: 72.8303),
        };
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const SheetTitle(title: 'Where are you now?'),
            for (final MapEntry<String, ({double lat, double lng})> entry
                in areas.entries)
              ListTile(
                leading: const Icon(
                  Icons.place_rounded,
                  color: AppColors.primary,
                ),
                title: Text(entry.key),
                onTap: () {
                  state.setLocation(
                    entry.key,
                    entry.value.lat,
                    entry.value.lng,
                  );
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTimePicker(BuildContext context, AppState state) async {
    double selected = state.params.timeHours;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.page,
                0,
                Insets.page,
                Insets.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SheetTitle(title: 'How long do you have?'),
                  Text(
                    _hoursLabel(selected),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Slider(
                    value: selected.clamp(1, 12),
                    min: 1,
                    max: 12,
                    divisions: 11,
                    label: _hoursLabel(selected),
                    onChanged: (double v) => setSheetState(() => selected = v),
                  ),
                  Row(
                    children: <Widget>[
                      for (final int preset in <int>[2, 3, 4, 6, 8])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${preset}h'),
                            selected: selected.round() == preset,
                            onSelected: (_) => setSheetState(
                              () => selected = preset.toDouble(),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Insets.lg),
                  FilledButton(
                    onPressed: () {
                      state.setTimeHours(selected);
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBudgetPicker(BuildContext context, AppState state) async {
    int selected = state.params.budgetInr;
    const List<int> presets = <int>[300, 500, 800, 1500, 2500, 5000];
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.page,
            0,
            Insets.page,
            Insets.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SheetTitle(title: 'What is your budget?'),
              const Text(
                'Total spend for the group, used to filter and rank places.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: Insets.lg),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: <Widget>[
                  for (final int preset in presets)
                    ChoiceChip(
                      label: Text(Fmt.inrExact(preset)),
                      selected: selected == preset,
                      onSelected: (_) => selected = preset,
                    ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              FilledButton(
                onPressed: () {
                  state.setBudget(selected);
                  Navigator.of(sheetContext).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
