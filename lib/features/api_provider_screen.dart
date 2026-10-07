import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_settings.dart';
import '../ai/embeddings.dart';
import '../ai/llm_api.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../providers.dart';
import 'widgets.dart';

final _testPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class ApiProviderScreen extends ConsumerStatefulWidget {
  const ApiProviderScreen({super.key});
  @override
  ConsumerState<ApiProviderScreen> createState() => _ApiProviderState();
}

class _ApiProviderState extends ConsumerState<ApiProviderScreen> {
  late ApiConfig cfg = ref.read(aiSettingsProvider).api;
  late final _url = TextEditingController(text: cfg.baseUrl);
  late final _model = TextEditingController(text: cfg.model);
  late final _embModel = TextEditingController(text: cfg.embeddingModel);
  final _key = TextEditingController();
  bool _hasKey = false;
  bool _testing = false;
  List<(bool, String)>? _result;

  @override
  void initState() {
    super.initState();
    ref.read(aiSettingsProvider.notifier).readKey().then((k) {
      if (mounted) setState(() => _hasKey = k != null && k.isNotEmpty);
    }).catchError((_) {}); // keystore unavailable: treat as no saved key
  }

  void _pick(ApiPreset p) => setState(() {
        cfg = cfg.copyWith(presetId: p.id, format: p.format, baseUrl: p.baseUrl);
        _url.text = p.baseUrl;
        _result = null;
      });

  Future<void> _persist() async {
    final ctrl = ref.read(aiSettingsProvider.notifier);
    cfg = cfg.copyWith(
        baseUrl: _url.text.trim(), model: _model.text.trim(), embeddingModel: _embModel.text.trim());
    await ctrl.setApi(cfg);
    if (_key.text.isNotEmpty) {
      await ctrl.writeKey(_key.text.trim());
      _key.clear();
      _hasKey = true;
    }
  }

