/// Money is stored as integer grosze to avoid floating point drift.
String formatMoney(int cents, {bool withCurrency = true}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(' ');
    buf.write(whole[i]);
  }
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$buf,$frac${withCurrency ? ' zł' : ''}';
}

/// Accepts "4,29", "4.29", "4 29" style input. Returns null when unparsable.
int? parseMoney(String input) {
  final s = input.trim().replaceAll(RegExp(r'[^\d,.\-]'), '').replaceAll(',', '.');
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null) return null;
  return (v * 100).round();
}

const _months = [
  'sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'
];
const _monthsFull = [
  'STYCZEŃ', 'LUTY', 'MARZEC', 'KWIECIEŃ', 'MAJ', 'CZERWIEC', 'LIPIEC', 'SIERPIEŃ',
  'WRZESIEŃ', 'PAŹDZIERNIK', 'LISTOPAD', 'GRUDZIEŃ'
];

String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
String monthLabel(DateTime d) => '${_monthsFull[d.month - 1]} ${d.year}';
