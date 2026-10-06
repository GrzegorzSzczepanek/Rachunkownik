import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/core/biometric_lock_gate.dart';
import 'package:rachunkownik/core/biometrics.dart';
import 'package:rachunkownik/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBiometricAuthService implements BiometricAuthService {
  bool supported = true;
  bool nextResult = true;
  int authCount = 0;
  String? lastReason;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    authCount++;
    lastReason = localizedReason;
    return nextResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiometricLockNotifier', () {
    test('toggling on requires successful auth', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeAuth = FakeBiometricAuthService();
      final container = ProviderContainer(
        overrides: [
          biometricAuthProvider.overrideWithValue(fakeAuth),
          initialBiometricLockProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // 1. Try enable when auth succeeds
      fakeAuth.nextResult = true;
      final notifier = container.read(biometricLockProvider.notifier);
      final ok1 = await notifier.setEnabled(true);
      expect(ok1, isTrue);
      expect(fakeAuth.authCount, 1);
      expect(container.read(biometricLockProvider), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(BiometricLockNotifier.prefKey), isTrue);

      // 2. Try disable when auth fails
      fakeAuth.nextResult = false;
      final ok2 = await notifier.setEnabled(false);
      expect(ok2, isFalse);
      expect(fakeAuth.authCount, 2);
      expect(container.read(biometricLockProvider), isTrue);
      expect(prefs.getBool(BiometricLockNotifier.prefKey), isTrue);

      // 3. Disable when auth succeeds
      fakeAuth.nextResult = true;
      final ok3 = await notifier.setEnabled(false);
      expect(ok3, isTrue);
      expect(container.read(biometricLockProvider), isFalse);
      expect(prefs.getBool(BiometricLockNotifier.prefKey), isFalse);
    });
  });

  group('BiometricLockGate widget', () {
    testWidgets('renders child immediately when lock is disabled', (tester) async {
      final fakeAuth = FakeBiometricAuthService();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          biometricAuthProvider.overrideWithValue(fakeAuth),
          initialBiometricLockProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          home: BiometricLockGate(
            child: Text('Sekretna treść'),
          ),
        ),
      ));

      expect(find.text('Sekretna treść'), findsOneWidget);
      expect(find.text('Odblokuj'), findsNothing);
      expect(fakeAuth.authCount, 0);
    });

    testWidgets('blocks child and prompts unlock when lock is enabled', (tester) async {
      final fakeAuth = FakeBiometricAuthService();
      fakeAuth.nextResult = false; // Initially user cancels or fails auth

      await tester.pumpWidget(ProviderScope(
        overrides: [
          biometricAuthProvider.overrideWithValue(fakeAuth),
          initialBiometricLockProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(
          home: BiometricLockGate(
            child: Text('Sekretna treść'),
          ),
        ),
      ));

      // Post-frame callback triggers initial auth
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Sekretna treść'), findsNothing);
      expect(find.text('Aplikacja jest zabezpieczona blokadą biometryczną.'), findsOneWidget);
      expect(find.text('Odblokuj'), findsOneWidget);

      // Now user taps "Odblokuj" and succeeds
      fakeAuth.nextResult = true;
      await tester.tap(find.text('Odblokuj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Sekretna treść'), findsOneWidget);
      expect(find.text('Odblokuj'), findsNothing);
    });
  });
}
