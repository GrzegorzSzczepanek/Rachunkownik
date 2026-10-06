import 'dart:async';
import 'dart:convert';

import '../core/money.dart';
import '../data/db.dart';
import '../domain/models.dart';
import '../domain/retrieval.dart';
import 'ai_settings.dart';
import 'embeddings.dart';
import 'llm_api.dart';
import 'local_runtime.dart';
import 'masking.dart';
import 'natural_expense_parser.dart';

class ChatAnswer {
  ChatAnswer(
    this.text, {
    required this.sourceCount,
    required this.engine,
    this.hits = const [],
    this.rangeLabel,
    this.createdReceipt,
  });

  final String text;
  final int sourceCount;

  /// "lokalnie" when the answer was computed on the device; a provider name
  /// when a model contributed (synonyms or an open-ended answer).
  final String engine;
  final List<Hit> hits;
  final String? rangeLabel;
  final Receipt? createdReceipt;
}

/// Answers questions about spending or automatically adds expenses described in chat.
class SpendingChat {
  SpendingChat({
    required this.db,
    required this.settings,
    this.llm,
    required this.local,
    this.embedder,
    this.now,
  });

  final AppDb db;
  final AiSettings settings;
  final LlmApi? llm;
  final LocalRuntime local;

  /// Set when the embeddings task runs on an API provider.
  final Embedder? embedder;
  final DateTime? now;

  bool get _apiChat => settings.engineFor(AiTask.chat) == AiEngine.api && llm != null;

  Future<ChatAnswer> ask(String question) async {
    final today = now ?? DateTime.now();

    // 1. If user is adding an expense (e.g. "Kupiłem w Żabce kawę za 8 zł")
    if (isExpenseInput(question)) {
      final receipt = await parseNaturalExpense(
        question,
        today,
        llm: _apiChat ? llm : null,
      );
      if (receipt.items.isNotEmpty && receipt.totalCents > 0) {
        final id = await db.saveReceipt(receipt);
        final saved = receipt.copy(id: id);

        final itemLines = saved.items
            .map((i) => '• ${i.name} – ${formatMoney(i.cents, withCurrency: true)} [${i.category}]')
            .join('\n');

        final text = 'Dodałem wydatek do bazy:\n'
            '${saved.store} – ${formatMoney(saved.totalCents)}\n\n'
            '$itemLines';

        return ChatAnswer(
          text,
          sourceCount: saved.items.length,
          engine: _apiChat ? '${settings.api.providerLabel} (czat)' : 'lokalnie (czat)',
          createdReceipt: saved,
        );
      }
    }

    // 2. Otherwise answer spending questions via retrieval pipeline
    final plan = parseQuery(question, today);
    final docs = await db.itemDocs(from: plan.range?.from, to: plan.range?.to);

    final semantic = (embedder != null && plan.terms.isNotEmpty && docs.isNotEmpty)
        ? await _semantic(docs, plan)
        : null;
    var hits = searchPlan(docs, plan, semantic: semantic);
    var usedModel = false;
    final usedEmbeddings = semantic != null && semantic.any((s) => s > 0);

    // Nothing matched: ask the model for synonyms, then try once more.
    if (hits.isEmpty && plan.terms.isNotEmpty && docs.isNotEmpty && _apiChat) {
      final extra = await _suggestTerms(plan.terms);
      if (extra.isNotEmpty) {
        hits = searchPlan(docs, plan, extraTerms: extra);
        usedModel = hits.isNotEmpty;
      }
    }

    if (hits.isEmpty && plan.terms.isNotEmpty && _apiChat) {
      // Probably not a lookup ("czy wydaję więcej niż rok temu?"): give the
      // model a compact monthly summary instead of raw items.
      final text = await _openEnded(question, today);
      if (text != null) {
        return ChatAnswer(text, sourceCount: 0, engine: settings.api.providerLabel);
      }
    }

    return ChatAnswer(
      composeAnswer(plan, hits),
      sourceCount: hits.length,
      engine: usedModel
          ? settings.api.providerLabel
          : usedEmbeddings
              ? '${settings.api.providerLabel} (embeddingi)'
              : 'lokalnie',
      hits: hits,
      rangeLabel: plan.range?.label,
    );
  }

  /// Embedding similarity per document, or null when the provider fails; the
  /// lexical search then runs alone.
  Future<List<double>?> _semantic(List<ItemDoc> docs, QueryPlan plan) async {
    try {
      final e = embedder!;
      final mask = settings.privacy.maskPersonalData;
      await EmbeddingIndexer(db, e, textOf: (d) => mask ? maskSensitive(embeddingText(d)) : embeddingText(d))
          .sync()
          .timeout(const Duration(seconds: 40));
      final q = (await e.embed([plan.terms.join(' ')]).timeout(const Duration(seconds: 15))).first;
      final raw = await db.vectorsFor(e.id, docs.map((d) => d.id));
      return semanticScores(q, docs, {for (final en in raw.entries) en.key: unpackVector(en.value)});
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _suggestTerms(List<String> terms) async {
    try {
      final res = await llm!
          .complete(
            system: 'Zwróć wyłącznie JSON {"terms":["..."]}: do 12 polskich słów, nazw produktów lub '
                'sklepów, które na paragonie mogą oznaczać to samo co podane słowo. Formy podstawowe, małe litery.',
            user: terms.join(' '),
            json: true,
            maxTokens: 150,
          )
          .timeout(const Duration(seconds: 8));
      final s = res.text.indexOf('{'), e = res.text.lastIndexOf('}');
      if (s < 0 || e <= s) return [];
      final data = jsonDecode(res.text.substring(s, e + 1));
      return [for (final t in (data['terms'] as List? ?? [])) t.toString()];
    } catch (_) {
      return [];
    }
  }

  Future<String?> _openEnded(String question, DateTime today) async {
    try {
      final from = DateTime(today.year - 1, today.month);
      final docs = await db.itemDocs(from: from);
      if (docs.isEmpty) return null;
      final byMonth = <String, Map<String, int>>{};
      for (final d in docs) {
        final key = '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}';
        final m = byMonth.putIfAbsent(key, () => {});
        m[d.category] = (m[d.category] ?? 0) + d.cents;
      }
      final keys = byMonth.keys.toList()..sort();
      var context = keys
          .map((k) => '$k: ${byMonth[k]!.entries.map((e) => '${e.key} ${formatMoney(e.value, withCurrency: false)}').join(', ')}')
          .join('\n');
      if (settings.privacy.maskPersonalData) context = maskSensitive(context);
      final res = await llm!
          .complete(
            system: 'Jesteś asystentem wydatków. Odpowiadaj po polsku, krótko, wyłącznie na podstawie '
                'podanych sum miesięcznych per kategoria (zł). Nie zgaduj; jeśli danych brakuje, powiedz to.',
            user: 'Dziś: ${today.year}-${today.month}-${today.day}.\n$context\n\nPytanie: $question',
            maxTokens: 400,
          )
          .timeout(const Duration(seconds: 30));
      return res.text.trim();
    } catch (_) {
      return null;
    }
  }
}
