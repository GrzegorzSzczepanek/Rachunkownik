import 'dart:math' as math;

import '../core/money.dart';

// ------------------------------------------------------------ normalisation

const _fold = {
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
};

/// Lowercase, strip Polish diacritics, keep letters/digits.
String foldPl(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_fold[c] ?? c);
  }
  return b.toString();
}

List<String> tokenize(String s) =>
    foldPl(s).split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toList();

const _longSuffixes = ['ami', 'ach', 'iem', 'ego', 'emu', 'owi', 'ymi', 'imi'];
const _midSuffixes = ['em', 'om', 'ow', 'ie', 'ej', 'ym', 'im', 'ia', 'iu', 'ch'];
const _vowels = 'aeiouy';

/// Cheap Polish stemmer: strips common case endings and undoes the k/c
/// alternation ("Żabka" / "w Żabce" -> "zabk"). Not linguistics, just enough
/// for shop and product words. Tokens of 3 characters or fewer stay as they are.
String stem(String token) {
  var t = foldPl(token);
  if (t.length <= 3) return t;
  for (final s in _longSuffixes) {
    if (t.endsWith(s) && t.length - s.length >= 3) return _alt(t.substring(0, t.length - s.length));
  }
  for (final s in _midSuffixes) {
    if (t.endsWith(s) && t.length - s.length >= 3) {
      t = t.substring(0, t.length - s.length);
      break;
    }
  }
  if (t.length > 3 && _vowels.contains(t[t.length - 1])) t = t.substring(0, t.length - 1);
  return _alt(t);
}

String _alt(String t) => t.endsWith('c') && t.length > 3 ? '${t.substring(0, t.length - 1)}k' : t;

