import 'dart:typed_data';

class LocalRuntimeUnavailable implements Exception {
  LocalRuntimeUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Seam for on-device inference. The app is wired against this interface so the
/// native binding (llama.cpp / MLX / MediaPipe) can be dropped in without
/// touching extraction, categorisation, search or chat.
abstract class LocalRuntime {
  bool get isReady;

  /// Text or vision generation with the active local model.
  Future<String> generate({
    required String system,
    required String user,
    Uint8List? image,
    bool json = false,
  });

  Future<List<double>> embed(String text);

  /// Frees native memory held by the loaded model.
  Future<void> release();
}

/// Fallback when the on-device engine could not start. Fails loudly instead
/// of silently pretending to work.
class UnavailableLocalRuntime implements LocalRuntime {
  const UnavailableLocalRuntime();

  @override
  bool get isReady => false;

  @override
  Future<String> generate({
    required String system,
    required String user,
    Uint8List? image,
    bool json = false,
  }) =>
      throw LocalRuntimeUnavailable(
          'Silnik lokalnych modeli nie jest dostępny na tym urządzeniu. Użyj trybu API.');

  @override
  Future<List<double>> embed(String text) =>
      throw LocalRuntimeUnavailable('Lokalne embeddingi nie są jeszcze podłączone.');

  @override
  Future<void> release() async {}
}

/// On-device text recognition (Apple Vision / ML Kit). Cheaper and more reliable
/// than a VLM for plain receipts; the small LLM then only structures the text.
abstract class OcrEngine {
  Future<String> recognize(Uint8List image);
}
