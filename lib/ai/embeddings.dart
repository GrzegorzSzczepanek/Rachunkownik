import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../data/db.dart';
import '../domain/retrieval.dart';
import 'ai_settings.dart';
import 'llm_api.dart';

/// Turns text into vectors. Only the OpenAI-compatible `/embeddings` endpoint
/// is implemented (OpenAI, Gemini's compatibility layer, Ollama, OpenRouter);
/// Anthropic has no embeddings API.
abstract class Embedder {
  /// Stable identity of the vector space: vectors from different ids must
  /// never be compared.
  String get id;
  Future<List<List<double>>> embed(List<String> texts);
}

class OpenAiEmbedder implements Embedder {
  OpenAiEmbedder(this.cfg, this.apiKey, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)));

  final ApiConfig cfg;
  final String? apiKey;
  final Dio _dio;

  @override
  String get id => '${cfg.presetId}:${cfg.embeddingModel}';

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    if (texts.isEmpty) return [];
    final base = cfg.baseUrl.endsWith('/') ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1) : cfg.baseUrl;
    try {
      final r = await _dio.post(
        '$base/embeddings',
        options: Options(headers: {if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey'}),
        data: {'model': cfg.embeddingModel, 'input': texts},
      );
      final data = (r.data as Map)['data'] as List;
      // Providers may reorder; `index` says which input a vector belongs to.
      final sorted = [...data]..sort((a, b) => ((a['index'] ?? 0) as int).compareTo((b['index'] ?? 0) as int));
      if (sorted.length != texts.length) {
        throw LlmException('Dostawca zwrócił ${sorted.length} wektorów dla ${texts.length} tekstów.');
      }
      return [
        for (final d in sorted) [for (final v in (d['embedding'] as List)) (v as num).toDouble()]
      ];
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      throw LlmException(status == null
          ? 'Brak połączenia z ${e.requestOptions.uri.host}: ${e.message}'
          : 'Błąd embeddingów ($status). Sprawdź nazwę modelu embeddingów.');
    }
  }
}

double cosine(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  final n = math.min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return (na == 0 || nb == 0) ? 0 : dot / (math.sqrt(na) * math.sqrt(nb));
}

Uint8List packVector(List<double> v) => Uint8List.fromList(Float32List.fromList(v).buffer.asUint8List());

List<double> unpackVector(Uint8List bytes) {
  final copy = Uint8List.fromList(bytes); // guarantees 4-byte alignment
  return Float32List.view(copy.buffer).toList();
}

/// Text that represents a receipt line in the vector space.
String embeddingText(ItemDoc d) => '${d.name} (${d.store}, ${d.category})';

/// Embeds receipt lines that have no vector for this embedder yet.
class EmbeddingIndexer {
  EmbeddingIndexer(this.db, this.embedder, {String Function(ItemDoc)? textOf})
      : textOf = textOf ?? embeddingText;
  final AppDb db;
  final Embedder embedder;

  /// What leaves the device for each line (e.g. with personal data masked).
  final String Function(ItemDoc) textOf;

  /// Indexes up to [maxItems] missing lines in batches; returns how many were
  /// added. Cheap when everything is indexed (one query).
  Future<int> sync({int maxItems = 400, int batch = 64}) async {
    final missing = await db.itemsMissingVectors(embedder.id, limit: maxItems);
    var done = 0;
    for (var i = 0; i < missing.length; i += batch) {
      final chunk = missing.sublist(i, math.min(i + batch, missing.length));
      final vecs = await embedder.embed([for (final d in chunk) textOf(d)]);
      await db.saveVectors(embedder.id, {for (var k = 0; k < chunk.length; k++) chunk[k].id: packVector(vecs[k])});
      done += chunk.length;
    }
    return done;
  }
}

/// Semantic bonus per document (aligned with [docs]). Scores only vectors that
/// stand out from the rest (mean + 1.5 sd), so the result doesn't depend on
/// how a particular model spreads its cosine values.
List<double> semanticScores(List<double> query, List<ItemDoc> docs, Map<int, List<double>> vectors) {
  final cos = <int, double>{};
  for (var k = 0; k < docs.length; k++) {
    final v = vectors[docs[k].id];
    if (v != null) cos[k] = cosine(query, v);
  }
  final out = List<double>.filled(docs.length, 0);
  if (cos.length < 5) return out;
  final mean = cos.values.reduce((a, b) => a + b) / cos.length;
  final variance = cos.values.fold(0.0, (a, c) => a + (c - mean) * (c - mean)) / cos.length;
  final threshold = mean + 1.5 * math.sqrt(variance);
  cos.forEach((k, c) {
    if (c > threshold) out[k] = (c - threshold) * 6 + 0.5;
  });
  return out;
}
