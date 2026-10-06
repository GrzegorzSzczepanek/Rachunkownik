import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/ai_settings.dart';
import 'package:rachunkownik/ai/llm_api.dart';
import 'package:rachunkownik/ai/local_runtime.dart';
import 'package:rachunkownik/ai/natural_expense_parser.dart';
import 'package:rachunkownik/ai/spending_chat.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeLlm implements LlmApi {
  FakeLlm(this.reply);
  final String Function(String system, String user) reply;
  final calls = <String>[];

  @override
  Future<LlmResult> complete({
    required String system,
    required String user,
    Uint8List? image,
    String imageMime = 'image/jpeg',
    bool json = false,
    int maxTokens = 2048,
  }) async {
    calls.add(user);
    return LlmResult(reply(system, user));
  }
}

Future<AppDb> freshDb() async {
  final dir = await Directory.systemTemp.createTemp('rachunkownik_chat_test');
  return AppDb.open(path: '${dir.path}/test.db');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final now = DateTime(2026, 10, 6, 12, 0);

  group('isExpenseInput intent classification', () {
    test('identifies spending queries as non-expense input', () {
      expect(isExpenseInput('Ile wydałem na kawę w tym miesiącu?'), isFalse);
      expect(isExpenseInput('kiedy ostatnio kupiłem paliwo?'), isFalse);
      expect(isExpenseInput('gdzie wydałem najwięcej?'), isFalse);
      expect(isExpenseInput('pokaż zakupy z wczoraj'), isFalse);
      expect(isExpenseInput('podsumuj moje wydatki'), isFalse);
      expect(isExpenseInput('co kupiłem w zeszłym tygodniu?'), isFalse);
    });

    test('identifies expense logging statements as expense input', () {
      expect(isExpenseInput('Kupiłem w Żabce kawę za 8 zł'), isTrue);
      expect(isExpenseInput('kupiłam chleb 5 zł i mleko 4 zł'), isTrue);
      expect(isExpenseInput('Wczoraj wydałem 50 zł na obiad'), isTrue);
      expect(isExpenseInput('Zapłaciłem 120 zł na Orlenie za paliwo'), isTrue);
      expect(isExpenseInput('Biedronka: masło 7.50 zł, ser 9 zł'), isTrue);
      expect(isExpenseInput('Kawa 12 zł'), isTrue);
    });
  });

  group('parseExpenseOffline', () {
    test('parses single item with store and currency', () {
      final r = parseExpenseOffline('Kupiłem w Żabce kawę za 8 zł', now);
      expect(r.store, 'Żabka');
      expect(r.totalCents, 800);
      expect(r.items.length, 1);
      expect(r.items.first.name, contains('Kaw'));
      expect(r.items.first.cents, 800);
      expect(r.items.first.category, 'Jedzenie');
      expect(r.date.day, now.day);
    });

    test('parses multiple items with conjunctions and commas', () {
      final r = parseExpenseOffline('Wczoraj w Biedronce kupiłem chleb 5 zł, masło 7,50 zł i mleko 4 zł', now);
      expect(r.store, 'Biedronka');
      expect(r.date.day, now.subtract(const Duration(days: 1)).day);
      expect(r.items.length, 3);
      expect(r.totalCents, 1650);
      expect(r.items.map((i) => i.category), everyElement('Jedzenie'));
    });

    test('handles transport and gas stations with store colon syntax', () {
      final r = parseExpenseOffline('Orlen: Benzyna 95 za 150 zł', now);
      expect(r.store, 'Orlen');
      expect(r.totalCents, 15000);
      expect(r.items.first.category, 'Transport');
    });

    test('handles relative dates: przedwczoraj and wczoraj', () {
      final rYesterday = parseExpenseOffline('Wczoraj wydałem 20 zł na kebab', now);
      expect(rYesterday.date.day, now.subtract(const Duration(days: 1)).day);

      final rBefore = parseExpenseOffline('Przedwczoraj kupiłem książkę za 49 zł', now);
      expect(rBefore.date.day, now.subtract(const Duration(days: 2)).day);
    });
  });

  group('parseNaturalExpense with LLM', () {
    test('uses LLM JSON reply when available', () async {
      final fakeLlm = FakeLlm((sys, user) => '''
{
  "store": "Rossmann",
  "date": "2026-10-06",
  "total": 35.50,
  "items": [
    {"name": "Szampon", "price": 18.50, "category": "Zdrowie"},
    {"name": "Pasta do zębów", "price": 17.00, "category": "Zdrowie"}
  ]
}
''');

      final r = await parseNaturalExpense('Kupiłem szampon i pastę w Rossmannie', now, llm: fakeLlm);
      expect(r.store, 'Rossmann');
      expect(r.totalCents, 3550);
      expect(r.items.length, 2);
      expect(r.items[0].name, 'Szampon');
      expect(r.items[0].cents, 1850);
      expect(r.items[1].name, 'Pasta do zębów');
      expect(r.items[1].cents, 1700);
      expect(fakeLlm.calls.length, 1);
    });

    test('gracefully falls back to offline parser when LLM fails', () async {
      final failingLlm = FakeLlm((sys, user) => throw Exception('API connection timeout'));
      final r = await parseNaturalExpense('Kupiłem w Lidlu czekoladę za 6 zł', now, llm: failingLlm);
      expect(r.store, 'Lidl');
      expect(r.totalCents, 600);
      expect(r.items.first.name, contains('Czekolad'));
    });
  });

  group('SpendingChat integration with natural expense', () {
    test('automatically logs expense into database and returns confirmation', () async {
      final db = await freshDb();
      final chat = SpendingChat(
        db: db,
        settings: AiSettings.defaults(),
        local: const UnavailableLocalRuntime(),
        now: now,
      );

      final answer = await chat.ask('Kupiłem w Żabce kawę za 8 zł i kanapkę za 12 zł');
      expect(answer.createdReceipt, isNotNull);
      expect(answer.createdReceipt!.store, 'Żabka');
      expect(answer.createdReceipt!.totalCents, 2000);
      expect(answer.createdReceipt!.id, isNotNull);
      expect(answer.text, contains('Dodałem wydatek do bazy'));
      expect(answer.text, contains('20,00'));

      // Check that it's persisted in the DB
      final all = await db.receipts();
      final savedInDb = all.firstWhere((r) => r.id == answer.createdReceipt!.id);
      expect(savedInDb.store, 'Żabka');
      expect(savedInDb.items.length, 2);

      // Now query the spending chat about coffee!
      final queryAnswer = await chat.ask('Ile wydałem na kawę?');
      expect(queryAnswer.createdReceipt, isNull);
      expect(queryAnswer.text, contains('8,00'));
    });
  });
}
