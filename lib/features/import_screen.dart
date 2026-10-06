import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final file = await FilePicker.pickFile(
        dialogTitle: 'Wybierz plik CSV z banku',
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
        setState(() {
          _busy = false;
          _error = 'Nie udało się wczytać pliku: $e';
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
    setState(() {
      _plan = planImport(rows, _receipts, _known,
          addUnmatched: _addUnmatched, claimedReceiptIds: _claimed);
      _error = rows.isEmpty
          ? 'Nie znaleziono żadnych transakcji. Sprawdź wybór kolumn (data, kwota, opis).'
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Zaimportowano ${plan.newReceipts.length} wydatków, '
            'dopasowano ${plan.matched} do paragonów.')));
    Navigator.of(context).pop();
  }

  List<DropdownMenuItem<int>> _colItems() {
    final header = _headerRow < _rows.length ? _rows[_headerRow] : const <String>[];
    return [
      for (var i = 0; i < header.length; i++)
        DropdownMenuItem(
            value: i,
            child: Text(header[i].isEmpty ? 'Kolumna ${i + 1}' : header[i].replaceAll('#', ''),
                overflow: TextOverflow.ellipsis)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Import z banku')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          const Text(
            'Wyeksportuj historię z bankowości internetowej do CSV (mBank, PKO BP, ING, Pekao, Santander '
            'i podobne). Plik jest czytany tylko na telefonie.',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: Text(_fileName == null ? 'Wybierz plik CSV' : 'Wybierz inny plik'),
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
                      ? '✓ Rozpoznano układ pliku automatycznie.'
                      : '⚠ Nie rozpoznałem układu. Wskaż kolumny poniżej.',
                  style: TextStyle(
                      color: _autoDetected ? AppColors.green : AppColors.amberInk, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                _dropdown('Data', _dateCol, (v) {
                  _dateCol = v;
                  _replan();
                }),
                const SizedBox(height: 10),
                _dropdown('Kwota', _amountCol, (v) {
                  _amountCol = v;
                  _replan();
                }),
                const SizedBox(height: 10),
                _dropdown('Opis', _descCols.length == 1 ? _descCols.first : null, (v) {
                  _descCols = v == null ? [] : [v];
                  _replan();
                }, hint: _descCols.length > 1 ? 'kilka kolumn (auto)' : 'wybierz'),
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
                const Text('Podsumowanie', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _stat('Nowe wydatki', '${plan.newReceipts.length}', formatMoney(plan.newTotalCents)),
                _stat('Dopasowane do paragonów', '${plan.matched}', 'bez dublowania'),
                _stat('Już zaimportowane', '${plan.duplicates}', 'pominięte'),
                _stat('Wpływy', '${plan.incomes}', 'pominięte'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dodaj wydatki bez paragonu', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Każda niedopasowana płatność zostanie zapisana jako wydatek z kategorią.'),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Align(alignment: Alignment.centerLeft, child: Eyebrow('PODGLĄD')),
                ),
                for (final t in plan.txns.take(8)) _previewRow(t),
                if (plan.txns.length > 8)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('+ ${plan.txns.length - 8} kolejnych', style: const TextStyle(color: AppColors.muted)),
                  ),
                if (plan.txns.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(20), child: Text('Nic nowego do zaimportowania.', style: TextStyle(color: AppColors.muted))),
              ]),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: (_busy || plan.txns.isEmpty) ? null : _import,
              child: Text('Importuj ${plan.txns.length} transakcji'),
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

  Widget _previewRow(ImportedTxn t) {
    final matched = t.matchedReceiptId != null;
    final created = t.newReceipt != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(created ? t.newReceipt!.store : cleanMerchant(t.row.description),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
                '${shortDate(t.row.date)}${created ? ' · ${t.newReceipt!.mainCategory}' : ''}',
                style: const TextStyle(color: AppColors.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Pill(matched ? 'Dopasowany' : created ? 'Nowy' : 'Zapisany',
            bg: matched ? AppColors.blueSoft : created ? AppColors.greenSoft : AppColors.chip,
            fg: matched ? AppColors.blue : created ? AppColors.green : AppColors.muted),
        const SizedBox(width: 10),
        Text(formatMoney(-t.row.cents, withCurrency: false), style: mono(size: 15, weight: FontWeight.w500)),
      ]),
    );
  }
}
