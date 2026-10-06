import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/core/localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppStrings and language mappings', () {
    test('Polish strings have app name Rachunkownik', () {
      const s = AppStrings.pl();
      expect(s.isEnglish, isFalse);
      expect(s.appName, 'Rachunkownik');
      expect(s.tabOverview, 'Przegląd');
      expect(s.tabReceipts, 'Paragony');
      expect(s.tabSubscriptions, 'Subskrypcje');
      expect(s.tabSettings, 'Ustawienia');
      expect(s.addReceipt, 'Dodaj paragon');
      expect(s.spent, 'WYDANE');
      expect(s.budget, 'Budżet');
      expect(s.unlock, 'Odblokuj');
    });

    test('English strings have app name Spendnik', () {
      const s = AppStrings.en();
      expect(s.isEnglish, isTrue);
      expect(s.appName, 'Spendnik');
      expect(s.tabOverview, 'Overview');
      expect(s.tabReceipts, 'Receipts');
      expect(s.tabSubscriptions, 'Subscriptions');
      expect(s.tabSettings, 'Settings');
      expect(s.addReceipt, 'Add receipt');
      expect(s.spent, 'SPENT');
      expect(s.budget, 'Budget');
      expect(s.unlock, 'Unlock');
    });

    test('isEnglishLocale resolves properly', () {
      expect(isEnglishLocale(AppLanguage.en), isTrue);
      expect(isEnglishLocale(AppLanguage.pl), isFalse);
    });

    test('categoryName translates expense and income categories in English', () {
      const en = AppStrings.en();
      expect(en.categoryName('Jedzenie'), 'Food');
      expect(en.categoryName('Dom'), 'Home');
      expect(en.categoryName('Transport'), 'Transport');
      expect(en.categoryName('Rozrywka'), 'Entertainment');
      expect(en.categoryName('Zdrowie'), 'Health');
      expect(en.categoryName('Ubrania'), 'Clothing');
      expect(en.categoryName('Inne'), 'Other');
      expect(en.categoryName('Wynagrodzenie'), 'Salary');
      expect(en.categoryName('Zlecenie'), 'Freelance');
      expect(en.categoryName('Premia'), 'Bonus');
      expect(en.categoryName('Zwrot'), 'Refund');
      expect(en.categoryName('Inwestycje'), 'Investments');
      expect(en.categoryName('Prezent'), 'Gift');
      expect(en.categoryName('CustomCategory'), 'CustomCategory');

      const pl = AppStrings.pl();
      expect(pl.categoryName('Jedzenie'), 'Jedzenie');
      expect(pl.categoryName('Wynagrodzenie'), 'Wynagrodzenie');
    });

    test('relativeDate outputs English or Polish labels', () {
      const en = AppStrings.en();
      const pl = AppStrings.pl();
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      expect(en.relativeDate(today), 'today');
      expect(pl.relativeDate(today), 'dziś');
      expect(en.relativeDate(yesterday), 'yesterday');
      expect(pl.relativeDate(yesterday), 'wczoraj');
    });
  });

  group('AppLanguageNotifier persistence', () {
    test('defaults to Polish language when no pref is stored', () async {
      final lang = await AppLanguageNotifier.load();
      expect(lang, AppLanguage.pl);
    });

    test('persists English selection to SharedPreferences', () async {
      final notifier = AppLanguageNotifier();
      await notifier.setLanguage(AppLanguage.en);
      expect(notifier.state, AppLanguage.en);

      final loaded = await AppLanguageNotifier.load();
      expect(loaded, AppLanguage.en);
    });

    test('persists Polish selection to SharedPreferences', () async {
      final notifier = AppLanguageNotifier();
      await notifier.setLanguage(AppLanguage.pl);
      expect(notifier.state, AppLanguage.pl);

      final loaded = await AppLanguageNotifier.load();
      expect(loaded, AppLanguage.pl);
    });

    test('clears preference when switching back to system', () async {
      final notifier = AppLanguageNotifier();
      await notifier.setLanguage(AppLanguage.en);
      await notifier.setLanguage(AppLanguage.system);
      expect(notifier.state, AppLanguage.system);

      final loaded = await AppLanguageNotifier.load();
      expect(loaded, AppLanguage.system);
    });
  });
}
