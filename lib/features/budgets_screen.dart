import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'periodic_budget_dialog.dart';
import 'widgets.dart';

/// Budżety per design/Budzety: period budgets (month, week, weekend, custom, recurring) and category limits.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final str = ref.watch(appStringsProvider);
    final summary = ref.watch(monthSummaryProvider).valueOrNull;
    final periodic = ref.watch(periodicBudgetsProvider).valueOrNull ?? const <PeriodicBudget>[];
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32), children: [
        HeroZone(
          bottom: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HeroBackHeader(str.budgets),
            Text(str.budgetsHint, style: fig(16, color: AppColors.text3, height: 24 / 16)),
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: () => showPeriodicBudgetDialog(context),
                icon: const Icon(Icons.add),
                label: Text(str.addBudget),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (periodic.isNotEmpty) ...[
              Text(str.tripAndPeriodBudgets, style: display(22)),
              const SizedBox(height: 4),
              for (var i = 0; i < periodic.length; i++) _periodic(context, str, periodic[i], i == 0),
              const SizedBox(height: 24),
            ],
            SectionHeader(str.categoryBudgets, action: str.edit, onAction: summary == null ? null : () => editCategoryBudgets(context, ref, summary)),
            if (summary == null || summary.budgets.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(str.budgetsHint, style: fig(15, color: AppColors.text2)))
            else
              for (var i = 0; i < summary.budgets.length; i++)
                BudgetRow(
                  name: str.categoryName(summary.budgets[i].category),
                  spent: summary.byCategory[summary.budgets[i].category] ?? 0,
                  limit: summary.budgets[i].limitCents,
                  first: i == 0,
                ),
          ]),
        ),
      ]),
    );
  }

  Widget _periodic(BuildContext context, AppStrings str, PeriodicBudget pb, bool first) {
    final status = pb.isUpcoming
        ? str.budgetUpcoming
        : pb.isPast
            ? str.budgetFinished
            : '${str.budgetActive} · ${pb.daysRemaining == 0 ? (str.isEnglish ? "Last day" : "Dziś koniec") : "${pb.daysRemaining} ${str.isEnglish ? 'd' : 'dni'}"}';
    final dates = '${shortDate(pb.startDate, isEnglish: str.isEnglish)} – ${shortDate(pb.endDate, isEnglish: str.isEnglish)}'
        '${pb.isRecurring ? ' · ${str.recurringWeekly}' : ''} · ${pb.category != null ? str.categoryName(pb.category!) : str.allExpenses}';
    return BudgetRow(
      name: pb.name,
      spent: pb.spentCents,
      limit: pb.limitCents,
      first: first,
      subtitle: '$status · $dates',
      onTap: () => showPeriodicBudgetDialog(context, initial: pb),
    );
  }
}

Future<void> editCategoryBudgets(BuildContext context, WidgetRef ref, MonthSummary s) async {
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
