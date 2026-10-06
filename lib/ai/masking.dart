/// Best-effort scrubbing of text before it leaves the device. It catches
/// patterns (card, PESEL, NIP, phone, e-mail); it can't know a person's name
/// or address, and it does nothing for images.
String maskSensitive(String input) {
  var s = input;
  s = s.replaceAllMapped(
      RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), (_) => '[e-mail]');
  s = s.replaceAllMapped(
      RegExp(r'\b(?:\d[ -]?){13,19}\b'), (m) => _maskDigits(m[0]!));
  s = s.replaceAllMapped(RegExp(r'\b\d{3}[ -]?\d{2,3}[ -]?\d{2,3}[ -]?\d{2,3}\b'), (m) {
    final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
    return digits.length == 10 ? '[NIP]' : m[0]!;
  });
  s = s.replaceAllMapped(RegExp(r'\b\d{11}\b'), (_) => '[PESEL]');
  s = s.replaceAllMapped(
      RegExp(r'(?<!\d)(?:\+48[ -]?)?\d{3}[ -]\d{3}[ -]\d{3}(?!\d)'), (_) => '[telefon]');
  return s;
}

String _maskDigits(String m) {
  final digits = m.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 13) return m;
  return '**** **** **** ${digits.substring(digits.length - 4)}';
}
