import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_settings.dart';
import 'ai/edge_runtime.dart';
import 'ai/embeddings.dart';
import 'ai/local_models.dart';
import 'ai/llm_api.dart';
import 'ai/local_runtime.dart';
import 'ai/receipt_extractor.dart';
import 'ai/spending_chat.dart';
import 'core/app_update.dart';
import 'core/biometrics.dart';
import 'data/db.dart';
import 'notifications/notification_gateway.dart';
import 'notifications/notification_sync.dart';
import 'domain/models.dart';
import 'domain/subscription_detector.dart';

final appUpdateClientProvider = Provider<AppUpdateClient>((ref) => GitHubUpdateClient());

final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError('override in main'));
final settingsStoreProvider = Provider<AiSettingsStore>((ref) => AiSettingsStore());
final initialAiSettingsProvider =
    Provider<AiSettings>((ref) => throw UnimplementedError('override in main'));
/// Whether the on-device engine initialised (set in main()).
final engineReadyProvider = Provider<bool>((ref) => false);

final notificationGatewayProvider = Provider<NotificationGateway>((ref) => LocalNotificationGateway());
final notificationSyncProvider =
    Provider<NotificationSync>((ref) => NotificationSync(ref.read(dbProvider), ref.read(notificationGatewayProvider)));

final biometricAuthProvider = Provider<BiometricAuthService>((ref) => LocalBiometricAuthService());
final initialBiometricLockProvider = Provider<bool>((ref) => false);

class BiometricLockNotifier extends Notifier<bool> {
  static const prefKey = 'security.biometric_lock';

  @override
  bool build() => ref.watch(initialBiometricLockProvider);

  Future<bool> setEnabled(bool enable) async {
    final auth = ref.read(biometricAuthProvider);
    final reason = enable
        ? 'Potwierdź tożsamość, aby włączyć blokadę biometryczną'
        : 'Potwierdź tożsamość, aby wyłączyć blokadę biometryczną';
    final ok = await auth.authenticate(localizedReason: reason);
    if (!ok) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, enable);
    state = enable;
    return true;
  }
}

final biometricLockProvider = NotifierProvider<BiometricLockNotifier, bool>(BiometricLockNotifier.new);

final localRuntimeProvider = Provider<LocalRuntime>((ref) {
  final ready = ref.watch(engineReadyProvider);
  if (!ready) return const UnavailableLocalRuntime();
  return EdgeAiRuntime(
    engineReady: true,
    activate: ref.read(modelDownloadsProvider.notifier).activateInEngine,
  );
});

/// Bumped after every write so the read providers below refetch.
class DataVersion extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final dataVersionProvider = NotifierProvider<DataVersion, int>(DataVersion.new);

class AiSettingsController extends Notifier<AiSettings> {
  @override
  AiSettings build() => ref.watch(initialAiSettingsProvider);

  AiSettingsStore get _store => ref.read(settingsStoreProvider);

  Future<void> _update(AiSettings s) async {
    state = s;
    await _store.save(s);
  }

  Future<void> setEngine(AiTask t, AiEngine e) =>
      _update(state.copyWith(engines: {...state.engines, t: e}));

  Future<void> setApi(ApiConfig c) => _update(state.copyWith(api: c));
  Future<void> setPrivacy(PrivacySettings p) => _update(state.copyWith(privacy: p));
  Future<String?> readKey() => _store.readKey();
  Future<void> writeKey(String? k) => _store.writeKey(k);

  Future<void> addTokens(int n) async {
    await _store.addTokens(n);
    state = state.copyWith(monthlyTokens: state.monthlyTokens + n);
  }

  Future<LlmApi?> llm() async {
    final cfg = state.api;
    if (cfg.baseUrl.isEmpty || cfg.model.isEmpty) return null;
    final key = await readKey();
    if (cfg.preset.needsKey && (key == null || key.isEmpty)) return null;
    return buildLlmApi(cfg, key);
  }

