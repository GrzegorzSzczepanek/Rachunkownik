import '../core/money.dart';
import 'models.dart';

/// A notification to show at [when].
class Reminder {
  const Reminder(this.id, this.when, this.title, this.body);
  final int id;
  final DateTime when;
  final String title;
  final String body;
}

/// Ids 100000+ belong to subscription reminders so they can be cleared without
/// touching other notifications: 100000 + subscriptionId * 10 + cycle.
const subscriptionReminderBase = 100000;
int subscriptionReminderId(int subscriptionId, int cycle) =>
    subscriptionReminderBase + subscriptionId * 10 + cycle;

DateTime _addPeriod(DateTime d, BillingPeriod p) => p == BillingPeriod.monthly
    ? DateTime(d.year, d.month + 1, d.day)
    : DateTime(d.year + 1, d.month, d.day);

/// Reminders for the next [cycles] renewals of every active subscription,
/// [daysBefore] days ahead at [hour]:00. Only future times are returned.
/// Looking several cycles ahead keeps reminders coming even if the app isn't
/// opened for a while; they are rebuilt whenever it is.
List<Reminder> planSubscriptionReminders(
  List<Subscription> subs,
  DateTime now, {
  int daysBefore = 1,
  int hour = 9,
  int cycles = 3,
}) {
  final out = <Reminder>[];
  for (final s in subs) {
    if (!s.active || s.id == null) continue;
    var renewal = s.nextRenewal(now);
    for (var c = 0; c < cycles; c++) {
      final remindDay = renewal.subtract(Duration(days: daysBefore));
      final when = DateTime(remindDay.year, remindDay.month, remindDay.day, hour);
      if (when.isAfter(now)) {
        final label = daysBefore == 0
            ? 'Dziś odnowienie'
            : daysBefore == 1
                ? 'Jutro odnowienie'
                : 'Za $daysBefore dni odnowienie';
        out.add(Reminder(
          subscriptionReminderId(s.id!, c),
          when,
          '$label: ${s.name}',
          '${formatMoney(s.cents)} · ${shortDate(renewal)}',
        ));
      }
      renewal = _addPeriod(renewal, s.period);
    }
  }
  return out;
}

/// What share of a budget is spent, as a level: 0 (<80%), 80 or 100.
int budgetLevel(int spentCents, int limitCents) {
  if (limitCents <= 0) return 0;
  final f = spentCents / limitCents;
  return f >= 1 ? 100 : (f >= 0.8 ? 80 : 0);
}

class BudgetAlert {
  const BudgetAlert(this.category, this.level, this.title, this.body);
  final String category;
  final int level;
  final String title;
  final String body;
}

/// Alerts for budgets whose level rose above what was already announced
/// ([announced]: category -> 0/80/100 for this month). Never repeats a level,
/// and going from 80 to 100 alerts again.
List<BudgetAlert> newBudgetAlerts(
  Map<String, int> spentByCategory,
  List<Budget> budgets,
  Map<String, int> announced,
  DateTime now,
) {
  final out = <BudgetAlert>[];
  for (final b in budgets) {
    final spent = spentByCategory[b.category] ?? 0;
    final level = budgetLevel(spent, b.limitCents);
    if (level == 0 || level <= (announced[b.category] ?? 0)) continue;
    final pct = (spent * 100 / b.limitCents).round();
    out.add(BudgetAlert(
      b.category,
      level,
      level == 100 ? 'Przekroczono budżet: ${b.category}' : 'Budżet ${b.category}: $pct%',
      '${formatMoney(spent)} z ${formatMoney(b.limitCents)} w tym miesiącu',
    ));
  }
  return out;
}
