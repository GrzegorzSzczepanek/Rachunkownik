import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart' as edge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart' show engineReadyProvider;

enum ModelRole { text, vision }

extension ModelRoleLabel on ModelRole {
  String get label => switch (this) {
        ModelRole.text => 'Tekst do JSON',
        ModelRole.vision => 'Odczyt obrazu',
      };
}

/// How flutter_edge_ai should treat the model (prompt format, tool/reasoning
/// syntax). Kept as plain Dart so the catalog and device check stay testable.
enum EngineModelType { gemma4, qwen, qwen3, general }

class ModelFile {
  const ModelFile(this.url, this.name, this.bytes);
  final String url;
  final String name;
  final int bytes;
}

class LocalModel {
  const LocalModel({
    required this.id,
    required this.name,
    required this.role,
    required this.description,
    required this.file,
    required this.engineType,
    this.recommendedTotalRamBytes = 0,
    this.kvBytesPerToken = 0,
    this.contextTokens = 4096,
    this.extraRamBytes = 0,
  });

  final String id;
  final String name;
  final ModelRole role;
  final String description;
  final ModelFile file;
  final EngineModelType engineType;

  /// Minimum device RAM recommended by the flutter_edge_ai model docs
  /// (flutteredge.ai/docs/models). Used as a floor next to our own estimate.
  final int recommendedTotalRamBytes;

  /// Inputs for the RAM estimate (see device_check.dart): KV cache is
  /// 2 · layers · kv_heads · head_dim · 2 bytes per token (f16). Derived from
  /// the base architecture; approximate for LiteRT's packaged variants.
  final int kvBytesPerToken;
  final int contextTokens;

  /// Vision-encoder working buffers.
  final int extraRamBytes;

  int get totalBytes => file.bytes;

  /// Package-side model id: the file name without its extension.
  String get installedId => file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
}

const _hf = 'https://huggingface.co';
const _gb = 1000 * 1000 * 1000;

/// Every entry is a public (non-gated) Hugging Face file; sizes are the real
/// byte sizes from the HF API (checked 2026-10-06), which differ from the
/// rounded figures in the package docs. A finished download is validated by the
/// installer; we only show them.
const modelCatalog = <LocalModel>[
  LocalModel(
    id: 'gemma-4-e2b',
    name: 'Gemma 4 E2B',
    role: ModelRole.vision,
    description: 'Najlepsza jakość odczytu paragonów, po polsku',
    file: ModelFile(
        '$_hf/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
        'gemma-4-E2B-it.litertlm',
        2588147712),
    engineType: EngineModelType.gemma4,
    recommendedTotalRamBytes: 4 * _gb,
    kvBytesPerToken: 50000, // approximate
    extraRamBytes: 400000000,
  ),
  LocalModel(
    id: 'qwen2-vl-2b',
    name: 'Qwen2-VL 2B',
    role: ModelRole.vision,
    description: 'Średni model z obrazem',
    file: ModelFile('$_hf/litert-community/Qwen2-VL-2B/resolve/main/Qwen2-VL-2B.litertlm',
        'Qwen2-VL-2B.litertlm', 1783424544),
    engineType: EngineModelType.qwen,
    recommendedTotalRamBytes: 3 * _gb,
    kvBytesPerToken: 28672, // 28 layers · 2 kv heads · 128 dim
    extraRamBytes: 300000000,
  ),
  LocalModel(
    id: 'fastvlm-0.5b',
    name: 'FastVLM 0.5B',
    role: ModelRole.vision,
    description: 'Szybki, dla słabszych telefonów',
    file: ModelFile('$_hf/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm',
        'FastVLM-0.5B.litertlm', 1156342768),
    engineType: EngineModelType.general,
    recommendedTotalRamBytes: 2 * _gb,
    kvBytesPerToken: 12288, // 24 layers · 2 kv heads · 64 dim
    extraRamBytes: 150000000,
  ),
  LocalModel(
    id: 'smolvlm2-500m',
    name: 'SmolVLM2 500M',
    role: ModelRole.vision,
    description: 'Najlżejszy z obrazem',
    file: ModelFile('$_hf/litert-community/SmolVLM2-500M/resolve/main/SmolVLM2-500M.litertlm',
        'SmolVLM2-500M.litertlm', 360822960),
    engineType: EngineModelType.general,
    recommendedTotalRamBytes: 2 * _gb,
    kvBytesPerToken: 40960, // 32 layers · 5 kv heads · 64 dim
    extraRamBytes: 150000000,
  ),
  LocalModel(
    id: 'qwen2.5-1.5b',
    name: 'Qwen 2.5 1.5B Instruct',
    role: ModelRole.text,
    description: 'Tekst do JSON, kategoryzacja',
    file: ModelFile(
        '$_hf/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
        'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
        1597931520),
    engineType: EngineModelType.qwen,
    recommendedTotalRamBytes: 3 * _gb,
    kvBytesPerToken: 28672, // 28 layers · 2 kv heads · 128 dim
  ),
  LocalModel(
    id: 'qwen3-0.6b',
    name: 'Qwen3 0.6B',
    role: ModelRole.text,
    description: 'Mały, szybki tekst do JSON',
    file: ModelFile('$_hf/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
        'Qwen3-0.6B.litertlm', 614236160),
    engineType: EngineModelType.qwen3,
    recommendedTotalRamBytes: 2 * _gb,
    kvBytesPerToken: 114688, // 28 layers · 8 kv heads · 128 dim
    contextTokens: 2048,
  ),
];

