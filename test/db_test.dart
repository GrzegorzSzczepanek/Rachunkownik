import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/bank_import.dart';
import 'package:rachunkownik/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


/// Each test gets its own database file; sqflite's in-memory path is shared.
Future<AppDb> freshDb() async {
  final dir = await Directory.systemTemp.createTemp('rachunkownik_test');
  return AppDb.open(path: '${dir.path}/test.db');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('save, query, aggregate, search, delete', () async {
    final db = await freshDb();
    final id = await db.saveReceipt(Receipt(
      store: 'Biedronka',
      date: DateTime(2026, 10, 5),
      totalCents: 878,
      items: [
        ReceiptItem(name: 'Mleko', cents: 429, category: 'Jedzenie'),
        ReceiptItem(name: 'Mydło', cents: 449, category: 'Dom'),
      ],
    ));
    final all = await db.receipts();
    expect(all.single.items.length, 2);
    expect(all.single.mainCategory, 'Dom');

    final by = await db.spendByCategory(DateTime(2026, 10), DateTime(2026, 11));
    expect(by, {'Jedzenie': 429, 'Dom': 449});
    expect(await db.totalSpend(DateTime(2026, 10), DateTime(2026, 11)), 878);
    expect((await db.searchItems('mlek')).length, 1);

    await db.setBudget('Jedzenie', 150000);
    expect((await db.budgets()).single.limitCents, 150000);
    await db.setBudget('Jedzenie', null);
    expect(await db.budgets(), isEmpty);

    await db.deleteReceipt(id);
    expect(await db.receipts(), isEmpty);
  });

  test('bank import: saved, linked to receipts, never imported twice', () async {
    final db = await freshDb();
    await db.saveReceipt(Receipt(
        store: 'Biedronka', date: DateTime(2026, 10, 5), totalCents: 8734, items: []));
    final receipts = await db.receipts();
    final rows = [
      BankRow(DateTime(2026, 10, 4), 'ZAKUP · BIEDRONKA', -8734),
      BankRow(DateTime(2026, 9, 12), 'GOOGLE *STORAGE', -999),
      BankRow(DateTime(2026, 10, 2), 'Wypłata', 500000),
    ];
    final plan = planImport(rows, receipts, await db.knownBankHashes(),
        claimedReceiptIds: await db.claimedReceiptIds());
    await db.saveImport(plan);

    final all = await db.receipts();
    expect(all.length, 2); // original + one new; the matched row did not double-count
    expect(all.where((r) => r.source == ReadSource.bank).single.store, 'GOOGLE *STORAGE');
    expect(await db.totalSpend(DateTime(2026, 9), DateTime(2026, 11)), 8734 + 999);
    expect((await db.knownBankHashes()).length, 2);
    // the matched receipt and the receipt created from the import are both taken
    expect((await db.claimedReceiptIds()).length, 2);

    final again = planImport(rows, await db.receipts(), await db.knownBankHashes(),
        claimedReceiptIds: await db.claimedReceiptIds());
    expect(again.txns, isEmpty);
    await db.saveImport(again);
    expect((await db.receipts()).length, 2);

    final months = await db.monthlyTotals(DateTime(2026, 10), count: 3);
    expect(months.map((m) => m.value).toList(), [0, 999, 8734]);
    expect((await db.topStores(DateTime(2026, 10), DateTime(2026, 11))).single.key, 'Biedronka');
  });

  test('upgrade from schema v1 keeps data and adds the bank table', () async {
    final dir = await Directory.systemTemp.createTemp('rachunkownik_db');
    final path = '${dir.path}/old.db';
    final old = await openDatabase(path, version: 1, onCreate: (d, v) async {
      await d.execute('''CREATE TABLE receipts(id INTEGER PRIMARY KEY AUTOINCREMENT,
        store TEXT NOT NULL, date INTEGER NOT NULL, total INTEGER NOT NULL,
        source TEXT NOT NULL, engine TEXT, image_path TEXT)''');
      await d.execute('''CREATE TABLE items(id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL, name TEXT NOT NULL, cents INTEGER NOT NULL,
        category TEXT NOT NULL, low_confidence INTEGER NOT NULL DEFAULT 0)''');
      await d.execute('CREATE TABLE budgets(category TEXT PRIMARY KEY, limit_cents INTEGER NOT NULL)');
      await d.execute('''CREATE TABLE subscriptions(id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, cents INTEGER NOT NULL, period TEXT NOT NULL,
        next_date INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 1)''');
      await d.execute('CREATE TABLE dismissed_subs(name TEXT PRIMARY KEY)');
      await d.insert('receipts', {
        'store': 'Stary', 'date': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        'total': 100, 'source': 'manual',
      });
    });
    await old.close();

    final db = await AppDb.open(path: path);
    expect((await db.receipts()).single.store, 'Stary');
    expect(await db.knownBankHashes(), isEmpty);
    await dir.delete(recursive: true);
  });

  test('updateReceipt rewrites lines and drops stale vectors; copy() is independent', () async {
    final db = await freshDb();
    final id = await db.saveReceipt(Receipt(
        store: 'Sklep', date: DateTime(2026, 10, 1), totalCents: 300, items: [
      ReceiptItem(name: 'A', cents: 100, category: 'Inne'),
      ReceiptItem(name: 'B', cents: 200, category: 'Inne'),
    ]));
    final saved = (await db.receipts()).single;
    await db.saveVectors('m', {for (final i in saved.items) i.id!: Uint8List.fromList([1, 2, 3, 4])});

    final edited = saved.copy()
      ..store = 'Inny'
      ..totalCents = 450
      ..items.removeLast()
      ..items.add(ReceiptItem(name: 'C', cents: 350, category: 'Dom'));
    expect(saved.items.length, 2); // the original was not touched
    expect(saved.store, 'Sklep');

    await db.updateReceipt(edited);
    final after = (await db.receipts()).single;
    expect(after.id, id);
    expect(after.store, 'Inny');
    expect(after.totalCents, 450);
    expect(after.items.map((i) => i.name), ['A', 'C']);
    expect(await db.vectorsFor('m', after.items.map((i) => i.id!)), isEmpty);
    expect(() => db.updateReceipt(Receipt(store: 'x', date: DateTime.now(), totalCents: 1, items: [])),
        throwsArgumentError);
  });
}
