import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'widgets.dart';

/// Subskrypcje per design/Subskrypcje: monthly total as the hero, flat renewals list.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final str = ref.watch(appStringsProvider);
    final subs = ref.watch(subscriptionsProvider).value ?? [];
    final candidates = ref.watch(subscriptionCandidatesProvider).value ?? [];
    final db = ref.read(dbProvider);
    void refresh() => ref.read(dataVersionProvider.notifier).bump();
    final active = subs.where((s) => s.active).toList();
    final monthly = active.fold(0, (a, s) => a + s.monthlyCents);
    final now = DateTime.now();
    final upcoming = [...active]..sort((a, b) => a.nextRenewal(now).compareTo(b.nextRenewal(now)));
    final bottom = 84 + MediaQuery.of(context).padding.bottom + 40;

    return ListView(padding: EdgeInsets.only(bottom: bottom), children: [
      HeroZone(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 52,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(str.tabSubscriptions, style: display(32)),
              Transform.translate(
                offset: const Offset(8, 0),
                child: Semantics(
                  button: true,
                  label: str.addSub,
                  child: GestureDetector(
                    onTap: () => showSubscriptionForm(context, ref),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
                      child: Icon(Icons.add, color: AppColors.accent),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          MoneyText(monthly),
          const SizedBox(height: 4),
          Text(str.isEnglish ? 'per month' : 'miesięcznie', style: fig(17, weight: 600)),
          const SizedBox(height: 4),
          Text('${formatMoney(monthly * 12)} ${str.yearly}, ${active.length} ${str.active}', style: fig(14, color: AppColors.text3)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final c in candidates)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: AppColors.warnBar, width: 2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str.detectedAutomatically, style: fig(14, weight: 700, color: AppColors.warn)),
                const SizedBox(height: 6),
                Text.rich(TextSpan(style: fig(16), children: [
                  TextSpan(text: c.name, style: fig(16, weight: 700)),
                  TextSpan(text: ': ${formatMoney(c.cents)}, ${c.period == BillingPeriod.monthly ? str.everyMonth : str.everyYear}, ${c.occurrences} ${str.candidatePrompt}'),
                ])),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () async {
                        await db.addSubscription(Subscription(name: c.name, cents: c.cents, period: c.period, nextDate: c.nextDate));
                        refresh();
                      },
                      child: Text(str.add),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () async {
                        await db.dismissSub(c.name);
                        refresh();
                      },
                      child: Text(str.notThis),
                    ),
                  ),
                ]),
              ]),
            ),
          Text(str.upcomingRenewals, style: display(22)),
          if (upcoming.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(str.noSubsHint, style: fig(16, color: AppColors.text3, height: 24 / 16))),
          for (var i = 0; i < upcoming.length; i++)
            Dismissible(
              key: ValueKey(upcoming[i].id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) async {
                final s = upcoming[i];
                await db.deleteSubscription(s.id!);
                refresh();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${str.isEnglish ? 'Deleted' : 'Usunięto'}: ${s.name}'),
                    action: SnackBarAction(
                      label: str.undo,
                      onPressed: () async {
                        await db.addSubscription(Subscription(name: s.name, cents: s.cents, period: s.period, nextDate: s.nextDate, active: s.active));
                        refresh();
                      },
                    ),
                  ));
                }
              },
              background: Container(color: AppColors.hero, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: Icon(Icons.delete_outline, color: AppColors.danger)),
              child: Builder(builder: (_) {
                final s = upcoming[i];
                final next = s.nextRenewal(now);
                final days = next.difference(DateTime(now.year, now.month, now.day)).inDays;
                return InkWell(
                  onTap: () => showSubscriptionForm(context, ref, initial: s),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 68),
                    decoration: BoxDecoration(border: Border(top: i == 0 ? BorderSide.none : BorderSide(color: AppColors.line), bottom: i == upcoming.length - 1 ? BorderSide(color: AppColors.line) : BorderSide.none)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.name, style: fig(17, weight: 700)),
                          Text('${shortDate(next, isEnglish: str.isEnglish)}, ${str.inDays(days)}${s.period == BillingPeriod.yearly ? ', ${str.isEnglish ? 'yearly' : 'rocznie'}' : ''}', style: fig(14, color: AppColors.text2)),
                        ]),
                      ),
                      Text(formatMoney(s.cents), style: fig(17, weight: 700)),
                    ]),
                  ),
                );
              }),
            ),
          const SizedBox(height: 16),
          Text(str.isEnglish ? 'Swipe a row to delete (you can undo). Reminders are set in Settings.' : 'Przesuń wiersz, żeby usunąć (można cofnąć). Przypomnienia ustawisz w Ustawieniach.', style: fig(14, color: AppColors.text2, height: 20 / 14)),
        ]),
      ),
    ]);
  }
}

