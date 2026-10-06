import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/models.dart';
import 'package:rachunkownik/domain/reminders.dart';
import 'package:rachunkownik/notifications/notification_gateway.dart';
import 'package:rachunkownik/notifications/notification_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeGateway implements NotificationGateway {
  final scheduled = <Reminder>[];
  final shown = <(int, String, String)>[];
  final cancelled = <int>[];

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(int id, String title, String body) async => shown.add((id, title, body));
  @override
  Future<void> schedule(Reminder r) async => scheduled.add(r);
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

Future<AppDb> freshDb() async {
  final dir = await Directory.systemTemp.createTemp('rachunkownik_test');
  return AppDb.open(path: '${dir.path}/test.db');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final now = DateTime(2026, 10, 5, 12);

  group('subscription reminders', () {
    test('monthly subscription: one reminder per upcoming cycle, day before at 9:00', () {
      final subs = [
        Subscription(id: 1, name: 'Netflix', cents: 4900, nextDate: DateTime(2026, 10, 14)),
      ];
      final plan = planSubscriptionReminders(subs, now);
      expect(plan.map((r) => r.when), [
        DateTime(2026, 10, 13, 9),
        DateTime(2026, 11, 13, 9),
        DateTime(2026, 12, 13, 9),
      ]);
      expect(plan.first.title, 'Jutro odnowienie: Netflix');
      expect(plan.first.body, contains('49,00'));
      expect(plan.map((r) => r.id).toSet().length, 3);
    });

    test('a stored date in the past rolls forward; reminders in the past are skipped', () {
      final subs = [
        Subscription(id: 2, name: 'Spotify', cents: 2399, nextDate: DateTime(2026, 8, 6)),
        // Renews tomorrow, but 9:00 today has already passed at 12:00.
        Subscription(id: 3, name: 'VPS', cents: 2900, nextDate: DateTime(2026, 10, 6)),
        Subscription(id: 4, name: 'Stara', cents: 100, nextDate: DateTime(2026, 11, 1), active: false),
      ];
      final plan = planSubscriptionReminders(subs, now);
      expect(plan.where((r) => r.title.contains('Spotify')).first.when, DateTime(2026, 11, 5, 9));
      expect(plan.where((r) => r.title.contains('VPS')).first.when, DateTime(2026, 11, 5, 9));
      expect(plan.any((r) => r.title.contains('Stara')), isFalse);
    });

    test('yearly and configurable lead time', () {
      final subs = [Subscription(id: 5, name: 'Dysk', cents: 12000, period: BillingPeriod.yearly, nextDate: DateTime(2026, 12, 20))];
      final plan = planSubscriptionReminders(subs, now, daysBefore: 3, cycles: 2);
      expect(plan.map((r) => r.when), [DateTime(2026, 12, 17, 9), DateTime(2027, 12, 17, 9)]);
      expect(plan.first.title, startsWith('Za 3 dni'));
    });
  });

  group('budget alerts', () {
    final budgets = [Budget(category: 'Jedzenie', limitCents: 100000)];

    test('levels and no repeats', () {
      expect(newBudgetAlerts({'Jedzenie': 79000}, budgets, {}, now), isEmpty);
      final at80 = newBudgetAlerts({'Jedzenie': 82000}, budgets, {}, now);
      expect(at80.single.level, 80);
      expect(at80.single.title, 'Budżet Jedzenie: 82%');
      expect(newBudgetAlerts({'Jedzenie': 85000}, budgets, {'Jedzenie': 80}, now), isEmpty);
      final at100 = newBudgetAlerts({'Jedzenie': 104000}, budgets, {'Jedzenie': 80}, now);
      expect(at100.single.level, 100);
      expect(at100.single.title, startsWith('Przekroczono budżet'));
      expect(newBudgetAlerts({'Jedzenie': 120000}, budgets, {'Jedzenie': 100}, now), isEmpty);
    });
  });

  group('NotificationSync', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<AppDb> withData() async {
      final db = await freshDb();
      await db.addSubscription(Subscription(name: 'Netflix', cents: 4900, nextDate: DateTime(2026, 10, 14)));
      await db.setBudget('Jedzenie', 100000);
      await db.saveReceipt(Receipt(store: 'Biedronka', date: DateTime(2026, 10, 2), totalCents: 82000, items: [
        ReceiptItem(name: 'Zakupy', cents: 82000, category: 'Jedzenie'),
      ]));
      return db;
    }

    test('does nothing until the user turns notifications on', () async {
      final g = FakeGateway();
      await NotificationSync(await withData(), g).run(now: now);
      expect(g.scheduled, isEmpty);
      expect(g.shown, isEmpty);
    });

    test('schedules reminders and replaces them on the next run', () async {
      SharedPreferences.setMockInitialValues({NotificationPrefs.subs: true});
      final g = FakeGateway();
      final sync = NotificationSync(await withData(), g);
      await sync.run(now: now);
      expect(g.scheduled.length, 3);
      expect(g.cancelled, isEmpty);

      await sync.run(now: now);
      expect(g.cancelled.length, 3); // the old ones are cleared first
      expect(g.scheduled.length, 6);

      SharedPreferences.setMockInitialValues({NotificationPrefs.subs: false, 'sub_reminder_ids': g.scheduled.take(3).map((r) => '${r.id}').toList()});
      final g2 = FakeGateway();
      await NotificationSync(await withData(), g2).run(now: now);
      expect(g2.scheduled, isEmpty);
      expect(g2.cancelled.length, 3); // switching off removes what was scheduled
    });

    test('budget alert fires once per level per month', () async {
      SharedPreferences.setMockInitialValues({NotificationPrefs.budget: true});
      final g = FakeGateway();
      final db = await withData();
      final sync = NotificationSync(db, g);
      await sync.run(now: now);
      expect(g.shown.length, 1);
      expect(g.shown.single.$2, 'Budżet Jedzenie: 82%');

      await sync.run(now: now);
      expect(g.shown.length, 1); // same level, no repeat

      await db.saveReceipt(Receipt(store: 'Kaufland', date: DateTime(2026, 10, 4), totalCents: 25000, items: [
        ReceiptItem(name: 'Zakupy', cents: 25000, category: 'Jedzenie'),
      ]));
      await sync.run(now: now);
      expect(g.shown.length, 2);
      expect(g.shown.last.$2, startsWith('Przekroczono budżet'));
    });
  });
}