int _lev(String a, String b, {int max = 2}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      rowMin = math.min(rowMin, cur[j]);
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

// ------------------------------------------------------------------ lexicon

/// Concept -> words that usually appear on receipts under it. Cheap stand-in
/// for semantic search; an LLM or an embedding model extends it per query.
const conceptLexicon = <String, List<String>>{
  'slodycze': ['czekolada', 'baton', 'ciastko', 'cukierki', 'wafel', 'lizak', 'zelki', 'ciasto', 'lody'],
  'napoje': ['woda', 'sok', 'cola', 'pepsi', 'piwo', 'kawa', 'herbata', 'napoj', 'oranzada'],
  'nabial': ['mleko', 'ser', 'jogurt', 'maslo', 'smietana', 'kefir', 'twarog', 'jajka'],
  'pieczywo': ['chleb', 'bulka', 'bagietka', 'drozdzowka', 'rogal'],
  'owoce': ['banan', 'jablko', 'gruszka', 'pomarancza', 'truskawki', 'winogrona', 'cytryna'],
  'warzywa': ['pomidor', 'ogorek', 'ziemniaki', 'marchew', 'cebula', 'salata', 'papryka'],
  'mieso': ['kurczak', 'szynka', 'kielbasa', 'wolowina', 'schab', 'poledwica', 'parowki'],
  'alkohol': ['piwo', 'wino', 'wodka', 'whisky', 'rum', 'gin'],
  'kawa': ['latte', 'espresso', 'cappuccino', 'americano', 'starbucks', 'costa'],
  'paliwo': ['benzyna', 'diesel', 'orlen', 'shell', 'bp', 'lotos', 'tankowanie'],
  'leki': ['apteka', 'tabletki', 'witaminy', 'ibuprofen', 'paracetamol', 'syrop'],
  'chemia': ['proszek', 'plyn', 'mydlo', 'szampon', 'zel', 'pasta', 'papier'],
  'subskrypcje': ['netflix', 'spotify', 'youtube', 'google', 'icloud', 'disney'],
};

/// Query words -> extra terms (weight lower than the user's own words).
List<String> expandTerms(List<String> stems) {
  final out = <String>{};
  for (final entry in conceptLexicon.entries) {
    final key = stem(entry.key);
    if (stems.contains(key)) out.addAll(entry.value);
  }
  return out.toList();
}

// ------------------------------------------------------------ query parsing

enum Intent { sum, count, top, list }

class DateRange {
  const DateRange(this.from, this.to, this.label);
  final DateTime from; // inclusive
  final DateTime to; // exclusive
  final String label;
}

class QueryPlan {
  QueryPlan(this.intent, this.terms, this.range, {this.byStore = false});
  final Intent intent;

  /// Content words left after removing time/intent/stop words, folded.
  final List<String> terms;
  final DateRange? range;

  /// "gdzie najwięcej" -> rank stores instead of categories.
  final bool byStore;
}

const _monthForms = {
  'styczen': 1, 'styczniu': 1, 'stycznia': 1, 'luty': 2, 'lutym': 2, 'lutego': 2,
  'marzec': 3, 'marcu': 3, 'marca': 3, 'kwiecien': 4, 'kwietniu': 4, 'kwietnia': 4,
  'maj': 5, 'maju': 5, 'maja': 5, 'czerwiec': 6, 'czerwcu': 6, 'czerwca': 6,
  'lipiec': 7, 'lipcu': 7, 'lipca': 7, 'sierpien': 8, 'sierpniu': 8, 'sierpnia': 8,
  'wrzesien': 9, 'wrzesniu': 9, 'wrzesnia': 9, 'pazdziernik': 10, 'pazdzierniku': 10,
  'pazdziernika': 10, 'listopad': 11, 'listopadzie': 11, 'listopada': 11,
  'grudzien': 12, 'grudniu': 12, 'grudnia': 12,
};

const _monthLocative = [
  'styczniu', 'lutym', 'marcu', 'kwietniu', 'maju', 'czerwcu', 'lipcu', 'sierpniu',
  'wrześniu', 'październiku', 'listopadzie', 'grudniu',
];
const _monthGenitive = [
  'stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', 'lipca', 'sierpnia',
  'września', 'października', 'listopada', 'grudnia',
];

final _stopWords = <String>{
  'ile', 'wydalem', 'wydalam', 'wydano', 'wydatki', 'wydatek', 'kosztowalo', 'kosztowaly', 'zaplacilem',
  'zaplacilam', 'na', 'w', 'we', 'z', 'ze', 'za', 'do', 'od', 'po', 'mam', 'mialem', 'miesiacu',
  'miesiac', 'miesiace', 'miesiecy', 'kwartale', 'kwartal', 'roku', 'rok', 'tygodniu', 'tydzien',
  'zeszlym', 'ubieglym', 'zeszly', 'tym', 'biezacym', 'ostatnim', 'ostatnie', 'ostatni', 'temu',
  'razy', 'raz', 'czesto', 'jak', 'jaki', 'jaka', 'jakie', 'byl', 'bylo', 'byla', 'moje', 'moj',
  'wszystkie', 'pokaz', 'co', 'czy', 'gdzie', 'najwiecej', 'najczesciej', 'lacznie',
  'razem', 'sumie', 'kupilem', 'kupilam', 'kupowalem', 'dni', 'dniach', 'dzien', 'dzisiaj', 'dzis',
  'wczoraj', 'sklep', 'sklepie', 'sklepach', 'zakupy', 'zakupow', 'pln', 'zl', 'i', 'oraz', 'lub',
  'mnie', 'moich', 'moim', 'a', 'o', 'to', 'sie', 'bylem',
};

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Turns a Polish question into an intent, a date range and content terms.
/// [now] is injectable so ranges are testable.
QueryPlan parseQuery(String question, DateTime now) {
  final q = foldPl(question);
  final tokens = tokenize(question);
  DateRange? range;
  final today = _day(now);

  DateRange month(int y, int m) {
    final from = DateTime(y, m);
    return DateRange(from, DateTime(y, m + 1), 'w ${_monthLocative[from.month - 1]} ${from.year}');
  }

  DateRange quarter(DateTime ref) {
    final startM = ((ref.month - 1) ~/ 3) * 3 + 1;
    final from = DateTime(ref.year, startM);
    final to = DateTime(from.year, from.month + 3);
    final lastM = DateTime(to.year, to.month - 1);
    return DateRange(from, to,
        'od ${_monthGenitive[from.month - 1]} do ${_monthGenitive[lastM.month - 1]} ${lastM.year}');
  }

  final lastN = RegExp(r'ostatni\w*\s+(\d+)?\s*(dni|dzien|tygodn\w*|miesi\w+)').firstMatch(q);

  if (lastN != null) {
    final n = int.tryParse(lastN[1] ?? '') ?? 1;
    final unit = lastN[2]!;
    final DateTime from;
    final String label;
    if (unit.startsWith('dn') || unit.startsWith('dzien')) {
      from = today.subtract(Duration(days: n));
      label = 'w ostatnich ${n == 1 ? 'dniu' : '$n dniach'}';
    } else if (unit.startsWith('tydz') || unit.startsWith('tygod')) {
      from = today.subtract(Duration(days: 7 * n));
      label = n == 1 ? 'w ostatnim tygodniu' : 'w ostatnich $n tygodniach';
    } else {
      from = DateTime(today.year, today.month - n, today.day);
      label = n == 1 ? 'w ostatnim miesiącu' : 'w ostatnich $n miesiącach';
    }
    range = DateRange(from, today.add(const Duration(days: 1)), label);
  } else if (RegExp(r'(zeszl|ubiegl)\w*\s+kwartal').hasMatch(q)) {
    range = quarter(DateTime(now.year, now.month - 3));
  } else if (RegExp(r'(tym|biezacym)\s+kwartal').hasMatch(q)) {
    range = quarter(now);
  } else if (RegExp(r'(zeszl|ubiegl)\w*\s+miesiac').hasMatch(q) || q.contains('miesiac temu')) {
    range = month(now.year, now.month - 1);
  } else if (RegExp(r'(tym|biezacym)\s+miesiac').hasMatch(q)) {
    range = month(now.year, now.month);
  } else if (RegExp(r'(zeszl|ubiegl)\w*\s+roku').hasMatch(q) || q.contains('rok temu')) {
    range = DateRange(DateTime(now.year - 1), DateTime(now.year), 'w ${now.year - 1} roku');
  } else if (RegExp(r'(tym|biezacym)\s+roku').hasMatch(q)) {
    range = DateRange(DateTime(now.year), DateTime(now.year + 1), 'w ${now.year} roku');
  } else if (RegExp(r'(tym|biezacym)\s+tygodniu').hasMatch(q)) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    range = DateRange(monday, today.add(const Duration(days: 1)), 'w tym tygodniu');
  } else if (q.contains('wczoraj')) {
    range = DateRange(today.subtract(const Duration(days: 1)), today, 'wczoraj');
  } else if (RegExp(r'\b(dzisiaj|dzis)\b').hasMatch(q)) {
    range = DateRange(today, today.add(const Duration(days: 1)), 'dzisiaj');
  } else {
    for (final t in tokens) {
      final m = _monthForms[t];
      if (m != null) {
        final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(q);
        final year = yearMatch != null
            ? int.parse(yearMatch[1]!)
            : (m > now.month ? now.year - 1 : now.year);
        range = month(year, m);
        break;
      }
    }
  }

  final monthWords = _monthForms.keys.toSet();
  final terms = [
    for (final t in tokens)
      if (!_stopWords.contains(t) && !monthWords.contains(t) && !RegExp(r'^\d+$').hasMatch(t) && t.length > 1) t
  ];

  final Intent intent;
  final byStore = q.contains('gdzie') || RegExp(r'w ktorym sklepie|ktore sklepy').hasMatch(q);
  if (RegExp(r'ile razy|jak czesto|ile (bylo|mam) (paragon|zakup|transakcj)').hasMatch(q)) {
    intent = Intent.count;
  } else if (terms.isEmpty && (q.contains('najwiecej') || q.contains('najczesciej') || byStore)) {
    intent = Intent.top;
  } else if (RegExp(r'\bile\b|laczn|razem|w sumie|suma').hasMatch(q)) {
    intent = Intent.sum;
  } else {
    intent = Intent.list;
  }
  return QueryPlan(intent, terms, range, byStore: byStore);
}

