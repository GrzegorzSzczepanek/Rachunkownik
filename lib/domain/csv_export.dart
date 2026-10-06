import 'package:csv/csv.dart';

import '../core/money.dart';
import 'models.dart';

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _sourceLabel = {
  ReadSource.manual: 'ręcznie',
  ReadSource.local: 'lokalny model',
  ReadSource.api: 'API',
  ReadSource.bank: 'import z banku',
};

/// One row per receipt line. Excel-friendly: UTF-8 BOM, ';' separator, decimal
/// comma. A receipt without lines still gets one row so no spending is lost.
String receiptsToCsv(List<Receipt> receipts) {
  final rows = <List<dynamic>>[
    ['Data', 'Sklep', 'Pozycja', 'Kategoria', 'Kwota pozycji', 'Suma paragonu', 'Źródło'],
  ];
  for (final r in receipts) {
    final total = formatMoney(r.totalCents, withCurrency: false).replaceAll(' ', '');
    final source = _sourceLabel[r.source] ?? '';
    if (r.items.isEmpty) {
      rows.add([_day(r.date), r.store, '', '', '', total, source]);
    }
    for (final i in r.items) {
      rows.add([
        _day(r.date),
        r.store,
        i.name,
        i.category,
        formatMoney(i.cents, withCurrency: false).replaceAll(' ', ''),
        total,
        source,
      ]);
    }
  }
  return Csv.excel().encode(rows);
}
