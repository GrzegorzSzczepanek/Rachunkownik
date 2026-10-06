import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_settings.dart';
import 'money.dart';

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
    required this.addIncome,
    required this.income,
    required this.incomes,
    required this.balance,
    required this.incomeAdded,
    required this.incomeCategory,
    required this.noIncomes,
    required this.spent,
    required this.budget,
    required this.budgets,
    required this.monthlyBudgets,
    required this.budgetsHint,
    required this.noLimit,
    required this.remaining,
    required this.overBudget,
    required this.chatPlaceholder,
    required this.addedFromChat,
    required this.addedIncomeFromChat,
    required this.edit,
    required this.undo,
    required this.undoSuccess,
    required this.analytics,
    required this.analyticsSub,
    required this.analyticsTitle,
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
    required this.biometricLockSub,
    required this.notifications,
    required this.exportCsv,
    required this.backupJson,
    required this.restoreJson,
    required this.bankImportCsv,
    required this.selectCsvFile,
    required this.updates,
    required this.updatesSub,
    required this.updatesUpToDate,
    required this.github,
    required this.searchHint,
    required this.deleteReceipt,
    required this.activeSubs,
    required this.monthly,
    required this.yearly,
    required this.active,
    required this.addSub,
    required this.unlock,
    required this.store,
    required this.date,
    required this.total,
    required this.items,
    required this.category,
    required this.save,
    required this.cancel,
    required this.delete,
    required this.ok,
    required this.takePhoto,
    required this.chooseGallery,
    required this.enterManual,
    required this.incomeSubtitle,
    required this.expensesTab,
    required this.incomesTab,
    required this.receiptTapHint,
    required this.incomeTapHint,
    required this.deleteReceiptSub,
    required this.noReceiptsCamera,
    required this.noIncomesTitle,
    required this.noIncomesDesc,
    required this.addFirstIncome,
    required this.reviewTitle,
    required this.receiptTitle,
    required this.storeName,
    required this.storeLabel,
    required this.itemsLabel,
    required this.receiptTotal,
    required this.newItem,
    required this.editItem,
    required this.itemName,
    required this.itemPrice,
    required this.saveReceipt,
    required this.saveChanges,
    required this.addItem,
    required this.needAtLeastOneItem,
    required this.typeManually,
    required this.tryViaApi,
    required this.newIncome,
    required this.editIncome,
    required this.incomeAmount,
    required this.incomeTitle,
    required this.incomeTitleHint,
    required this.incomeTitleError,
    required this.incomeAmountError,
    required this.incomeNote,
    required this.incomeNoteHint,
    required this.saveIncome,
    required this.deleteIncome,
    required this.incomeSaved,
    required this.incomeUndone,
    required this.calculatedLocally,
    required this.showItems,
    required this.andMore,
    required this.source,
    required this.monthlyEyebrow,
    required this.detectedAutomatically,
    required this.everyMonth,
    required this.everyYear,
    required this.candidatePrompt,
    required this.notThis,
    required this.add,
    required this.upcomingRenewals,
    required this.noSubsHint,
    required this.newSub,
    required this.subName,
    required this.subAmount,
    required this.billingPeriod,
    required this.nextRenewal,
    required this.monthlyPeriod,
    required this.yearlyPeriod,
    required this.last6Months,
    required this.categories,
    required this.incomesByCategory,
    required this.dayByDay,
    required this.topMerchants,
    required this.vsPreviousMonth,
    required this.noPreviousMonthData,
    required this.noExpensesToAnalyze,
    required this.settingsSubtitle,
    required this.aiSection,
    required this.aiAllLocal,
    required this.enginesPerTask,
    required this.enginesPerTaskSub,
    required this.privacyMaskTitle,
    required this.privacyMaskSub,
    required this.privacyConsentTitle,
    required this.privacyConsentSub,
    required this.privacyRetryTitle,
    required this.privacyRetrySub,
    required this.privacyTokensTitle,
    required this.notifSubsTitle,
    required this.notifSubsSub,
    required this.notifRemind,
    required this.notifBudgetTitle,
    required this.notifBudgetSub,
    required this.localToggle,
    required this.apiToggle,
    required this.noData,
    required this.totalSummary,
    required this.testConnection,
    required this.onPaymentDay,
    required this.versionLabel,
    required this.githubError,
    required this.notifPermissionDenied,
    required this.biometricAuthFailed,
    required this.exportNoReceipts,
    required this.expensesCsvSubject,
    required this.backupSubject,
    required this.restoreDialogTitle,
    required this.restoreDialogContent,
    required this.restoreAndReplace,
  });

  const AppStrings.pl()
      : isEnglish = false,
        appName = 'Rachunkownik',
        tabOverview = 'Przegląd',
        tabReceipts = 'Paragony',
        tabSubscriptions = 'Subskrypcje',
        tabSettings = 'Ustawienia',
        addReceipt = 'Dodaj paragon',
        addIncome = 'Dodaj dochód',
        income = 'Dochód',
        incomes = 'Dochody',
        balance = 'Bilans',
        incomeAdded = 'Dodano dochód',
        incomeCategory = 'Kategoria dochodu',
        noIncomes = 'Brak zapisanych dochodów.',
        spent = 'WYDANE',
        budget = 'Budżet',
        budgets = 'Budżety',
        monthlyBudgets = 'Budżety miesięczne',
        budgetsHint = 'Ustaw limity per kategoria, a dostaniesz alert po przekroczeniu 80%.',
        noLimit = 'brak limitu',
        remaining = 'zostało',
        overBudget = 'ponad budżet',
        chatPlaceholder = 'Zapytaj lub wpisz: np. Kawa 12 zł w Żabce',
        addedFromChat = 'Dodano nowy wydatek z czatu',
        addedIncomeFromChat = 'Dodano dochód z czatu',
        edit = 'Edytuj',
        undo = 'Cofnij dodanie',
        undoSuccess = 'Cofnięto dodanie wydatku',
        analytics = 'Analiza i wykresy',
        analyticsSub = 'Trendy, kategorie, dzień po dniu',
        analyticsTitle = 'Analiza',
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
        biometricLockSub = 'Wymagaj Face ID, odcisku palca lub kodu PIN przy uruchomieniu aplikacji.',
        notifications = 'Powiadomienia',
        exportCsv = 'Eksport do CSV',
        backupJson = 'Kopia zapasowa (JSON)',
        restoreJson = 'Przywróć z kopii (JSON)',
        bankImportCsv = 'Import z banku (CSV)',
        selectCsvFile = 'Wybierz plik CSV',
        updates = 'Aktualizacje',
        updatesSub = 'Sprawdź nowe wydania na GitHubie',
        updatesUpToDate = 'Masz najnowszą wersję aplikacji',
        github = 'Repozytorium GitHub',
        searchHint = 'Szukaj sklepu lub pozycji',
        deleteReceipt = 'Usuń paragon',
        activeSubs = 'Aktywne subskrypcje',
        monthly = 'Miesięcznie',
        yearly = 'rocznie',
        active = 'aktywne',
        addSub = 'Dodaj subskrypcję',
        unlock = 'Odblokuj',
        store = 'Sklep',
        date = 'Data',
        total = 'Suma',
        items = 'Pozycje',
        category = 'Kategoria',
        save = 'Zapisz',
        cancel = 'Anuluj',
        delete = 'Usuń',
        ok = 'OK',
        takePhoto = 'Zrób zdjęcie paragonu',
        chooseGallery = 'Wybierz z galerii',
        enterManual = 'Wpisz wydatek ręcznie',
        incomeSubtitle = 'Wypłata, premia, przelew, zlecenie',
        expensesTab = 'Wydatki',
        incomesTab = 'Dochody',
        receiptTapHint = 'Dotknij paragon, aby go zobaczyć lub poprawić. Przytrzymaj, aby usunąć.',
        incomeTapHint = 'Dotknij dochód, aby edytować. Przytrzymaj, aby usunąć.',
        deleteReceiptSub = 'Zniknie też zapisane zdjęcie.',
        noReceiptsCamera = 'Brak paragonów. Dotknij przycisku aparatu, aby dodać pierwszy.',
        noIncomesTitle = 'Brak zapisanych dochodów',
        noIncomesDesc = 'Dodaj pensję, przelew, zlecenie lub premię, aby śledzić swój bilans.',
        addFirstIncome = 'Dodaj pierwszy dochód',
        reviewTitle = 'Sprawdź paragon',
        receiptTitle = 'Paragon',
        storeName = 'Nazwa sklepu',
        storeLabel = 'SKLEP',
        itemsLabel = 'POZYCJE',
        receiptTotal = 'Suma paragonu',
        newItem = 'Nowa pozycja',
        editItem = 'Edytuj pozycję',
        itemName = 'Nazwa',
        itemPrice = 'Kwota',
        saveReceipt = 'Zapisz paragon',
        saveChanges = 'Zapisz zmiany',
        addItem = 'Dodaj pozycję',
        needAtLeastOneItem = 'Dodaj co najmniej jedną pozycję z kwotą.',
        typeManually = 'Wpisz ręcznie',
        tryViaApi = 'Spróbuj przez API',
        newIncome = 'Nowy dochód',
        editIncome = 'Edytuj dochód',
        incomeAmount = 'Kwota',
        incomeTitle = 'Tytuł / Źródło',
        incomeTitleHint = 'np. Wypłata, Zlecenie, Premia',
        incomeTitleError = 'Podaj źródło lub tytuł dochodu.',
        incomeAmountError = 'Wpisz poprawną kwotę dochodu.',
        incomeNote = 'Notatka (opcjonalnie)',
        incomeNoteHint = 'np. przelew na konto główne',
        saveIncome = 'Zapisz dochód',
        deleteIncome = 'Usuń dochód',
        incomeSaved = 'Zapisano dochód',
        incomeUndone = 'Cofnięto dodanie dochodu',
        calculatedLocally = 'Obliczone na telefonie',
        showItems = 'Pokaż pozycje',
        andMore = 'więcej',
        source = 'Źródło',
        monthlyEyebrow = 'CO MIESIĄC',
        detectedAutomatically = '🔍 WYKRYTO AUTOMATYCZNIE',
        everyMonth = 'co miesiąc',
        everyYear = 'co rok',
        candidatePrompt = 'ostatnie płatności. Dodać jako subskrypcję?',
        notThis = 'To nie ono',
        add = 'Dodaj',
        upcomingRenewals = 'NADCHODZĄCE ODNOWIENIA',
        noSubsHint = 'Brak subskrypcji. Dodaj ręcznie albo poczekaj na automatyczne wykrycie (3 podobne płatności u tego samego sprzedawcy).',
        newSub = 'Nowa subskrypcja',
        subName = 'Nazwa',
        subAmount = 'Kwota',
        billingPeriod = 'Okres rozliczeniowy',
        nextRenewal = 'Następne odnowienie',
        monthlyPeriod = 'Miesięcznie',
        yearlyPeriod = 'Rocznie',
        last6Months = 'Ostatnie 6 miesięcy',
        categories = 'Kategorie',
        incomesByCategory = 'Dochody wg kategorii',
        dayByDay = 'Dzień po dniu',
        topMerchants = 'Najwięcej wydane w',
        vsPreviousMonth = 'vs poprzedni miesiąc',
        noPreviousMonthData = 'Brak danych z poprzedniego miesiąca',
        noExpensesToAnalyze = 'Brak wydatków do pokazania. Dodaj paragon albo zaimportuj dane z banku.',
        settingsSubtitle = 'Preferencje, bezpieczeństwo, kopie danych i AI',
        aiSection = 'Sztuczna inteligencja (AI)',
        aiAllLocal = 'Wszystko zostaje na telefonie. Nic nie jest wysyłane na serwery.',
        enginesPerTask = 'Silniki per zadanie',
        enginesPerTaskSub = 'Wybierz silnik dla OCR, kategoryzacji i czatu',
        privacyMaskTitle = 'Maskuj numer karty, PESEL i dane kontaktowe',
        privacyMaskSub = 'Dotyczy tekstu (OCR, kontekst czatu). Zdjęć nie zamazuje.',
        privacyConsentTitle = 'Pytaj o zgodę przed każdym wysłaniem zdjęcia',
        privacyConsentSub = 'Z nazwą dostawcy: „Zdjęcie paragonu zostanie wysłane do…”.',
        privacyRetryTitle = 'Proponuj ponowną próbę przez API przy niskiej pewności',
        privacyRetrySub = 'Tylko jako propozycja na ekranie sprawdzania paragonu.',
        privacyTokensTitle = 'Pokazuj licznik tokenów',
        notifSubsTitle = 'Przypomnienia o odnowieniu subskrypcji',
        notifSubsSub = 'Rano, przed dniem płatności.',
        notifRemind = 'Przypomnij',
        notifBudgetTitle = 'Alerty budżetowe',
        notifBudgetSub = 'Po przekroczeniu 80% i 100% budżetu kategorii.',
        localToggle = 'Lokalnie',
        apiToggle = 'API',
        noData = 'Brak danych',
        totalSummary = 'Razem',
        testConnection = 'Testuj połączenie',
        onPaymentDay = 'w dniu płatności',
        versionLabel = 'Wersja',
        githubError = 'Nie udało się połączyć z GitHubem.',
        notifPermissionDenied = 'Brak zgody na powiadomienia. Włącz je dla aplikacji w ustawieniach systemu.',
        biometricAuthFailed = 'Weryfikacja biometryczna nie powiodła się.',
        exportNoReceipts = 'Brak paragonów w wybranym zakresie.',
        expensesCsvSubject = 'Wydatki (CSV)',
        backupSubject = 'Kopia zapasowa Rachunkownik',
        restoreDialogTitle = 'Przywrócić bazę danych?',
        restoreDialogContent = 'Przywrócenie kopii zapasowej zastąpi wszystkie bieżące paragony, pozycje, budżety, subskrypcje i transakcje bankowe danymi z wybranego pliku.\n\nCzy na pewno chcesz kontynuować?',
        restoreAndReplace = 'Przywróć i zastąp';

  const AppStrings.en()
      : isEnglish = true,
        appName = 'Spendnik',
        tabOverview = 'Overview',
        tabReceipts = 'Receipts',
        tabSubscriptions = 'Subscriptions',
        tabSettings = 'Settings',
        addReceipt = 'Add receipt',
        addIncome = 'Add income',
        income = 'Income',
        incomes = 'Income',
        balance = 'Balance',
        incomeAdded = 'Income recorded',
        incomeCategory = 'Income category',
        noIncomes = 'No income recorded yet.',
        spent = 'SPENT',
        budget = 'Budget',
        budgets = 'Budgets',
        monthlyBudgets = 'Monthly budgets',
        budgetsHint = 'Set category limits to get notified after exceeding 80%.',
        noLimit = 'no limit',
        remaining = 'remaining',
        overBudget = 'over budget',
        chatPlaceholder = 'Ask or type: e.g. Coffee \$4 at Starbucks',
        addedFromChat = 'Added new expense from chat',
        addedIncomeFromChat = 'Added income from chat',
        edit = 'Edit',
        undo = 'Undo',
        undoSuccess = 'Undid adding expense',
        analytics = 'Analytics & charts',
        analyticsSub = 'Trends, categories, day by day',
        analyticsTitle = 'Analytics',
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
        biometricLockSub = 'Require Face ID, fingerprint or PIN code on app launch.',
        notifications = 'Notifications',
        exportCsv = 'Export to CSV',
        backupJson = 'Backup (JSON)',
        restoreJson = 'Restore from backup (JSON)',
        bankImportCsv = 'Bank import (CSV)',
        selectCsvFile = 'Select CSV file',
        updates = 'Updates',
        updatesSub = 'Check for new releases on GitHub',
        updatesUpToDate = 'You are on the latest version of the app',
        github = 'GitHub Repository',
        searchHint = 'Search store or item',
        deleteReceipt = 'Delete receipt',
        activeSubs = 'Active subscriptions',
        monthly = 'Monthly',
        yearly = 'yearly',
        active = 'active',
        addSub = 'Add subscription',
        unlock = 'Unlock',
        store = 'Store',
        date = 'Date',
        total = 'Total',
        items = 'Items',
        category = 'Category',
        save = 'Save',
        cancel = 'Cancel',
        delete = 'Delete',
        ok = 'OK',
        takePhoto = 'Take photo of receipt',
        chooseGallery = 'Choose from gallery',
        enterManual = 'Add expense manually',
        incomeSubtitle = 'Salary, bonus, transfer, freelance',
        expensesTab = 'Expenses',
        incomesTab = 'Income',
        receiptTapHint = 'Tap a receipt to view or edit. Long press to delete.',
        incomeTapHint = 'Tap an income to edit. Long press to delete.',
        deleteReceiptSub = 'The saved photo will also be removed.',
        noReceiptsCamera = 'No receipts yet. Tap the camera button to add your first one.',
        noIncomesTitle = 'No income recorded yet',
        noIncomesDesc = 'Add salary, transfer, freelance or bonus to track your balance.',
        addFirstIncome = 'Add first income',
        reviewTitle = 'Review receipt',
        receiptTitle = 'Receipt',
        storeName = 'Store name',
        storeLabel = 'STORE',
        itemsLabel = 'ITEMS',
        receiptTotal = 'Receipt total',
        newItem = 'New item',
        editItem = 'Edit item',
        itemName = 'Name',
        itemPrice = 'Amount',
        saveReceipt = 'Save receipt',
        saveChanges = 'Save changes',
        addItem = 'Add item',
        needAtLeastOneItem = 'Add at least one item with an amount.',
        typeManually = 'Enter manually',
        tryViaApi = 'Try via API',
        newIncome = 'New income',
        editIncome = 'Edit income',
        incomeAmount = 'Amount',
        incomeTitle = 'Title / Source',
        incomeTitleHint = 'e.g. Salary, Freelance, Bonus',
        incomeTitleError = 'Enter income source or title.',
        incomeAmountError = 'Enter a valid income amount.',
        incomeNote = 'Note (optional)',
        incomeNoteHint = 'e.g. transfer to main account',
        saveIncome = 'Save income',
        deleteIncome = 'Delete income',
        incomeSaved = 'Income saved',
        incomeUndone = 'Undid income entry',
        calculatedLocally = 'Calculated on device',
        showItems = 'Show items',
        andMore = 'more',
        source = 'Source',
        monthlyEyebrow = 'MONTHLY',
        detectedAutomatically = '🔍 DETECTED AUTOMATICALLY',
        everyMonth = 'monthly',
        everyYear = 'yearly',
        candidatePrompt = 'recent payments. Add as subscription?',
        notThis = 'Dismiss',
        add = 'Add',
        upcomingRenewals = 'UPCOMING RENEWALS',
        noSubsHint = 'No subscriptions. Add manually or wait for automatic detection (3 similar payments to the same merchant).',
        newSub = 'New subscription',
        subName = 'Name',
        subAmount = 'Amount',
        billingPeriod = 'Billing period',
        nextRenewal = 'Next renewal',
        monthlyPeriod = 'Monthly',
        yearlyPeriod = 'Yearly',
        last6Months = 'Last 6 months',
        categories = 'Categories',
        incomesByCategory = 'Income by category',
        dayByDay = 'Day by day',
        topMerchants = 'Top merchants',
        vsPreviousMonth = 'vs previous month',
        noPreviousMonthData = 'No data from previous month',
        noExpensesToAnalyze = 'No expenses to display. Add a receipt or import bank data.',
        settingsSubtitle = 'Preferences, security, backups and AI',
        aiSection = 'Artificial Intelligence (AI)',
        aiAllLocal = 'Everything stays on device. Nothing is sent to external servers.',
        enginesPerTask = 'Engines per task',
        enginesPerTaskSub = 'Choose engine for OCR, categorization and chat',
        privacyMaskTitle = 'Mask card number, national ID and contact details',
        privacyMaskSub = 'Applies to text (OCR, chat context). Does not blur photos.',
        privacyConsentTitle = 'Ask for consent before sending photos',
        privacyConsentSub = 'With provider name: "Receipt photo will be sent to...".',
        privacyRetryTitle = 'Suggest API retry on low confidence',
        privacyRetrySub = 'Only as a suggestion on the receipt review screen.',
        privacyTokensTitle = 'Show token counter',
        notifSubsTitle = 'Subscription renewal reminders',
        notifSubsSub = 'Morning, before payment day.',
        notifRemind = 'Remind',
        notifBudgetTitle = 'Budget alerts',
        notifBudgetSub = 'When exceeding 80% and 100% of category budget.',
        localToggle = 'Local',
        apiToggle = 'API',
        noData = 'No data',
        totalSummary = 'Total',
        testConnection = 'Test connection',
        onPaymentDay = 'on payment day',
        versionLabel = 'Version',
        githubError = 'Could not connect to GitHub.',
        notifPermissionDenied = 'Notifications permission denied. Enable them in system settings.',
        biometricAuthFailed = 'Biometric authentication failed.',
        exportNoReceipts = 'No receipts in selected range.',
        expensesCsvSubject = 'Expenses (CSV)',
        backupSubject = 'Spendnik Backup',
        restoreDialogTitle = 'Restore database?',
        restoreDialogContent = 'Restoring backup will replace all current receipts, items, budgets, subscriptions and bank transactions with data from the selected file.\n\nAre you sure you want to continue?',
        restoreAndReplace = 'Restore and replace';

  final bool isEnglish;
  final String appName;
  final String tabOverview;
  final String tabReceipts;
  final String tabSubscriptions;
  final String tabSettings;
  final String addReceipt;
  final String addIncome;
  final String income;
  final String incomes;
  final String balance;
  final String incomeAdded;
  final String incomeCategory;
  final String noIncomes;
  final String spent;
  final String budget;
  final String budgets;
  final String monthlyBudgets;
  final String budgetsHint;
  final String noLimit;
  final String remaining;
  final String overBudget;
  final String chatPlaceholder;
  final String addedFromChat;
  final String addedIncomeFromChat;
  final String edit;
  final String undo;
  final String undoSuccess;
  final String analytics;
  final String analyticsSub;
  final String analyticsTitle;
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
  final String biometricLockSub;
  final String notifications;
  final String exportCsv;
  final String backupJson;
  final String restoreJson;
  final String bankImportCsv;
  final String selectCsvFile;
  final String updates;
  final String updatesSub;
  final String updatesUpToDate;
  final String github;
  final String searchHint;
  final String deleteReceipt;
  final String activeSubs;
  final String monthly;
  final String yearly;
  final String active;
  final String addSub;
  final String unlock;
  final String store;
  final String date;
  final String total;
  final String items;
  final String category;
  final String save;
  final String cancel;
  final String delete;
  final String ok;
  final String takePhoto;
  final String chooseGallery;
  final String enterManual;
  final String incomeSubtitle;
  final String expensesTab;
  final String incomesTab;
  final String receiptTapHint;
  final String incomeTapHint;
  final String deleteReceiptSub;
  final String noReceiptsCamera;
  final String noIncomesTitle;
  final String noIncomesDesc;
  final String addFirstIncome;
  final String reviewTitle;
  final String receiptTitle;
  final String storeName;
  final String storeLabel;
  final String itemsLabel;
  final String receiptTotal;
  final String newItem;
  final String editItem;
  final String itemName;
  final String itemPrice;
  final String saveReceipt;
  final String saveChanges;
  final String addItem;
  final String needAtLeastOneItem;
  final String typeManually;
  final String tryViaApi;
  final String newIncome;
  final String editIncome;
  final String incomeAmount;
  final String incomeTitle;
  final String incomeTitleHint;
  final String incomeTitleError;
  final String incomeAmountError;
  final String incomeNote;
  final String incomeNoteHint;
  final String saveIncome;
  final String deleteIncome;
  final String incomeSaved;
  final String incomeUndone;
  final String calculatedLocally;
  final String showItems;
  final String andMore;
  final String source;
  final String monthlyEyebrow;
  final String detectedAutomatically;
  final String everyMonth;
  final String everyYear;
  final String candidatePrompt;
  final String notThis;
  final String add;
  final String upcomingRenewals;
  final String noSubsHint;
  final String newSub;
  final String subName;
  final String subAmount;
  final String billingPeriod;
  final String nextRenewal;
  final String monthlyPeriod;
  final String yearlyPeriod;
  final String last6Months;
  final String categories;
  final String incomesByCategory;
  final String dayByDay;
  final String topMerchants;
  final String vsPreviousMonth;
  final String noPreviousMonthData;
  final String noExpensesToAnalyze;
  final String settingsSubtitle;
  final String aiSection;
  final String aiAllLocal;
  final String enginesPerTask;
  final String enginesPerTaskSub;
  final String privacyMaskTitle;
  final String privacyMaskSub;
  final String privacyConsentTitle;
  final String privacyConsentSub;
  final String privacyRetryTitle;
  final String privacyRetrySub;
  final String privacyTokensTitle;
  final String notifSubsTitle;
  final String notifSubsSub;
  final String notifRemind;
  final String notifBudgetTitle;
  final String notifBudgetSub;
  final String localToggle;
  final String apiToggle;
  final String noData;
  final String totalSummary;
  final String testConnection;
  final String onPaymentDay;
  final String versionLabel;
  final String githubError;
  final String notifPermissionDenied;
  final String biometricAuthFailed;
  final String exportNoReceipts;
  final String expensesCsvSubject;
  final String backupSubject;
  final String restoreDialogTitle;
  final String restoreDialogContent;
  final String restoreAndReplace;

  String aiTaskLabel(AiTask t) {
    if (!isEnglish) return t.label;
    return switch (t) {
      AiTask.receiptReading => 'Receipt reading',
      AiTask.categorization => 'Categorization',
      AiTask.embeddings => 'Search (embeddings)',
      AiTask.chat => 'Expense chat',
    };
  }

  String localDetail(AiTask t) {
    if (!isEnglish) {
      return switch (t) {
        AiTask.receiptReading => 'Model z obsługą obrazu (pobierz w Modelach lokalnych)',
        AiTask.categorization => 'Reguły słownikowe + opcjonalnie model tekstowy',
        AiTask.embeddings => 'Wyszukiwanie w kodzie: odmiana, literówki, synonimy (bez modelu)',
        AiTask.chat => 'Wymaga dużego modelu. Zwykle lepiej API',
      };
    }
    return switch (t) {
      AiTask.receiptReading => 'Vision model (download in Local models)',
      AiTask.categorization => 'Dictionary rules + optional text model',
      AiTask.embeddings => 'In-code search: inflection, typos, synonyms (no model)',
      AiTask.chat => 'Requires a large model. API is usually better',
    };
  }

  String daysBefore(int d) {
    if (isEnglish) return '$d ${d == 1 ? "day" : "days"} before';
    return '$d ${d == 1 ? "dzień" : "dni"} wcześniej';
  }

  String updateError(Object e) =>
      isEnglish ? 'Update check error: $e' : 'Błąd sprawdzania aktualizacji: $e';

  String exportFailed(Object e) =>
      isEnglish ? 'Export failed: $e' : 'Nie udało się wyeksportować: $e';

  String backupFailed(Object e) =>
      isEnglish ? 'Failed to create backup: $e' : 'Nie udało się utworzyć kopii zapasowej: $e';

  String restoreSuccess(String summary) =>
      isEnglish ? 'Successfully restored database:\n$summary' : 'Pomyślnie przywrócono bazę danych:\n$summary';

  String restoreFailed(Object e) =>
      isEnglish ? 'Failed to restore backup: $e' : 'Nie udało się przywrócić kopii: $e';

  /// Translates stored category names to display labels in the active language.
  String categoryName(String cat) {
    if (!isEnglish) return cat;
    return switch (cat) {
      'Jedzenie' => 'Food',
      'Dom' => 'Home',
      'Transport' => 'Transport',
      'Rozrywka' => 'Entertainment',
      'Zdrowie' => 'Health',
      'Ubrania' => 'Clothing',
      'Inne' => 'Other',
      'Wynagrodzenie' => 'Salary',
      'Zlecenie' => 'Freelance',
      'Premia' => 'Bonus',
      'Zwrot' => 'Refund',
      'Inwestycje' => 'Investments',
      'Prezent' => 'Gift',
      _ => cat,
    };
  }

  /// Relative date string: "today", "yesterday", or short formatted date.
  String relativeDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days == 0) return isEnglish ? 'today' : 'dziś';
    if (days == 1) return isEnglish ? 'yesterday' : 'wczoraj';
    return shortDate(d, isEnglish: isEnglish);
  }

  String itemsCount(int n) {
    if (isEnglish) return '$n ${n == 1 ? 'item' : 'items'}';
    return '$n ${plPlural(n, 'pozycja', 'pozycje', 'pozycji')}';
  }

  String inDays(int d) {
    if (isEnglish) return d == 0 ? 'today' : 'in $d days';
    return d == 0 ? 'dziś' : 'za $d dni';
  }

  String deleteReceiptConfirm(String store) =>
      isEnglish ? 'Delete receipt $store?' : 'Usunąć paragon $store?';

  String deleteIncomeConfirm(String title) =>
      isEnglish ? 'Delete income $title?' : 'Usunąć dochód $title?';
}

/// Polish pluralization helper.
String plPlural(int n, String one, String few, String many) {
  if (n == 1) return one;
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
  return many;
}
