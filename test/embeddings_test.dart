import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/ai_settings.dart';
import 'package:rachunkownik/ai/embeddings.dart';
import 'package:rachunkownik/ai/llm_api.dart';
import 'package:rachunkownik/ai/local_runtime.dart';
import 'package:rachunkownik/ai/spending_chat.dart';
import 'package:rachunkownik/data/db.dart';
import 'package:rachunkownik/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<AppDb> freshDb() async {
  final dir = await Directory.systemTemp.createTemp('rachunkownik_test');
  return AppDb.open(path: '${dir.path}/test.db');
}

/// Concept vectors: [sweets, drinks, fuel, other].
class FakeEmbedder implements Embedder {
  int calls = 0;
  int textsEmbedded = 0;

  @override
  String get id => 'fake:v1';

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    calls++;
    textsEmbedded += texts.length;
    return [for (final t in texts) _vec(t.toLowerCase())];
  }

  List<double> _vec(String t) {
    bool any(List<String> w) => w.any(t.contains);
    final v = [
      any(['czekolad', 'baton', 'deser', 'ciastk', 'wafel']) ? 1.0 : 0.0,
      any(['kaw', 'woda', 'sok', 'napoj']) ? 1.0 : 0.0,
      any(['benzyn', 'paliw', 'tankow']) ? 1.0 : 0.0,
      0.0,
    ];
    if (v.every((x) => x == 0)) v[3] = 1;
    return v;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final now = DateTime(2026, 10, 5);

  test('vectors survive a round trip through bytes; cosine is sane', () {
    final v = [0.5, -1.25, 3.0, 0.0];
    expect(unpackVector(packVector(v)), v);
    expect(cosine([1, 0], [1, 0]), closeTo(1, 1e-9));
    expect(cosine([1, 0], [0, 1]), 0);
    expect(cosine([0, 0], [1, 1]), 0);
  });

  group('OpenAiEmbedder over HTTP', () {
    late HttpServer server;
    late List<Map<String, Object?>> seen;

    setUp(() async {
      seen = [];
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        seen.add({'path': req.uri.path, 'auth': req.headers.value('authorization'), 'body': body});
        if (req.headers.value('authorization') != 'Bearer sk-test') {
          req.response.statusCode = 401;
          req.response.write('{"error":{"message":"bad key"}}');
        } else {
          final inputs = (body['input'] as List).cast<String>();
          // Deliberately reversed: the client must honour "index".
          final data = [
            for (var i = inputs.length - 1; i >= 0; i--)
              {'index': i, 'embedding': [inputs[i].length.toDouble(), 1.0]}
          ];
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'data': data}));
        }
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    ApiConfig cfg() => ApiConfig(
        presetId: 'custom', baseUrl: 'http://127.0.0.1:${server.port}/v1', embeddingModel: 'emb-1');

    test('sends model + inputs with the key and returns vectors in input order', () async {
      final e = OpenAiEmbedder(cfg(), 'sk-test');
      final out = await e.embed(['a', 'bbb', 'cc']);
      expect(out.map((v) => v.first), [1.0, 3.0, 2.0]);
      expect(seen.single['path'], '/v1/embeddings');
      expect((seen.single['body'] as Map)['model'], 'emb-1');
      expect(e.id, 'custom:emb-1');
    });

    test('a rejected key becomes a readable error', () async {
      final e = OpenAiEmbedder(cfg(), 'wrong');
      expect(() => e.embed(['x']), throwsA(isA<LlmException>().having((x) => x.message, 'message', contains('401'))));
    });
  });

  group('hybrid search', () {
    Future<AppDb> seeded() async {
      final db = await freshDb();
      Future<void> add(String store, String name, int cents, String cat, {int day = 1}) => db.saveReceipt(Receipt(
          store: store,
          date: DateTime(2026, 9, day),
          totalCents: cents,
          items: [ReceiptItem(name: name, cents: cents, category: cat)]));
      await add('Żabka', 'Czekolada mleczna', 449, 'Jedzenie', day: 1);
      await add('Żabka', 'Baton Snickers', 349, 'Jedzenie', day: 2);
      await add('Starbucks', 'Latte', 1800, 'Jedzenie', day: 3);
      await add('Biedronka', 'Woda niegazowana', 249, 'Jedzenie', day: 4);
      await add('Orlen', 'Benzyna 95', 21000, 'Transport', day: 5);
      await add('Biedronka', 'Chleb', 599, 'Jedzenie', day: 6);
      await add('Rossmann', 'Szampon', 1299, 'Dom', day: 7);
      await add('IKEA', 'Żarówka', 1999, 'Dom', day: 8);
      return db;
    }

    SpendingChat chat(AppDb db, Embedder? e) => SpendingChat(
        db: db,
        settings: AiSettings.defaults().copyWith(engines: {AiTask.chat: AiEngine.local, AiTask.embeddings: AiEngine.api}),
        local: const UnavailableLocalRuntime(),
        embedder: e,
        now: now);

    test('without embeddings a word with no lexical link finds nothing', () async {
      final a = await chat(await seeded(), null).ask('ile wydałem na deser');
      expect(a.text, contains('Nie znalazłem'));
    });

    test('with embeddings the same question finds sweets by meaning, sum stays exact', () async {
      final e = FakeEmbedder();
      final db = await seeded();
      final a = await chat(db, e).ask('ile wydałem na deser');
      expect(a.text, contains('7,98')); // 4,49 + 3,49
      expect(a.sourceCount, 2);
      expect(a.engine, contains('embeddingi'));
    });

    test('lines are embedded once; a second question only embeds the query', () async {
      final e = FakeEmbedder();
      final db = await seeded();
      final c = chat(db, e);
      await c.ask('ile wydałem na deser');
      final afterFirst = e.textsEmbedded; // 8 lines + 1 query
      expect(afterFirst, 9);
      await c.ask('ile wydałem na paliwo');
      expect(e.textsEmbedded, afterFirst + 1);
      expect(await db.itemsMissingVectors(e.id), isEmpty);
    });

    test('deleting a receipt removes its vectors; a failing provider falls back to words', () async {
      final e = FakeEmbedder();
      final db = await seeded();
      await chat(db, e).ask('ile wydałem na deser');
      final first = (await db.receipts()).first;
      await db.deleteReceipt(first.id!);
      final left = await db.vectorsFor(e.id, (await db.itemDocs()).map((d) => d.id));
      expect(left.length, 7);

      final broken = _Broken();
      final a = await chat(db, broken).ask('ile wydałem na benzynę');
      expect(a.text, contains('210,00')); // lexical match still works
      expect(a.engine, 'lokalnie');
    });
  });
}

class _Broken implements Embedder {
  @override
  String get id => 'broken';
  @override
  Future<List<List<double>>> embed(List<String> texts) => throw LlmException('offline');
}
