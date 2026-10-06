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
const _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

const _monthsFull = [
  'STYCZEŃ', 'LUTY', 'MARZEC', 'KWIECIEŃ', 'MAJ', 'CZERWIEC', 'LIPIEC', 'SIERPIEŃ',
  'WRZESIEŃ', 'PAŹDZIERNIK', 'LISTOPAD', 'GRUDZIEŃ'
];
const _monthsFullEn = [
  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST',
  'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
];

String shortDate(DateTime d, {bool isEnglish = false}) =>
    isEnglish ? '${d.day} ${_monthsEn[d.month - 1]}' : '${d.day} ${_months[d.month - 1]}';
String longDate(DateTime d, {bool isEnglish = false}) =>
    isEnglish ? '${d.day} ${_monthsEn[d.month - 1]} ${d.year}' : '${d.day} ${_months[d.month - 1]} ${d.year}';
String monthLabel(DateTime d, {bool isEnglish = false}) =>
    isEnglish ? '${_monthsFullEn[d.month - 1]} ${d.year}' : '${_monthsFull[d.month - 1]} ${d.year}';
