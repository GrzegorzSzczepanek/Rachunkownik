# Rachunkownik (Paragon)

Mobilna aplikacja Flutter do śledzenia wydatków: paragony z OCR, ręczne wpisy, kategoryzacja,
budżety, subskrypcje, czat o wydatkach. Projekty ekranów: `design/`.

## Architektura

- `lib/domain` – modele, wykrywanie subskrypcji (czysty Dart).
- `lib/data` – SQLite (`sqflite`; na desktopie `sqflite_common_ffi`). Kwoty w groszach.
- `lib/ai` – silniki per zadanie (odczyt paragonu / kategoryzacja / embeddingi / czat),
  każde: **Lokalnie** albo **API**.
  - `llm_api.dart` – klient OpenAI-compatible (OpenAI, Gemini, OpenRouter, Ollama, własny URL)
    i Anthropic. Klucz w Keychain/Keystore.
  - `local_models.dart` – katalog modeli `.litertlm` (Hugging Face, bez tokenu) i pobieranie
    przez instalator `flutter_edge_ai`.
  - `edge_runtime.dart` – uruchamianie aktywnego modelu (`flutter_edge_ai` + LiteRT-LM).
  - `device_check.dart` – czy model pójdzie na tym telefonie (RAM, miejsce, limit iOS).
- `lib/features` – ekrany.

## Uruchomienie

`flutter_edge_ai` wymaga Fluttera 3.44+. Projekt używa własnego SDK w `.flutter-sdk/`
(Flutter 3.47.6, poza gitem):

```bash
git clone --depth 1 -b 3.47.6 https://github.com/flutter/flutter.git .flutter-sdk   # raz
.flutter-sdk/bin/flutter pub get
.flutter-sdk/bin/flutter test
.flutter-sdk/bin/flutter run     # iOS wymaga pełnego Xcode; Android: minSdk 30, arm64
```

## Wyszukiwanie i czat o wydatkach

`lib/domain/retrieval.dart` + `lib/ai/spending_chat.dart`. Pytanie jest rozbierane w kodzie
(okres: „w zeszłym kwartale”, „w lipcu”, „ostatnie 30 dni”; intencja: suma / ile razy / na co
najwięcej / lista), pozycje rankowane (odmiana, literówki, słownik synonimów), a **odpowiedź i
liczby liczy kod, nie model**. Model (API) tylko podpowiada synonimy, gdy nic nie pasuje, i
odpowiada na pytania, których nie da się sprowadzić do wyszukania (dostaje wtedy tylko sumy
miesięczne per kategoria, bez nazw sklepów i produktów).
Opcjonalnie: embeddingi przez `/embeddings` dostawcy (OpenAI, Gemini, Ollama, OpenRouter),
zapisywane lokalnie i łączone z wyszukiwaniem słownikowym. Lokalnych embeddingów brak:
wielojęzyczny model pakietu (EmbeddingGemma) wymaga tokenu Hugging Face.

## Status

Zweryfikowane: testy (53), analiza, build APK, uruchomienie na emulatorze Android, pobieranie
modelu z aplikacji, kalkulator zgodności urządzenia, start silnika lokalnego i ładowanie modelu,
import CSV (plik Windows-1250, 104 wiersze), wykresy, eksport CSV (okno udostępniania),
migracja bazy v2->v3 na istniejących danych, czat o wydatkach na zaimportowanych danych.
Niezweryfikowane: pełny odczyt paragonu lokalnym modelem (emulator za wolny), iOS (brak Xcode),
macOS (dodatkowa konfiguracja Podfile, patrz README `flutter_edge_ai`), import z PKO/ING na
prawdziwych plikach, embeddingi na prawdziwym dostawcy (testowane na lokalnym serwerze HTTP).
