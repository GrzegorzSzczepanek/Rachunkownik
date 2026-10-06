import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ai/spending_chat.dart';
import '../domain/retrieval.dart' show plPlural;
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'scan_flow.dart' show ReviewScreen;
import 'widgets.dart';

class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({super.key});
  @override
  ConsumerState<OverviewScreen> createState() => _OverviewState();
}

class _OverviewState extends ConsumerState<OverviewScreen> {
  final _q = TextEditingController();
  ChatAnswer? _answer;
  bool _asking = false;

  Future<void> _ask() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => _asking = true);
    try {
      final chat = await ref.read(aiSettingsProvider.notifier).chat();
      final a = await chat.ask(q);
      if (mounted) setState(() => _answer = a);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(monthSummaryProvider);
    final receipts = ref.watch(receiptsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        summary.when(
          data: (s) => _header(s),
          loading: () => const SizedBox(height: 120),
          error: (e, _) => Text('$e'),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _q,
          onSubmitted: (_) => _ask(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Ile wydałem na kawę w zeszłym kwartale?',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _asking
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _ask),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        if (_answer != null) ...[
          const SizedBox(height: 12),
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_answer!.text, style: const TextStyle(fontSize: 16, height: 1.4)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_answer!.sourceCount > 0) Pill('Źródło: ${_answer!.sourceCount} ${plPlural(_answer!.sourceCount, 'pozycja', 'pozycje', 'pozycji')}'),
                _answer!.engine == 'lokalnie'
                    ? const Pill('Obliczone na telefonie', bg: AppColors.greenSoft, fg: AppColors.green)
                    : Pill('Model: ${_answer!.engine}', bg: AppColors.blueSoft, fg: AppColors.blue),
              ]),
              if (_answer!.hits.length > 1)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text('Pokaż pozycje', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.green)),
                    children: [
                      for (final h in _answer!.hits.take(15))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(children: [
                            SizedBox(width: 54, child: Text(shortDate(h.doc.date), style: const TextStyle(color: AppColors.muted))),
                            Expanded(
                              child: Text(h.doc.name == h.doc.store ? h.doc.name : '${h.doc.name} · ${h.doc.store}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            Text(formatMoney(h.doc.cents, withCurrency: false), style: mono(size: 14, weight: FontWeight.w500)),
                          ]),
                        ),
                      if (_answer!.hits.length > 15)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('… i ${_answer!.hits.length - 15} więcej', style: const TextStyle(color: AppColors.muted)),
                        ),
                    ],
                  ),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        summary.maybeWhen(data: (s) => _budgets(context, s), orElse: () => const SizedBox()),
        const SizedBox(height: 20),
        SectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: const Icon(Icons.bar_chart_rounded, color: AppColors.green),
            title: const Text('Analiza i wykresy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            subtitle: const Text('Trendy, kategorie, dzień po dniu'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
            onTap: () => context.push('/analytics'),
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Ostatnie paragony', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              TextButton(onPressed: () => context.go('/receipts'), child: const Text('Wszystkie')),
            ]),
            receipts.maybeWhen(
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Brak paragonów. Dotknij przycisku skanowania, aby dodać pierwszy.',
                          style: TextStyle(color: AppColors.muted)))
                  : Column(children: [
                      for (final r in list.take(3))
                        ReceiptTile(r,
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => ReviewScreen(initial: r)))),
                    ]),
              orElse: () => const SizedBox(),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _header(MonthSummary s) {
    final frac = s.budgetTotal == 0 ? 0.0 : s.spent / s.budgetTotal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Eyebrow('${monthLabel(s.month)} · WYDANE'),
      const SizedBox(height: 6),
      Text(formatMoney(s.spent), style: mono(size: 44)),
      if (s.budgetTotal > 0) ...[
        const SizedBox(height: 10),
        ProgressBar(frac, color: frac > 1 ? AppColors.amber : AppColors.green),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Budżet ${formatMoney(s.budgetTotal)}', style: const TextStyle(color: AppColors.muted)),
          Text(s.remaining >= 0 ? 'zostało ${formatMoney(s.remaining)}' : 'ponad budżet ${formatMoney(-s.remaining)}',
              style: mono(size: 14, weight: FontWeight.w400, color: AppColors.muted)),
        ]),
      ],
    ]);
  }

  Widget _budgets(BuildContext context, MonthSummary s) {
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Budżety', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          TextButton(onPressed: () => _editBudgets(context, s), child: const Text('Edytuj')),
        ]),
        if (s.budgets.isEmpty)
          const Text('Ustaw limity per kategoria, a dostaniesz alert po przekroczeniu 80%.',
              style: TextStyle(color: AppColors.muted)),
        for (final b in s.budgets) ...[
          const SizedBox(height: 12),
          Builder(builder: (_) {
            final spent = s.byCategory[b.category] ?? 0;
            final f = spent / b.limitCents;
            final warn = f >= 0.8;
            final color = warn ? AppColors.amber : AppColors.green;
            return Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(b.category, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('${formatMoney(spent, withCurrency: false)} / ${formatMoney(b.limitCents)} · ${(f * 100).round()}%',
                    style: mono(size: 13, weight: warn ? FontWeight.w700 : FontWeight.w400,
                        color: warn ? AppColors.amberInk : AppColors.muted)),
              ]),
              const SizedBox(height: 6),
              ProgressBar(f, color: color),
            ]);
          }),
        ],
      ]),
    );
  }

  Future<void> _editBudgets(BuildContext context, MonthSummary s) async {
    final ctrls = {
      for (final c in defaultCategories)
        c: TextEditingController(
            text: s.budgets.where((b) => b.category == c).map((b) => (b.limitCents / 100).round().toString()).firstOrNull ?? '')
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Budżety miesięczne'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in ctrls.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: e.value,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: e.key, suffixText: 'zł', hintText: 'brak limitu'),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zapisz')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(dbProvider);
    for (final e in ctrls.entries) {
      final v = int.tryParse(e.value.text.trim());
      await db.setBudget(e.key, v == null ? null : v * 100);
    }
    ref.read(dataVersionProvider.notifier).bump();
  }
}

class ReceiptTile extends StatelessWidget {
  const ReceiptTile(this.r, {super.key, this.onTap, this.onLongPress});
  final Receipt r;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(r.date.year, r.date.month, r.date.day)).inDays;
    final when = days == 0 ? 'dziś' : days == 1 ? 'wczoraj' : shortDate(r.date);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Initial(r.store, green: days == 0),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.store, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('$when · ${r.items.length} pozycji · ${r.mainCategory}',
                  style: const TextStyle(color: AppColors.muted)),
            ]),
          ),
          Text(formatMoney(r.totalCents), style: mono(size: 16)),
        ]),
      ),
    );
  }
}
