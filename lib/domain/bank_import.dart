import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';

import '../ai/categorizer.dart';
import 'models.dart';

// ---------------------------------------------------------------- decoding

const _cp1250 = {
  0xA5: 'Ą', 0xB9: 'ą', 0xC6: 'Ć', 0xE6: 'ć', 0xCA: 'Ę', 0xEA: 'ę', 0xA3: 'Ł', 0xB3: 'ł',
  0xD1: 'Ń', 0xF1: 'ń', 0xD3: 'Ó', 0xF3: 'ó', 0x8C: 'Ś', 0x9C: 'ś', 0x8F: 'Ź', 0x9F: 'ź',
  0xAF: 'Ż', 0xBF: 'ż',
};

/// Polish banks export UTF-8 or Windows-1250. Tries strict UTF-8 first (after
/// removing a BOM), then falls back to Windows-1250 for the Polish letters.
String decodeBankBytes(Uint8List bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = b.sublist(3);
  try {
    return utf8.decode(b);
  } on FormatException {
    final sb = StringBuffer();
    for (final c in b) {
      sb.write(c < 0x80 ? String.fromCharCode(c) : (_cp1250[c] ?? String.fromCharCode(c)));
    }
    return sb.toString();
  }
}

// ----------------------------------------------------------------- parsing

/// Picks the delimiter from the lines most likely to be the header (the file
/// often starts with a free-text preamble that would fool whole-file detection).
String detectDelimiter(String text) {
  final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).take(40).toList();
  var best = ';';
  var bestScore = -1;
  for (final d in [';', ',', '\t', '|']) {
    // Score = most fields on a line that also looks like a header.
    var score = 0;
    for (final l in lines) {
      final n = l.split(d).length;
      final lower = l.toLowerCase();
      if (n >= 3 && (lower.contains('data') || lower.contains('date')) && lower.contains('kwota')) {
        if (n > score) score = n;
      }
    }
    if (score == 0) {
      for (final l in lines) {
        final n = l.split(d).length;
        if (n > score) score = n;
      }
      score = score ~/ 2; // weaker evidence than an actual header match
    }
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return best;
}

List<List<String>> parseCsvText(String text) {
  final d = detectDelimiter(text);
  final rows = Csv(fieldDelimiter: d, autoDetect: false).decode(text);
  return [for (final r in rows) [for (final c in r) c.toString().trim()]];
}

String _norm(String s) {
  const map = {'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z'};
  final lower = s.toLowerCase().replaceAll('#', '').trim();
  return lower.split('').map((c) => map[c] ?? c).join();
}

/// Which columns hold what. Indices are into each row.
class CsvLayout {
  CsvLayout({
    required this.headerRow,
    required this.dateCol,
    required this.descCols,
    this.amountCol,
    this.debitCol,
    this.creditCol,
  });

  final int headerRow;
  final int dateCol;
  final List<int> descCols;
  final int? amountCol;
  final int? debitCol;
  final int? creditCol;

  bool get isValid => descCols.isNotEmpty && (amountCol != null || debitCol != null || creditCol != null);

  CsvLayout copyWith({int? dateCol, List<int>? descCols, int? amountCol}) => CsvLayout(
        headerRow: headerRow,
        dateCol: dateCol ?? this.dateCol,
        descCols: descCols ?? this.descCols,
        amountCol: amountCol ?? this.amountCol,
        debitCol: debitCol,
        creditCol: creditCol,
      );
}

