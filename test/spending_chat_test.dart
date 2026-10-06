import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/ai_settings.dart';
import 'package:rachunkownik/ai/llm_api.dart';
import 'package:rachunkownik/ai/local_runtime.dart';
import 'package:rachunkownik/ai/spending_chat.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/models.dart';
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


/// Each test gets its own database file; sqflite's in-memory path is shared.
Future<AppDb> freshDb() async {
  final dir = await Directory.systemTemp.createTemp('rachunkownik_test');
  return AppDb.open(path: '${dir.path}/test.db');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final now = DateTime(2026, 10, 5);

  Future<AppDb> seeded() async {
    final db = await freshDb();
    Future<void> add(String store, DateTime d, List<(String, int, String)> items) =>
        db.saveReceipt(Receipt(
          store: store,
          date: d,
          totalCents: items.fold(0, (a, i) => a + i.$2),
          items: [for (final i in items) ReceiptItem(name: i.$1, cents: i.$2, category: i.$3)],
        ));
    await add('Starbucks', DateTime(2026, 7, 3), [('Kawa latte', 1800, 'Jedzenie')]);
    await add('Biedronka', DateTime(2026, 8, 10), [('Kawa mielona 250g', 2299, 'Jedzenie'), ('Chleb', 599, 'Jedzenie')]);
    await add('Orlen', DateTime(2026, 9, 2), [('Benzyna 95', 21000, 'Transport')]);
    await add('Starbucks', DateTime(2026, 5, 3), [('Kawa latte', 1700, 'Jedzenie')]); // outside the quarter
    return db;
  }

  AiSettings api() => AiSettings.defaults(); // chat -> API by default

  test('sum for an inflected product in last quarter: exact, local, no model call', () async {
    final llm = FakeLlm((_, _) => 'NIE POWINNO SIĘ WYWOŁAĆ');
    final chat = SpendingChat(
        db: await seeded(), settings: api(), llm: llm, local: const UnavailableLocalRuntime(), now: now);
    final a = await chat.ask('Ile wydałem na kawę w zeszłym kwartale?');
    expect(a.text, contains('40,99'));
    expect(a.text, contains('od lipca do września 2026'));
    expect(a.sourceCount, 2);
    expect(a.engine, 'lokalnie');
    expect(llm.calls, isEmpty);
  });

  test('no match: the model only suggests search words, the sum is still computed locally', () async {
    final llm = FakeLlm((sys, user) => '{"terms":["benzyna","paliwo"]}');
    final chat = SpendingChat(
        db: await seeded(), settings: api(), llm: llm, local: const UnavailableLocalRuntime(), now: now);
    final a = await chat.ask('ile wydałem na tankowanie');
    expect(a.text, contains('210,00'));
    expect(a.engine, 'OpenRouter');
    expect(llm.calls.single, 'tankowanie');
  });

  test('open-ended question falls back to a model fed only monthly category sums', () async {
    final llm = FakeLlm((_, user) => 'Odpowiedź modelu');
    final chat = SpendingChat(
        db: await seeded(), settings: api(), llm: llm, local: const UnavailableLocalRuntime(), now: now);
    final a = await chat.ask('czy wydaję więcej niż rok temu');
    expect(a.text, 'Odpowiedź modelu');
    expect(llm.calls.single, contains('Transport'));
    expect(llm.calls.single, isNot(contains('Biedronka'))); // no store/item names leave the phone
  });

  test('without an API model a miss is reported honestly', () async {
    final chat = SpendingChat(
        db: await seeded(),
        settings: AiSettings.defaults().copyWith(engines: {AiTask.chat: AiEngine.local}),
        local: const UnavailableLocalRuntime(),
        now: now);
    final a = await chat.ask('ile wydałem na pizzę');
    expect(a.text, contains('Nie znalazłem'));
  });
}
