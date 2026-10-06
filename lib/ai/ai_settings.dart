import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiTask { receiptReading, categorization, embeddings, chat }

enum AiEngine { local, api }

enum ApiFormat { openai, anthropic }

extension AiTaskLabel on AiTask {
  String get label => switch (this) {
        AiTask.receiptReading => 'Odczyt paragonu',
        AiTask.categorization => 'Kategoryzacja',
        AiTask.embeddings => 'Wyszukiwanie (embeddingi)',
        AiTask.chat => 'Czat o wydatkach',
      };
}

class ApiPreset {
  const ApiPreset(this.id, this.label, this.format, this.baseUrl, {this.needsKey = true});
  final String id;
  final String label;
  final ApiFormat format;
  final String baseUrl;
  final bool needsKey;
}

const apiPresets = [
  ApiPreset('openai', 'OpenAI', ApiFormat.openai, 'https://api.openai.com/v1'),
  ApiPreset('anthropic', 'Anthropic', ApiFormat.anthropic, 'https://api.anthropic.com'),
  ApiPreset('gemini', 'Gemini', ApiFormat.openai,
      'https://generativelanguage.googleapis.com/v1beta/openai'),
  ApiPreset('openrouter', 'OpenRouter', ApiFormat.openai, 'https://openrouter.ai/api/v1'),
  ApiPreset('ollama', 'Ollama', ApiFormat.openai, 'http://localhost:11434/v1', needsKey: false),
  ApiPreset('custom', 'Własny', ApiFormat.openai, ''),
];

class ApiConfig {
  const ApiConfig({
    this.presetId = 'openrouter',
    this.format = ApiFormat.openai,
    this.baseUrl = 'https://openrouter.ai/api/v1',
    this.model = '',
    this.embeddingModel = '',
  });

  final String presetId;
  final ApiFormat format;
  final String baseUrl;
  final String model;

  /// Optional: model name for the provider's `/embeddings` endpoint.
  final String embeddingModel;

  ApiPreset get preset => apiPresets.firstWhere((p) => p.id == presetId,
      orElse: () => apiPresets.last);
  String get providerLabel => preset.label;

  ApiConfig copyWith(
          {String? presetId, ApiFormat? format, String? baseUrl, String? model, String? embeddingModel}) =>
      ApiConfig(
        presetId: presetId ?? this.presetId,
        format: format ?? this.format,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        embeddingModel: embeddingModel ?? this.embeddingModel,
      );

  Map<String, dynamic> toJson() => {
        'preset': presetId,
        'format': format.name,
        'baseUrl': baseUrl,
        'model': model,
        'embeddingModel': embeddingModel,
      };

  factory ApiConfig.fromJson(Map<String, dynamic> j) => ApiConfig(
        presetId: j['preset'] as String? ?? 'openrouter',
        format: ApiFormat.values.byName(j['format'] as String? ?? 'openai'),
        baseUrl: j['baseUrl'] as String? ?? '',
        model: j['model'] as String? ?? '',
        embeddingModel: j['embeddingModel'] as String? ?? '',
      );
}

class PrivacySettings {
  const PrivacySettings({
    this.maskPersonalData = true,
    this.askBeforeSendingImage = true,
    this.suggestApiRetry = true,
    this.showTokenCounter = true,
  });
  final bool maskPersonalData;
  final bool askBeforeSendingImage;
  final bool suggestApiRetry;
  final bool showTokenCounter;

  PrivacySettings copyWith({bool? mask, bool? ask, bool? retry, bool? tokens}) =>
      PrivacySettings(
        maskPersonalData: mask ?? maskPersonalData,
        askBeforeSendingImage: ask ?? askBeforeSendingImage,
        suggestApiRetry: retry ?? suggestApiRetry,
        showTokenCounter: tokens ?? showTokenCounter,
      );
}

class AiSettings {
  const AiSettings({
    required this.engines,
    this.api = const ApiConfig(),
    this.privacy = const PrivacySettings(),
    this.monthlyTokens = 0,
  });

  final Map<AiTask, AiEngine> engines;
  final ApiConfig api;
  final PrivacySettings privacy;
  final int monthlyTokens;

  /// Defaults favour privacy: everything local except chat, which has no
  /// sensible small local model yet.
  factory AiSettings.defaults() => AiSettings(engines: {
        AiTask.receiptReading: AiEngine.local,
        AiTask.categorization: AiEngine.local,
        AiTask.embeddings: AiEngine.local,
        AiTask.chat: AiEngine.api,
      });

  AiEngine engineFor(AiTask t) => engines[t] ?? AiEngine.local;

  AiSettings copyWith({
    Map<AiTask, AiEngine>? engines,
    ApiConfig? api,
    PrivacySettings? privacy,
    int? monthlyTokens,
  }) =>
      AiSettings(
        engines: engines ?? this.engines,
        api: api ?? this.api,
        privacy: privacy ?? this.privacy,
        monthlyTokens: monthlyTokens ?? this.monthlyTokens,
      );
}

/// Persists settings; the API key goes to the platform keystore, never to prefs.
class AiSettingsStore {
  AiSettingsStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();
  final FlutterSecureStorage _secure;

  static const _keyApi = 'api_key';

  Future<AiSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final d = AiSettings.defaults();
    final engines = {
      for (final t in AiTask.values)
        t: AiEngine.values.byName(p.getString('engine_${t.name}') ?? d.engineFor(t).name)
    };
    final apiJson = p.getString('api_config');
    final month = _monthKey();
    return AiSettings(
      engines: engines,
      api: apiJson == null ? d.api : ApiConfig.fromJson(jsonDecode(apiJson)),
      privacy: PrivacySettings(
        maskPersonalData: p.getBool('priv_mask') ?? true,
        askBeforeSendingImage: p.getBool('priv_ask') ?? true,
        suggestApiRetry: p.getBool('priv_retry') ?? true,
        showTokenCounter: p.getBool('priv_tokens') ?? true,
      ),
      monthlyTokens: p.getInt('tokens_$month') ?? 0,
    );
  }

  Future<void> save(AiSettings s) async {
    final p = await SharedPreferences.getInstance();
    for (final e in s.engines.entries) {
      await p.setString('engine_${e.key.name}', e.value.name);
    }
    await p.setString('api_config', jsonEncode(s.api.toJson()));
    await p.setBool('priv_mask', s.privacy.maskPersonalData);
    await p.setBool('priv_ask', s.privacy.askBeforeSendingImage);
    await p.setBool('priv_retry', s.privacy.suggestApiRetry);
    await p.setBool('priv_tokens', s.privacy.showTokenCounter);
  }

  Future<void> addTokens(int n) async {
    final p = await SharedPreferences.getInstance();
    final k = 'tokens_${_monthKey()}';
    await p.setInt(k, (p.getInt(k) ?? 0) + n);
  }

  Future<String?> readKey() => _secure.read(key: _keyApi);
  Future<void> writeKey(String? key) => key == null || key.isEmpty
      ? _secure.delete(key: _keyApi)
      : _secure.write(key: _keyApi, value: key);

  static String _monthKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}';
  }
}
