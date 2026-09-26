import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data_providers.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/context_strip.dart';
import '../widgets/top_app_bar.dart';
import 'role_shells.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = Breakpoints.isMobile(width);

    if (mobile) {
      return ExplorerShell(navigationShell: navigationShell);
    }

    return Scaffold(
      body: Column(
        children: [
          LocalIqAppBar(currentIndex: navigationShell.currentIndex),
          const ContextStrip(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: null,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/companion'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        tooltip: 'Ask LocalIQ Companion',
        child: const Icon(Icons.auto_awesome_rounded, size: 20),
      ),
    );
  }
}

/// Re-exported for the map service check used by the shell in tests.
bool mapTilesAvailable(WidgetRef ref) =>
    ref.watch(mapServiceProvider).hasTiles;
