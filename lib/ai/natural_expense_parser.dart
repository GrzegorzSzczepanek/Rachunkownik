import 'dart:convert';

import '../domain/models.dart';
import 'categorizer.dart';
import 'llm_api.dart';

const _knownStores = <String, String>{
  'żabka': 'Żabka',
  'żabce': 'Żabka',
  'zabka': 'Żabka',
  'zabce': 'Żabka',
  'biedronka': 'Biedronka',
  'biedronce': 'Biedronka',
  'biedra': 'Biedronka',
  'lidl': 'Lidl',
  'lidlu': 'Lidl',
  'kaufland': 'Kaufland',
  'kauflandzie': 'Kaufland',
  'dino': 'Dino',
  'carrefour': 'Carrefour',
  'auchan': 'Auchan',
  'orlen': 'Orlen',
  'orlenie': 'Orlen',
  'shell': 'Shell',
  'shellu': 'Shell',
  'bp': 'BP',
  'circle k': 'Circle K',
  'stacja': 'Stacja paliw',
  'stacji': 'Stacja paliw',
  'rossmann': 'Rossmann',
  'rossmannie': 'Rossmann',
  'hebe': 'Hebe',
  'apteka': 'Apteka',
  'aptece': 'Apteka',
  'zara': 'Zara',
  'zarze': 'Zara',
  'h&m': 'H&M',
  'hm': 'H&M',
  'reserved': 'Reserved',
  'ccc': 'CCC',
  'ikea': 'IKEA',
  'ikei': 'IKEA',
  'castorama': 'Castorama',
  'castoramie': 'Castorama',
  'leroy': 'Leroy Merlin',
  'mcdonald': "McDonald's",
  'mcdonalds': "McDonald's",
  'maku': "McDonald's",
  'kfc': 'KFC',
  'starbucks': 'Starbucks',
  'costa': 'Costa Coffee',
  'uber': 'Uber',
  'uberze': 'Uber',
  'bolt': 'Bolt',
  'bolcie': 'Bolt',
};

const _expensePrompt = '''
Jesteś parserem wydatków z języka naturalnego. Użytkownik podaje, co kupił lub na co wydał pieniądze.
Zwróć WYŁĄCZNIE obiekt JSON:
{
  "store": string,
  "date": "YYYY-MM-DD",
  "total": number,
  "items": [
    {"name": string, "price": number, "category": string}
  ]
}
Zasady:
- price i total to kwoty w złotych (np. 15.50).
- category wybierz z: Jedzenie, Dom, Transport, Rozrywka, Zdrowie, Ubrania, Inne.
- Jeśli brak sklepu, wpisz nazwę miejsca lub "Zakupy".
- Jeśli użytkownik podał tylko jeden ogólny wydatek, stwórz jedną pozycję o tej kwocie.
- Odpowiedz wyłącznie czystym JSON-em bez komentarza.
''';

/// Determines whether user text is an intent to record an expense vs ask a question.
bool isExpenseInput(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return false;

  // Typical query starters
  final queryStarters = [
    'ile',
    'kiedy',
    'gdzie',
    'czy',
    'jak',
    'pokaż',
    'znajdź',
    'szukaj',
    'podsumuj',
    'wypisz',
    'co '
  ];
  if (queryStarters.any((p) => t.startsWith(p))) return false;

  final hasPrice = RegExp(r'\d+(?:[.,]\d+)?\s*(?:zł|pln|zl|\b)').hasMatch(t);

  final expenseVerbs = [
    'kupił',
    'kupiłam',
    'kupiłem',
    'kupion',
    'wydał',
    'wydałam',
    'wydałem',
    'zapłacił',
    'zapłaciłam',
    'zapłaciłem',
    'tankowa',
    'dodaj',
    'zapisz',
    'zjadł',
    'zamówi'
  ];
  final hasExpenseVerb = expenseVerbs.any((v) => t.contains(v));

  // Store pattern: "Biedronka: ..." with a price
  final hasStoreColon = RegExp(r'^[a-ząćęłńóśźż0-9\s]{2,20}[:\-]\s*').hasMatch(t);

  return (hasExpenseVerb && hasPrice) || (hasStoreColon && hasPrice) || (hasPrice && t.split(' ').length <= 6);
}