/// Finds the header row and maps columns by their names (mBank, PKO BP, ING,
/// Pekao, Santander and similar). Returns null when nothing recognisable is found.
CsvLayout? detectLayout(List<List<String>> rows) {
  for (var i = 0; i < rows.length && i < 60; i++) {
    final h = rows[i].map(_norm).toList();
    if (h.length < 3) continue;
    final hasDate = h.any((c) => c.contains('data') || c == 'date');
    final hasAmount = h.any((c) => c.contains('kwota') || c.contains('obciazenia') || c.contains('uznania'));
    if (!hasDate || !hasAmount) continue;

    int? firstWhere(bool Function(String) test) {
      for (var j = 0; j < h.length; j++) {
        if (test(h[j])) return j;
      }
      return null;
    }

    // Prefer the operation/transaction date over the booking date.
    final date = firstWhere((c) => c.contains('data operacji') || c.contains('data transakcji')) ??
        firstWhere((c) => c.contains('data ksiegowania')) ??
        firstWhere((c) => c.contains('data'));
    if (date == null) continue;

    final amount = firstWhere((c) => c.startsWith('kwota') && !c.contains('saldo') && !c.contains('blokad'));
    final debit = firstWhere((c) => c.contains('obciazenia') || c == 'wn');
    final credit = firstWhere((c) => c.contains('uznania') || c == 'ma');

    final desc = <int>[];
    for (var j = 0; j < h.length; j++) {
      final c = h[j];
      final textual = c.contains('opis') ||
          c.contains('tytul') ||
          c.contains('kontrahent') ||
          c.contains('nadawca') ||
          c.contains('odbiorca') ||
          c.contains('szczegoly') ||
          c.contains('lokalizacja');
      final noise = c.contains('numer') || c.contains('nr ') || c.contains('rachunk') || c.contains('konto');
      if (textual && !noise) desc.add(j);
    }
    final layout = CsvLayout(
      headerRow: i,
      dateCol: date,
      descCols: desc,
      amountCol: amount,
      debitCol: amount == null ? debit : null,
      creditCol: amount == null ? credit : null,
    );
    if (layout.isValid) return layout;
  }
  return null;
}

/// "-1 234,56 PLN", "1.234,56", "-12.50", "12,5" -> cents. Null when not a number.
int? parseAmountCents(String raw) {
  var s = raw.replaceAll(RegExp(r'[^\d,.\-+]'), '');
  if (s.isEmpty || s == '-' || s == '+') return null;
  final negative = s.startsWith('-');
  s = s.replaceAll(RegExp(r'[-+]'), '');
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  final sep = lastComma > lastDot ? lastComma : lastDot;
  String whole;
  String frac = '';
  if (sep >= 0 && s.length - sep - 1 <= 2 && s.length - sep - 1 >= 1) {
    whole = s.substring(0, sep).replaceAll(RegExp(r'[.,]'), '');
    frac = s.substring(sep + 1);
  } else {
    whole = s.replaceAll(RegExp(r'[.,]'), '');
  }
  if (whole.isEmpty) whole = '0';
  final w = int.tryParse(whole);
  if (w == null) return null;
  final f = int.tryParse(frac.padRight(2, '0')) ?? 0;
  final cents = w * 100 + f;
  return negative ? -cents : cents;
}

