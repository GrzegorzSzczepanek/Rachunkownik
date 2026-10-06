import '../domain/models.dart';

/// Offline keyword categoriser. Used when no model is available and as the
/// zero-cost first pass for manual entries.
const _rules = <String, List<String>>{
  'Jedzenie': [
    'mleko', 'chleb', 'bułk', 'ser ', 'masło', 'jajk', 'woda', 'sok', 'kawa', 'herbat',
    'czekolad', 'baton', 'ciast', 'mięs', 'kurczak', 'szynk', 'kiełbas', 'jogurt', 'banan',
    'jabłk', 'pomidor', 'ziemniak', 'makaron', 'ryż', 'piwo', 'wino', 'cola', 'żabka',
    'biedronka', 'lidl', 'kaufland', 'starbucks', 'restaur', 'pizza', 'burger'
  ],
  'Transport': ['paliw', 'benzyn', 'orlen', 'bp ', 'shell', 'uber', 'bolt', 'bilet', 'parking', 'ztm', 'pkp'],
  'Zdrowie': ['apteka', 'rossmann', 'hebe', 'lek ', 'witamin', 'tablet', 'plast', 'doctor', 'lekarz'],
  'Rozrywka': ['kino', 'empik', 'netflix', 'spotify', 'gra ', 'książk', 'bilet na', 'steam'],
  'Dom': ['ikea', 'castorama', 'leroy', 'żarówk', 'proszek', 'płyn do', 'papier toal', 'mydło', 'szampon', 'ręcznik'],
  'Ubrania': ['koszul', 'spodnie', 'buty', 'kurtk', 'sukienk', 'reserved', 'h&m', 'zara'],
};

String guessCategory(String itemName, {String? store}) {
  final hay = '${itemName.toLowerCase()} ${store?.toLowerCase() ?? ''} ';
  for (final e in _rules.entries) {
    if (e.value.any(hay.contains)) return e.key;
  }
  return 'Inne';
}

void categorizeMissing(Receipt r) {
  for (final i in r.items) {
    if (i.category == 'Inne') i.category = guessCategory(i.name, store: r.store);
  }
}
