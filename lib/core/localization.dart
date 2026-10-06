import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  pl,
  en,
  system,
}

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  AppLanguageNotifier([super.initial = AppLanguage.pl]);

  static const prefKey = 'settings.app_language';

  static Future<AppLanguage> load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(prefKey);
    if (val == 'en') return AppLanguage.en;
    if (val == 'system') return AppLanguage.system;
    return AppLanguage.pl;
  }

  Future<void> setLanguage(AppLanguage lang) async {
    state = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, lang.name);
  }
}

final initialAppLanguageProvider = Provider<AppLanguage>((ref) => AppLanguage.pl);

final appLanguageProvider =
    StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  final init = ref.watch(initialAppLanguageProvider);
  return AppLanguageNotifier(init);
});

bool isEnglishLocale(AppLanguage lang) {
  if (lang == AppLanguage.en) return true;
  if (lang == AppLanguage.system) {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return code.toLowerCase().startsWith('en');
  }
  return false;
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(appLanguageProvider);
  return isEnglishLocale(lang) ? const AppStrings.en() : const AppStrings.pl();
});

class AppStrings {
  const AppStrings({
    required this.isEnglish,
    required this.appName,
    required this.tabOverview,
    required this.tabReceipts,
    required this.tabSubscriptions,
    required this.tabSettings,
    required this.addReceipt,
    required this.spent,
    required this.budget,
    required this.chatPlaceholder,
    required this.addedFromChat,
    required this.edit,
    required this.undo,
    required this.undoSuccess,
    required this.analytics,
    required this.analyticsSub,
    required this.recentReceipts,
    required this.all,
    required this.noReceipts,
    required this.language,
    required this.languageDesc,
    required this.languageSystem,
    required this.languagePl,
    required this.languageEn,
    required this.aiModels,
    required this.aiModelsSub,
    required this.apiProvider,
    required this.localModels,
    required this.security,
    required this.biometricLock,
    required this.notifications,
    required this.exportCsv,
    required this.backupJson,
    required this.restoreJson,
    required this.updates,
    required this.updatesSub,
    required this.updatesUpToDate,
    required this.github,
    required this.searchHint,
    required this.deleteReceipt,
    required this.activeSubs,
    required this.monthly,
    required this.addSub,
    required this.unlock,
    required this.store,
    required this.date,
    required this.total,
    required this.items,
    required this.category,
    required this.save,
    required this.cancel,
  });

  const AppStrings.pl()
      : isEnglish = false,
        appName = 'Rachunkownik',
        tabOverview = 'Przegląd',
        tabReceipts = 'Paragony',
        tabSubscriptions = 'Subskrypcje',
        tabSettings = 'Ustawienia',
        addReceipt = 'Dodaj paragon',
        spent = 'WYDANE',
        budget = 'Budżet',
        chatPlaceholder = 'Zapytaj lub wpisz: np. Kawa 12 zł w Żabce',
        addedFromChat = 'Dodano nowy wydatek z czatu',
        edit = 'Edytuj',
        undo = 'Cofnij dodanie',
        undoSuccess = 'Cofnięto dodanie wydatku',
        analytics = 'Analiza i wykresy',
        analyticsSub = 'Trendy, kategorie, dzień po dniu',
        recentReceipts = 'Ostatnie paragony',
        all = 'Wszystkie',
        noReceipts = 'Brak paragonów. Dotknij przycisku skanowania, aby dodać pierwszy.',
        language = 'Język / Language',
        languageDesc = 'Wybierz język aplikacji (Spendnik po angielsku)',
        languageSystem = 'Domyślny (system)',
        languagePl = 'Polski (Rachunkownik)',
        languageEn = 'English (Spendnik)',
        aiModels = 'Model AI',
        aiModelsSub = 'Każde zadanie wykonuje inny silnik. Wybierz, co zostaje na telefonie.',
        apiProvider = 'Dostawca API',
        localModels = 'Modele lokalne i pobieranie',
        security = 'Bezpieczeństwo',
        biometricLock = 'Blokada biometryczna',
        notifications = 'Powiadomienia',
        exportCsv = 'Eksport do CSV',
        backupJson = 'Kopia zapasowa (JSON)',
        restoreJson = 'Przywróć z kopii (JSON)',
        updates = 'Aktualizacje',
        updatesSub = 'Sprawdź nowe wydania na GitHubie',
        updatesUpToDate = 'Masz najnowszą wersję aplikacji',
        github = 'Repozytorium GitHub',
        searchHint = 'Szukaj sklepu lub pozycji',
        deleteReceipt = 'Usuń paragon',
        activeSubs = 'Aktywne subskrypcje',
        monthly = 'Miesięcznie',
        addSub = 'Dodaj subskrypcję',
        unlock = 'Odblokuj',
        store = 'Sklep',
        date = 'Data',
        total = 'Suma',
        items = 'Pozycje',
        category = 'Kategoria',
        save = 'Zapisz',
        cancel = 'Anuluj';

