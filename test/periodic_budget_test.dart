import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/ai_settings.dart';
import 'package:rachunkownik/app.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/models.dart';
import 'package:rachunkownik/features/periodic_budget_dialog.dart';
import 'package:rachunkownik/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Periodic budgets DB operations', () {
    test('save, query spend calculation, update and delete periodic budget', () async {
      final dir = await Directory.systemTemp.createTemp('rk_periodic_test');
      final db = await AppDb.open(path: '${dir.path}/test.db');

      final friday = DateTime(2026, 10, 9, 12, 0);
      final saturday = DateTime(2026, 10, 10, 15, 30);
      final mondayAfter = DateTime(2026, 10, 12, 9, 0);

      // Save receipts
      await db.saveReceipt(Receipt(
        store: 'Restauracja Zakopane',
        date: friday,
        totalCents: 15000,
        items: [ReceiptItem(name: 'Obiad', cents: 15000, category: 'Jedzenie')],
      ));
      await db.saveReceipt(Receipt(
        store: 'Termy',
        date: saturday,
        totalCents: 12000,
        items: [ReceiptItem(name: 'Bilety', cents: 12000, category: 'Rozrywka')],
      ));
      await db.saveReceipt(Receipt(
        store: 'Stacja paliw (poza weekendem)',
        date: mondayAfter,
        totalCents: 20000,
        items: [ReceiptItem(name: 'Paliwo', cents: 20000, category: 'Transport')],
      ));

      // 1. All expenses weekend budget
      final weekendBudget = PeriodicBudget(
        name: 'Weekend w górach',
        limitCents: 40000, // 400 zł
        period: BudgetPeriod.custom,
        startDate: DateTime(2026, 10, 9),
        endDate: DateTime(2026, 10, 11),
      );
      final id = await db.savePeriodicBudget(weekendBudget);
      expect(id, isPositive);

      final list = await db.periodicBudgets();
      expect(list.length, 1);
      final b = list.first;
      expect(b.name, 'Weekend w górach');
      // Friday (150) + Saturday (120) = 270 zł; Monday is excluded
      expect(b.spentCents, 27000);
      expect(b.remainingCents, 13000);
      expect(b.isOverBudget, isFalse);

      // 2. Category-specific weekend budget (only 'Jedzenie')
      await db.savePeriodicBudget(PeriodicBudget(
        name: 'Weekend jedzenie',
        category: 'Jedzenie',
        limitCents: 20000,
        period: BudgetPeriod.custom,
        startDate: DateTime(2026, 10, 9),
        endDate: DateTime(2026, 10, 11),
      ));

      final list2 = await db.periodicBudgets();
      expect(list2.length, 2);
      final foodBudget = list2.firstWhere((x) => x.name == 'Weekend jedzenie');
      expect(foodBudget.spentCents, 15000); // Only restaurant food

      // 3. Update budget limit
      await db.updatePeriodicBudget(PeriodicBudget(
        id: b.id,
        name: 'Weekend w górach (zwiększony)',
        limitCents: 50000,
        period: b.period,
        startDate: b.startDate,
        endDate: b.endDate,
      ));
      final updated = (await db.periodicBudgets()).firstWhere((x) => x.id == b.id);
      expect(updated.name, 'Weekend w górach (zwiększony)');
      expect(updated.limitCents, 50000);

      // 4. Delete budget
      await db.deletePeriodicBudget(b.id!);
      expect((await db.periodicBudgets()).length, 1);
    });

    test('backup and restore preserves periodic budgets', () async {
      final dir1 = await Directory.systemTemp.createTemp('rk_pb_b1');
      final db1 = await AppDb.open(path: '${dir1.path}/b1.db');
      await db1.savePeriodicBudget(PeriodicBudget(
        name: 'Wyjazd majowy',
        limitCents: 100000,
        period: BudgetPeriod.custom,
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 4),
      ));

      final exported = await db1.exportBackup();
      expect(exported.containsKey('periodic_budgets'), isTrue);

      final dir2 = await Directory.systemTemp.createTemp('rk_pb_b2');
      final db2 = await AppDb.open(path: '${dir2.path}/b2.db');
      await db2.restoreBackup(exported);

      final restored = await db2.periodicBudgets();
      expect(restored.length, 1);
      expect(restored.first.name, 'Wyjazd majowy');
      expect(restored.first.limitCents, 100000);
    });
  });

  testWidgets('Overview screen creates weekend periodic budget and displays it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('rk_ui_pb');
      final d = await AppDb.open(path: '${dir.path}/ui.db');
      return d;
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db!),
        initialAiSettingsProvider.overrideWithValue(AiSettings.defaults()),
      ],
      child: const RachunkownikApp(),
    ));
    await settle(tester);

    // Budgets section is visible on Overview
    expect(find.text('Budżety'), findsOneWidget);
    expect(find.text('Dodaj budżet'), findsWidgets);

    // Tap "Dodaj budżet"
    await tester.tap(find.text('Dodaj budżet').first);
    await settle(tester);

    // Modal bottom sheet opens
    expect(find.text('Ten weekend'), findsOneWidget);
    expect(find.text('Ten tydzień'), findsOneWidget);
    expect(find.text('Własny okres'), findsOneWidget);

    // Enter name & limit
    final nameField = find.byKey(const ValueKey('budgetNameField'));
    await tester.enterText(nameField, 'Mój wypad na weekend');
    await tester.pumpAndSettle();

    final limitField = find.byKey(const ValueKey('budgetLimitField'));
    await tester.ensureVisible(limitField);
    await tester.enterText(limitField, '600');
    await tester.pumpAndSettle();

    // Save
    await tester.ensureVisible(find.byKey(const ValueKey('budgetSaveButton')));
    await tester.tap(find.byKey(const ValueKey('budgetSaveButton')));
    await settle(tester);

    // Verified: Budget is displayed in Overview section
    expect(find.text('Mój wypad na weekend'), findsOneWidget);
    expect(find.textContaining('600,00'), findsWidgets);
    expect(find.text('Budżety wyjazdowe i okresowe'), findsOneWidget);
  });
}
