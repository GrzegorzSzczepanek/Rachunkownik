import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/ai_settings.dart';
import 'package:rachunkownik/app.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/models.dart';
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

  testWidgets('open a saved receipt, fix a line and the total, save', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('rk_edit');
      final d = await AppDb.open(path: '${dir.path}/t.db');
      await d.saveReceipt(Receipt(
        store: 'Biedronka',
        date: DateTime.now(),
        totalCents: 878,
        items: [
          ReceiptItem(name: 'Mleko', cents: 429, category: 'Jedzenie'),
          ReceiptItem(name: 'Chleb', cents: 449, category: 'Jedzenie'),
        ],
      ));
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

    await tester.tap(find.text('Paragony').last);
    await settle(tester);
    await tester.tap(find.text('Biedronka'));
    await settle(tester);
    expect(find.text('Zapisz zmiany'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // Fix a line: Mleko 4,29 -> 5,00
    await tester.tap(find.text('Mleko'));
    await settle(tester);
    final price = find.widgetWithText(TextField, '4,29');
    await tester.enterText(price, '5,00');
    await tester.tap(find.text('OK'));
    await settle(tester);

    // Fix the receipt total.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '9,49');
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.textContaining('9,49'), findsWidgets);

    await tester.tap(find.text('Zapisz zmiany'));
    await settle(tester);

    final saved = (await tester.runAsync(() => db.receipts()))!.single;
    expect(saved.items.map((i) => i.cents), [500, 449]);
    expect(saved.totalCents, 949);
  });
}