  Future<ReceiptExtractor> extractor() async => ReceiptExtractor(
        settings: state,
        llm: await llm(),
        local: ref.read(localRuntimeProvider),
        onTokens: addTokens,
      );

  /// Embeddings run on the provider only when the task is set to API, the
  /// provider speaks the OpenAI format and an embedding model is named.
  Future<Embedder?> embedder() async {
    final cfg = state.api;
    if (state.engineFor(AiTask.embeddings) != AiEngine.api ||
        cfg.format != ApiFormat.openai ||
        cfg.embeddingModel.isEmpty ||
        cfg.baseUrl.isEmpty) {
      return null;
    }
    final key = await readKey();
    if (cfg.preset.needsKey && (key == null || key.isEmpty)) return null;
    return OpenAiEmbedder(cfg, key);
  }

  Future<SpendingChat> chat() async => SpendingChat(
        db: ref.read(dbProvider),
        settings: state,
        llm: await llm(),
        local: ref.read(localRuntimeProvider),
        embedder: await embedder(),
      );
}

final aiSettingsProvider =
    NotifierProvider<AiSettingsController, AiSettings>(AiSettingsController.new);

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1);

class MonthSummary {
  MonthSummary(this.month, this.spent, this.byCategory, this.budgets);
  final DateTime month;
  final int spent;
  final Map<String, int> byCategory;
  final List<Budget> budgets;

  int get budgetTotal => budgets.fold(0, (a, b) => a + b.limitCents);
  int get remaining => budgetTotal - spent;
  int get withoutBudget => byCategory.entries
      .where((e) => !budgets.any((b) => b.category == e.key))
      .fold(0, (a, e) => a + e.value);
}

final monthSummaryProvider = FutureProvider<MonthSummary>((ref) async {
  ref.watch(dataVersionProvider);
  final db = ref.read(dbProvider);
  final m = monthStart(DateTime.now());
  final to = nextMonthStart(m);
  return MonthSummary(
      m, await db.totalSpend(m, to), await db.spendByCategory(m, to), await db.budgets());
});

final receiptsProvider = FutureProvider<List<Receipt>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).receipts();
});

final subscriptionsProvider = FutureProvider<List<Subscription>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.read(dbProvider).subscriptions();
});

final subscriptionCandidatesProvider = FutureProvider<List<SubscriptionCandidate>>((ref) async {
  ref.watch(dataVersionProvider);
  final db = ref.read(dbProvider);
  final receipts = await db.receipts();
  final existing = (await db.subscriptions()).map((s) => s.name.toUpperCase()).toSet();
  return detectSubscriptions(
    [for (final r in receipts) Charge(r.store, r.totalCents, r.date)],
    ignore: await db.dismissedSubs(),
    existing: existing,
  );
});

/// Everything the analytics screen shows for one calendar month.
class AnalyticsData {
  AnalyticsData({
    required this.month,
    required this.total,
    required this.previousTotal,
    required this.byCategory,
    required this.monthly,
    required this.daily,
    required this.topStores,
  });

  final DateTime month;
  final int total;
  final int previousTotal;
  final Map<String, int> byCategory;
  final List<MapEntry<DateTime, int>> monthly; // last 6 months ending at [month]
  final Map<int, int> daily; // day of month -> cents
  final List<MapEntry<String, int>> topStores;

  int get daysInMonth => DateTime(month.year, month.month + 1, 0).day;
}

final analyticsProvider = FutureProvider.family<AnalyticsData, DateTime>((ref, month) async {
  ref.watch(dataVersionProvider);
  final db = ref.read(dbProvider);
  final from = monthStart(month);
  final to = nextMonthStart(month);
  final prev = DateTime(month.year, month.month - 1);
  return AnalyticsData(
    month: from,
    total: await db.totalSpend(from, to),
    previousTotal: await db.totalSpend(prev, from),
    byCategory: await db.spendByCategory(from, to),
    monthly: await db.monthlyTotals(from),
    daily: await db.dailyTotals(from, to),
    topStores: await db.topStores(from, to),
  );
});
