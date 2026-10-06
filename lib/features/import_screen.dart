import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/bank_import.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'widgets.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});
  @override
  ConsumerState<ImportScreen> createState() => _ImportState();
}

class _ImportState extends ConsumerState<ImportScreen> {
  String? _fileName;
  List<List<String>> _rows = [];
  int _headerRow = 0;
  int? _dateCol;
  int? _amountCol;
  List<int> _descCols = [];
  bool _autoDetected = false;
  bool _addUnmatched = true;
  ImportPlan? _plan;
  List<Receipt> _receipts = [];
  Set<String> _known = {};
  Set<int> _claimed = {};
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    try {
      final str = ref.read(appStringsProvider);
      final file = await FilePicker.pickFile(
        dialogTitle: str.isEnglish ? 'Select bank CSV file' : 'Wybierz plik CSV z banku',
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt'],
      );
      if (file == null) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final text = decodeBankBytes(await file.readAsBytes());
      final rows = parseCsvText(text);
      final db = ref.read(dbProvider);
      _receipts = await db.receipts();
      _known = await db.knownBankHashes();
      _claimed = await db.claimedReceiptIds();
      final layout = detectLayout(rows);
      setState(() {
        _fileName = file.name;
        _rows = rows;
        _autoDetected = layout != null;
        if (layout != null) {
          _headerRow = layout.headerRow;
          _dateCol = layout.dateCol;
          _amountCol = layout.amountCol;
          _descCols = layout.descCols;
        } else {
          // Best guess for the header: the widest row near the top.
          var best = 0;
          for (var i = 0; i < rows.length && i < 60; i++) {
            if (rows[i].length > rows[best].length) best = i;
          }
          _headerRow = best;
          _dateCol = null;
          _amountCol = null;
          _descCols = [];
        }
        _busy = false;
      });
      _replan();
    } catch (e) {
      if (mounted) {
        final str = ref.read(appStringsProvider);
        setState(() {
          _busy = false;
          _error = str.isEnglish ? 'Failed to load file: $e' : 'Nie udało się wczytać pliku: $e';
        });
      }
    }
  }

  void _replan() {
    final d = _dateCol;
    if (d == null || _amountCol == null || _descCols.isEmpty) {
      setState(() => _plan = null);
      return;
    }
    final layout =
        CsvLayout(headerRow: _headerRow, dateCol: d, descCols: _descCols, amountCol: _amountCol);
    final rows = extractRows(_rows, layout);
    final str = ref.read(appStringsProvider);
    setState(() {
      _plan = planImport(rows, _receipts, _known,
          addUnmatched: _addUnmatched, claimedReceiptIds: _claimed);
      _error = rows.isEmpty
          ? (str.isEnglish
              ? 'No transactions found. Check selected columns (date, amount, description).'
              : 'Nie znaleziono żadnych transakcji. Sprawdź wybór kolumn (data, kwota, opis).')
          : null;
    });
  }

  Future<void> _import() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _busy = true);
    await ref.read(dbProvider).saveImport(plan);
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    final str = ref.read(appStringsProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(str.isEnglish
            ? 'Imported ${plan.newReceipts.length} expenses, matched ${plan.matched} to receipts.'
            : 'Zaimportowano ${plan.newReceipts.length} wydatków, dopasowano ${plan.matched} do paragonów.')));
    Navigator.of(context).pop();
  }

  List<DropdownMenuItem<int>> _colItems() {
    final header = _headerRow < _rows.length ? _rows[_headerRow] : const <String>[];
    final str = ref.read(appStringsProvider);
    return [
      for (var i = 0; i < header.length; i++)
        DropdownMenuItem(
            value: i,
            child: Text(header[i].isEmpty ? (str.isEnglish ? 'Column ${i + 1}' : 'Kolumna ${i + 1}') : header[i].replaceAll('#', ''),
                overflow: TextOverflow.ellipsis)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final str = ref.watch(appStringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(str.isEnglish ? 'Bank import' : 'Import z banku')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Text(
            str.isEnglish
                ? 'Export your online banking history to CSV. The file is processed only on your phone.'
                : 'Wyeksportuj historię z bankowości internetowej do CSV (mBank, PKO BP, ING, Pekao, Santander '
                  'i podobne). Plik jest czytany tylko na telefonie.',
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: Text(_fileName == null ? str.selectCsvFile : (str.isEnglish ? 'Choose another file' : 'Wybierz inny plik')),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (_fileName != null) ...[
            const SizedBox(height: 20),
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_fileName!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  _autoDetected
                      ? (str.isEnglish ? '✓ File layout detected automatically.' : '✓ Rozpoznano układ pliku automatycznie.')
                      : (str.isEnglish ? '⚠ Could not detect layout. Select columns below.' : '⚠ Nie rozpoznałem układu. Wskaż kolumny poniżej.'),
                  style: TextStyle(
                      color: _autoDetected ? AppColors.green : AppColors.amberInk, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                _dropdown(str.date, _dateCol, (v) {
                  _dateCol = v;
                  _replan();
                }, hint: str.isEnglish ? 'select' : 'wybierz'),
                const SizedBox(height: 10),
                _dropdown(str.isEnglish ? 'Amount' : 'Kwota', _amountCol, (v) {
                  _amountCol = v;
                  _replan();
                }, hint: str.isEnglish ? 'select' : 'wybierz'),
                const SizedBox(height: 10),
                _dropdown(str.isEnglish ? 'Description' : 'Opis', _descCols.length == 1 ? _descCols.first : null, (v) {
                  _descCols = v == null ? [] : [v];
                  _replan();
                }, hint: _descCols.length > 1 ? (str.isEnglish ? 'multiple columns (auto)' : 'kilka kolumn (auto)') : (str.isEnglish ? 'select' : 'wybierz')),
              ]),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: AppColors.amberInk, fontWeight: FontWeight.w600)),
            ),
          if (plan != null) ...[
            const SizedBox(height: 16),
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str.isEnglish ? 'Summary' : 'Podsumowanie', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _stat(str.isEnglish ? 'New expenses' : 'Nowe wydatki', '${plan.newReceipts.length}', formatMoney(plan.newTotalCents)),
                _stat(str.isEnglish ? 'Matched to receipts' : 'Dopasowane do paragonów', '${plan.matched}', str.isEnglish ? 'no duplicates' : 'bez dublowania'),
                _stat(str.isEnglish ? 'Already imported' : 'Już zaimportowane', '${plan.duplicates}', str.isEnglish ? 'skipped' : 'pominięte'),
                _stat(str.isEnglish ? 'Income' : 'Wpływy', '${plan.incomes}', str.isEnglish ? 'skipped' : 'pominięte'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(str.isEnglish ? 'Add expenses without receipt' : 'Dodaj wydatki bez paragonu', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(str.isEnglish
                      ? 'Each unmatched payment will be saved as an expense with category.'
                      : 'Każda niedopasowana płatność zostanie zapisana jako wydatek z kategorią.'),
                  value: _addUnmatched,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.green,
                  onChanged: (v) {
                    _addUnmatched = v;
                    _replan();
                  },
                ),
              ]),
            ),
            const SizedBox(height: 16),
            SectionCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Align(alignment: Alignment.centerLeft, child: Eyebrow(str.isEnglish ? 'PREVIEW' : 'PODGLĄD')),
                ),
                for (final t in plan.txns.take(8)) _previewRow(t, str),
                if (plan.txns.length > 8)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(str.isEnglish ? '+ ${plan.txns.length - 8} more' : '+ ${plan.txns.length - 8} kolejnych', style: const TextStyle(color: AppColors.muted)),
                  ),
                if (plan.txns.isEmpty)
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(str.isEnglish ? 'Nothing new to import.' : 'Nic nowego do zaimportowania.', style: const TextStyle(color: AppColors.muted))),
              ]),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: (_busy || plan.txns.isEmpty) ? null : _import,
              child: Text(str.isEnglish ? 'Import ${plan.txns.length} transactions' : 'Importuj ${plan.txns.length} transakcji'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dropdown(String label, int? value, ValueChanged<int?> on, {String hint = 'wybierz'}) {
    final items = _colItems();
    return DropdownButtonFormField<int>(
      initialValue: items.any((i) => i.value == value) ? value : null,
      isExpanded: true,
      items: items,
      hint: Text(hint),
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => setState(() => on(v)),
    );
  }

  Widget _stat(String k, String v, String note) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k)),
          Text(v, style: mono(size: 15)),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(note, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
        ]),
      );

  Widget _previewRow(ImportedTxn t, AppStrings str) {
    final matched = t.matchedReceiptId != null;
    final created = t.newReceipt != null;
    final badgeLabel = matched
        ? (str.isEnglish ? 'Matched' : 'Dopasowany')
        : created
            ? (str.isEnglish ? 'New' : 'Nowy')
            : (str.isEnglish ? 'Saved' : 'Zapisany');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(created ? t.newReceipt!.store : cleanMerchant(t.row.description),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
                '${shortDate(t.row.date, isEnglish: str.isEnglish)}${created ? ' · ${str.categoryName(t.newReceipt!.mainCategory)}' : ''}',
                style: const TextStyle(color: AppColors.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Pill(badgeLabel,
            bg: matched ? AppColors.blueSoft : created ? AppColors.greenSoft : AppColors.chip,
            fg: matched ? AppColors.blue : created ? AppColors.green : AppColors.muted),
        const SizedBox(width: 10),
        Text(formatMoney(-t.row.cents, withCurrency: false), style: mono(size: 15, weight: FontWeight.w500)),
      ]),
    );
  }
}