edge.ModelType toEdgeType(EngineModelType t) => switch (t) {
      EngineModelType.gemma4 => edge.ModelType.gemma4,
      EngineModelType.qwen => edge.ModelType.qwen,
      EngineModelType.qwen3 => edge.ModelType.qwen3,
      EngineModelType.general => edge.ModelType.general,
    };

enum ModelState { notInstalled, downloading, paused, installed, failed }

class ModelStatus {
  const ModelStatus(this.state, {this.received = 0, this.error, this.bytesPerSec = 0});
  final ModelState state;
  final int received;
  final String? error;
  final double bytesPerSec;

  static const none = ModelStatus(ModelState.notInstalled);
}

/// Downloads and tracks local models through flutter_edge_ai's installer
/// (retries, typed errors, on-disk skip). Which model is *active* per role is
/// our own choice, stored in preferences and applied by the runtime.
class ModelDownloads extends Notifier<Map<String, ModelStatus>> {
  final _cancel = <String, edge.CancelToken>{};
  late final bool _engineReady = ref.read(engineReadyProvider);

  @override
  Map<String, ModelStatus> build() {
    _scan().catchError((_) {}); // engine unavailable (tests/web): stay "not installed"
    return {for (final m in modelCatalog) m.id: ModelStatus.none};
  }

  Future<void> _scan() async {
    if (!_engineReady) return;
    final installed = (await edge.FlutterEdgeAi.listInstalledModels()).toSet();
    final next = Map.of(state);
    for (final m in modelCatalog) {
      final has = installed.contains(m.installedId) || installed.contains(m.file.name);
      if (has) {
        next[m.id] = ModelStatus(ModelState.installed, received: m.totalBytes);
      } else if (next[m.id]?.state == ModelState.installed) {
        next[m.id] = ModelStatus.none;
      }
    }
    state = next;
  }

  void _set(String id, ModelStatus s) => state = {...state, id: s};

