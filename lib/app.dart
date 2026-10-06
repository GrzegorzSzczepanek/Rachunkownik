import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_update.dart';
import 'core/biometric_lock_gate.dart';
import 'core/localization.dart';
import 'core/theme.dart';
import 'features/analytics_screen.dart';
import 'features/api_provider_screen.dart';
import 'features/import_screen.dart';
import 'features/local_models_screen.dart';
import 'features/overview_screen.dart';
import 'features/receipts_screen.dart';
import 'features/settings_screen.dart';
import 'features/shell.dart';
import 'features/subscriptions_screen.dart';
import 'providers.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/analytics', builder: (_, _) => const AnalyticsScreen()),
    GoRoute(path: '/import', builder: (_, _) => const ImportScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (_, _) => const OverviewScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/receipts', builder: (_, _) => const ReceiptsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/subscriptions', builder: (_, _) => const SubscriptionsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
            routes: [
              GoRoute(path: 'api', builder: (_, _) => const ApiProviderScreen()),
              GoRoute(path: 'models', builder: (_, _) => const LocalModelsScreen()),
            ],
          ),
        ]),
      ],
    ),
  ],
);

class RachunkownikApp extends ConsumerStatefulWidget {
  const RachunkownikApp({super.key});

  @override
  ConsumerState<RachunkownikApp> createState() => _RachunkownikAppState();
}

class _RachunkownikAppState extends ConsumerState<RachunkownikApp> with WidgetsBindingObserver {
  bool _checkedUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Rebuild reminders at launch (an old schedule may have run out).
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(notificationSyncProvider).run());
    _checkAutoUpdate();
  }

  void _checkAutoUpdate() {
    if (_checkedUpdate) return;
    _checkedUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final client = ref.read(appUpdateClientProvider);
        final update = await client.checkForUpdate();
        if (update != null && update.hasUpdate && mounted) {
          final navCtx = _router.routerDelegate.navigatorKey.currentContext;
          if (navCtx != null && navCtx.mounted) {
            showUpdateDialog(navCtx, update);
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Local models hold gigabytes of RAM; give them back when we leave the screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(localRuntimeProvider).release();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Any change to receipts, imports or subscriptions can move a budget or a renewal.
    ref.listen(dataVersionProvider, (_, _) => ref.read(notificationSyncProvider).run());
    return _app(context);
  }

  Widget _app(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    return MaterialApp.router(
      title: s.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
      builder: (context, child) => BiometricLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
