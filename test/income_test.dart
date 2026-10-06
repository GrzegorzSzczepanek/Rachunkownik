import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/categorizer.dart';
import 'package:rachunkownik/ai/natural_expense_parser.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<AppDb> freshDb() async {
  final dir = await Directory.systemTemp.createTemp('rachunkownik_income_test');
  return AppDb.open(path: '${dir.path}/test.db');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Income auto-categorization', () {
    test('categorizes salary, bonus, freelancing, gifts, returns, investments', () {
      expect(guessIncomeCategory('Wypłata za wrzesień'), 'Wynagrodzenie');
      expect(guessIncomeCategory('Wynagrodzenie z umowy o pracę'), 'Wynagrodzenie');
      expect(guessIncomeCategory('Pensja'), 'Wynagrodzenie');
      expect(guessIncomeCategory('Przelew od pracodawcy'), 'Wynagrodzenie');

      expect(guessIncomeCategory('Zlecenie dla klienta X'), 'Zlecenie');
      expect(guessIncomeCategory('Faktura B2B'), 'Zlecenie');
      expect(guessIncomeCategory('Projekt graficzny freelance'), 'Zlecenie');

      expect(guessIncomeCategory('Premia kwartalna'), 'Premia');
      expect(guessIncomeCategory('Bonus roczny'), 'Premia');

      expect(guessIncomeCategory('Zwrot podatku PIT'), 'Zwrot');
      expect(guessIncomeCategory('Zwrot z Allegro'), 'Zwrot');
      expect(guessIncomeCategory('Cashback z karty'), 'Zwrot');

      expect(guessIncomeCategory('Dywidenda z akcji'), 'Inwestycje');
      expect(guessIncomeCategory('Odsetki lokata'), 'Inwestycje');
      expect(guessIncomeCategory('Zysk z kryptowalut'), 'Inwestycje');

      expect(guessIncomeCategory('Prezent urodzinowy od babci'), 'Prezent');
      expect(guessIncomeCategory('Podarunek od rodziców'), 'Prezent');

      expect(guessIncomeCategory('Sprzedaż starego telefonu'), 'Inne');
      expect(guessIncomeCategory('Losowy wpływ'), 'Inne');
    });
  });

  group('Natural language income parser', () {
    test('detects income phrases and parses amount, title, and category', () {
      expect(isIncomeInput('Wypłata 6500 zł'), isTrue);
      expect(isIncomeInput('Dostałem 250 zł premii'), isTrue);
      expect(isIncomeInput('Wpływ za zlecenie 1200 pln'), isTrue);
      expect(isIncomeInput('Kupiłem chleb za 5 zł'), isFalse);
      expect(isIncomeInput('Ile wydałem w tym miesiącu?'), isFalse);

      final date = DateTime(2026, 10, 7);
      final income1 = parseNaturalIncome('Wypłata 5400 zł', date);
      expect(income1.cents, 540000);
      expect(income1.title, contains('Wypłata'));
      expect(income1.category, 'Wynagrodzenie');

      final income2 = parseNaturalIncome('Dostałem 300,50 zł premii', date);
      expect(income2.cents, 30050);
      expect(income2.title, contains('Premii'));
      expect(income2.category, 'Premia');

      final income3 = parseNaturalIncome('Zwrot podatku 1500 zł', date);
      expect(income3.cents, 150000);
      expect(income3.category, 'Zwrot');
    });
  });

  group('AppDb income operations', () {
    test('CRUD, monthly totals, category breakdown, and backup restore', () async {
      final db = await freshDb();

      // 1. Save incomes
      final id1 = await db.saveIncome(Income(
        title: 'Wypłata',
        cents: 500000,
        category: 'Wynagrodzenie',
        date: DateTime(2026, 10, 1),
        note: 'Przelew główny',
      ));

      final id2 = await db.saveIncome(Income(
        title: 'Projekt freelance',
        cents: 120000,
        category: 'Zlecenie',
        date: DateTime(2026, 10, 3),
      ));

      final id3 = await db.saveIncome(Income(
        title: 'Premia kwartalna',
        cents: 80000,
        category: 'Premia',
        date: DateTime(2026, 10, 5),
      ));

      // Incomes in September (different month)
      await db.saveIncome(Income(
        title: 'Wypłata wrzesień',
        cents: 480000,
        category: 'Wynagrodzenie',
        date: DateTime(2026, 9, 1),
      ));

      // 2. Query all & filter by date
      final octIncomes = await db.incomes(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31, 23, 59, 59),
      );
      expect(octIncomes.length, 3);
      expect(octIncomes.first.cents, 80000); // Sorted desc by date

      // 3. Total and breakdown
      final totalOct = await db.totalIncome(
        DateTime(2026, 10, 1),
        DateTime(2026, 11, 1),
      );
      expect(totalOct, 500000 + 120000 + 80000);

      final byCat = await db.incomeByCategory(
        DateTime(2026, 10, 1),
        DateTime(2026, 11, 1),
      );
      expect(byCat['Wynagrodzenie'], 500000);
      expect(byCat['Zlecenie'], 120000);
      expect(byCat['Premia'], 80000);

      // 4. Update
      final updated = octIncomes.firstWhere((i) => i.id == id2).copy(
        cents: 150000,
        title: 'Projekt freelance (z bonusem)',
      );
      await db.updateIncome(updated);

      final refreshed = (await db.incomes()).firstWhere((i) => i.id == id2);
      expect(refreshed.cents, 150000);
      expect(refreshed.title, 'Projekt freelance (z bonusem)');

      // 5. Backup export and restore
      final backupJson = await db.exportBackupJson();
      expect(backupJson, contains('Projekt freelance (z bonusem)'));

      // Delete one income
      await db.deleteIncome(id1);
      expect((await db.incomes()).any((i) => i.id == id1), isFalse);

      // Restore from backup
      final stats = await db.restoreBackupJson(backupJson);
      expect(stats.incomesCount, 4);

      final restoredIncomes = await db.incomes();
      expect(restoredIncomes.length, 4);
      expect(restoredIncomes.any((i) => i.title == 'Wypłata'), isTrue);
    });
  });
}
