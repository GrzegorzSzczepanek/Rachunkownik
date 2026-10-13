import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../providers.dart';
import 'widgets.dart';

/// Legacy per-category palette (kept for other screens); the analysis itself uses one accent.
const _categoryColors = <String, Color>{
  'Jedzenie': Color(0xFF1F5F4A),
  'Dom': Color(0xFF2B4BC9),
  'Transport': Color(0xFFC4780E),
  'Rozrywka': Color(0xFF8A4FBF),
  'Zdrowie': Color(0xFFB5483A),
  'Ubrania': Color(0xFF3D8FA3),
  'Inne': Color(0xFF8C8C86),
};

Color categoryColor(String c) => _categoryColors[c] ?? AppColors.muted;

const _shortMonths = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
const _shortMonthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Compact axis label: 1250 zł -> "1,3k".
String _axis(double cents) {
  final zl = cents / 100;
  if (zl >= 1000) return '${(zl / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
  return zl.round().toString();
}

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsState();
}

class _AnalyticsState extends ConsumerState<AnalyticsScreen> {
  DateTime _month = monthStart(DateTime.now());

  bool get _isCurrent => _month == monthStart(DateTime.now());

  void _shift(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    final data = ref.watch(analyticsProvider(_month));
    final budget = _isCurrent ? ref.watch(monthSummaryProvider).valueOrNull?.budgetTotal ?? 0 : 0;
    final d = data.valueOrNull;
    final delta = d == null || d.previousTotal == 0 ? null : (d.total - d.previousTotal) / d.previousTotal;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32), children: [
        HeroZone(
          bottom: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 52,
              child: Row(children: [
                Transform.translate(offset: const Offset(-12, 0), child: const BackButton()),
                const Spacer(),
                IconButton(tooltip: str.isEnglish ? 'Previous month' : 'Poprzedni miesiąc', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                SizedBox(width: 130, child: Text(monthLabel(_month, isEnglish: str.isEnglish), textAlign: TextAlign.center, style: fig(16, weight: 700))),
                Transform.translate(
                  offset: const Offset(12, 0),
                  child: IconButton(tooltip: str.isEnglish ? 'Next month' : 'Następny miesiąc', icon: const Icon(Icons.chevron_right), onPressed: _isCurrent ? null : () => _shift(1)),
                ),
              ]),
            ),
            MoneyText(d?.total ?? 0),
            const SizedBox(height: 4),
            Text(str.isEnglish ? 'spent this month' : 'wydane w tym miesiącu', style: fig(16, weight: 600)),
            const SizedBox(height: 4),
            Text(
              delta != null
                  ? 'o ${(delta.abs() * 100).round()}% ${delta >= 0 ? (str.isEnglish ? 'more' : 'więcej') : (str.isEnglish ? 'less' : 'mniej')} ${str.vsPreviousMonth} (${formatMoney(d!.previousTotal)})'
                  : str.noPreviousMonthData,
              style: fig(14, weight: delta != null ? 600 : 400, color: delta != null && delta > 0 ? AppColors.warn : AppColors.text3),
            ),
            if (d != null) ...[
              const SizedBox(height: 16),
              Row(children: [
                _stat(str.incomes, '+${formatMoney(d.income)}', AppColors.income),
                const SizedBox(width: 24),
                _stat(str.balance, '${d.balance >= 0 ? '+' : ''}${formatMoney(d.balance)}', d.balance >= 0 ? AppColors.income : AppColors.warn),
              ]),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: data.when(
            data: (d) => _body(d, str, budget),
            loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('$e'),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: fig(14, color: AppColors.text3)),
        Text(value, style: fig(18, weight: 700, color: color)),
      ]);

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: display(22)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _body(AnalyticsData d, AppStrings str, int budget) {
    if (d.total == 0 && d.monthly.every((m) => m.value == 0)) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(str.noExpensesToAnalyze, style: fig(16, color: AppColors.text3, height: 24 / 16)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(str.last6Months, _monthlyBars(d, str, budget)),
      _section(str.categories, _categories(d, str)),
      _section(str.isEnglish ? 'Running total' : 'Narastająco w miesiącu', _cumulative(d, str, budget)),
      if (d.incomeByCategory.isNotEmpty) _section(str.incomesByCategory, _incomeCategories(d, str)),
      _section(str.dayByDay, _daily(d, str)),
      if (d.topStores.isNotEmpty) _section(str.topMerchants, _stores(d)),
    ]);
  }