  Future<bool> _wifiOk() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('wifi_only') ?? true)) return true;
    final c = await Connectivity().checkConnectivity();
    return c.contains(ConnectivityResult.wifi) || c.contains(ConnectivityResult.ethernet);
  }

  edge.InferenceInstallationBuilder _builder(LocalModel m) => edge.FlutterEdgeAi.installModel(
        modelType: toEdgeType(m.engineType),
        fileType: edge.ModelFileType.litertlm, // declares the engine
      ).fromNetwork(m.file.url);

  Future<void> download(LocalModel m) async {
    if (state[m.id]?.state == ModelState.downloading) return;
    if (!_engineReady) {
      _set(m.id, const ModelStatus(ModelState.failed,
          error: 'Silnik lokalnych modeli nie jest dostępny na tym urządzeniu.'));
      return;
    }
    if (!await _wifiOk()) {
      _set(m.id, const ModelStatus(ModelState.failed,
          error: 'Brak Wi-Fi. Wyłącz „Pobieraj tylko przez Wi-Fi”, aby pobrać przez dane komórkowe.'));
      return;
    }
    final token = edge.CancelToken();
    _cancel[m.id] = token;
    final sw = Stopwatch()..start();
    _set(m.id, const ModelStatus(ModelState.downloading));
    try {
      await _builder(m).withCancelToken(token).withProgress((percent) {
        final received = (m.totalBytes * percent / 100).round();
        final secs = sw.elapsedMilliseconds / 1000;
        _set(m.id,
            ModelStatus(ModelState.downloading, received: received, bytesPerSec: secs > 1 ? received / secs : 0));
      }).install();
      _set(m.id, ModelStatus(ModelState.installed, received: m.totalBytes));
      await setActive(m); // the latest install becomes active for its role
    } catch (e) {
      if (edge.CancelToken.isCancel(e)) {
        _set(m.id, ModelStatus(ModelState.paused, received: state[m.id]?.received ?? 0));
      } else {
        _set(m.id, ModelStatus(ModelState.failed, received: state[m.id]?.received ?? 0, error: _explain(e)));
      }
    } finally {
      _cancel.remove(m.id);
    }
  }

  String _explain(Object e) {
    final s = e.toString();
    if (s.contains('401') || s.contains('403')) {
      return 'Dostęp odmówiony (401/403). Model wymaga zgody na licencję w Hugging Face.';
    }
    return 'Błąd pobierania: $s';
  }

  void pause(String id) => _cancel[id]?.cancel('user');

  Future<void> delete(LocalModel m) async {
    _cancel[m.id]?.cancel('delete');
    if (_engineReady) {
      try {
        await edge.FlutterEdgeAi.uninstallModel(m.installedId);
      } catch (_) {}
    }
    final p = await SharedPreferences.getInstance();
    if (p.getString(activeKey(m.role)) == m.id) await p.remove(activeKey(m.role));
    _set(m.id, ModelStatus.none);
  }

  // ---- active model per role ----

  static String activeKey(ModelRole r) => 'active_model_${r.name}';

  Future<void> setActive(LocalModel m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(activeKey(m.role), m.id);
    ref.read(activeModelsProvider.notifier).refresh();
  }

  /// Makes [m] the model the engine loads next. install() skips the download
  /// when the file is already on disk, so this is cheap.
  Future<void> activateInEngine(LocalModel m) async {
    await _builder(m).install();
  }
}

final modelDownloadsProvider =
    NotifierProvider<ModelDownloads, Map<String, ModelStatus>>(ModelDownloads.new);

/// Active model id per role (preferences), exposed for the UI and the runtime.
class ActiveModels extends Notifier<Map<ModelRole, String>> {
  @override
  Map<ModelRole, String> build() {
    refresh();
    return const {};
  }

  Future<void> refresh() async {
    final p = await SharedPreferences.getInstance();
    state = {
      for (final r in ModelRole.values)
        if (p.getString(ModelDownloads.activeKey(r)) != null) r: p.getString(ModelDownloads.activeKey(r))!,
    };
  }
}

final activeModelsProvider =
    NotifierProvider<ActiveModels, Map<ModelRole, String>>(ActiveModels.new);