// ------------------------------------------------------------------ ranking

class ItemDoc {
  ItemDoc({
    required this.id,
    required this.receiptId,
    required this.name,
    required this.store,
    required this.category,
    required this.date,
    required this.cents,
  });
  final int id;
  final int receiptId;
  final String name;
  final String store;
  final String category;
  final DateTime date;
  final int cents;

  late final List<String> stems =
      tokenize('$name $store $category').map(stem).toSet().toList();
}

class WeightedTerm {
  WeightedTerm(this.stem, this.weight);
  final String stem;
  final double weight;
}

class Hit {
  Hit(this.doc, this.score);
  final ItemDoc doc;
  final double score;
}

/// How well one query stem matches one document stem (0 = not at all).
double _termMatch(String q, String d) {
  if (q == d) return 1.0;
  if (q.length >= 4 && d.length >= 4 && (d.startsWith(q) || q.startsWith(d)) && (d.length - q.length).abs() <= 3) {
    return 0.85;
  }
  if (q.length >= 5 && d.length >= 5 && _lev(q, d, max: 1) <= 1) return 0.7; // typo
  return 0;
}

/// BM25-style ranking of [docs] for [terms]. With no terms every document is
/// returned (score 1) so callers can aggregate a whole period.
List<Hit> rank(List<ItemDoc> docs, List<WeightedTerm> terms, {List<double>? semantic}) {
  if (terms.isEmpty) return [for (final d in docs) Hit(d, 1.0)];
  final n = docs.length;
  // Document frequency per query term (using soft matching).
  final df = List<int>.filled(terms.length, 0);
  final matches = <List<double>>[];
  for (final d in docs) {
    final row = List<double>.filled(terms.length, 0);
    for (var i = 0; i < terms.length; i++) {
      var best = 0.0;
      for (final s in d.stems) {
        final m = _termMatch(terms[i].stem, s);
        if (m > best) best = m;
        if (best == 1.0) break;
      }
      row[i] = best;
      if (best > 0) df[i]++;
    }
    matches.add(row);
  }
  final hits = <Hit>[];
  for (var k = 0; k < docs.length; k++) {
    var score = 0.0;
    for (var i = 0; i < terms.length; i++) {
      final m = matches[k][i];
      if (m == 0) continue;
      final idf = math.log(1 + (n - df[i] + 0.5) / (df[i] + 0.5));
      score += terms[i].weight * m * (idf + 0.5);
    }
    if (semantic != null) score += semantic[k];
    if (score > 0) hits.add(Hit(docs[k], score));
  }
  hits.sort((a, b) => b.score.compareTo(a.score));
  return hits;
}