  const AppStrings.en()
      : isEnglish = true,
        appName = 'Spendnik',
        tabOverview = 'Overview',
        tabReceipts = 'Receipts',
        tabSubscriptions = 'Subscriptions',
        tabSettings = 'Settings',
        addReceipt = 'Add receipt',
        spent = 'SPENT',
        budget = 'Budget',
        chatPlaceholder = 'Ask or type: e.g. Coffee \$4 at Starbucks',
        addedFromChat = 'Added new expense from chat',
        edit = 'Edit',
        undo = 'Undo',
        undoSuccess = 'Undid adding expense',
        analytics = 'Analytics & charts',
        analyticsSub = 'Trends, categories, day by day',
        recentReceipts = 'Recent receipts',
        all = 'View all',
        noReceipts = 'No receipts yet. Tap the scan button to add your first one.',
        language = 'Language',
        languageDesc = 'Choose interface language (Spendnik in English)',
        languageSystem = 'Default (system)',
        languagePl = 'Polski (Rachunkownik)',
        languageEn = 'English (Spendnik)',
        aiModels = 'AI Model',
        aiModelsSub = 'Each task runs on a dedicated engine. Choose what stays on device.',
        apiProvider = 'API Provider',
        localModels = 'Local models & downloads',
        security = 'Security',
        biometricLock = 'Biometric lock',
        notifications = 'Notifications',
        exportCsv = 'Export to CSV',
        backupJson = 'Backup (JSON)',
        restoreJson = 'Restore from backup (JSON)',
        updates = 'Updates',
        updatesSub = 'Check for new releases on GitHub',
        updatesUpToDate = 'You are on the latest version of the app',
        github = 'GitHub Repository',
        searchHint = 'Search store or item',
        deleteReceipt = 'Delete receipt',
        activeSubs = 'Active subscriptions',
        monthly = 'Monthly',
        addSub = 'Add subscription',
        unlock = 'Unlock',
        store = 'Store',
        date = 'Date',
        total = 'Total',
        items = 'Items',
        category = 'Category',
        save = 'Save',
        cancel = 'Cancel';

  final bool isEnglish;
  final String appName;
  final String tabOverview;
  final String tabReceipts;
  final String tabSubscriptions;
  final String tabSettings;
  final String addReceipt;
  final String spent;
  final String budget;
  final String chatPlaceholder;
  final String addedFromChat;
  final String edit;
  final String undo;
  final String undoSuccess;
  final String analytics;
  final String analyticsSub;
  final String recentReceipts;
  final String all;
  final String noReceipts;
  final String language;
  final String languageDesc;
  final String languageSystem;
  final String languagePl;
  final String languageEn;
  final String aiModels;
  final String aiModelsSub;
  final String apiProvider;
  final String localModels;
  final String security;
  final String biometricLock;
  final String notifications;
  final String exportCsv;
  final String backupJson;
  final String restoreJson;
  final String updates;
  final String updatesSub;
  final String updatesUpToDate;
  final String github;
  final String searchHint;
  final String deleteReceipt;
  final String activeSubs;
  final String monthly;
  final String addSub;
  final String unlock;
  final String store;
  final String date;
  final String total;
  final String items;
  final String category;
  final String save;
  final String cancel;
}
