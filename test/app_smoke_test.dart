import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/ai_settings.dart';
import 'package:rachunkownik/ai/device_check.dart';
import 'package:rachunkownik/app.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/models.dart';
import 'package:rachunkownik/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real sqflite I/O runs outside the fake-async zone, so let it finish between pumps.
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

  testWidgets('every tab and the AI settings screens render', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    // Tests render with the wide Ahem font, so use a roomy (still mobile-layout) viewport.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = await tester.runAsync(() async {
      final d = await AppDb.open(path: inMemoryDatabasePath);
      await d.saveReceipt(Receipt(
        store: 'Biedronka',
        date: DateTime.now(),
        totalCents: 878,
        items: [ReceiptItem(name: 'Mleko', cents: 878, category: 'Jedzenie')],
      ));
      await d.setBudget('Jedzenie', 150000);
      return d;
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db!),
        initialAiSettingsProvider.overrideWithValue(AiSettings.defaults()),
        deviceProfileProvider.overrideWith((ref) async => const DeviceProfile(
              os: OsFamily.ios,
              name: 'iPhone16,1',
              totalRamBytes: 3 * 1000 * 1000 * 1000,
              freeDiskBytes: 18 * 1000 * 1000 * 1000,
            )),
      ],
      child: const RachunkownikApp(),
    ));
    await settle(tester);
    expect(find.text('Budżety'), findsOneWidget);
    expect(find.text('Biedronka'), findsWidgets);

    for (final tab in ['Paragony', 'Subskrypcje', 'Ustawienia']) {
      await tester.tap(find.text(tab).last);
      await settle(tester);
    }
    expect(find.text('Model AI'), findsOneWidget);
    expect(find.text('Czat o wydatkach'), findsOneWidget);

    await tester.tap(find.text('Dostawca API'));
    await settle(tester);
    expect(find.text('Testuj połączenie'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // Data tools: charts, import, export entry points.
    await tester.tap(find.text('Analiza i wykresy').last);
    await settle(tester);
    expect(find.text('Ostatnie 6 miesięcy'), findsOneWidget);
    expect(find.text('Kategorie'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Import z banku (CSV)'));
    await settle(tester);
    expect(find.text('Wybierz plik CSV'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Eksport do CSV'), findsOneWidget);

    await tester.tap(find.text('Modele lokalne i pobieranie'));
    await settle(tester);
    expect(find.text('Pobierz'), findsWidgets);
    expect(find.text('Gemma 4 E2B'), findsOneWidget);
    // 3 GB phone: Gemma 4 is below the publisher's RAM floor, SmolVLM2 is recommended.
    expect(find.textContaining('Za ciężki dla tego telefonu'), findsWidgets);
    expect(find.textContaining('Pójdzie płynnie'), findsWidgets);
    expect(find.text('Polecany'), findsWidgets);
    expect(find.text('iPhone16,1'), findsOneWidget);
  });
}