/// Ranks [docs] for a parsed question. Query words count fully; lexicon
/// synonyms and [extraTerms] (e.g. from an LLM) count 0.6.
List<Hit> searchPlan(List<ItemDoc> docs, QueryPlan plan,
    {List<String> extraTerms = const [], List<double>? semantic}) {
  final base = plan.terms.map(stem).toSet();
  final extra = <String>{
    for (final w in [...expandTerms(base.toList()), ...extraTerms]) ...tokenize(w).map(stem),
  }..removeAll(base);
  return rank(docs, [
    for (final b in base) WeightedTerm(b, 1.0),
    for (final e in extra) WeightedTerm(e, 0.6),
  ], semantic: semantic);
}

// ------------------------------------------------------------------- answer

class Aggregate {
  Aggregate(this.hits);
  final List<Hit> hits;

  int get totalCents => hits.fold(0, (a, h) => a + h.doc.cents);
  int get receipts => hits.map((h) => h.doc.receiptId).toSet().length;

  List<MapEntry<String, int>> _group(String Function(ItemDoc) key, {bool byCount = false}) {
    final sum = <String, int>{};
    final cnt = <String, Set<int>>{};
    for (final h in hits) {
      final k = key(h.doc);
      sum[k] = (sum[k] ?? 0) + h.doc.cents;
      (cnt[k] ??= {}).add(h.doc.receiptId);
    }
    final list = sum.entries.toList();
    list.sort((a, b) => byCount
        ? (cnt[b.key]!.length - cnt[a.key]!.length)
        : b.value.compareTo(a.value));
    return list;
  }

