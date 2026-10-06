import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';
import 'notification_gateway.dart';

class NotificationPrefs {
  static const budget = 'notify_budget';
  static const subs = 'notify_subs';
  static const days = 'notify_days';
  static const _scheduledIds = 'sub_reminder_ids';
  static String level(DateTime now, String category) =>
      'budget_level_${now.year}-${now.month}_$category';
}

int budgetAlertId(String category) {
  final i = defaultCategories.indexOf(category);
  return 200000 + (i < 0 ? 99 : i);
}

/// Brings the OS notifications in line with the data: reminders for upcoming
/// renewals and alerts for budgets that crossed 80% or 100% this month.
/// Safe to call often; it only shows what is new.
class NotificationSync {
  NotificationSync(this.db, this.gateway);
  final AppDb db;
  final NotificationGateway gateway;

  Future<void> run({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final p = await SharedPreferences.getInstance();
    try {
      await _subscriptions(p, t);
      await _budgets(p, t);
    } catch (_) {
      // Notifications are a convenience; never let them break the app.
    }
  }

  Future<void> _subscriptions(SharedPreferences p, DateTime now) async {
    for (final id in p.getStringList(NotificationPrefs._scheduledIds) ?? const <String>[]) {
      await gateway.cancel(int.parse(id));
    }
    final ids = <String>[];
    if (p.getBool(NotificationPrefs.subs) ?? false) {
      final plan = planSubscriptionReminders(await db.subscriptions(), now,
          daysBefore: p.getInt(NotificationPrefs.days) ?? 1);
      for (final r in plan) {
        await gateway.schedule(r);
        ids.add('${r.id}');
      }
    }
    await p.setStringList(NotificationPrefs._scheduledIds, ids);
  }

  Future<void> _budgets(SharedPreferences p, DateTime now) async {
    if (!(p.getBool(NotificationPrefs.budget) ?? false)) return;
    final from = DateTime(now.year, now.month);
    final spent = await db.spendByCategory(from, DateTime(now.year, now.month + 1));
    final budgets = await db.budgets();
    final announced = {
      for (final b in budgets) b.category: p.getInt(NotificationPrefs.level(now, b.category)) ?? 0,
    };
    for (final a in newBudgetAlerts(spent, budgets, announced, now)) {
      await gateway.show(budgetAlertId(a.category), a.title, a.body);
      await p.setInt(NotificationPrefs.level(now, a.category), a.level);
    }
  }
}
