import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/bank_import.dart';
import 'package:rachunkownik/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<AppDb> freshDb() async {
  final dir = await Directory.systemTemp.createTemp('backup_test_');
  return AppDb.open(path: '${dir.path}/test.db');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('backup and restore roundtrip preserves receipts, items, budgets, subscriptions and bank links', () async {
    final db1 = await freshDb();

    // 1. Seed db1
    final r1Id = await db1.saveReceipt(Receipt(
      store: 'Lidl',
      date: DateTime(2026, 9, 20),
      totalCents: 1599,
      source: ReadSource.manual,
      items: [
        ReceiptItem(name: 'Chleb', cents: 499, category: 'Jedzenie'),
        ReceiptItem(name: 'Masło', cents: 1100, category: 'Jedzenie', lowConfidence: true),
      ],
    ));

    await db1.setBudget('Jedzenie', 80000);
    await db1.addSubscription(Subscription(
      name: 'Netflix',
      cents: 4900,
      period: BillingPeriod.monthly,
      nextDate: DateTime(2026, 10, 15),
    ));
    await db1.dismissSub('Przelew własny');

    final plan = planImport(
      [BankRow(DateTime(2026, 9, 20), 'ZAKUP LIDL', -1599)],
      await db1.receipts(),
      await db1.knownBankHashes(),
      claimedReceiptIds: await db1.claimedReceiptIds(),
    );
    await db1.saveImport(plan);

    // Verify db1 state
    expect(await db1.receipts(), hasLength(1));
    expect(await db1.budgets(), hasLength(1));
    expect(await db1.subscriptions(), hasLength(1));
    expect(await db1.dismissedSubs(), contains('Przelew własny'));
    expect(await db1.claimedReceiptIds(), contains(r1Id));

    // 2. Export backup
    final jsonStr = await db1.exportBackupJson();
    expect(jsonStr, contains('rachunkownik'));
    expect(jsonStr, contains('Lidl'));
    expect(jsonStr, contains('Netflix'));

    // 3. Create fresh db2 and seed with dummy data to prove restore wipes it
    final db2 = await freshDb();
    await db2.saveReceipt(Receipt(
      store: 'DummyStore',
      date: DateTime(2026, 1, 1),
      totalCents: 100,
      items: [ReceiptItem(name: 'Coś', cents: 100, category: 'Inne')],
    ));
    await db2.setBudget('Transport', 20000);
    expect(await db2.receipts(), hasLength(1));

    // 4. Restore into db2
    final stats = await db2.restoreBackupJson(jsonStr);
    expect(stats.receiptsCount, 1);
    expect(stats.itemsCount, 2);
    expect(stats.budgetsCount, 1);
    expect(stats.subscriptionsCount, 1);
    expect(stats.bankTransactionsCount, 1);

    // 5. Verify restored state in db2
    final restoredReceipts = await db2.receipts();
    expect(restoredReceipts, hasLength(1));
    expect(restoredReceipts.single.store, 'Lidl');
    expect(restoredReceipts.single.totalCents, 1599);
    expect(restoredReceipts.single.items, hasLength(2));
    expect(restoredReceipts.single.items[1].lowConfidence, isTrue);

    final restoredBudgets = await db2.budgets();
    expect(restoredBudgets, hasLength(1));
    expect(restoredBudgets.single.category, 'Jedzenie');
    expect(restoredBudgets.single.limitCents, 80000);

    final restoredSubs = await db2.subscriptions();
    expect(restoredSubs, hasLength(1));
    expect(restoredSubs.single.name, 'Netflix');
    expect(restoredSubs.single.cents, 4900);

    expect(await db2.dismissedSubs(), contains('Przelew własny'));

    // Check bank link integrity: the restored receipt id should be claimed by bank transaction
    final newReceiptId = restoredReceipts.single.id!;
    expect(await db2.claimedReceiptIds(), contains(newReceiptId));
  });

  test('restoreBackup throws on invalid signature or unsupported version', () async {
    final db = await freshDb();

    // Invalid JSON structure
    expect(() => db.restoreBackupJson('not a json'), throwsFormatException);
    expect(() => db.restoreBackupJson('[]'), throwsFormatException);

    // Wrong app signature
    expect(
      () => db.restoreBackupJson(jsonEncode({'app': 'other_app', 'version': 1})),
      throwsFormatException,
    );

    // Unsupported version
    expect(
      () => db.restoreBackupJson(jsonEncode({'app': 'rachunkownik', 'version': 99})),
      throwsFormatException,
    );
  });
}