  Widget _incomeCategories(AnalyticsData d, AppStrings str) {
    final sorted = d.incomeByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(children: [
      for (var i = 0; i < sorted.length; i++)
        Container(
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(border: Border(top: i == 0 ? BorderSide.none : BorderSide(color: AppColors.line))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(str.categoryName(sorted[i].key), style: fig(16, weight: 600)),
            Text('+${formatMoney(sorted[i].value)}', style: fig(16, weight: 700, color: AppColors.income)),
          ]),
        ),
    ]);
  }

  Widget _monthlyBars(AnalyticsData d, AppStrings str, int budget) {
    final months = str.isEnglish ? _shortMonthsEn : _shortMonths;
    final maxV = d.monthly.map((e) => e.value).fold(0, (a, b) => a > b ? a : b);
    final maxY = [maxV, budget].reduce((a, b) => a > b ? a : b).toDouble();
    return SizedBox(
      height: 190,
      child: BarChart(BarChartData(
        maxY: maxY == 0 ? 100 : maxY * 1.15,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: AppColors.line, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          if (budget > 0)
            HorizontalLine(
              y: budget.toDouble(),
              color: AppColors.outline,
              strokeWidth: 1.5,
              dashArray: [6, 4],
              label: HorizontalLineLabel(show: true, alignment: Alignment.topRight, style: fig(12, color: AppColors.text2), labelResolver: (_) => '${str.isEnglish ? 'goal' : 'cel'} ${formatMoney(budget)}'),
            ),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox() : Text(_axis(v), style: fig(11, color: AppColors.text2)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final m = d.monthly[v.toInt()].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(months[m.month - 1], style: fig(13, weight: m == d.month ? 700 : 400, color: m == d.month ? AppColors.text : AppColors.text2)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(getTooltipItem: (g, _, rod, _) => BarTooltipItem(formatMoney(rod.toY.round()), fig(13, weight: 700, color: Colors.white)))),
        barGroups: [
          for (var i = 0; i < d.monthly.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: d.monthly[i].value.toDouble(),
                width: 26,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(2)),
                color: d.monthly[i].key == d.month ? AppColors.accent : AppColors.track,
              ),
            ]),
        ],
      )),
    );
  }

  /// Categories as sorted bars with amounts (replaces the old donut).
  Widget _categories(AnalyticsData d, AppStrings str) {
    final entries = d.byCategory.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return Text(str.noData, style: fig(16, color: AppColors.text2));
    final maxV = entries.first.value;
    final sum = entries.fold(0, (a, e) => a + e.value);
    return Column(children: [
      for (var i = 0; i < entries.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(top: i == 0 ? BorderSide.none : BorderSide(color: AppColors.line))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(str.categoryName(entries[i].key), style: fig(16, weight: 600)),
              Text('${formatMoney(entries[i].value)}  ·  ${(entries[i].value / sum * 100).round()}%', style: fig(16, weight: 700)),
            ]),
            const SizedBox(height: 6),
            ProgressBar(entries[i].value / maxV, height: 8),
          ]),
        ),
    ]);
  }

  /// Running total through the month; for the current month it is drawn against an even-pace line to the budget.
  Widget _cumulative(AnalyticsData d, AppStrings str, int budget) {
    final days = d.daysInMonth;
    final lastDay = _isCurrent ? DateTime.now().day : days;
    var run = 0;
    final spots = <FlSpot>[const FlSpot(0, 0)];
    for (var day = 1; day <= lastDay; day++) {
      run += d.daily[day] ?? 0;
      spots.add(FlSpot(day.toDouble(), run.toDouble()));
    }
    final maxY = [run, budget].reduce((a, b) => a > b ? a : b).toDouble();
    return SizedBox(
      height: 170,
      child: LineChart(LineChartData(
        minX: 0,
        maxX: days.toDouble(),
        minY: 0,
        maxY: maxY == 0 ? 100 : maxY * 1.15,
        gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: AppColors.line, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox() : Text(_axis(v), style: fig(11, color: AppColors.text2)))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 5,
              getTitlesWidget: (v, _) => v == 0 ? const SizedBox() : Padding(padding: const EdgeInsets.only(top: 4), child: Text('${v.toInt()}', style: fig(11, color: AppColors.text2))),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          if (budget > 0)
            LineChartBarData(spots: [const FlSpot(0, 0), FlSpot(days.toDouble(), budget.toDouble())], color: AppColors.outline, barWidth: 2, dashArray: [6, 4], dotData: const FlDotData(show: false)),
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: AppColors.accent,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: AppColors.accent.withValues(alpha: 0.12)),
          ),
        ],
      )),
    );
  }

  Widget _daily(AnalyticsData d, AppStrings str) {
    final months = str.isEnglish ? _shortMonthsEn : _shortMonths;
    final days = d.daysInMonth;
    final maxY = d.daily.values.fold(0, (a, b) => a > b ? a : b).toDouble();
    return SizedBox(
      height: 150,
      child: BarChart(BarChartData(
        maxY: maxY == 0 ? 100 : maxY * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) {
                final day = v.toInt() + 1;
                return (day == 1 || day % 5 == 0) ? Padding(padding: const EdgeInsets.only(top: 4), child: Text('$day', style: fig(11, color: AppColors.text2))) : const SizedBox();
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, _, rod, _) => BarTooltipItem('${g.x + 1} ${months[d.month.month - 1]}\n${formatMoney(rod.toY.round())}', fig(12, weight: 700, color: Colors.white)),
          ),
        ),
        barGroups: [
          for (var day = 1; day <= days; day++)
            BarChartGroupData(x: day - 1, barRods: [
              BarChartRodData(toY: (d.daily[day] ?? 0).toDouble(), width: 5, borderRadius: const BorderRadius.vertical(top: Radius.circular(2)), color: AppColors.accent),
            ]),
        ],
      )),
    );
  }

  Widget _stores(AnalyticsData d) {
    final maxV = d.topStores.first.value;
    return Column(children: [
      for (var i = 0; i < d.topStores.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(top: i == 0 ? BorderSide.none : BorderSide(color: AppColors.line))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(d.topStores[i].key, overflow: TextOverflow.ellipsis, style: fig(16, weight: 600))),
              Text(formatMoney(d.topStores[i].value), style: fig(16, weight: 700)),
            ]),
            const SizedBox(height: 6),
            ProgressBar(maxV == 0 ? 0 : d.topStores[i].value / maxV, height: 8),
          ]),
        ),
    ]);
  }
}
