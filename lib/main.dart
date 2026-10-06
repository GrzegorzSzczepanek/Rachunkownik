import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_settings.dart';
import 'ai/edge_runtime.dart';
import 'app.dart';
import 'core/localization.dart';
import 'data/db.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  final settings = await AiSettingsStore().load();
  final engineReady = await initEdgeAi();
  final prefs = await SharedPreferences.getInstance();
  final biometricLock = prefs.getBool(BiometricLockNotifier.prefKey) ?? false;
  final appLanguage = await AppLanguageNotifier.load();
  runApp(ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(db),
      initialAiSettingsProvider.overrideWithValue(settings),
      engineReadyProvider.overrideWithValue(engineReady),
      initialBiometricLockProvider.overrideWithValue(biometricLock),
      initialAppLanguageProvider.overrideWithValue(appLanguage),
    ],
    child: const RachunkownikApp(),
  ));
}
