import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'budgets_screen.dart';
import 'chat_screen.dart';
import 'income_dialog.dart';
import 'scan_flow.dart' show ReviewScreen;
import 'widgets.dart';

/// Przegląd per design/Main and Przeglad-dol: one hero number (spent), budget bar and
/// balance in the hero, the chat field as the only "add" action, flat lists below.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final str = ref.watch(appStringsProvider);
    final summary = ref.watch(monthSummaryProvider).valueOrNull;
    final receipts = ref.watch(receiptsProvider).valueOrNull ?? const <Receipt>[];
    final subs = ref.watch(subscriptionsProvider).valueOrNull ?? const <Subscription>[];
    final bottom = 84 + MediaQuery.of(context).padding.bottom + 40;
    final upcoming = [...subs.where((s) => s.active)]..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return ListView(padding: EdgeInsets.only(bottom: bottom), children: [
      if (summary == null) const SizedBox(height: 280) else _hero(context, summary, str),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
            child: Container(
              height: 56,
              padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Expanded(child: Text(str.chatPlaceholder, maxLines: 1, overflow: TextOverflow.ellipsis, style: fig(16, color: AppColors.text2))),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.arrow_upward, color: AppColors.onAccent),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          if (summary != null) ..._budgets(context, summary, str),
          const SizedBox(height: 8),
          NavRow(
            topLine: summary != null && summary.budgets.isNotEmpty ? true : false,
            minHeight: 72,
            bold: true,
            leading: Icon(Icons.bar_chart_rounded, color: AppColors.accent, size: 26),
            title: str.analytics,
            subtitle: str.analyticsSub,
            onTap: () => context.push('/analytics'),
          ),
          if (upcoming.isNotEmpty)
            NavRow(
              minHeight: 72,
              bold: true,
              bottomLine: true,
              leading: Icon(Icons.repeat, color: AppColors.accent, size: 26),
              title: str.isEnglish ? 'Next subscription' : 'Najbliższa subskrypcja',
              subtitle: '${upcoming.first.name}, ${formatMoney(upcoming.first.cents)}, ${str.inDays(upcoming.first.nextDate.difference(DateTime.now()).inDays.clamp(0, 9999))}',
              onTap: () => context.go('/subscriptions'),
            ),
          const SizedBox(height: 20),
          SectionHeader(str.recentReceipts, action: str.all, onAction: () => context.go('/receipts')),
          if (receipts.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(str.noReceipts, style: fig(16, color: AppColors.text3, height: 24 / 16)))
          else
            for (var i = 0; i < receipts.take(3).length; i++)
              ReceiptTile(receipts[i],
                  bottomLine: i == receipts.take(3).length - 1,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(initial: receipts[i])))),
        ]),
      ),
    ]);
  }

  Widget _hero(BuildContext context, MonthSummary s, AppStrings str) {
    final frac = s.budgetTotal == 0 ? 0.0 : s.spent / s.budgetTotal;
    final warn = frac >= 0.8;
    return HeroZone(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 52,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(monthLabel(s.month, isEnglish: str.isEnglish), style: fig(15, color: AppColors.text3)),
            Transform.translate(
              offset: const Offset(8, 0),
              child: TextButton(onPressed: () => showIncomeDialog(context), child: Text(str.addIncome, style: fig(15, weight: 600, color: AppColors.accent))),
            ),
          ]),
        ),
        MoneyText(s.spent),
        const SizedBox(height: 4),
        Text(str.isEnglish ? 'spent this month' : 'wydane w tym miesiącu', style: fig(17, weight: 600)),
        if (s.budgetTotal > 0) ...[
          const SizedBox(height: 16),
          ProgressBar(frac, height: 12, color: warn ? AppColors.warnBar : AppColors.accent, track: warn ? AppColors.warnTrack : null),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${str.budget} ${formatMoney(s.budgetTotal)}', style: fig(14, color: AppColors.text3)),
            Text(
              s.remaining >= 0 ? '${str.remaining} ${formatMoney(s.remaining)}' : '${str.overBudget} ${formatMoney(-s.remaining)}',
              style: fig(14, weight: 700, color: s.remaining >= 0 ? AppColors.text : AppColors.warn),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        Row(children: [
          _stat(str.incomes, '+${formatMoney(s.income)}', AppColors.income),
          const SizedBox(width: 24),
          _stat(str.balance, '${s.balance >= 0 ? '+' : ''}${formatMoney(s.balance)}', s.balance >= 0 ? AppColors.income : AppColors.warn),
        ]),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: fig(14, color: AppColors.text3)),
        Text(value, style: fig(18, weight: 700, color: color)),
      ]);

  /// Category budgets as flat rows. Period budgets and editing live in [BudgetsScreen].
  List<Widget> _budgets(BuildContext context, MonthSummary s, AppStrings str) {
    return [
      SectionHeader(str.budgets, action: str.all, onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetsScreen()))),
      if (s.budgets.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(str.budgetsHint, style: fig(15, color: AppColors.text3, height: 22 / 15)),
        )
      else
        for (var i = 0; i < s.budgets.length; i++)
          BudgetRow(
            name: str.categoryName(s.budgets[i].category),
            spent: s.byCategory[s.budgets[i].category] ?? 0,
            limit: s.budgets[i].limitCents,
            first: i == 0,
          ),
    ];
  }
}

/// One receipt as a flat list row (no store initial tile).
class ReceiptTile extends ConsumerWidget {
  const ReceiptTile(this.r, {super.key, this.onTap, this.onLongPress, this.bottomLine = false});
  final Receipt r;
  final VoidCallback? onTap, onLongPress;
  final bool bottomLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final str = ref.watch(appStringsProvider);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: bottomLine ? BorderSide(color: AppColors.line) : BorderSide.none)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.store, maxLines: 1, overflow: TextOverflow.ellipsis, style: fig(17, weight: 700)),
              Text('${str.relativeDate(r.date)}, ${str.itemsCount(r.items.length)}, ${str.categoryName(r.mainCategory)}', style: fig(14, color: AppColors.text2)),
            ]),
          ),
          const SizedBox(width: 12),
          Text(formatMoney(r.totalCents), style: fig(17, weight: 700)),
        ]),
      ),
    );
  }
}
