# Rachunkownik (Spendnik): brief dla projektanta (Claude Design)

Android (Flutter), wersja 1.2.3. Polski interfejs (**Rachunkownik**), opcjonalnie angielski (**Spendnik**). Dane tylko na telefonie.
Zrzuty aktualnego stanu: `docs/screenshots/` (dane przykładowe).

## Cel produktu
Śledzenie wydatków **bez ręcznego przepisywania**: zrób zdjęcie paragonu albo napisz zdanie („Kawa 12 zł"), a reszta (sklep, pozycje, kategorie) dzieje się sama. Prywatność jest cechą produktu: wszystko lokalnie, AI lokalne lub przez własny klucz API.

## Tożsamość wizualna (obecnie)
- Tło `#F3F2EE`, białe karty z dużym zaokrągleniem, zieleń `#1F5F4A`; bursztyn `#C4780E` dla ostrzeżeń (budżet blisko limitu), niebieski `#2B4BC9`.
- Kwoty w czcionce monospace, nagłówki sekcji WIELKIMI LITERAMI, wygląd Material 3.
- **Dietownik** (aplikacja siostrzana) dostał nowy system: strefa „hero" z jedną dużą liczbą, Bricolage Grotesque + Figtree, listy rozdzielane linią zamiast kart, tryb ciemny, bez CAPS i monospace. Rachunkownik jest wizualnie starszy; dobrze byłoby ujednolicić.

## Nawigacja
Dolny pasek: **Przegląd · Paragony · [duży przycisk skanera w środku] · Subskrypcje · Ustawienia**. Na szerokim ekranie lewy pasek (rail) z przyciskiem „Dodaj paragon".

## Ekrany i funkcje

### Przegląd
- Miesiąc, duża kwota „wydane", przycisk „Dodaj dochód".
- Karta Dochody / Bilans; pasek budżetu miesięcznego („zostało X").
- **Pole czatu**: „Zapytaj lub wpisz: np. Kawa 12 zł". Zdanie dodaje wydatek lub dochód (z „Cofnij"), pytanie („ile wydałem na jedzenie w lipcu?") dostaje odpowiedź.
- **Budżety**: paski per kategoria (kolor ostrzegawczy od 80%), „Dodaj budżet", „Budżety kategorii", okresowe (ten tydzień, ten weekend, własny okres, cykliczne).
- Wejście do **Analizy**, lista **Ostatnie paragony** z „Wszystkie".

### Skanowanie paragonu
- Zdjęcie z aparatu lub galerii. Odczyt **lokalnym modelem na telefonie** albo **przez API** (zmiana jednym tapem, gdy lokalny jest wolny), licznik czasu.
- Ekran korekty: sklep, data, pozycje (nazwa, kwota, ilość, kategoria), suma, „podziel na osobne pozycje", wpis ręczny, zapis jako kopia.
- Pozycje o niskiej pewności oznaczone do sprawdzenia.

### Paragony i dochody
Dwie zakładki: **Wydatki (N)** i **Dochody (N)**. Edycja po dotknięciu, usuwanie z potwierdzeniem, zdjęcie paragonu zachowane.

### Subskrypcje
- Suma miesięczna i roczna, liczba aktywnych, **nadchodzące odnowienia** z liczbą dni.
- **Wykrywanie automatyczne** na podstawie powtarzających się wydatków („Wykryto automatycznie", „To nie to").
- Dodawanie ręczne (miesięczna/roczna), przypomnienia N dni przed.

### Analiza
Przełącznik miesięcy, wydane vs poprzedni miesiąc, dochody i bilans, wykres 6 miesięcy, **kategorie** (pierścień + lista z %), wykres dzień po dniu.

### Import z banku
CSV (UTF-8 i Windows-1250, PKO/ING itd.), rozpoznawanie separatora, deduplikacja transakcji, łączenie z paragonami.

### Ustawienia
- **Silniki AI per zadanie** (odczyt paragonu, kategoryzacja, embeddingi, czat): Lokalnie albo API. Dostawcy: OpenAI, Anthropic, Gemini, OpenRouter, Ollama, własny adres. Klucz w Keychain/Keystore.
- Modele lokalne (pobieranie, zgodność z urządzeniem: RAM, miejsce), maskowanie danych osobowych przed wysyłką, licznik tokenów.
- Powiadomienia: odnowienia subskrypcji (N dni przed / w dniu), alerty budżetów (80% i 100%).
- Bezpieczeństwo: blokada biometryczna. Język: system / polski / angielski.
- Dane: eksport CSV, kopia JSON i przywracanie, aktualizacje z GitHuba.

## Zasady, które warto zachować
- Dwa dotknięcia do dodania wydatku, „Cofnij" zamiast pytań „czy na pewno".
- Kwoty liczy kod, nie AI. Wartości niepewne wyraźnie oznaczone.
- Prywatność widoczna w interfejsie (co wysyłamy do API, a co zostaje lokalnie).

## Problemy widoczne na zrzutach
- **Błąd układu:** nagłówek karty „Budżety" wylewa się poza kartę (żółto-czarny pasek „RIGHT OVERFLOWED BY 20 PIXELS") gdy są dwa linki obok tytułu.
- Przegląd jest długi i gęsty: pole czatu, budżety, analiza i paragony mają podobną wagę, brak jednego „bohatera".
- Czcionka monospace dla kwot i nagłówki CAPS wyglądają inaczej niż w Dietowniku.
- Brak trybu ciemnego, brak widgetu, domyślna ikona Fluttera.
- Zakładka Subskrypcje ma duży pusty obszar poniżej listy.

## Co mamy, a czego brakuje (pomysły)
**Mamy:** OCR paragonów (lokalnie/API), czat z wydatkami, budżety (miesięczne, per kategoria, okresowe), subskrypcje, analiza, import z banku, powiadomienia, blokada biometryczna, PL/EN, kopie, aktualizacje.

**Można dodać:**
- Wspólny system projektu z Dietownikiem (hero, tryb ciemny, bez CAPS).
- **Widget** „wydano w tym miesiącu" i szybkie skanowanie z pulpitu.
- Wydatki cykliczne i **cele oszczędnościowe**, prognoza „zostanie do końca miesiąca".
- Paragony do **gwarancji** i zwrotów, tagi, wiele kont i walut, podział wydatków z osobami.
- Skan kodów QR/KSeF z faktur, import z większej liczby banków (mBank, Santander, Revolut).
- Porównanie cen produktów między sklepami z historii.
- Podsumowanie miesiąca w jednym zdaniu od AI (z liczbami liczonymi kodem).
- Wersja na iOS (kod gotowy, brak testów bez Xcode).