/// Parses a natural-language description into a [Receipt].
/// Uses LLM when available, falling back to an offline rule-based parser.
Future<Receipt> parseNaturalExpense(
  String text,
  DateTime now, {
  LlmApi? llm,
}) async {
  if (llm != null) {
    try {
      final res = await llm
          .complete(
            system: _expensePrompt,
            user: 'Dzisiejsza data: ${now.toIso8601String().substring(0, 10)}.\nTreść: $text',
            json: true,
            maxTokens: 400,
          )
          .timeout(const Duration(seconds: 12));

      final start = res.text.indexOf('{');
      final end = res.text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final Map<String, dynamic> j = jsonDecode(res.text.substring(start, end + 1));
        final items = <ReceiptItem>[];
        for (final it in (j['items'] as List? ?? [])) {
          if (it is! Map) continue;
          final name = it['name']?.toString().trim() ?? 'Pozycja';
          final p = it['price'];
          final cents = (p is num)
              ? (p * 100).round()
              : (double.tryParse(p.toString().replaceAll(',', '.')) ?? 0 * 100).round();
          final cat = it['category']?.toString() ?? 'Inne';
          items.add(ReceiptItem(
            name: name,
            cents: cents,
            category: defaultCategories.contains(cat) ? cat : guessCategory(name),
          ));
        }

        final store = j['store']?.toString().trim();
        final dateParsed = DateTime.tryParse(j['date']?.toString() ?? '') ?? now;
        final totalRaw = j['total'];
        final totalCents = (totalRaw is num)
            ? (totalRaw * 100).round()
            : items.fold<int>(0, (a, i) => a + i.cents);

        final r = Receipt(
          store: (store != null && store.isNotEmpty) ? store : 'Zakupy',
          date: dateParsed,
          totalCents: totalCents > 0 ? totalCents : items.fold<int>(0, (a, i) => a + i.cents),
          items: items.isNotEmpty ? items : [ReceiptItem(name: 'Wydatek', cents: totalCents)],
          source: ReadSource.manual,
          engineLabel: 'Czat AI',
        );
        categorizeMissing(r);
        return r;
      }
    } catch (_) {
      // Fallback to offline rule-based parser below
    }
  }

  return parseExpenseOffline(text, now);
}

