import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../providers.dart';
import 'income_dialog.dart';
import 'widgets.dart';

/// One colour per category, readable next to each other and on white.
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
  String? _focus; // category highlighted in the donut

  bool get _isCurrent => _month == monthStart(DateTime.now());

  void _shift(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _focus = null;
      });

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    final data = ref.watch(analyticsProvider(_month));
    return Scaffold(
      appBar: AppBar(title: Text(str.analyticsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton.filledTonal(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Text(monthLabel(_month, isEnglish: str.isEnglish), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            IconButton.filledTonal(
                onPressed: _isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 12),
          data.when(
            data: (d) => _body(d, str),
            loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('$e'),
          ),
        ],
      ),
    );
  }

  Widget _body(AnalyticsData d, AppStrings str) {
    if (d.total == 0 && d.monthly.every((m) => m.value == 0)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(str.noExpensesToAnalyze,
            style: const TextStyle(color: AppColors.muted)),
      );
    }
    final delta = d.previousTotal == 0 ? null : (d.total - d.previousTotal) / d.previousTotal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Eyebrow(str.spent),
      Text(formatMoney(d.total), style: mono(size: 36)),
      const SizedBox(height: 4),
      if (delta != null)
        Text(
          '${delta >= 0 ? '▲' : '▼'} ${(delta.abs() * 100).round()}% ${str.vsPreviousMonth} '
          '(${formatMoney(d.previousTotal)})',
          style: TextStyle(color: delta > 0 ? AppColors.amberInk : AppColors.green, fontWeight: FontWeight.w600),
        )
      else
        Text(str.noPreviousMonthData, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 14),
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
                  Text(str.incomes, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('+${formatMoney(d.income)}',
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
                  Text(str.balance, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${d.balance >= 0 ? '+' : ''}${formatMoney(d.balance)}',
                    style: mono(
                      size: 15,
                      weight: FontWeight.w700,
                      color: d.balance >= 0 ? AppColors.green : AppColors.amberInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _card(str.last6Months, _monthlyBars(d, str)),
      const SizedBox(height: 16),
      _card(str.categories, _categories(d, str)),
      if (d.incomeByCategory.isNotEmpty) ...[
        const SizedBox(height: 16),
        _card(str.incomesByCategory, _incomeCategories(d, str)),
      ],
      const SizedBox(height: 16),
      _card(str.dayByDay, _daily(d, str)),
      if (d.topStores.isNotEmpty) ...[
        const SizedBox(height: 16),
        _card(str.topMerchants, _stores(d)),
      ],
    ]);
  }

  Widget _card(String title, Widget child) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          child,
        ]),
      );

  Widget _incomeCategories(AnalyticsData d, AppStrings str) {
    final sorted = d.incomeByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(children: [
      for (final e in sorted) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(incomeIconFor(e.key), size: 18, color: AppColors.green),
                const SizedBox(width: 8),
                Text(str.categoryName(e.key), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              Text('+${formatMoney(e.value)}',
                  style: mono(size: 15, weight: FontWeight.w700, color: AppColors.green)),
            ],
          ),
        ),
        if (e != sorted.last) const Divider(height: 1),
      ],
    ]);
  }

  Widget _monthlyBars(AnalyticsData d, AppStrings str) {
    final months = str.isEnglish ? _shortMonthsEn : _shortMonths;
    final maxY = d.monthly.map((e) => e.value).fold(0, (a, b) => a > b ? a : b).toDouble();
    return SizedBox(
      height: 200,
      child: BarChart(BarChartData(
        maxY: maxY == 0 ? 100 : maxY * 1.15,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox()
                  : Text(_axis(v), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final m = d.monthly[v.toInt()].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(months[m.month - 1],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: m == d.month ? FontWeight.w800 : FontWeight.w500,
                          color: m == d.month ? AppColors.ink : AppColors.muted)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                formatMoney(rod.toY.round()), const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
        barGroups: [
          for (var i = 0; i < d.monthly.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: d.monthly[i].value.toDouble(),
                width: 22,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                color: d.monthly[i].key == d.month ? AppColors.green : AppColors.greenSoft,
              ),
            ]),
        ],
      )),
    );
  }

  Widget _categories(AnalyticsData d, AppStrings str) {
    final entries = d.byCategory.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return Text(str.noData, style: const TextStyle(color: AppColors.muted));
    final sum = entries.fold(0, (a, e) => a + e.value);
    return Column(children: [
      SizedBox(
        height: 190,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 62,
            pieTouchData: PieTouchData(touchCallback: (event, resp) {
              final i = resp?.touchedSection?.touchedSectionIndex;
              if (event.isInterestedForInteractions && i != null && i >= 0 && i < entries.length) {
                setState(() => _focus = entries[i].key);
              }
            }),
            sections: [
              for (final e in entries)
                PieChartSectionData(
                  value: e.value.toDouble(),
                  color: categoryColor(e.key),
                  radius: _focus == e.key ? 34 : 26,
                  showTitle: false,
                ),
            ],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_focus != null ? str.categoryName(_focus!) : str.totalSummary, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
            Text(formatMoney(_focus == null ? sum : d.byCategory[_focus] ?? 0), style: mono(size: 18)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      for (final e in entries)
        InkWell(
          onTap: () => setState(() => _focus = _focus == e.key ? null : e.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: categoryColor(e.key), borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(str.categoryName(e.key),
                    style: TextStyle(
                        fontWeight: _focus == e.key ? FontWeight.w800 : FontWeight.w500, fontSize: 15)),
              ),
              Text('${(e.value / sum * 100).round()}%', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(width: 12),
              SizedBox(
                  width: 96,
                  child: Text(formatMoney(e.value), textAlign: TextAlign.right, style: mono(size: 14, weight: FontWeight.w500))),
            ]),
          ),
        ),
    ]);
  }

  Widget _daily(AnalyticsData d, AppStrings str) {
    final months = str.isEnglish ? _shortMonthsEn : _shortMonths;
    final days = d.daysInMonth;
    final maxY = d.daily.values.fold(0, (a, b) => a > b ? a : b).toDouble();
    return SizedBox(
      height: 160,
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
                return (day == 1 || day % 5 == 0)
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('$day', style: const TextStyle(fontSize: 11, color: AppColors.muted)))
                    : const SizedBox();
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${group.x + 1} ${months[d.month.month - 1]}\n${formatMoney(rod.toY.round())}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ),
        barGroups: [
          for (var day = 1; day <= days; day++)
            BarChartGroupData(x: day - 1, barRods: [
              BarChartRodData(
                toY: (d.daily[day] ?? 0).toDouble(),
                width: 5,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                color: AppColors.green,
              ),
            ]),
        ],
      )),
    );
  }

  Widget _stores(AnalyticsData d) {
    final maxV = d.topStores.first.value;
    return Column(children: [
      for (final s in d.topStores)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(s.key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(formatMoney(s.value), style: mono(size: 14, weight: FontWeight.w500)),
            ]),
            const SizedBox(height: 4),
            ProgressBar(maxV == 0 ? 0 : s.value / maxV, height: 6),
          ]),
        ),
    ]);
  }
}
