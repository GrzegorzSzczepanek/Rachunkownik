import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/receipt_images.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'income_dialog.dart';
import 'overview_screen.dart';
import 'scan_flow.dart' show ReviewScreen;
import 'widgets.dart';

enum _ViewMode { expenses, incomes }

/// Paragony i Dochody per design/Paragony, Dochody and Paragon-edycja.
class ReceiptsScreen extends ConsumerStatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  ConsumerState<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends ConsumerState<ReceiptsScreen> {
  _ViewMode _mode = _ViewMode.expenses;

  Widget _segment(String label, bool sel, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: sel ? AppColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(11)),
            child: Text(label, style: fig(15, weight: sel ? 700 : 600, color: sel ? AppColors.onAccent : AppColors.text3)),
          ),
        ),
      );

  /// Delete right away and offer "Cofnij": restores the receipt and keeps the photo until the bar closes.
  Future<void> _deleteReceipt(Receipt r) async {
    final str = ref.read(appStringsProvider);
    final db = ref.read(dbProvider);
    await db.deleteReceipt(r.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    var undone = false;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
          content: Text(str.isEnglish ? 'Receipt deleted' : 'Paragon usunięty'),
          action: SnackBarAction(
            label: str.undo,
            onPressed: () async {
              undone = true;
              await db.saveReceipt(Receipt(
                  store: r.store, date: r.date, totalCents: r.totalCents, source: r.source, engineLabel: r.engineLabel, imagePath: r.imagePath,
                  items: [for (final i in r.items) ReceiptItem(name: i.name, cents: i.cents, category: i.category, lowConfidence: i.lowConfidence)]));
              ref.read(dataVersionProvider.notifier).bump();
            },
          ),
        ))
        .closed
        .then((_) {
      if (!undone) deleteReceiptImage(r.imagePath);
    });
  }

  Future<void> _copyReceipt(Receipt r) async {
    await ref.read(dbProvider).saveReceipt(Receipt(
        store: r.store, date: DateTime.now(), totalCents: r.totalCents, source: ReadSource.manual,
        items: [for (final i in r.items) ReceiptItem(name: i.name, cents: i.cents, category: i.category)]));
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(appStringsProvider).isEnglish ? 'Saved a copy' : 'Zapisano kopię')));
  }

  Future<void> _showPhoto(Receipt r) async {
    final bytes = await readReceiptImage(r.imagePath);
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(appStringsProvider).isEnglish ? 'No photo saved for this receipt' : 'Ten paragon nie ma zapisanego zdjęcia')));
      return;
    }
    await showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes))));
  }

  void _receiptSheet(Receipt r) {
    final str = ref.read(appStringsProvider);
    Widget action(String title, VoidCallback onTap, {String? trailing, bool chevron = false}) => NavRow(
          minHeight: 52,
          title: title,
          trailing: trailing != null ? Text(trailing, style: fig(14, weight: 500, color: AppColors.text2)) : (chevron ? Icon(Icons.chevron_right, color: AppColors.text2) : const SizedBox.shrink()),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)))),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.store, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(26)),
                  Text('${str.relativeDate(r.date)}, ${str.itemsCount(r.items.length)}', style: fig(15, color: AppColors.text3)),
                ]),
              ),
              Text(formatMoney(r.totalCents), style: display(32)),
            ]),
            const SizedBox(height: 12),
            action(str.isEnglish ? 'Edit store, date and items' : 'Edytuj sklep, datę i pozycje',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(initial: r))), chevron: true),
            if (r.imagePath != null) action(str.isEnglish ? 'View receipt photo' : 'Zobacz zdjęcie paragonu', () => _showPhoto(r), chevron: true),
            action(str.saveAsCopy, () => _copyReceipt(r)),
            action(str.isEnglish ? 'Delete receipt' : 'Usuń paragon', () => _deleteReceipt(r), trailing: str.isEnglish ? 'You can undo' : 'Możesz cofnąć'),
          ]),
        ),
      ),
    );
  }

  Future<void> _deleteIncome(Income inc) async {
    final str = ref.read(appStringsProvider);
    final db = ref.read(dbProvider);
    await db.deleteIncome(inc.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${str.isEnglish ? 'Deleted' : 'Usunięto'}: ${inc.title}'),
      action: SnackBarAction(
        label: str.undo,
        onPressed: () async {
          await db.saveIncome(Income(title: inc.title, cents: inc.cents, category: inc.category, date: inc.date, note: inc.note));
          ref.read(dataVersionProvider.notifier).bump();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    final receipts = ref.watch(receiptsProvider);
    final incomes = ref.watch(incomesProvider);
    final now = DateTime.now();
    final monthIncome = (incomes.valueOrNull ?? const <Income>[]).where((i) => i.date.year == now.year && i.date.month == now.month).fold<int>(0, (a, i) => a + i.cents);
    final bottom = 84 + MediaQuery.of(context).padding.bottom + 40;
    final expenses = _mode == _ViewMode.expenses;

    return ListView(padding: EdgeInsets.only(bottom: bottom), children: [
      HeroZone(
        bottom: 20,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: 52, child: Align(alignment: Alignment.centerLeft, child: Text(str.tabReceipts, style: display(32)))),
          const SizedBox(height: 8),
          Container(
            height: 52,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              _segment('${str.expensesTab} (${receipts.valueOrNull?.length ?? 0})', expenses, () => setState(() => _mode = _ViewMode.expenses)),
              _segment('${str.incomesTab} (${incomes.valueOrNull?.length ?? 0})', !expenses, () => setState(() => _mode = _ViewMode.incomes)),
            ]),
          ),
          if (!expenses) ...[
            const SizedBox(height: 20),
            MoneyText(monthIncome, size: 56, unitSize: 24, color: AppColors.income, plus: true),
            Text(str.isEnglish ? 'income this month' : 'dochodów w tym miesiącu', style: fig(16, weight: 600)),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: expenses ? _expenses(str, receipts) : _incomes(str, incomes),
      ),
    ]);
  }

  Widget _expenses(AppStrings str, AsyncValue<List<Receipt>> receipts) => receipts.when(
        data: (list) => list.isEmpty
            ? Padding(padding: const EdgeInsets.only(top: 24), child: Text(str.noReceiptsCamera, style: fig(16, color: AppColors.text3, height: 24 / 16)))
            : Column(children: [
                for (var i = 0; i < list.length; i++)
                  ReceiptTile(list[i], bottomLine: i == list.length - 1, onTap: () => _receiptSheet(list[i]), onLongPress: () => _receiptSheet(list[i])),
              ]),
        loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text('$e'),
      );

  Widget _incomes(AppStrings str, AsyncValue<List<Income>> incomes) => incomes.when(
        data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str.noIncomesTitle, style: display(22)),
                const SizedBox(height: 6),
                Text(str.noIncomesDesc, style: fig(16, color: AppColors.text3, height: 24 / 16)),
              ]),
            )
          else
            for (var i = 0; i < list.length; i++)
              IncomeTile(list[i],
                  bottomLine: i == list.length - 1,
                  onTap: () => showIncomeDialog(context, initial: list[i]),
                  onLongPress: () => _deleteIncome(list[i])),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => showIncomeDialog(context), child: Text(list.isEmpty ? str.addFirstIncome : str.addIncome)),
          const SizedBox(height: 8),
          Text(str.incomeTapHint, style: fig(13, color: AppColors.text2)),
        ]),
        loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text('$e'),
      );
}
