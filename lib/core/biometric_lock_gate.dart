import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'localization.dart';
import 'theme.dart';

/// Wraps the app content and displays a lock screen whenever biometric
/// lock is enabled and the user has not yet authenticated.
class BiometricLockGate extends ConsumerStatefulWidget {
  const BiometricLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends ConsumerState<BiometricLockGate> with WidgetsBindingObserver {
  late bool _unlocked;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final isLocked = ref.read(biometricLockProvider);
    _unlocked = !isLocked;
    if (isLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final isLocked = ref.read(biometricLockProvider);
      if (isLocked && _unlocked) {
        setState(() => _unlocked = false);
      }
    } else if (state == AppLifecycleState.resumed) {
      final isLocked = ref.read(biometricLockProvider);
      if (isLocked && !_unlocked && !_authenticating) {
        _authenticate();
      }
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    try {
      final auth = ref.read(biometricAuthProvider);
      final ok = await auth.authenticate(localizedReason: 'Odblokuj dostęp do aplikacji Rachunkownik');
      if (mounted) {
        setState(() {
          _unlocked = ok;
          _authenticating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _authenticating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockEnabled = ref.watch(biometricLockProvider);
    if (!lockEnabled || _unlocked) {
      return widget.child;
    }

    final str = ref.watch(appStringsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.green.withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.green),
                ),
                const SizedBox(height: 28),
                Text(
                  str.appName,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  str.isEnglish
                      ? 'The app is secured with biometric lock.'
                      : 'Aplikacja jest zabezpieczona blokadą biometryczną.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: AppColors.muted),
                ),
                const SizedBox(height: 36),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _authenticating ? null : _authenticate,
                  icon: _authenticating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint_rounded, size: 24),
                  label: Text(
                    _authenticating
                        ? (str.isEnglish ? 'Verifying...' : 'Weryfikacja...')
                        : str.unlock,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
