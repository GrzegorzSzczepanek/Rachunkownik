import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ai/spending_chat.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'income_dialog.dart';
import 'periodic_budget_dialog.dart';
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
      if (mounted) {
        setState(() => _answer = a);
        if (a.createdReceipt != null || a.createdIncome != null) {
          _q.clear();
          ref.read(dataVersionProvider.notifier).bump();
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _undoReceipt(Receipt r) async {
    final id = r.id;
    if (id == null) return;
    try {
      await ref.read(dbProvider).deleteReceipt(id);
      ref.read(dataVersionProvider.notifier).bump();
      setState(() => _answer = null);
      if (mounted) {
        final str = ref.read(appStringsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${str.undoSuccess}: ${r.store}'),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _undoIncome(Income inc) async {
    final id = inc.id;
    if (id == null) return;
    try {
      await ref.read(dbProvider).deleteIncome(id);
      ref.read(dataVersionProvider.notifier).bump();
      setState(() => _answer = null);
      if (mounted) {
        final str = ref.read(appStringsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${str.incomeUndone}: ${inc.title}'),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    final summary = ref.watch(monthSummaryProvider);
    final receipts = ref.watch(receiptsProvider);
    final periodicBudgets = ref.watch(periodicBudgetsProvider).valueOrNull ?? [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        summary.when(
          data: (s) => _header(context, s, str),
          loading: () => const SizedBox(height: 120),
          error: (e, _) => Text('$e'),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _q,
          onSubmitted: (_) => _ask(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: str.chatPlaceholder,
            prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
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
          if (_answer!.createdReceipt != null)
            SectionCard(
              border: AppColors.green,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(str.addedFromChat,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green)),
                  ),
                  Text(
                    formatMoney(_answer!.createdReceipt!.totalCents),
                    style: mono(size: 18, weight: FontWeight.w800, color: AppColors.green),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(
                  '${_answer!.createdReceipt!.store} · ${shortDate(_answer!.createdReceipt!.date)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                for (final item in _answer!.createdReceipt!.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w500))),
                      Pill(item.category, bg: AppColors.chip, fg: AppColors.ink),
                      const SizedBox(width: 8),
                      Text(formatMoney(item.cents, withCurrency: false), style: mono(size: 14)),
                    ]),
                  ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: Text(str.undo),
                    onPressed: () => _undoReceipt(_answer!.createdReceipt!),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(str.edit),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ReviewScreen(initial: _answer!.createdReceipt!)),
                      );
                      if (mounted) setState(() => _answer = null);
                    },
                  ),
                ]),
              ]),
            )
          else if (_answer!.createdIncome != null)
            SectionCard(
              border: AppColors.green,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(str.addedIncomeFromChat,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green)),
                  ),
                  Text(
                    '+${formatMoney(_answer!.createdIncome!.cents)}',
                    style: mono(size: 18, weight: FontWeight.w800, color: AppColors.green),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(
                  '${_answer!.createdIncome!.title} · ${shortDate(_answer!.createdIncome!.date, isEnglish: str.isEnglish)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Pill(str.categoryName(_answer!.createdIncome!.category), bg: AppColors.greenSoft, fg: AppColors.green),
                  if (_answer!.createdIncome!.note != null) ...[
                    const SizedBox(width: 8),
                    Text(_answer!.createdIncome!.note!, style: const TextStyle(color: AppColors.muted)),
                  ],
                ]),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: Text(str.undo),
                    onPressed: () => _undoIncome(_answer!.createdIncome!),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(str.edit),
                    onPressed: () async {
                      await showIncomeDialog(context, initial: _answer!.createdIncome!);
                      if (mounted) setState(() => _answer = null);
                    },
                  ),
                ]),
              ]),
            )
          else
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_answer!.text, style: const TextStyle(fontSize: 16, height: 1.4)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (_answer!.sourceCount > 0)
                    Pill('${str.source}: ${str.itemsCount(_answer!.sourceCount)}'),
                  _answer!.engine == 'lokalnie'
                      ? Pill(str.calculatedLocally, bg: AppColors.greenSoft, fg: AppColors.green)
                      : Pill('${str.isEnglish ? 'Model' : 'Model'}: ${_answer!.engine}', bg: AppColors.blueSoft, fg: AppColors.blue),
                ]),
                if (_answer!.hits.length > 1)
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title:
                          Text(str.showItems, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.green)),
                      children: [
                        for (final h in _answer!.hits.take(15))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: [
                              SizedBox(
                                  width: 54, child: Text(shortDate(h.doc.date, isEnglish: str.isEnglish), style: const TextStyle(color: AppColors.muted))),
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
                            child: Text('… ${str.isEnglish ? 'and' : 'i'} ${_answer!.hits.length - 15} ${str.andMore}',
                                style: const TextStyle(color: AppColors.muted)),
                          ),
                      ],
                    ),
                  ),
              ]),
            ),
        ],
        const SizedBox(height: 20),
        summary.maybeWhen(data: (s) => _budgets(context, s, periodicBudgets), orElse: () => const SizedBox()),
        const SizedBox(height: 20),
        SectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: const Icon(Icons.bar_chart_rounded, color: AppColors.green),
            title: Text(str.analytics, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            subtitle: Text(str.analyticsSub),
            trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
            onTap: () => context.push('/analytics'),
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(str.recentReceipts, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              TextButton(onPressed: () => context.go('/receipts'), child: Text(str.all)),
            ]),
            receipts.maybeWhen(
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(str.noReceipts,
                          style: const TextStyle(color: AppColors.muted)))
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

  Widget _header(BuildContext context, MonthSummary s, AppStrings str) {
    final frac = s.budgetTotal == 0 ? 0.0 : s.spent / s.budgetTotal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Eyebrow('${monthLabel(s.month, isEnglish: str.isEnglish)} · ${str.spent}'),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.green,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: () => showIncomeDialog(context),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
            label: Text(str.addIncome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(formatMoney(s.spent), style: mono(size: 40)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(str.incomes,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('+${formatMoney(s.income)}',
                      style: mono(size: 15, weight: FontWeight.w700, color: AppColors.green)),
                ],
              ),
            ),
            Container(width: 1, height: 32, color: AppColors.border),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(str.balance,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${s.balance >= 0 ? '+' : ''}${formatMoney(s.balance)}',
                    style: mono(
                      size: 15,
                      weight: FontWeight.w700,
                      color: s.balance >= 0 ? AppColors.green : AppColors.amberInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (s.budgetTotal > 0) ...[
        const SizedBox(height: 12),
        ProgressBar(frac, color: frac > 1 ? AppColors.amber : AppColors.green),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${str.budget} ${formatMoney(s.budgetTotal)}', style: const TextStyle(color: AppColors.muted)),
          Text(s.remaining >= 0 ? '${str.remaining} ${formatMoney(s.remaining)}' : '${str.overBudget} ${formatMoney(-s.remaining)}',
              style: mono(size: 14, weight: FontWeight.w400, color: AppColors.muted)),
        ]),
      ],
    ]);
  }

  Widget _budgets(BuildContext context, MonthSummary s, List<PeriodicBudget> periodicBudgets) {
    final str = ref.watch(appStringsProvider);
    final hasCategoryBudgets = s.budgets.isNotEmpty;
    final hasPeriodicBudgets = periodicBudgets.isNotEmpty;
    final isEmpty = !hasCategoryBudgets && !hasPeriodicBudgets;

    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(str.budgets, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(str.addBudget),
              onPressed: () => showPeriodicBudgetDialog(context),
            ),
            TextButton(
              onPressed: () => _editBudgets(context, s),
              child: Text(str.categoryBudgets),
            ),
          ]),
        ]),
        if (isEmpty) ...[
          const SizedBox(height: 8),
          Text(str.budgetsHint, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.weekend_rounded, size: 18),
              label: Text('${str.thisWeekend} (${str.addBudget})'),
              onPressed: () => showPeriodicBudgetDialog(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(str.categoryBudgets),
              onPressed: () => _editBudgets(context, s),
            ),
          ]),
        ],
        if (hasPeriodicBudgets) ...[
          const SizedBox(height: 8),
          Text(str.tripAndPeriodBudgets,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.muted)),
          for (final pb in periodicBudgets) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.chip.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: pb.isOverBudget
                      ? Colors.red.withValues(alpha: 0.4)
                      : (pb.fraction >= 0.8 ? AppColors.amber.withValues(alpha: 0.4) : AppColors.border),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      pb.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (pb.isUpcoming)
                    Pill(str.budgetUpcoming, bg: AppColors.blueSoft, fg: AppColors.blue)
                  else if (pb.isPast)
                    Pill(str.budgetFinished, bg: AppColors.track, fg: AppColors.muted)
                  else
                    Pill(
                      '${str.budgetActive} · ${pb.daysRemaining == 0 ? (str.isEnglish ? "Last day" : "Dziś koniec") : "${pb.daysRemaining}d"}',
                      bg: AppColors.greenSoft,
                      fg: AppColors.green,
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.muted),
                    tooltip: str.editBudget,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => showPeriodicBudgetDialog(context, initial: pb),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    '${shortDate(pb.startDate, isEnglish: str.isEnglish)} – ${shortDate(pb.endDate, isEnglish: str.isEnglish)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  if (pb.isRecurring) ...[
                    const SizedBox(width: 6),
                    Pill(str.recurringWeekly, bg: AppColors.chip, fg: AppColors.muted),
                  ],
                  const SizedBox(width: 6),
                  Pill(
                    pb.category != null ? str.categoryName(pb.category!) : str.allExpenses,
                    bg: AppColors.chip,
                    fg: AppColors.ink,
                  ),
                ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    '${formatMoney(pb.spentCents, withCurrency: false)} / ${formatMoney(pb.limitCents)} · ${(pb.fraction * 100).round()}%',
                    style: mono(
                      size: 13,
                      weight: pb.isOverBudget ? FontWeight.w700 : FontWeight.w500,
                      color: pb.isOverBudget ? Colors.red : (pb.fraction >= 0.8 ? AppColors.amberInk : AppColors.muted),
                    ),
                  ),
                  Text(
                    pb.isOverBudget
                        ? '${str.overBudget} ${formatMoney(pb.spentCents - pb.limitCents)}'
                        : '${str.remaining} ${formatMoney(pb.remainingCents)}',
                    style: mono(
                      size: 12,
                      weight: FontWeight.w600,
                      color: pb.isOverBudget ? Colors.red : AppColors.muted,
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                ProgressBar(
                  pb.fraction,
                  color: pb.isOverBudget
                      ? Colors.red
                      : (pb.fraction >= 0.8 ? AppColors.amber : AppColors.green),
                ),
              ]),
            ),
          ],
        ],
        if (hasCategoryBudgets) ...[
          const SizedBox(height: 14),
          if (hasPeriodicBudgets) ...[
            Text(str.categoryBudgets,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.muted)),
            const SizedBox(height: 4),
          ],
          for (final b in s.budgets) ...[
            const SizedBox(height: 10),
            Builder(builder: (_) {
              final spent = s.byCategory[b.category] ?? 0;
              final f = spent / b.limitCents;
              final warn = f >= 0.8;
              final color = warn ? AppColors.amber : AppColors.green;
              return Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(str.categoryName(b.category), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('${formatMoney(spent, withCurrency: false)} / ${formatMoney(b.limitCents)} · ${(f * 100).round()}%',
                      style: mono(
                          size: 13,
                          weight: warn ? FontWeight.w700 : FontWeight.w400,
                          color: warn ? AppColors.amberInk : AppColors.muted)),
                ]),
                const SizedBox(height: 6),
                ProgressBar(f, color: color),
              ]);
            }),
          ],
        ],
      ]),
    );
  }

  Future<void> _editBudgets(BuildContext context, MonthSummary s) async {
    final str = ref.read(appStringsProvider);
    final ctrls = {
      for (final c in defaultCategories)
        c: TextEditingController(
            text: s.budgets.where((b) => b.category == c).map((b) => (b.limitCents / 100).round().toString()).firstOrNull ?? '')
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(str.monthlyBudgets),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in ctrls.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: e.value,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: str.categoryName(e.key),
                    suffixText: 'zł',
                    hintText: str.noLimit,
                  ),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(str.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(str.save)),
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

class ReceiptTile extends ConsumerWidget {
  const ReceiptTile(this.r, {super.key, this.onTap, this.onLongPress});
  final Receipt r;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final str = ref.watch(appStringsProvider);
    final when = str.relativeDate(r.date);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Initial(r.store, green: when == 'dziś' || when == 'today'),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.store, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('$when · ${str.itemsCount(r.items.length)} · ${str.categoryName(r.mainCategory)}',
                  style: const TextStyle(color: AppColors.muted)),
            ]),
          ),
          Text(formatMoney(r.totalCents), style: mono(size: 16)),
        ]),
      ),
    );
  }
}
