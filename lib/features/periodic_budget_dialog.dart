import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'widgets.dart';

DateTime thisWeekendStart([DateTime? from]) {
  final now = from ?? DateTime.now();
  final daysUntilFriday = DateTime.friday - now.weekday;
  final friday = now.add(Duration(days: daysUntilFriday));
  return DateTime(friday.year, friday.month, friday.day);
}

DateTime thisWeekendEnd([DateTime? from]) {
  final start = thisWeekendStart(from);
  final sunday = start.add(const Duration(days: 2));
  return DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);
}

DateTime thisWeekStart([DateTime? from]) {
  final now = from ?? DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
}

DateTime thisWeekEnd([DateTime? from]) {
  final start = thisWeekStart(from);
  final sunday = start.add(const Duration(days: 6));
  return DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);
}

Future<bool?> showPeriodicBudgetDialog(BuildContext context, {PeriodicBudget? initial}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _PeriodicBudgetDialog(initial: initial),
  );
}

class _PeriodicBudgetDialog extends ConsumerStatefulWidget {
  const _PeriodicBudgetDialog({this.initial});
  final PeriodicBudget? initial;

  @override
  ConsumerState<_PeriodicBudgetDialog> createState() => _PeriodicBudgetDialogState();
}

enum _PresetType { weekend, week, custom }

class _PeriodicBudgetDialogState extends ConsumerState<_PeriodicBudgetDialog> {
  late final TextEditingController _name;
  late final TextEditingController _limit;
  late DateTime _startDate;
  late DateTime _endDate;
  late BudgetPeriod _period;
  late bool _isRecurring;
  String? _category;
  _PresetType _preset = _PresetType.weekend;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _name = TextEditingController(text: init.name);
      _limit = TextEditingController(
          text: formatMoney(init.limitCents, withCurrency: false).replaceAll('\u00A0', ''));
      _startDate = init.startDate;
      _endDate = init.endDate;
      _period = init.period;
      _isRecurring = init.isRecurring;
      _category = init.category;
      _preset = _period == BudgetPeriod.weekly ? _PresetType.week : _PresetType.custom;
    } else {
      _name = TextEditingController(text: '');
      _limit = TextEditingController();
      _startDate = thisWeekendStart();
      _endDate = thisWeekendEnd();
      _period = BudgetPeriod.custom;
      _isRecurring = false;
      _category = null;
      _preset = _PresetType.weekend;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _applyPreset(_PresetType preset) {
    setState(() {
      _preset = preset;
      switch (preset) {
        case _PresetType.weekend:
          _period = BudgetPeriod.custom;
          _startDate = thisWeekendStart();
          _endDate = thisWeekendEnd();
          _isRecurring = false;
          if (_name.text.trim().isEmpty) {
            _name.text = ref.read(appStringsProvider).thisWeekend;
          }
        case _PresetType.week:
          _period = BudgetPeriod.weekly;
          _startDate = thisWeekStart();
          _endDate = thisWeekEnd();
          if (_name.text.trim().isEmpty) {
            _name.text = ref.read(appStringsProvider).thisWeek;
          }
        case _PresetType.custom:
          _period = BudgetPeriod.custom;
          _isRecurring = false;
      }
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: DateTime(_endDate.year, _endDate.month, _endDate.day),
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        _preset = _PresetType.custom;
        _period = BudgetPeriod.custom;
      });
    }
  }

  Future<void> _save() async {
    final nameText = _name.text.trim();
    final str = ref.read(appStringsProvider);
    final limitCents = parseMoney(_limit.text);

    if (nameText.isEmpty) {
      showError(context, str.budgetName);
      return;
    }
    if (limitCents == null || limitCents <= 0) {
      showError(context, str.budgetLimit);
      return;
    }

    final db = ref.read(dbProvider);
    final init = widget.initial;
    if (init == null) {
      await db.savePeriodicBudget(PeriodicBudget(
        name: nameText,
        category: _category,
        limitCents: limitCents,
        period: _period,
        startDate: _startDate,
        endDate: _endDate,
        isRecurring: _isRecurring,
      ));
    } else {
      await db.updatePeriodicBudget(PeriodicBudget(
        id: init.id,
        name: nameText,
        category: _category,
        limitCents: limitCents,
        period: _period,
        startDate: _startDate,
        endDate: _endDate,
        isRecurring: _isRecurring,
      ));
    }

    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final init = widget.initial;
    if (init?.id == null) return;
    await ref.read(dbProvider).deletePeriodicBudget(init!.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    final isEdit = widget.initial != null;

    final dateRangeStr =
        '${shortDate(_startDate, isEnglish: str.isEnglish)} – ${shortDate(_endDate, isEnglish: str.isEnglish)}';

    return AlertDialog(
      title: Text(isEdit ? str.editBudget : str.addBudget),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Presets
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(str.thisWeekend),
                  selected: _preset == _PresetType.weekend,
                  onSelected: (_) => _applyPreset(_PresetType.weekend),
                ),
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(str.thisWeek),
                  selected: _preset == _PresetType.week,
                  onSelected: (_) => _applyPreset(_PresetType.week),
                ),
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(str.customPeriod),
                  selected: _preset == _PresetType.custom,
                  onSelected: (_) => _applyPreset(_PresetType.custom),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('budgetNameField'),
              controller: _name,
              decoration: InputDecoration(
                labelText: str.budgetName,
                hintText: str.budgetNameHint,
                prefixIcon: const Icon(Icons.label_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('budgetLimitField'),
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: str.budgetLimit,
                suffixText: 'zł',
                prefixIcon: const Icon(Icons.savings_outlined),
              ),
            ),
            const SizedBox(height: 12),
            // Date range picker card
            InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.chip,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 20, color: AppColors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            str.budgetPeriod,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateRangeStr,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_calendar_rounded, size: 18, color: AppColors.muted),
                  ],
                ),
              ),
            ),
            if (_period == BudgetPeriod.weekly) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(str.recurringWeekly, style: const TextStyle(fontWeight: FontWeight.w600)),
                value: _isRecurring,
                onChanged: (v) => setState(() => _isRecurring = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category ?? '',
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(str.allExpenses),
                ),
                for (final c in defaultCategories)
                  DropdownMenuItem<String>(
                    value: c,
                    child: Text(str.categoryName(c)),
                  ),
              ],
              onChanged: (v) => setState(() => _category = (v == null || v.isEmpty) ? null : v),
              decoration: InputDecoration(
                labelText: str.category,
                prefixIcon: const Icon(Icons.category_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (isEdit)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _delete,
            child: Text(str.deleteBudget),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(str.cancel),
        ),
        FilledButton(
          key: const ValueKey('budgetSaveButton'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          onPressed: _save,
          child: Text(str.save),
        ),
      ],
    );
  }
}