  List<MapEntry<String, int>> stores({bool byCount = false}) => _group((d) => d.store, byCount: byCount);
  List<MapEntry<String, int>> categories() => _group((d) => d.category);
  int visits(String store) => hits.where((h) => h.doc.store == store).map((h) => h.doc.receiptId).toSet().length;
}

/// Polish plural form: 1 pozycja, 2-4 pozycje, 5+ pozycji.
String plPlural(int n, String one, String few, String many) {
  if (n == 1) return one;
  final last = n % 10, last2 = n % 100;
  if (last >= 2 && last <= 4 && !(last2 >= 12 && last2 <= 14)) return few;
  return many;
}

/// A deterministic answer: numbers come from the data, never from a model.
String composeAnswer(QueryPlan plan, List<Hit> hits, {int listLimit = 6}) {
  final where = plan.range?.label ?? 'w całym okresie';
  final what = plan.terms.isEmpty ? '' : ' dla „${plan.terms.join(' ')}”';
  if (hits.isEmpty) return 'Nie znalazłem wydatków$what $where.';
  final agg = Aggregate(hits);
  final n = hits.length;
  final items = '$n ${plPlural(n, 'pozycja', 'pozycje', 'pozycji')}';

  String topStores() {
    final s = agg.stores(byCount: true).take(2).toList();
    if (s.isEmpty || n < 3) return '';
    return ' Najczęściej: ${s.map((e) => '${e.key} (${agg.visits(e.key)} ${plPlural(agg.visits(e.key), 'raz', 'razy', 'razy')})').join(', ')}.';
  }

  switch (plan.intent) {
    case Intent.sum:
      return '${formatMoney(agg.totalCents)} w $items $where.${topStores()}';
    case Intent.count:
      final r = agg.receipts;
      return '$r ${plPlural(r, 'raz', 'razy', 'razy')} $where '
          '(${formatMoney(agg.totalCents)} łącznie).${topStores()}';
    case Intent.top:
      if (plan.byStore) {
        final s = agg.stores().take(3).toList();
        return 'Najwięcej wydano w: ${s.map((e) => '${e.key} ${formatMoney(e.value)}').join(', ')} $where.';
      }
      final total = agg.totalCents;
      final c = agg.categories().take(3).toList();
      return 'Najwięcej wydano na: ${c.map((e) => '${e.key} ${formatMoney(e.value)} (${total == 0 ? 0 : (e.value * 100 / total).round()}%)').join(', ')} $where.';
    case Intent.list:
      final head = hits.take(listLimit).map((h) =>
          '${shortDate(h.doc.date)} · ${h.doc.store} · ${h.doc.name} · ${formatMoney(h.doc.cents)}');
      final more = n > listLimit ? '\n… i ${n - listLimit} więcej.' : '';
      return 'Znalazłem $items$what $where, razem ${formatMoney(agg.totalCents)}:\n${head.join('\n')}$more';
  }
}
