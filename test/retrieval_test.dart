import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/domain/retrieval.dart';

final now = DateTime(2026, 10, 5);

int _id = 0;
ItemDoc doc(String name, String store, String cat, DateTime d, int cents, {int? receipt}) =>
    ItemDoc(id: _id++, receiptId: receipt ?? _id, name: name, store: store, category: cat, date: d, cents: cents);

void main() {
  test('stemmer unifies Polish case forms and the k/c alternation', () {
    expect({stem('kawa'), stem('kawę'), stem('kawy'), stem('kawie'), stem('kawą')}.length, 1);
    expect({stem('mleko'), stem('mleka'), stem('mlekiem')}.length, 1);
    expect({stem('Żabka'), stem('Żabce'), stem('Żabki')}.map(foldPl).toSet().length, 1);
    expect(stem('zabce'), stem('zabka'));
    expect(stem('biedronce'), stem('biedronka'));
    expect(stem('ser'), 'ser');
  });

  group('query parsing', () {
    test('quarter / month / relative ranges', () {
      final lastQ = parseQuery('Ile wydałem na kawę w zeszłym kwartale?', now);
      // October is in Q4, so "last quarter" is July-September.
      expect(lastQ.range!.from, DateTime(2026, 7));
      expect(lastQ.range!.to, DateTime(2026, 10));
      expect(lastQ.range!.label, 'od lipca do września 2026');
      expect(lastQ.terms, ['kawe']);
      expect(lastQ.intent, Intent.sum);

      final thisM = parseQuery('ile wydałem w tym miesiącu', now);
      expect(thisM.range!.from, DateTime(2026, 10));
      expect(thisM.range!.label, 'w październiku 2026');

      final lastM = parseQuery('wydatki w zeszłym miesiącu', now);
      expect(lastM.range!.from, DateTime(2026, 9));

      final named = parseQuery('ile wydałem w lipcu na paliwo', now);
      expect(named.range!.from, DateTime(2026, 7));
      expect(named.terms, ['paliwo']);

      final lastYearMonth = parseQuery('co kupiłem w grudniu', now);
      expect(lastYearMonth.range!.from, DateTime(2025, 12)); // December is still ahead this year

      final lastN = parseQuery('ile wydałem w ostatnich 30 dniach', now);
      expect(lastN.range!.from, DateTime(2026, 9, 5));
      final lastThree = parseQuery('wydatki w ostatnich 3 miesiącach', now);
      expect(lastThree.range!.from, DateTime(2026, 7, 5));

      expect(parseQuery('ile wydałem na kawę', now).range, isNull);
    });

    test('intents', () {
      expect(parseQuery('ile razy byłem w Żabce', now).intent, Intent.count);
      expect(parseQuery('na co najwięcej wydałem w tym roku', now).intent, Intent.top);
      expect(parseQuery('gdzie najwięcej wydaję', now).byStore, isTrue);
      expect(parseQuery('co kupiłem wczoraj', now).intent, Intent.list);
      expect(parseQuery('ile wydałem w Żabce', now).terms, ['zabce']);
    });
  });

  group('retrieval over items', () {
    final docs = [
      doc('Kawa latte', 'Starbucks', 'Jedzenie', DateTime(2026, 7, 3), 1800, receipt: 1),
      doc('Kawa mielona 250g', 'Biedronka', 'Jedzenie', DateTime(2026, 8, 10), 2299, receipt: 2),
      doc('Czekolada mleczna 100g', 'Żabka', 'Jedzenie', DateTime(2026, 8, 11), 449, receipt: 3),
      doc('Baton Snickers', 'Żabka', 'Jedzenie', DateTime(2026, 9, 1), 349, receipt: 4),
      doc('Benzyna 95', 'Orlen', 'Transport', DateTime(2026, 9, 2), 21000, receipt: 5),
      doc('Mleko 3,2%', 'Biedronka', 'Jedzenie', DateTime(2026, 9, 3), 429, receipt: 6),
    ];

    List<Hit> ask(String q, {List<String> extra = const []}) {
      final plan = parseQuery(q, now);
      final inRange = plan.range == null
          ? docs
          : docs.where((d) => !d.date.isBefore(plan.range!.from) && d.date.isBefore(plan.range!.to)).toList();
      return searchPlan(inRange, plan, extraTerms: extra);
    }

    test('inflected query finds the product and the exact sum comes from the data', () {
      final hits = ask('Ile wydałem na kawę w zeszłym kwartale?');
      expect(hits.length, 2);
      expect(Aggregate(hits).totalCents, 1800 + 2299);
      final text = composeAnswer(parseQuery('Ile wydałem na kawę w zeszłym kwartale?', now), hits);
      expect(text, contains('40,99'));
      expect(text, contains('od lipca do września 2026'));
    });

    test('store names match through case forms', () {
      expect(ask('ile wydałem w Żabce').length, 2);
      expect(ask('ile wydałem w Biedronce').length, 2);
    });

    test('concepts expand through the lexicon (słodycze -> czekolada, baton)', () {
      final names = ask('ile wydałem na słodycze').map((h) => h.doc.name).toSet();
      expect(names, containsAll(['Czekolada mleczna 100g', 'Baton Snickers']));
      expect(names, isNot(contains('Benzyna 95')));
    });

    test('tolerates a typo', () {
      expect(ask('ile na benzyne wydalem').map((h) => h.doc.name), ['Benzyna 95']);
      expect(ask('ile wydałem na czekolde').single.doc.name, 'Czekolada mleczna 100g');
      expect(ask('ile wydałem na czkolada').length, 1);
    });

    test('extra terms from an LLM broaden the match', () {
      expect(ask('ile na paliwo').single.doc.name, 'Benzyna 95'); // lexicon: paliwo -> benzyna
      expect(ask('ile wydałem na tankowanie', extra: ['benzyna']).length, 1);
    });

    test('no terms: aggregate the whole range', () {
      final plan = parseQuery('na co najwięcej wydałem', now);
      final hits = searchPlan(docs, plan);
      expect(hits.length, docs.length);
      final text = composeAnswer(plan, hits);
      expect(text, startsWith('Najwięcej wydano na: Transport'));
    });

    test('count, nothing found, singular wording', () {
      final count = composeAnswer(parseQuery('ile razy kupiłem kawę', now),
          ask('ile razy kupiłem kawę'));
      expect(count, startsWith('2 razy'));
      expect(composeAnswer(parseQuery('ile na pizzę', now), ask('ile na pizzę')),
          contains('Nie znalazłem'));
      final one = composeAnswer(parseQuery('ile na benzynę', now), ask('ile na benzynę'));
      expect(one, contains('1 pozycja'));
    });
  });
}
