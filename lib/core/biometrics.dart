import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

abstract class BiometricAuthService {
  Future<bool> isSupported();
  Future<bool> authenticate({required String localizedReason});
}

class LocalBiometricAuthService implements BiometricAuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isSupported() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
