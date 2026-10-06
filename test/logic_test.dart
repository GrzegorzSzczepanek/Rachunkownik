import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/masking.dart';
import 'package:rachunkownik/ai/receipt_extractor.dart';
import 'package:rachunkownik/core/money.dart';
import 'package:rachunkownik/domain/models.dart';
import 'package:rachunkownik/domain/subscription_detector.dart';

void main() {
  test('money formatting and parsing', () {
    expect(formatMoney(348250), '3 482,50 zł');
    expect(formatMoney(5), '0,05 zł');
    expect(parseMoney('4,29'), 429);
    expect(parseMoney('4.29 zł'), 429);
    expect(parseMoney('abc'), isNull);
  });

  test('receipt JSON is parsed from messy model output', () {
    const raw = '''Oto wynik:
```json
{"store":"Biedronka","date":"2026-10-05","total":8.78,
 "items":[{"name":"Mleko 3,2% 1 l","price":4.29,"category":"Jedzenie","confidence":0.95},
          {"name":"BAN LUZ","price":4.49,"category":"Nieznana","confidence":0.4}]}
```''';
    final r = parseReceiptJson(raw, source: ReadSource.api);
    expect(r.store, 'Biedronka');
    expect(r.totalCents, 878);
    expect(r.items.length, 2);
    expect(r.items[1].lowConfidence, isTrue);
    expect(r.items[1].category, isNot('Nieznana'));
    expect(r.sumsMatch, isTrue);
  });

  test('receipt JSON parser tolerates trailing commas and string prices with commas', () {
    const raw = '''
    {
      "store": "Żabka",
      "date": "2026-10-06",
      "total": "12,50 zł",
      "items": [
        {"name": "Kawa", "price": "7,50", "category": "Jedzenie",},
        {"name": "Drożdżówka", "price": 5.0, "category": "Jedzenie",},
      ],
    }''';
    final r = parseReceiptJson(raw, source: ReadSource.local);
    expect(r.store, 'Żabka');
    expect(r.totalCents, 1250);
    expect(r.items.length, 2);
    expect(r.items[0].cents, 750);
    expect(r.items[1].cents, 500);
    expect(r.sumsMatch, isTrue);
  });

  test('non-JSON reply raises a clear error', () {
    expect(() => parseReceiptJson('przepraszam', source: ReadSource.api),
        throwsA(isA<ExtractionException>()));
  });

  test('masking hides card, PESEL, e-mail', () {
    final m = maskSensitive('karta 4111 1111 1111 1234 pesel 44051401359 a@b.pl');
    expect(m, contains('1234'));
    expect(m, isNot(contains('4111 1111')));
    expect(m, contains('[PESEL]'));
    expect(m, contains('[e-mail]'));
  });

  test('subscription detector finds monthly, ignores irregular', () {
    final charges = [
      for (var m = 7; m <= 9; m++) Charge('Google *Storage', 999, DateTime(2026, m, 12)),
      Charge('Biedronka', 1000, DateTime(2026, 7, 1)),
      Charge('Biedronka', 3000, DateTime(2026, 8, 20)),
      Charge('Biedronka', 1000, DateTime(2026, 9, 2)),
    ];
    final found = detectSubscriptions(charges);
    expect(found.length, 1);
    expect(found.first.name, 'GOOGLE *STORAGE');
    expect(found.first.period, BillingPeriod.monthly);
    expect(found.first.nextDate, DateTime(2026, 10, 12));
  });

  test('subscription rolls renewal forward', () {
    final s = Subscription(name: 'x', cents: 100, nextDate: DateTime(2026, 8, 9));
    expect(s.nextRenewal(DateTime(2026, 10, 5)), DateTime(2026, 10, 9));
  });
}
