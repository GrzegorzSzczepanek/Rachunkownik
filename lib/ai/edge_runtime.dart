import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart' as edge;
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_models.dart';
import 'local_runtime.dart';

/// Registers the on-device engine once. Returns false (instead of throwing)
/// where the platform setup is missing, so the app still starts and falls back
/// to API mode.
Future<bool> initEdgeAi() async {
  try {
    await edge.FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()]);
    return true;
  } catch (_) {
    return false;
  }
}

/// Runs the user's active local model (flutter_edge_ai / LiteRT-LM).
class EdgeAiRuntime implements LocalRuntime {
  EdgeAiRuntime({required this.engineReady, required this.activate});

  final bool engineReady;

  /// Makes the model the engine's active one (cheap when already on disk).
  final Future<void> Function(LocalModel) activate;

  LocalModel? _loaded;
  bool _loadedWithImage = false;
  edge.InferenceModel? _model;

  @override
  bool get isReady => engineReady;

  Future<LocalModel?> _activeFor(ModelRole role) async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(ModelDownloads.activeKey(role));
    if (id == null) return null;
    return modelCatalog.where((m) => m.id == id).firstOrNull;
  }

  Future<edge.InferenceModel> _load(LocalModel m, {required bool image}) async {
    if (_model != null && _loaded?.id == m.id && _loadedWithImage == image) return _model!;
    await release();
    await activate(m);
    _model = await edge.FlutterEdgeAi.getActiveModel(
      maxTokens: 4096,
      supportImage: image,
      // Gemma 4 on GPU can misread digits at half precision; amounts matter here.
      activationDataType: m.engineType == EngineModelType.gemma4 ? edge.ActivationDataType.float32 : null,
    );
    _loaded = m;
    _loadedWithImage = image;
    return _model!;
  }

  @override
  Future<String> generate({
    required String system,
    required String user,
    Uint8List? image,
    bool json = false,
  }) async {
    if (!engineReady) {
      throw LocalRuntimeUnavailable(
          'Silnik lokalnych modeli nie jest dostępny na tym urządzeniu. Użyj trybu API.');
    }
    final needImage = image != null;
    final model = needImage
        ? await _activeFor(ModelRole.vision)
        : (await _activeFor(ModelRole.text) ?? await _activeFor(ModelRole.vision));
    if (model == null) {
      throw LocalRuntimeUnavailable(needImage
          ? 'Nie wybrano modelu z obsługą obrazu. Pobierz go w Ustawienia → Modele lokalne.'
          : 'Nie wybrano modelu. Pobierz go w Ustawienia → Modele lokalne.');
    }
    final useImage = needImage && model.role == ModelRole.vision;
    final inference = await _load(model, image: useImage);
    final chat = await inference.createChat(
      temperature: 0.0,
      topK: 1,
      supportImage: useImage,
      systemInstruction: system,
      maxOutputTokens: 1500,
    );
    try {
      await chat.addQueryChunk(edge.Message(text: user, isUser: true, imageBytes: image));
      final out = StringBuffer();
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is edge.TextResponse) out.write(r.token);
      }
      return out.toString();
    } finally {
      await chat.close();
    }
  }

  @override
  Future<List<double>> embed(String text) => throw LocalRuntimeUnavailable(
      'Lokalne embeddingi nie są jeszcze dostępne (brak wielojęzycznego modelu bez tokenu). '
      'Wyszukiwanie działa po słowach kluczowych.');

  /// Frees the model's memory (called when the app goes to the background).
  @override
  Future<void> release() async {
    final m = _model;
    _model = null;
    _loaded = null;
    try {
      await m?.close();
    } catch (_) {}
  }
}