/// Offline rule-based parser for Polish natural language purchase entries.
Receipt parseExpenseOffline(String rawText, DateTime now) {
  var t = rawText.trim();

  // Normalize decimal commas (e.g. 7,50 -> 7.50) so they don't get split as item separators
  t = t.replaceAllMapped(RegExp(r'(\d+),(\d+)'), (m) => '${m[1]}.${m[2]}');

  // 1. Detect date
  var date = now;
  final lower = t.toLowerCase();
  if (lower.contains('przedwczoraj')) {
    date = now.subtract(const Duration(days: 2));
    t = t.replaceAll(RegExp(r'\bprzedwczoraj\b', caseSensitive: false), ' ');
  } else if (lower.contains('wczoraj')) {
    date = now.subtract(const Duration(days: 1));
    t = t.replaceAll(RegExp(r'\bwczoraj\b', caseSensitive: false), ' ');
  } else if (lower.contains('dzisiaj') || lower.contains('dziś')) {
    t = t.replaceAll(RegExp(r'\b(?:dzisiaj|dziś)\b', caseSensitive: false), ' ');
  }

  // 2. Detect store
  String? store;

  // Check colon/dash prefix: "Biedronka: mleko..."
  final prefixMatch = RegExp(r'^([A-ZĄĆĘŁŃÓŚŹŻa-ząćęłńóśźż0-9\s]{2,20})[:\-]\s*(.*)$').firstMatch(t);
  if (prefixMatch != null) {
    final cand = prefixMatch.group(1)!.trim();
    store = _knownStores[cand.toLowerCase()] ?? cand;
    t = prefixMatch.group(2)!.trim();
  } else {
    // Check known stores mentioned with "w" or "na"
    for (final entry in _knownStores.entries) {
      final pattern = RegExp(r'\b(?:w|na)\s+' + RegExp.escape(entry.key) + r'\b', caseSensitive: false);
      if (pattern.hasMatch(t)) {
        store = entry.value;
        t = t.replaceAll(pattern, ' ');
        break;
      }
    }
    // Check if store mentioned without preposition if known
    if (store == null) {
      for (final entry in _knownStores.entries) {
        final pattern = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b', caseSensitive: false);
        if (pattern.hasMatch(t)) {
          store = entry.value;
          t = t.replaceAll(pattern, ' ');
          break;
        }
      }
    }
  }

  // Strip common action verbs wherever they occur
  t = t.replaceAll(
    RegExp(
      r'\b(?:kupiłem|kupiłam|wydałem|wydałam|zapłaciłem|zapłaciłam|dodaj|zapisz|tankowałem|kupił|kupiła|wydał|wydała)\b',
      caseSensitive: false,
    ),
    ' ',
  );

  // Helper to extract a price match from a text chunk
  RegExpMatch? findPriceMatch(String chunk) {
    // 1. Explicit currency: 15.50 zł, 150 pln, 12 zl
    final withCurrency = RegExp(r'(\d+(?:\.\d+)?)\s*(?:zł|pln|zl)\b', caseSensitive: false).firstMatch(chunk);
    if (withCurrency != null) return withCurrency;

    // 2. Preceded by za/po: za 15.50, po 8
    final withPreposition = RegExp(r'\b(?:za|po)\s+(\d+(?:\.\d+)?)\b', caseSensitive: false).firstMatch(chunk);
    if (withPreposition != null) return withPreposition;

    // 3. Number at the end of chunk: chleb 5, masło 7.50
    final atEnd = RegExp(r'\b(\d+(?:\.\d+)?)\s*$', caseSensitive: false).firstMatch(chunk);
    if (atEnd != null) return atEnd;

    // 4. Any standalone number not followed by unit of measure
    final anyNum = RegExp(r'\b(\d+(?:\.\d+)?)(?!\s*(?:l|ml|kg|g|%|cm|m)\b)', caseSensitive: false).firstMatch(chunk);
    return anyNum;
  }

  // 3. Extract items and prices
  final chunks = t.split(RegExp(r'[,;]|\s+i\s+|\s+oraz\s+'));
  final items = <ReceiptItem>[];

  for (var chunk in chunks) {
    chunk = chunk.trim();
    if (chunk.isEmpty) continue;
    final match = findPriceMatch(chunk);
    if (match != null) {
      final val = double.tryParse(match.group(1)!);
      if (val != null) {
        final cents = (val * 100).round();
        var name = chunk.substring(0, match.start) + chunk.substring(match.end);
        name = name
            .replaceAll(RegExp(r'\b(?:zł|pln|zl)\b', caseSensitive: false), ' ')
            .replaceAll(RegExp(r'\b(?:za|na|dla|w|z|do)\b', caseSensitive: false), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (name.isEmpty) {
          name = (store != null && store.isNotEmpty) ? store : 'Wydatek';
        } else {
          name = name[0].toUpperCase() + name.substring(1);
        }
        items.add(ReceiptItem(
          name: name,
          cents: cents,
          category: guessCategory(name, store: store),
        ));
      }
    }
  }

  // Fallback: if no items parsed from chunks, try entire text
  if (items.isEmpty) {
    final match = findPriceMatch(t);
    if (match != null) {
      final val = double.tryParse(match.group(1)!);
      if (val != null) {
        final cents = (val * 100).round();
        var name = t.substring(0, match.start) + t.substring(match.end);
        name = name
            .replaceAll(RegExp(r'\b(?:zł|pln|zl)\b', caseSensitive: false), ' ')
            .replaceAll(RegExp(r'\b(?:za|na|dla|w|z|do)\b', caseSensitive: false), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (name.isEmpty) {
          name = (store != null && store.isNotEmpty) ? store : 'Wydatek';
        } else {
          name = name[0].toUpperCase() + name.substring(1);
        }
        items.add(ReceiptItem(
          name: name,
          cents: cents,
          category: guessCategory(name, store: store),
        ));
      }
    }
  }

  final finalStore = (store != null && store.isNotEmpty)
      ? store
      : (items.isNotEmpty && items.first.name != 'Wydatek' ? items.first.name : 'Zakupy');

  final totalCents = items.fold<int>(0, (a, i) => a + i.cents);
  final r = Receipt(
    store: finalStore,
    date: date,
    totalCents: totalCents,
    items: items,
    source: ReadSource.manual,
    engineLabel: 'Czat (ręcznie)',
  );
  categorizeMissing(r);
  return r;
}