  Future<void> _test() async {
    await _persist();
    setState(() {
      _testing = true;
      _result = null;
    });
    final key = await ref.read(aiSettingsProvider.notifier).readKey();
    final api = buildLlmApi(cfg, key);
    final out = <(bool, String)>[];
    final sw = Stopwatch()..start();
    const system = 'Odpowiadaj wyłącznie JSON-em.';
    const prompt = 'Zwróć {"ok": true}. Obraz dołączony jest tylko do testu.';
    final str = ref.read(appStringsProvider);
    try {
      LlmResult? res;
      try {
        res = await api.complete(
            system: system, user: prompt, image: Uint8List.fromList(_testPng),
            imageMime: 'image/png', json: true, maxTokens: 50);
        out.add((true, str.isEnglish
            ? 'Connected · ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s'
            : 'Połączono · ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s'));
        out.add((true, str.isEnglish ? 'Input image: supported' : 'Obraz na wejściu: obsługiwany'));
      } on LlmException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == null) rethrow;
        // Reachable but rejected the image: check text-only to tell the two apart.
        final t = await api.complete(system: system, user: prompt, json: true, maxTokens: 50);
        out.add((true, str.isEnglish
            ? 'Connected · ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s'
            : 'Połączono · ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s'));
        out.add((false, str.isEnglish
            ? 'Input image: model does not accept it (${e.message}). Choose a vision model.'
            : 'Obraz na wejściu: model go nie przyjmuje (${e.message}). Wybierz model z obsługą obrazu.'));
        res = t;
      }
      final text = res.text;
      final s = text.indexOf('{'), e = text.lastIndexOf('}');
      var jsonOk = false;
      if (s >= 0 && e > s) {
        try {
          jsonDecode(text.substring(s, e + 1));
          jsonOk = true;
        } catch (_) {}
      }
      out.add((jsonOk, str.isEnglish
          ? 'JSON output: ${jsonOk ? 'supported' : 'model did not return valid JSON'}'
          : 'Wyjście JSON: ${jsonOk ? 'obsługiwane' : 'model nie zwrócił poprawnego JSON-a'}'));
    } catch (e) {
      out.add((false, e.toString()));
    }
    if (cfg.embeddingModel.isNotEmpty && cfg.format == ApiFormat.openai) {
      try {
        final v = await OpenAiEmbedder(cfg, key).embed(['czekolada']);
        out.add((true, str.isEnglish
            ? 'Embeddings: working (dim ${v.first.length})'
            : 'Embeddingi: działają (wymiar ${v.first.length})'));
      } catch (e) {
        out.add((false, str.isEnglish ? 'Embeddings: $e' : 'Embeddingi: $e'));
      }
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _result = out;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(str.apiProvider)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Text(
            str.isEnglish
                ? 'Any OpenAI or Anthropic compatible endpoint supporting images.'
                : 'Dowolny punkt zgodny z OpenAI lub Anthropic, który przyjmuje obrazy.',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in apiPresets)
              ChoiceChip(
                label: Text(p.id == 'custom' ? (str.isEnglish ? 'Custom' : 'Własny') : p.label),
                selected: cfg.presetId == p.id,
                onSelected: (_) => _pick(p),
                selectedColor: AppColors.ink,
                labelStyle: TextStyle(
                    color: cfg.presetId == p.id ? Colors.white : AppColors.ink, fontWeight: FontWeight.w600),
                showCheckmark: false,
              ),
          ]),
          const SizedBox(height: 18),
          DropdownButtonFormField<ApiFormat>(
            initialValue: cfg.format,
            decoration: InputDecoration(labelText: str.isEnglish ? 'API Format' : 'Format API'),
            items: const [
              DropdownMenuItem(value: ApiFormat.openai, child: Text('OpenAI-compatible (/chat/completions)')),
              DropdownMenuItem(value: ApiFormat.anthropic, child: Text('Anthropic (/v1/messages)')),
            ],
            onChanged: (v) => setState(() => cfg = cfg.copyWith(format: v)),
          ),
          const SizedBox(height: 14),
          TextField(controller: _url, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Base URL')),
          const SizedBox(height: 14),
          TextField(
            controller: _key,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: str.isEnglish ? 'API Key' : 'Klucz API',
              hintText: _hasKey
                  ? (str.isEnglish ? '•••••••• (saved, enter new to change)' : '•••••••• (zapisany, wpisz nowy, aby zmienić)')
                  : cfg.preset.needsKey
                      ? (str.isEnglish ? 'paste key' : 'wklej klucz')
                      : (str.isEnglish ? 'not required' : 'niewymagany'),
              helperText: str.isEnglish
                  ? 'Key is stored in Keychain / Keystore. It is not saved in database or logs.'
                  : 'Klucz trafia do Keychain / Keystore. Nie jest zapisywany w bazie ani w logach.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 14),
          TextField(controller: _model,
              decoration: InputDecoration(
                labelText: 'Model',
                hintText: str.isEnglish ? 'vision-capable model name' : 'nazwa modelu z obsługą obrazu',
              )),
          if (cfg.format == ApiFormat.openai) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _embModel,
              decoration: InputDecoration(
                labelText: str.isEnglish ? 'Embedding model (optional)' : 'Model embeddingów (opcjonalnie)',
                hintText: 'np. text-embedding-3-small',
                helperText: str.isEnglish
                    ? 'Enables semantic search when "Search" task is set to API. Receipt item names will be sent to the provider.'
                    : 'Włącza wyszukiwanie po znaczeniu, gdy zadanie „Wyszukiwanie” jest ustawione na API. '
                      'Do dostawcy trafiają nazwy pozycji z paragonów.',
                helperMaxLines: 3,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(children: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _testing ? null : _test,
              child: _testing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(str.testConnection),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(str.isEnglish ? 'sends a tiny test image' : 'wysyła malutki obraz testowy', style: const TextStyle(color: AppColors.muted))),
          ]),
          if (_result != null) ...[
            const SizedBox(height: 14),
            SectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final r in _result!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${r.$1 ? '✓' : '✗'} ${r.$2}',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: r.$1 ? AppColors.green : AppColors.amberInk)),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () async {
              await _persist();
              if (context.mounted) Navigator.of(context).maybePop();
            },
            child: Text(str.save),
          ),
        ],
      ),
    );
  }
}
