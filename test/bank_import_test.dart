import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/domain/bank_import.dart';
import 'package:rachunkownik/domain/csv_export.dart';
import 'package:rachunkownik/domain/models.dart';

const mbank = '''mBank S.A. Bankowość Detaliczna;
Skrócony Elektroniczny Wyciąg z Rachunku;
;
#Data księgowania;#Data operacji;#Opis operacji;#Tytuł;#Nadawca/Odbiorca;#Numer konta;#Kwota;#Saldo po operacji;
2026-10-05;2026-10-04;ZAKUP PRZY UŻYCIU KARTY;BIEDRONKA 1234 WARSZAWA;BIEDRONKA;'12 3456';-87,34 PLN;1 234,00 PLN;
2026-10-03;2026-10-02;PRZELEW PRZYCHODZĄCY;Wypłata;Firma Sp. z o.o.;'98 7654';5 000,00 PLN;5 321,34 PLN;
2026-09-12;2026-09-12;ZAKUP PRZY UŻYCIU KARTY;GOOGLE *STORAGE;GOOGLE;'';-9,99 PLN;100,00 PLN;
''';

const pko = '''"Data operacji","Data waluty","Typ transakcji","Kwota","Waluta","Saldo po transakcji","Opis transakcji"
"2026-10-05","2026-10-05","Płatność kartą","-42.90","PLN","+1000.00","Tytuł: ROSSMANN 123"
"2026-10-01","2026-10-01","Przelew","1 250,00","PLN","+1042.90","Zwrot"
''';

const ing = '''"Lista transakcji";;
"Data transakcji";"Data księgowania";"Dane kontrahenta";"Tytuł";"Nr rachunku";"Nazwa banku";"Szczegóły";"Nr transakcji";"Kwota transakcji (waluta rachunku)";"Waluta";"Kwota blokady/zwolnienie blokady";"Waluta";
05.10.2026;05.10.2026;"ŻABKA Z1234";"Płatność kartą 05.10.2026";;;;;-14,48;PLN;;
''';

