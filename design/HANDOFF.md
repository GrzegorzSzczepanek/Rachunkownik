# Rachunkownik (Spendnik), przekazanie projektu do implementacji

Pliki `*.dc.html` to makiety 390x844 (telefon). Traktuj je jako wzorzec wyglądu i zachowania, nie jako kod do przepisania 1:1. Otwórz je w przeglądarce, linki między ekranami działają. `canvas.json` ma układ płótna i tytuły ekranów.

Zasada nadrzędna: funkcje aplikacji zostają (skan paragonu lokalnie i przez API, czat wpisujący wydatki i odpowiadający na pytania, budżety, subskrypcje, analiza, dochody, eksport i kopia). Zmienia się wygląd, przepływ i teksty. Ujednolicamy z aplikacją siostrzaną Dietownik, więc jeśli jej motyw jest już w repo, użyj tych samych tokenów i wspólnych widgetów.

## Tokeny (zastąp motyw w lib/core/theme.dart)

| Rola | Wartość |
|---|---|
| tło strony | `#FFFFFF` |
| strefa hero (nagłówek) | `#E3EDE8` |
| tor paska | `#C5D9CF` |
| tor paska ostrzegawczego | `#F0DDBF` |
| tekst | `#17201C` |
| tekst drugorzędny | `#566059`, `#3A463F` |
| linia | `#E1E6E3` |
| obrys przycisku | `#CBD3CE` |
| wypełnienie pola | `#EEF2EF` |
| akcent (primary) | `#1F5F4A`, ciemny tekst na nim `#12392C` |
| ostrzeżenie (pasek) | `#B56A0A`, tekst `#8A4B06` |
| usuwanie | `#B04A35` |
| dochód (kwota) | `#12392C` |

Czcionki (dodaj do assets i pubspec): Bricolage Grotesque 700/800 do nagłówków i dużych liczb, Figtree 400 do 700 do reszty. Cyfry tabelaryczne (`FontFeature.tabularFigures()`). Usuń monospace dla kwot i wszystkie nagłówki sekcji WIELKIMI LITERAMI.

Skala: liczba hero 72 px (Bricolage 800, odstęp liter -0.02em, "zł" mniejsze, 28 px, obok), druga liczba 56 px, tytuł ekranu 30 do 32 px, nagłówek sekcji 20 do 22 px (Bricolage), treść 16 do 17 px, opis 14 px.

Kształt: strefa hero ma zaokrąglony dół (32 px), przycisk główny 56 px i promień 16, pola 52 px i promień 14, chipy 44 do 48 px, cel dotyku minimum 48 px. Listy rozdzielone linią `#E1E6E3`, bez kart w kartach, bez cieni, bez gradientów i bez kafelków z literą sklepu. Paski postępu 8 px (budżety) i 12 px (budżet miesięczny w hero).

Kwoty: spacja jako separator tysięcy, przecinek dziesiętny, " zł" po kwocie (np. `6 245,00 zł`). Dochody z plusem.

## Zasady UX

- Zapis ma kosztować 1 do 2 dotknięć. Wpisanie zdania w czacie od razu zapisuje wydatek i pokazuje "Cofnij".
- Zamiast okien potwierdzenia: akcja od razu i "Cofnij" (usunięcie paragonu też). Jeśli wolisz zostawić potwierdzenie przy usuwaniu, tylko tam.
- Szacunki i niepewne odczyty z `~` i opisem "Sprawdź". AI nie udaje pewności.
- Jeden bohater na ekran, czyli jedna duża liczba.
- Kolor ostrzegawczy (bursztyn) od 80% budżetu, razem z tekstem "zostało 21 zł", nie samym kolorem.
- Stany błędów i offline zaprojektowane, nie domyślne.

## Dolna nawigacja

Wysokość 84 px: Przegląd, Paragony, środkowy duży przycisk skanera (70 px, biała obwódka 6 px, wystaje 28 px w górę), Subskrypcje, Ustawienia. Aktywna zakładka zielona, waga 700. Na szerokim ekranie zostaje lewy pasek, a skaner jako przycisk "Dodaj paragon". Ekrany szczegółowe (skan, korekta, analiza, formularze) nie mają paska.

## Mapa ekranów

Nazwy plików w lib/ są domysłem, sprawdź w repo.

| Makieta | Ekran |
|---|---|
| Main | Przegląd: hero wydane, pasek budżetu, dochody i bilans, pole czatu, budżety |
| Przeglad-dol | Przegląd niżej: Analiza, najbliższa subskrypcja, ostatnie paragony |
| Czat-odpowiedz | czat: wpis wydatku z "Cofnij" i odpowiedź na pytanie |
| Skan | aparat albo galeria, wybór odczytu |
| Skan-odczyt | odczyt z licznikiem czasu i przełączeniem na API |
| Skan-korekta | korekta: sklep, data, pozycje, suma, "Sprawdź", podział na wpisy, wpis ręczny |
| Paragony, Dochody | dwie zakładki Wydatki (N) i Dochody (N) |
| Paragon-edycja | arkusz: edycja, zdjęcie, kopia, usuń z "Cofnij" |
| Subskrypcje, Subskrypcja-dodaj | lista z odnowieniami i formularz |
| Analiza | miesiąc z nawigacją, 6 miesięcy, kategorie jako paski |
| Budzety, Budzet-dodaj | budżety okresowe (miesiąc, tydzień, weekend, własny, cykliczne) i dodawanie |
| Ustawienia | cel miesięczny, odczyt (telefon lub internet), API, modele, język, kategorie, dane |

## Zmiany względem obecnej aplikacji

- Wykres kołowy kategorii zastąpiony posortowanymi paskami z kwotami.
- Nagłówek "Budżety" bez wciśniętych w niego linków (obecnie overflow), linki do "Wszystkie" w osobnym wierszu.
- Pasek budżetu miesięcznego i dochody/bilans przeniesione do strefy hero.
- Pole czatu na Przeglądzie jest jedyną akcją "dodaj", skaner tylko na środkowym przycisku.
- Brak danych z poprzedniego miesiąca to zwykły tekst pod liczbą, a nie osobny stan.

## Uwagi

Przykładowe dane (sklepy, kwoty, odpowiedź czatu, kategorie w Analizie) są wymyślone na podstawie zrzutów. Nie ma makiet trybu ciemnego, szerokiego ekranu, szczegółów kategorii, okna "Własny okres", ani ekranów dostawcy API i modeli lokalnych (linki w Ustawieniach są martwe). Dopracuj je według wzorca z Dietownika.

## Sugerowana kolejność

1. Tokeny i czcionki w ThemeData, motyw przycisków, pól i chipów.
2. Dolna nawigacja i wspólna strefa hero.
3. Przegląd (wersja główna, po przewinięciu, czat).
4. Skan, odczyt, korekta.
5. Paragony, Dochody, edycja.
6. Subskrypcje, Budżety, Analiza, Ustawienia.

Po każdym ekranie uruchom aplikację, porównaj z makietą i zrób osobny commit.
