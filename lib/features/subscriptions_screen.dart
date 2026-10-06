import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'widgets.dart';

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider).value ?? [];
    final candidates = ref.watch(subscriptionCandidatesProvider).value ?? [];
    final db = ref.read(dbProvider);
    void refresh() => ref.read(dataVersionProvider.notifier).bump();
    final active = subs.where((s) => s.active).toList();
    final monthly = active.fold(0, (a, s) => a + s.monthlyCents);
    final now = DateTime.now();
    final upcoming = [...active]..sort((a, b) => a.nextRenewal(now).compareTo(b.nextRenewal(now)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Subskrypcje', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          IconButton.filledTonal(
              onPressed: () => _add(context, ref), icon: const Icon(Icons.add), tooltip: 'Dodaj'),
        ]),
        const SizedBox(height: 14),
        const Eyebrow('CO MIESIĄC'),
        Text(formatMoney(monthly), style: mono(size: 44)),
        Text('${formatMoney(monthly * 12)} rocznie · ${active.length} aktywne',
            style: mono(size: 14, weight: FontWeight.w400, color: AppColors.muted)),
        const SizedBox(height: 20),
        for (final c in candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SectionCard(
              border: AppColors.amber,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🔍 WYKRYTO AUTOMATYCZNIE',
                    style: TextStyle(color: AppColors.amberInk, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                const SizedBox(height: 10),
                Text.rich(TextSpan(children: [
                  TextSpan(text: c.name, style: mono(size: 16)),
                  TextSpan(
                      text: ': ${formatMoney(c.cents)}, ${c.period == BillingPeriod.monthly ? 'co miesiąc' : 'co rok'}, '
                          '${c.occurrences} ostatnie płatności. Dodać jako subskrypcję?',
                      style: const TextStyle(fontSize: 16)),
                ])),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await db.addSubscription(Subscription(
                            name: c.name, cents: c.cents, period: c.period, nextDate: c.nextDate));
                        refresh();
                      },
                      child: const Text('Dodaj'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await db.dismissSub(c.name);
                        refresh();
                      },
                      child: const Text('To nie ono'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('NADCHODZĄCE ODNOWIENIA'),
            if (upcoming.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Brak subskrypcji. Dodaj ręcznie albo poczekaj na automatyczne wykrycie '
                    '(3 podobne płatności u tego samego sprzedawcy).',
                    style: TextStyle(color: AppColors.muted)),
              ),
            for (final s in upcoming)
              Dismissible(
                key: ValueKey(s.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) async {
                  await db.deleteSubscription(s.id!);
                  refresh();
                },
                background: Container(color: AppColors.amberSoft, alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_outline)),
                child: Builder(builder: (_) {
                  final next = s.nextRenewal(now);
                  final days = next.difference(DateTime(now.year, now.month, now.day)).inDays;
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                    child: Row(children: [
                      Initial(s.name),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          Text('${shortDate(next)} · ${days == 0 ? 'dziś' : 'za $days dni'}',
                              style: const TextStyle(color: AppColors.muted)),
                        ]),
                      ),
                      Text(formatMoney(s.cents), style: mono(size: 16)),
                    ]),
                  );
                }),
              ),
          ]),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final price = TextEditingController();
    var period = BillingPeriod.monthly;
    var next = DateTime.now().add(const Duration(days: 30));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nowa subskrypcja'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nazwa')),
            const SizedBox(height: 10),
            TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Kwota', suffixText: 'zł')),
            const SizedBox(height: 10),
            SegmentedButton<BillingPeriod>(
              segments: const [
                ButtonSegment(value: BillingPeriod.monthly, label: Text('Miesięcznie')),
                ButtonSegment(value: BillingPeriod.yearly, label: Text('Rocznie')),
              ],
              selected: {period},
              onSelectionChanged: (s) => setS(() => period = s.first),
            ),
            TextButton(
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx, initialDate: next, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setS(() => next = d);
              },
              child: Text('Następne odnowienie: ${longDate(next)}'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dodaj')),
          ],
        ),
      ),
    );
    final cents = parseMoney(price.text);
    if (ok != true || name.text.trim().isEmpty || cents == null) return;
    await ref.read(dbProvider).addSubscription(
        Subscription(name: name.text.trim(), cents: cents, period: period, nextDate: next));
    ref.read(dataVersionProvider.notifier).bump();
  }
}
