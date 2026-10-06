import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/categorizer.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'widgets.dart';

const _incomeIcons = <String, IconData>{
  'Wynagrodzenie': Icons.account_balance_wallet_rounded,
  'Zlecenie': Icons.laptop_chromebook_rounded,
  'Premia': Icons.star_rounded,
  'Zwrot': Icons.replay_rounded,
  'Inwestycje': Icons.trending_up_rounded,
  'Prezent': Icons.card_giftcard_rounded,
  'Inne': Icons.category_rounded,
};

IconData incomeIconFor(String category) =>
    _incomeIcons[category] ?? Icons.attach_money_rounded;

/// Shows a dialog or modal sheet to add or edit an Income.
Future<bool?> showIncomeDialog(BuildContext context, {Income? initial}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _IncomeSheet(initial: initial),
  );
}

class _IncomeSheet extends ConsumerStatefulWidget {
  const _IncomeSheet({this.initial});
  final Income? initial;

  @override
  ConsumerState<_IncomeSheet> createState() => _IncomeSheetState();
}

class _IncomeSheetState extends ConsumerState<_IncomeSheet> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  late String _category;
  bool _manuallyPickedCategory = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _title = TextEditingController(text: init?.title ?? '');
    _amount = TextEditingController(
        text: init != null ? formatMoney(init.cents, withCurrency: false).replaceAll('\u00A0', '') : '');
    _note = TextEditingController(text: init?.note ?? '');
    _date = init?.date ?? DateTime.now();
    _category = init?.category ?? 'Wynagrodzenie';
    if (init != null) _manuallyPickedCategory = true;

    _title.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (!_manuallyPickedCategory) {
      final guessed = guessIncomeCategory(_title.text);
      if (guessed != _category) {
        setState(() => _category = guessed);
      }
    }
  }

  @override
  void dispose() {
    _title.removeListener(_onTitleChanged);
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final str = ref.read(appStringsProvider);
    final title = _title.text.trim();
    final cents = parseMoney(_amount.text);
    if (title.isEmpty) {
      showError(context, str.incomeTitleError);
      return;
    }
    if (cents == null || cents <= 0) {
      showError(context, str.incomeAmountError);
      return;
    }

    final db = ref.read(dbProvider);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();

    if (widget.initial != null) {
      final updated = widget.initial!.copy();
      updated.title = title;
      updated.cents = cents;
      updated.date = _date;
      updated.category = _category;
      updated.note = note;
      await db.updateIncome(updated);
    } else {
      await db.saveIncome(Income(
        title: title,
        cents: cents,
        date: _date,
        category: _category,
        note: note,
      ));
    }

    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${str.incomeSaved}: $title (${formatMoney(cents)}) [${str.categoryName(_category)}]'),
          backgroundColor: AppColors.green,
        ),
      );
    }
  }

  Future<void> _delete() async {
    final id = widget.initial?.id;
    if (id == null) return;
    final str = ref.read(appStringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(str.deleteIncomeConfirm(widget.initial!.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(str.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(str.delete)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).deleteIncome(id);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final str = ref.watch(appStringsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: AppColors.green, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEdit ? str.editIncome : str.addIncome,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                if (isEdit)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _amount,
              autofocus: !isEdit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: mono(size: 28, weight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: str.incomeAmount,
                suffixText: 'zł',
                suffixStyle: mono(size: 22, weight: FontWeight.w700),
                hintText: '0,00',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: '${str.incomeTitle} (${str.incomeTitleHint})',
                prefixIcon: const Icon(Icons.title_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              str.isEnglish
                  ? 'Income category (choose or matched automatically):'
                  : 'Kategoria dochodu (wybierz lub dopasuje się automatycznie):',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in defaultIncomeCategories)
                  FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          incomeIconFor(c),
                          size: 16,
                          color: _category == c ? Colors.white : AppColors.ink,
                        ),
                        const SizedBox(width: 6),
                        Text(str.categoryName(c)),
                      ],
                    ),
                    selected: _category == c,
                    selectedColor: AppColors.green,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _category == c ? Colors.white : AppColors.ink,
                      fontWeight: _category == c ? FontWeight.w700 : FontWeight.w500,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _category = c;
                          _manuallyPickedCategory = true;
                        });
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                      '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: '${str.incomeNote} (${str.incomeNoteHint})',
                prefixIcon: const Icon(Icons.note_alt_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  isEdit ? str.saveChanges : str.addIncome,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IncomeTile extends ConsumerWidget {
  const IncomeTile(this.inc, {super.key, this.onTap, this.onLongPress});
  final Income inc;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final str = ref.watch(appStringsProvider);
    final when = str.relativeDate(inc.date);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(incomeIconFor(inc.category), color: AppColors.green, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inc.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                Text(when, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const Text(' · ', style: TextStyle(color: AppColors.muted)),
                Text(str.categoryName(inc.category),
                    style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ]),
          ),
          Text('+${formatMoney(inc.cents)}',
              style: mono(size: 16, weight: FontWeight.w700, color: AppColors.green)),
        ]),
      ),
    );
  }
}

