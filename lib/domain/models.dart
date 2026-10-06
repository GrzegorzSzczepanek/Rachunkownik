const defaultCategories = [
  'Jedzenie',
  'Dom',
  'Transport',
  'Rozrywka',
  'Zdrowie',
  'Ubrania',
  'Inne',
];

enum ReadSource { manual, local, api, bank }

class ReceiptItem {
  ReceiptItem({
    this.id,
    required this.name,
    required this.cents,
    this.category = 'Inne',
    this.lowConfidence = false,
  });

  final int? id;
  String name;
  int cents;
  String category;
  bool lowConfidence;
}

class Receipt {
  Receipt({
    this.id,
    required this.store,
    required this.date,
    required this.totalCents,
    required this.items,
    this.source = ReadSource.manual,
    this.engineLabel,
    this.imagePath,
  });

  final int? id;
  String store;
  DateTime date;
  int totalCents;
  List<ReceiptItem> items;
  ReadSource source;
  String? engineLabel;
  String? imagePath;

  /// Deep copy, so a screen can edit without touching cached lists.
  Receipt copy({int? id}) => Receipt(
        id: id ?? this.id,
        store: store,
        date: date,
        totalCents: totalCents,
        source: source,
        engineLabel: engineLabel,
        imagePath: imagePath,
        items: [
          for (final i in items)
            ReceiptItem(id: i.id, name: i.name, cents: i.cents, category: i.category, lowConfidence: i.lowConfidence)
        ],
      );

  int get itemsSum => items.fold(0, (a, i) => a + i.cents);
  bool get sumsMatch => itemsSum == totalCents;

  /// Category with the largest share of the receipt, used as the row label.
  String get mainCategory {
    if (items.isEmpty) return 'Inne';
    final by = <String, int>{};
    for (final i in items) {
      by[i.category] = (by[i.category] ?? 0) + i.cents;
    }
    return by.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

class Budget {
  Budget({required this.category, required this.limitCents});
  final String category;
  final int limitCents;
}

enum BillingPeriod { monthly, yearly }

class Subscription {
  Subscription({
    this.id,
    required this.name,
    required this.cents,
    this.period = BillingPeriod.monthly,
    required this.nextDate,
    this.active = true,
  });

  final int? id;
  final String name;
  final int cents;
  final BillingPeriod period;
  final DateTime nextDate;
  final bool active;

  int get monthlyCents => period == BillingPeriod.monthly ? cents : (cents / 12).round();

  /// Next renewal on or after [from], rolling the stored date forward.
  DateTime nextRenewal(DateTime from) {
    var d = nextDate;
    final today = DateTime(from.year, from.month, from.day);
    while (d.isBefore(today)) {
      d = period == BillingPeriod.monthly
          ? DateTime(d.year, d.month + 1, d.day)
          : DateTime(d.year + 1, d.month, d.day);
    }
    return d;
  }
}

const defaultIncomeCategories = [
  'Wynagrodzenie',
  'Zlecenie',
  'Premia',
  'Zwrot',
  'Inwestycje',
  'Prezent',
  'Inne',
];

class Income {
  Income({
    this.id,
    required this.title,
    required this.cents,
    required this.date,
    this.category = 'Wynagrodzenie',
    this.note,
  });

  final int? id;
  String title;
  int cents;
  DateTime date;
  String category;
  String? note;

  Income copy({
    int? id,
    String? title,
    int? cents,
    DateTime? date,
    String? category,
    String? note,
  }) =>
      Income(
        id: id ?? this.id,
        title: title ?? this.title,
        cents: cents ?? this.cents,
        date: date ?? this.date,
        category: category ?? this.category,
        note: note ?? this.note,
      );
}

