import 'models.dart';

class SubscriptionCandidate {
  SubscriptionCandidate({
    required this.name,
    required this.cents,
    required this.period,
    required this.occurrences,
    required this.nextDate,
  });
  final String name;
  final int cents;
  final BillingPeriod period;
  final int occurrences;
  final DateTime nextDate;
}

/// One charge: a store/merchant paid [cents] on [date]. Fed from receipts today,
/// from bank import later.
class Charge {
  Charge(this.merchant, this.cents, this.date);
  final String merchant;
  final int cents;
  final DateTime date;
}

/// Same merchant + similar amount (±5%) + steady interval (monthly 26–35 days,
/// yearly 355–375) over at least [minOccurrences] charges.
List<SubscriptionCandidate> detectSubscriptions(
  List<Charge> charges, {
  int minOccurrences = 3,
  Set<String> ignore = const {},
  Set<String> existing = const {},
}) {
  final byMerchant = <String, List<Charge>>{};
  for (final c in charges) {
    byMerchant.putIfAbsent(c.merchant.trim().toUpperCase(), () => []).add(c);
  }
  final out = <SubscriptionCandidate>[];
  for (final e in byMerchant.entries) {
    if (ignore.contains(e.key) || existing.contains(e.key)) continue;
    final list = e.value..sort((a, b) => a.date.compareTo(b.date));
    // Longest trailing run of similar-amount charges.
    final ref = list.last.cents;
    final run = list.reversed
        .takeWhile((c) => (c.cents - ref).abs() <= ref * 0.05)
        .toList()
        .reversed
        .toList();
    if (run.length < minOccurrences) continue;
    final gaps = [
      for (var i = 1; i < run.length; i++) run[i].date.difference(run[i - 1].date).inDays
    ];
    final monthly = gaps.every((g) => g >= 26 && g <= 35);
    final yearly = gaps.every((g) => g >= 355 && g <= 375);
    if (!monthly && !yearly) continue;
    final period = monthly ? BillingPeriod.monthly : BillingPeriod.yearly;
    final last = run.last.date;
    out.add(SubscriptionCandidate(
      name: e.key,
      cents: ref,
      period: period,
      occurrences: run.length,
      nextDate: monthly
          ? DateTime(last.year, last.month + 1, last.day)
          : DateTime(last.year + 1, last.month, last.day),
    ));
  }
  return out;
}
