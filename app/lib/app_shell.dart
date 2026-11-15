import 'package:flutter/material.dart';

import 'app_state.dart';
import 'features/farm/farm_screen.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/outlook/outlook_screen.dart';
import 'l10n/app_localizations.dart';
import 'theme/theme.dart';

/// Main app scaffold: four tabs kept alive in an [IndexedStack].
///
/// Tracker lifecycle: refreshes (POWER sync + replay + notifications) on
/// start, when the app resumes and whenever the My farm tab is opened. The
/// refresh runs in the background ([AppState.refreshTracker] never throws
/// and overlapping calls share one run), so the UI never waits on the
/// network.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static const int homeTab = 0;
  static const int farmTab = 3;

  /// Switches the enclosing shell to [index] (no-op outside a shell).
  static void selectTab(BuildContext context, int index) =>
      context.findAncestorStateOfType<_AppShellState>()?._select(index);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() => AppScope.of(context).refreshTracker().ignore();

  void _select(int i) {
    if (i == AppShell.farmTab && i != _index) _refresh();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AniColors.cream,
      body: IndexedStack(
        index: _index,
        children: const [HomeScreen(), OutlookScreen(), LibraryScreen(), FarmScreen()],
      ),
      bottomNavigationBar: AniBottomNav(
        currentIndex: _index,
        onTap: _select,
        items: [
          AniNavItem(Icons.home_outlined, l.navHome),
          AniNavItem(Icons.wb_sunny_outlined, l.navOutlook),
          AniNavItem(Icons.eco_outlined, l.navCrops),
          AniNavItem(Icons.agriculture_outlined, l.navMyFarm),
        ],
      ),
    );
  }
}
