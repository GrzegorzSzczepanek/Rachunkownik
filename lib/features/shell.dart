import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/localization.dart';
import '../core/theme.dart';
import 'scan_flow.dart';

/// Bottom navigation per design/Main: 84 px bar, four tabs and a 70 px scanner button with a
/// 6 px ring that rises 28 px above it. Wide screens keep a left rail.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _navHeight = 84.0, _scanSize = 70.0, _scanRise = 28.0;

  void _go(int i) => shell.goBranch(i, initialLocation: true);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final items = [
      (Icons.home_outlined, Icons.home, s.tabOverview),
      (Icons.receipt_long_outlined, Icons.receipt_long, s.tabReceipts),
      (Icons.repeat, Icons.repeat, s.tabSubscriptions),
      (Icons.tune, Icons.tune, s.tabSettings),
    ];

    if (MediaQuery.sizeOf(context).width >= 900) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Row(children: [
          NavigationRail(
            extended: true,
            backgroundColor: AppColors.bg,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(8, 24, 8, 16),
              child: Text(s.appName, style: display(24)),
            ),
            trailing: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(onPressed: () => startScan(context), icon: const Icon(Icons.add), label: Text(s.addReceipt)),
            ),
            destinations: [
              for (final i in items) NavigationRailDestination(icon: Icon(i.$1), selectedIcon: Icon(i.$2), label: Text(i.$3)),
            ],
          ),
          Expanded(child: shell),
        ]),
      );
    }

    final inset = MediaQuery.of(context).padding.bottom;
    final navTotal = _navHeight + inset;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        Column(children: [
          Expanded(child: shell),
          Container(
            height: navTotal,
            padding: EdgeInsets.fromLTRB(8, 0, 8, inset),
            decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _tab(0, items[0]),
              _tab(1, items[1]),
              const SizedBox(width: 92),
              _tab(2, items[2]),
              _tab(3, items[3]),
            ]),
          ),
        ]),
        Positioned(
          left: 0,
          right: 0,
          bottom: navTotal - (_scanSize - _scanRise),
          child: Center(
            child: Semantics(
              button: true,
              label: s.addReceipt,
              child: GestureDetector(
                onTap: () => startScan(context),
                child: Container(
                  width: _scanSize,
                  height: _scanSize,
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 6)),
                  child: Icon(Icons.document_scanner_outlined, size: 28, color: AppColors.onAccent),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tab(int i, (IconData, IconData, String) item) {
    final sel = shell.currentIndex == i;
    final color = sel ? AppColors.accent : AppColors.text2;
    return Expanded(
      child: Semantics(
        button: true,
        selected: sel,
        label: item.$3,
        child: InkWell(
          onTap: () => _go(i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(sel ? item.$2 : item.$1, size: 24, color: color),
                const SizedBox(height: 3),
                Text(item.$3, style: fig(12, weight: sel ? 700 : 600, color: color)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
