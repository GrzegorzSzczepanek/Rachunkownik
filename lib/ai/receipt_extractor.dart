import 'dart:convert';
import 'dart:typed_data';

import '../domain/models.dart';
import 'ai_settings.dart';
import 'categorizer.dart';
import 'llm_api.dart';
import 'local_runtime.dart';
import 'masking.dart';

final receiptSystemPrompt = '''
Jesteś parserem polskich paragonów. Zwróć WYŁĄCZNIE obiekt JSON bez komentarza:
{"store": string, "date": "YYYY-MM-DD", "total": number,
 "items": [{"name": string, "price": number, "category": string, "confidence": number}]}
Zasady:
- price i total to kwoty w złotych (kropka dziesiętna), cena końcowa pozycji po rabacie.
- category wybierz z: ${defaultCategories.join(', ')}.
- confidence 0..1: ile pewności masz co do odczytu nazwy i ceny.
- Pomiń pozycje typu SUMA, PTU, reszta, forma płatności. Nie wymyślaj pozycji.
- Jeśli nie widzisz daty, użyj null.''';

class ExtractionException implements Exception {
  ExtractionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ExtractionResult {
  ExtractionResult(this.receipt, {this.tokens = 0, this.elapsed = Duration.zero});
  final Receipt receipt;
  final int tokens;
  final Duration elapsed;
}

/// Parses the model's JSON reply into a [Receipt]. Tolerates code fences and
/// prose around the object, since small models rarely obey "JSON only".
Receipt parseReceiptJson(String raw, {required ReadSource source, String? engineLabel}) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw ExtractionException('Model nie zwrócił JSON-a.');
  }
  final jsonSubstring = raw.substring(start, end + 1);
  Map<String, dynamic> j;
  try {
    j = jsonDecode(jsonSubstring) as Map<String, dynamic>;
  } on FormatException {
    // Retry with sanitized trailing commas (common in small local model output)
    try {
      final sanitized = jsonSubstring
          .replaceAll(RegExp(r',\s*\}'), '}')
          .replaceAll(RegExp(r',\s*\]'), ']');
      j = jsonDecode(sanitized) as Map<String, dynamic>;
    } on FormatException {
      throw ExtractionException('Odpowiedź modelu nie jest poprawnym JSON-em.');
    }
  }
  int cents(Object? v) {
    if (v is num) return (v * 100).round();
    if (v == null) return 0;
    final str = v.toString().trim();
    final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(str);
    if (match != null) {
      final numStr = match.group(1)!.replaceAll(',', '.');
      final val = double.tryParse(numStr);
      if (val != null) return (val * 100).round();
    }
    return 0;
  }

  final items = <ReceiptItem>[];
  for (final it in (j['items'] as List? ?? [])) {
    if (it is! Map) continue;
    final name = it['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final cat = it['category']?.toString() ?? 'Inne';
    final conf = (it['confidence'] as num?)?.toDouble() ?? 1.0;
    items.add(ReceiptItem(
      name: name,
      cents: cents(it['price']),
      category: defaultCategories.contains(cat) ? cat : 'Inne',
      lowConfidence: conf < 0.7,
    ));
  }
  final total = cents(j['total']);
  final r = Receipt(
    store: (j['store']?.toString().trim().isNotEmpty ?? false)
        ? j['store'].toString().trim()
        : 'Nieznany sklep',
    date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
    totalCents: total > 0 ? total : items.fold<int>(0, (a, i) => a + i.cents),
    items: items,
    source: source,
    engineLabel: engineLabel,
  );
  categorizeMissing(r);
  return r;
}

class ReceiptExtractor {
  ReceiptExtractor({
    required this.settings,
    required this.llm,
    required this.local,
    this.ocr,
    this.onTokens,
  });

  final AiSettings settings;
  final LlmApi? llm;
  final LocalRuntime local;
  final OcrEngine? ocr;
  final void Function(int tokens)? onTokens;

  Future<ExtractionResult> extract(Uint8List image, {AiEngine? forceEngine}) async {
    final engine = forceEngine ?? settings.engineFor(AiTask.receiptReading);
    final sw = Stopwatch()..start();
    if (engine == AiEngine.api) {
      final api = llm;
      if (api == null) throw ExtractionException('Skonfiguruj dostawcę API w ustawieniach.');
      final res = await api.complete(
        system: receiptSystemPrompt,
        user: 'Odczytaj ten paragon.',
        image: image,
        json: true,
        maxTokens: 3000,
      );
      onTokens?.call(res.totalTokens);
      final label = '${settings.api.providerLabel} · ${settings.api.model}';
      return ExtractionResult(
        parseReceiptJson(res.text, source: ReadSource.api, engineLabel: label),
        tokens: res.totalTokens,
        elapsed: sw.elapsed,
      );
    }

    // Local: OCR first (cheap, accurate), then a small text model structures it.
    String reply;
    String label;
    if (ocr != null) {
      var text = await ocr!.recognize(image);
      if (settings.privacy.maskPersonalData) text = maskSensitive(text);
      reply = await local.generate(
          system: receiptSystemPrompt, user: 'Tekst z paragonu:\n$text', json: true);
      label = 'OCR + model lokalny';
    } else {
      reply = await local.generate(
          system: receiptSystemPrompt, user: 'Odczytaj ten paragon.', image: image, json: true);
      label = 'Model lokalny (obraz)';
    }
    return ExtractionResult(
      parseReceiptJson(reply, source: ReadSource.local, engineLabel: label),
      elapsed: sw.elapsed,
    );
  }
}