/// Nowa subskrypcja per design/Subskrypcja-dodaj; also edits an existing one.
Future<void> showSubscriptionForm(BuildContext context, WidgetRef ref, {Subscription? initial}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => _SubscriptionForm(initial: initial)));

class _SubscriptionForm extends ConsumerStatefulWidget {
  const _SubscriptionForm({this.initial});
  final Subscription? initial;
  @override
  ConsumerState<_SubscriptionForm> createState() => _SubscriptionFormState();
}

class _SubscriptionFormState extends ConsumerState<_SubscriptionForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _price = TextEditingController(text: widget.initial == null ? '' : formatMoney(widget.initial!.cents, withCurrency: false).replaceAll(' ', ''));
  late BillingPeriod _period = widget.initial?.period ?? BillingPeriod.monthly;
  late DateTime _next = widget.initial?.nextDate ?? DateTime.now().add(const Duration(days: 30));

  Future<void> _save() async {
    final cents = parseMoney(_price.text);
    if (_name.text.trim().isEmpty || cents == null) return;
    final db = ref.read(dbProvider);
    final s = Subscription(id: widget.initial?.id, name: _name.text.trim(), cents: cents, period: _period, nextDate: _next, active: widget.initial?.active ?? true);
    widget.initial == null ? await db.addSubscription(s) : await db.updateSubscription(s);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final s = widget.initial!;
    await ref.read(dbProvider).deleteSubscription(s.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    Widget seg(String label, bool sel, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? AppColors.bg : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                boxShadow: sel ? [BoxShadow(color: const Color(0xFF17201C).withValues(alpha: 0.18), blurRadius: 2, offset: const Offset(0, 1))] : null,
              ),
              child: Text(label, style: fig(15, weight: sel ? 700 : 600, color: sel ? AppColors.text : AppColors.text3)),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 140), children: [
          HeroZone(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              HeroBackHeader(str.newSub, size: 15),
              Text(str.subName, style: fig(14, color: AppColors.text3)),
              const SizedBox(height: 6),
              HeroField(controller: _name, hint: 'Netflix'),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str.subAmount, style: fig(16, weight: 700)),
              const SizedBox(height: 8),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: fig(20, weight: 700),
                decoration: InputDecoration(hintText: '0,00', suffixText: 'zł', suffixStyle: fig(16, color: AppColors.text2)),
              ),
              const SizedBox(height: 20),
              Text(str.isEnglish ? 'How often' : 'Jak często', style: fig(16, weight: 700)),
              const SizedBox(height: 8),
              Container(
                height: 52,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  seg(str.monthlyPeriod, _period == BillingPeriod.monthly, () => setState(() => _period = BillingPeriod.monthly)),
                  seg(str.yearlyPeriod, _period == BillingPeriod.yearly, () => setState(() => _period = BillingPeriod.yearly)),
                ]),
              ),
              const SizedBox(height: 20),
              Text(str.nextRenewal, style: fig(16, weight: 700)),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _next, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => _next = d);
                },
                child: Container(
                  height: 52,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
                  child: Text(longDate(_next, isEnglish: str.isEnglish), style: fig(16, weight: 500)),
                ),
              ),
            ]),
          ),
        ]),
        Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(onPressed: _save, child: Text(str.save)),
            if (widget.initial != null)
              TextButton(onPressed: _delete, child: Text(str.isEnglish ? 'Delete subscription' : 'Usuń subskrypcję', style: fig(16, weight: 600, color: AppColors.danger))),
          ]),
        ),
      ]),
    );
  }
}
