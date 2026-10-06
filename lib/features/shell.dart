import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import 'scan_flow.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Przegląd'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Paragony'),
    (Icons.repeat, Icons.repeat, 'Subskrypcje'),
    (Icons.tune, Icons.tune, 'Ustawienia'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: true,
            backgroundColor: Colors.white,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            leading: const Padding(
              padding: EdgeInsets.fromLTRB(8, 24, 8, 16),
              child: Text('Paragon', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            trailing: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => startScan(context),
                icon: const Icon(Icons.add),
                label: const Text('Dodaj paragon'),
              ),
            ),
            destinations: [
              for (final i in _items)
                NavigationRailDestination(icon: Icon(i.$1), selectedIcon: Icon(i.$2), label: Text(i.$3)),
            ],
          ),
          Expanded(child: shell),
        ]),
      );
    }
    return Scaffold(
      body: SafeArea(bottom: false, child: shell),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () => startScan(context),
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.document_scanner_outlined, size: 30),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        height: 72,
        padding: EdgeInsets.zero,
        shape: const CircularNotchedRectangle(),
        child: Row(children: [
          _tab(0), _tab(1),
          const Spacer(),
          _tab(2), _tab(3),
        ]),
      ),
    );
  }

  Widget _tab(int i) {
    final sel = shell.currentIndex == i;
    final color = sel ? AppColors.green : AppColors.muted;
    return Expanded(
      flex: 2,
      child: InkWell(
        onTap: () => _go(i),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(sel ? _items[i].$2 : _items[i].$1, color: color),
          const SizedBox(height: 2),
          Text(_items[i].$3,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}