void main() {
  test('amount parsing handles Polish and English formats', () {
    expect(parseAmountCents('-87,34 PLN'), -8734);
    expect(parseAmountCents('5 000,00 PLN'), 500000);
    expect(parseAmountCents('1.234,56'), 123456);
    expect(parseAmountCents('-12.50'), -1250);
    expect(parseAmountCents('+1000.00'), 100000);
    expect(parseAmountCents('12,5'), 1250);
    expect(parseAmountCents('1 234'), 123400);
    expect(parseAmountCents('abc'), isNull);
    expect(parseAmountCents(''), isNull);
  });

  test('date parsing handles common bank formats and rejects junk', () {
    expect(parseBankDate('2026-10-05'), DateTime(2026, 10, 5));
    expect(parseBankDate('05.10.2026'), DateTime(2026, 10, 5));
    expect(parseBankDate('05-10-2026 14:22'), DateTime(2026, 10, 5));
    expect(parseBankDate('2026/10/05'), DateTime(2026, 10, 5));
    expect(parseBankDate('31.02.2026'), isNull);
    expect(parseBankDate('Data'), isNull);
  });

  test('mBank: preamble skipped, operation date preferred, amounts parsed', () {
    final rows = parseCsvText(mbank);
    final layout = detectLayout(rows)!;
    expect(rows[layout.headerRow].first, '#Data księgowania');
    expect(rows[layout.dateCol == 1 ? layout.headerRow : layout.headerRow][layout.dateCol], '#Data operacji');
    final data = extractRows(rows, layout);
    expect(data.length, 3);
    expect(data.first.date, DateTime(2026, 10, 4));
    expect(data.first.cents, -8734);
    expect(data[1].cents, 500000);
    expect(data.first.description, contains('BIEDRONKA'));
  });

  test('PKO BP: comma-separated quoted file', () {
    final data = extractRows(parseCsvText(pko), detectLayout(parseCsvText(pko))!);
    expect(data.length, 2);
    expect(data.first.cents, -4290);
    expect(data.first.description, contains('ROSSMANN'));
    expect(data[1].cents, 125000);
  });

  test('ING: DD.MM.YYYY dates, first amount column wins over blocked-amount', () {
    final data = extractRows(parseCsvText(ing), detectLayout(parseCsvText(ing))!);
    expect(data.length, 1);
    expect(data.single.date, DateTime(2026, 10, 5));
    expect(data.single.cents, -1448);
    expect(data.single.description, contains('ŻABKA'));
  });

  test('unrecognised file yields no layout', () {
    expect(detectLayout(parseCsvText('a;b;c\n1;2;3\n')), isNull);
  });

  test('Windows-1250 bytes decode to Polish letters; UTF-8 passes through', () {
    // "Żabka łódź" in cp1250: Ż=AF a b k a space ł=B3 ó=F3 d ź=9F
    final cp = Uint8List.fromList([0xAF, 0x61, 0x62, 0x6B, 0x61, 0x20, 0xB3, 0xF3, 0x64, 0x9F]);
    expect(decodeBankBytes(cp), 'Żabka łódź');
    final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...'Żabka'.codeUnits.map((c) => c).toList().isEmpty ? [] : [0xC5, 0xBB, 0x61]]);
    expect(decodeBankBytes(bom), 'Ża');
  });

  test('merchant names are cleaned', () {
    expect(cleanMerchant('ZAKUP PRZY UŻYCIU KARTY · BIEDRONKA 1234 WARSZAWA'), 'BIEDRONKA WARSZAWA');
    expect(cleanMerchant('Płatność kartą: ŻABKA Z1234 05.10.2026'), 'ŻABKA Z1234');
    expect(cleanMerchant(''), 'Przelew');
  });

  group('planImport', () {
    final rows = [
      BankRow(DateTime(2026, 10, 4), 'BIEDRONKA', -8734),
      BankRow(DateTime(2026, 10, 2), 'Wypłata', 500000),
      BankRow(DateTime(2026, 9, 12), 'GOOGLE *STORAGE', -999),
    ];

    test('matches a receipt, skips income, creates the rest', () {
      final receipt = Receipt(
          id: 7, store: 'Biedronka', date: DateTime(2026, 10, 5), totalCents: 8734, items: []);
      final plan = planImport(rows, [receipt], {});
      expect(plan.matched, 1);
      expect(plan.txns.firstWhere((t) => t.matchedReceiptId == 7).newReceipt, isNull);
      expect(plan.incomes, 1);
      expect(plan.newReceipts.length, 1);
      expect(plan.newReceipts.single.totalCents, 999);
      expect(plan.newReceipts.single.source, ReadSource.bank);
      expect(plan.newReceipts.single.items.single.name, 'GOOGLE *STORAGE'); // merchant, not the raw description
    });

    test('a receipt is only claimed once; far-away dates do not match', () {
      final receipt = Receipt(id: 1, store: 'X', date: DateTime(2026, 10, 5), totalCents: 8734, items: []);
      final two = [rows[0], BankRow(DateTime(2026, 10, 4), 'BIEDRONKA', -8734)];
      expect(planImport(two, [receipt], {}).matched, 1);
      final far = Receipt(id: 2, store: 'X', date: DateTime(2026, 8, 1), totalCents: 8734, items: []);
      expect(planImport([rows[0]], [far], {}).matched, 0);
    });

    test('re-importing the same file adds nothing; identical rows in one file both count', () {
      final first = planImport(rows, [], {});
      final hashes = first.txns.map((t) => t.hash).toSet();
      final again = planImport(rows, [], hashes);
      expect(again.txns, isEmpty);
      expect(again.duplicates, 2); // the income is skipped before hashing counts? no: all known
      final twoCoffees = [
        BankRow(DateTime(2026, 10, 4), 'KAWA', -1000),
        BankRow(DateTime(2026, 10, 4), 'KAWA', -1000),
      ];
      expect(planImport(twoCoffees, [], {}).newReceipts.length, 2);
    });

    test('addUnmatched=false records but does not create expenses', () {
      final plan = planImport(rows, [], {}, addUnmatched: false);
      expect(plan.newReceipts, isEmpty);
      expect(plan.txns.length, 2);
    });
  });

  test('CSV export is Excel-friendly and keeps every receipt', () {
    final csv = receiptsToCsv([
      Receipt(store: 'Biedronka; sp.', date: DateTime(2026, 10, 5), totalCents: 878, items: [
        ReceiptItem(name: 'Mleko "3,2%"', cents: 429, category: 'Jedzenie'),
        ReceiptItem(name: 'Chleb', cents: 449, category: 'Jedzenie'),
      ]),
      Receipt(store: 'Pusty', date: DateTime(2026, 10, 6), totalCents: 100, items: [], source: ReadSource.bank),
    ]);
    expect(csv.startsWith('﻿'), isTrue);
    final lines = csv.trim().split(RegExp(r'\r?\n'));
    expect(lines.length, 4); // header + 2 item rows + 1 row for the receipt without items
    expect(lines.first, contains('Data;Sklep;Pozycja'));
    expect(csv, contains('"Biedronka; sp."'));
    expect(csv, contains('4,29'));
    expect(csv, contains('import z banku'));
  });
}