/// YYYY-MM-DD, DD-MM-YYYY, DD.MM.YYYY, DD/MM/YYYY, YYYY.MM.DD (time ignored).
DateTime? parseBankDate(String raw) {
  final s = raw.trim();
  var m = RegExp(r'^(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(s);
  if (m != null) {
    return _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'^(\d{1,2})[-./](\d{1,2})[-./](\d{4})').firstMatch(s);
  if (m != null) {
    return _valid(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }
  return null;
}

DateTime? _valid(int y, int mo, int d) {
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
  final dt = DateTime(y, mo, d);
  return dt.month == mo ? dt : null;
}

class BankRow {
  BankRow(this.date, this.description, this.cents);
  final DateTime date;
  final String description;
  final int cents; // negative = money out
}

/// Rows below the header that have a parsable date and amount.
List<BankRow> extractRows(List<List<String>> rows, CsvLayout l) {
  final out = <BankRow>[];
  for (var i = l.headerRow + 1; i < rows.length; i++) {
    final r = rows[i];
    String at(int? c) => (c != null && c < r.length) ? r[c] : '';
    final date = parseBankDate(at(l.dateCol));
    if (date == null) continue;
    int? cents;
    if (l.amountCol != null) {
      cents = parseAmountCents(at(l.amountCol));
    } else {
      final d = parseAmountCents(at(l.debitCol));
      final c = parseAmountCents(at(l.creditCol));
      if (d != null && d != 0) {
        cents = -d.abs();
      } else if (c != null) {
        cents = c.abs();
      }
    }
    if (cents == null) continue;
    final desc = l.descCols.map(at).where((s) => s.isNotEmpty).join(' · ');
    out.add(BankRow(date, desc, cents));
  }
  return out;
}

// ---------------------------------------------------------------- planning

const _noisePrefixes = [
  'płatność kartą', 'platnosc karta', 'zakup przy użyciu karty', 'transakcja kartą',
  'transakcja bezgotówkowa', 'płatność blik', 'przelew na telefon', 'przelew zewnętrzny',
  'przelew wewnętrzny', 'przelew',
];

/// Best-effort merchant name from a bank description. The description is the
/// bank's columns joined with " · ": generic parts (operation type such as
/// "ZAKUP PRZY UŻYCIU KARTY") are dropped, the first informative one is kept.
String cleanMerchant(String description) {
  for (final part in description.split(' · ')) {
    var s = part.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = s.toLowerCase();
    for (final p in _noisePrefixes) {
      if (lower.startsWith(p)) {
        s = s.substring(p.length).replaceFirst(RegExp(r'^[\s:\-–,]+'), '');
        break;
      }
    }
    s = s
        .replaceAll(RegExp(r'\b\d{2}[-.]\d{2}[-.]\d{4}\b'), '')
        .replaceAll(RegExp(r'\b\d{4}-\d{2}-\d{2}\b'), '')
        .replaceAll(RegExp(r'\b\d{3,}\b'), '') // store / card numbers
        .replaceAll(RegExp(r'\*{2,}\d*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.isEmpty) continue;
    return s.length > 40 ? s.substring(0, 40).trim() : s;
  }
  return 'Przelew';
}

String _hash(BankRow r, int occurrence) =>
    sha1.convert(utf8.encode('${r.date.toIso8601String()}|${r.cents}|${r.description}|$occurrence')).toString();

class ImportedTxn {
  ImportedTxn(this.row, this.hash, {this.matchedReceiptId, this.newReceipt});
  final BankRow row;
  final String hash;
  final int? matchedReceiptId;
  final Receipt? newReceipt;
}

class ImportPlan {
  ImportPlan(this.txns, {required this.duplicates, required this.incomes});
  final List<ImportedTxn> txns;
  final int duplicates;
  final int incomes;

  int get matched => txns.where((t) => t.matchedReceiptId != null).length;
  List<Receipt> get newReceipts => [for (final t in txns) if (t.newReceipt != null) t.newReceipt!];
  int get newTotalCents => newReceipts.fold(0, (a, r) => a + r.totalCents);
}

/// Decides what an import does without touching the database:
/// - already imported rows (same hash) are skipped;
/// - money in is skipped (this app tracks spending);
/// - an expense matching a saved receipt (same amount, within [dayWindow] days,
///   receipt not yet claimed) is linked to it instead of double-counted;
/// - the rest become single-line expenses when [addUnmatched] is set.
ImportPlan planImport(
  List<BankRow> rows,
  List<Receipt> receipts,
  Set<String> knownHashes, {
  bool addUnmatched = true,
  int dayWindow = 4,
  Set<int> claimedReceiptIds = const {},
}) {
  final claimed = {...claimedReceiptIds};
  final seen = <String, int>{};
  final txns = <ImportedTxn>[];
  var dup = 0;
  var inc = 0;
  for (final r in rows) {
    final baseKey = '${r.date.toIso8601String()}|${r.cents}|${r.description}';
    final n = seen[baseKey] = (seen[baseKey] ?? -1) + 1;
    final h = _hash(r, n);
    if (knownHashes.contains(h)) {
      dup++;
      continue;
    }
    if (r.cents >= 0) {
      inc++;
      continue;
    }
    final amount = -r.cents;
    Receipt? match;
    for (final rc in receipts) {
      if (rc.id == null || claimed.contains(rc.id)) continue;
      if (rc.totalCents == amount && rc.date.difference(r.date).inDays.abs() <= dayWindow) {
        match = rc;
        break;
      }
    }
    if (match != null) {
      claimed.add(match.id!);
      txns.add(ImportedTxn(r, h, matchedReceiptId: match.id));
      continue;
    }
    if (!addUnmatched) {
      txns.add(ImportedTxn(r, h));
      continue;
    }
    final store = cleanMerchant(r.description);
    final cat = guessCategory(r.description, store: store);
    txns.add(ImportedTxn(
      r,
      h,
      newReceipt: Receipt(
        store: store,
        date: r.date,
        totalCents: amount,
        source: ReadSource.bank,
        engineLabel: 'Import z banku',
        // A bank line has no product detail; the merchant is the useful name (the raw
        // description is mostly the operation type and would pollute search).
        items: [ReceiptItem(name: store, cents: amount, category: cat)],
      ),
    ));
  }
  return ImportPlan(txns, duplicates: dup, incomes: inc);
}
