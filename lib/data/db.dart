import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:typed_data';

import '../domain/bank_import.dart';
import '../domain/models.dart';
import '../domain/retrieval.dart';

class AppDb {
  AppDb(this._db);
  final Database _db;

  static Future<AppDb> open({String? path}) async {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final file = path ?? p.join((await getApplicationSupportDirectory()).path, 'rachunkownik.db');
    final db = await openDatabase(file, version: 5, onCreate: _create, onUpgrade: _upgrade);
    return AppDb(db);
  }

  static Future<void> _create(Database db, int v) async {
    await db.execute('''CREATE TABLE receipts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      store TEXT NOT NULL, date INTEGER NOT NULL, total INTEGER NOT NULL,
      source TEXT NOT NULL, engine TEXT, image_path TEXT)''');
    await db.execute('''CREATE TABLE items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      receipt_id INTEGER NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
      name TEXT NOT NULL, cents INTEGER NOT NULL, category TEXT NOT NULL,
      low_confidence INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE budgets(
      category TEXT PRIMARY KEY, limit_cents INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE subscriptions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, cents INTEGER NOT NULL, period TEXT NOT NULL,
      next_date INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 1)''');
    await db.execute('''CREATE TABLE dismissed_subs(name TEXT PRIMARY KEY)''');
    await db.execute('CREATE INDEX idx_receipts_date ON receipts(date)');
    await db.execute('CREATE INDEX idx_items_receipt ON items(receipt_id)');
    await _createBankTable(db);
    await _createVectorTable(db);
    await _createIncomeTable(db);
    await _createPeriodicBudgetsTable(db);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _createBankTable(db);
    if (from < 3) await _createVectorTable(db);
    if (from < 4) await _createIncomeTable(db);
    if (from < 5) await _createPeriodicBudgetsTable(db);
  }

  static Future<void> _createPeriodicBudgetsTable(Database db) async {
    await db.execute('''CREATE TABLE periodic_budgets(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, category TEXT, limit_cents INTEGER NOT NULL,
      period TEXT NOT NULL, start_date INTEGER NOT NULL, end_date INTEGER NOT NULL,
      is_recurring INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('CREATE INDEX idx_periodic_budgets_dates ON periodic_budgets(start_date, end_date)');
  }

  static Future<void> _createIncomeTable(Database db) async {
    await db.execute('''CREATE TABLE incomes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL, cents INTEGER NOT NULL, category TEXT NOT NULL,
      date INTEGER NOT NULL, note TEXT)''');
    await db.execute('CREATE INDEX idx_incomes_date ON incomes(date)');
  }

  static Future<void> _createVectorTable(Database db) => db.execute('''CREATE TABLE item_vectors(
      item_id INTEGER NOT NULL, model TEXT NOT NULL, vec BLOB NOT NULL,
      PRIMARY KEY (item_id, model))''');

  static Future<void> _createBankTable(Database db) => db.execute('''CREATE TABLE bank_transactions(
      hash TEXT PRIMARY KEY, date INTEGER NOT NULL, description TEXT NOT NULL,
      cents INTEGER NOT NULL, receipt_id INTEGER)''');

  // ---- receipts ----

  Future<int> saveReceipt(Receipt r) async {
    return _db.transaction((tx) async {
      final id = await tx.insert('receipts', {
        'store': r.store,
        'date': r.date.millisecondsSinceEpoch,
        'total': r.totalCents,
        'source': r.source.name,
        'engine': r.engineLabel,
        'image_path': r.imagePath,
      });
      for (final i in r.items) {
        await tx.insert('items', {
          'receipt_id': id,
          'name': i.name,
          'cents': i.cents,
          'category': i.category,
          'low_confidence': i.lowConfidence ? 1 : 0,
        });
      }
      return id;
    });
  }

  /// Rewrites a saved receipt and its lines; stale embedding vectors go with the old lines.
  Future<void> updateReceipt(Receipt r) async {
    final id = r.id;
    if (id == null) throw ArgumentError('Receipt has no id');
    await _db.transaction((tx) async {
      await tx.update(
          'receipts',
          {
            'store': r.store,
            'date': r.date.millisecondsSinceEpoch,
            'total': r.totalCents,
            'source': r.source.name,
            'engine': r.engineLabel,
            'image_path': r.imagePath,
          },
          where: 'id = ?',
          whereArgs: [id]);
      await tx.rawDelete(
          'DELETE FROM item_vectors WHERE item_id IN (SELECT id FROM items WHERE receipt_id = ?)', [id]);
      await tx.delete('items', where: 'receipt_id = ?', whereArgs: [id]);
      for (final i in r.items) {
        await tx.insert('items', {
          'receipt_id': id,
          'name': i.name,
          'cents': i.cents,
          'category': i.category,
          'low_confidence': i.lowConfidence ? 1 : 0,
        });
      }
    });
  }

  Future<void> deleteReceipt(int id) async {
    await _db.rawDelete(
        'DELETE FROM item_vectors WHERE item_id IN (SELECT id FROM items WHERE receipt_id = ?)', [id]);
    await _db.delete('items', where: 'receipt_id = ?', whereArgs: [id]);
    await _db.delete('receipts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Receipt>> receipts({DateTime? from, DateTime? to, int? limit}) async {
    final where = <String>[];
    final args = <Object>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('date < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final rows = await _db.query('receipts',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'date DESC, id DESC',
        limit: limit);
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final itemRows = await _db.query('items',
        where: 'receipt_id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
    final byReceipt = <int, List<ReceiptItem>>{};
    for (final r in itemRows) {
      byReceipt.putIfAbsent(r['receipt_id'] as int, () => []).add(ReceiptItem(
            id: r['id'] as int,
            name: r['name'] as String,
            cents: r['cents'] as int,
            category: r['category'] as String,
            lowConfidence: (r['low_confidence'] as int) == 1,
          ));
    }
    return rows
        .map((r) => Receipt(
              id: r['id'] as int,
              store: r['store'] as String,
              date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
              totalCents: r['total'] as int,
              source: ReadSource.values.byName(r['source'] as String),
              engineLabel: r['engine'] as String?,
              imagePath: r['image_path'] as String?,
              items: byReceipt[r['id'] as int] ?? [],
            ))
        .toList();
  }

  /// Per-category spend within [from, to).
  Future<Map<String, int>> spendByCategory(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery('''
      SELECT i.category AS c, SUM(i.cents) AS s FROM items i
      JOIN receipts r ON r.id = i.receipt_id
      WHERE r.date >= ? AND r.date < ? GROUP BY i.category''',
        [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    return {for (final r in rows) r['c'] as String: (r['s'] as int?) ?? 0};
  }

  Future<int> totalSpend(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
        'SELECT SUM(total) AS s FROM receipts WHERE date >= ? AND date < ?',
        [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    return (rows.first['s'] as int?) ?? 0;
  }

  /// Keyword search over item names and stores (the non-AI fallback for search).
  Future<List<Map<String, Object?>>> searchItems(String term, {DateTime? from, DateTime? to}) {
    final like = '%${term.toLowerCase()}%';
    return _db.rawQuery('''
      SELECT i.name, i.cents, i.category, r.store, r.date FROM items i
      JOIN receipts r ON r.id = i.receipt_id
      WHERE (LOWER(i.name) LIKE ? OR LOWER(r.store) LIKE ?)
        AND r.date >= ? AND r.date < ? ORDER BY r.date DESC''', [
      like,
      like,
      (from ?? DateTime(2000)).millisecondsSinceEpoch,
      (to ?? DateTime(2100)).millisecondsSinceEpoch,
    ]);
  }

  // ---- bank import ----

  Future<Set<String>> knownBankHashes() async =>
      (await _db.query('bank_transactions', columns: ['hash'])).map((r) => r['hash'] as String).toSet();

  /// Receipts already linked to a bank transaction (can't be matched twice).
  Future<Set<int>> claimedReceiptIds() async => (await _db.query('bank_transactions',
          columns: ['receipt_id'], where: 'receipt_id IS NOT NULL'))
      .map((r) => r['receipt_id'] as int)
      .toSet();

  /// Applies an [ImportPlan] atomically: new expenses first, then every
  /// transaction (matched, new or ignored) is recorded so re-imports skip it.
  Future<void> saveImport(ImportPlan plan) async {
    await _db.transaction((tx) async {
      for (final t in plan.txns) {
        var receiptId = t.matchedReceiptId;
        final r = t.newReceipt;
        if (r != null) {
          receiptId = await tx.insert('receipts', {
            'store': r.store,
            'date': r.date.millisecondsSinceEpoch,
            'total': r.totalCents,
            'source': r.source.name,
            'engine': r.engineLabel,
            'image_path': null,
          });
          for (final i in r.items) {
            await tx.insert('items', {
              'receipt_id': receiptId,
              'name': i.name,
              'cents': i.cents,
              'category': i.category,
              'low_confidence': 0,
            });
          }
        }
        await tx.insert(
            'bank_transactions',
            {
              'hash': t.hash,
              'date': t.row.date.millisecondsSinceEpoch,
              'description': t.row.description,
              'cents': t.row.cents,
              'receipt_id': receiptId,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  // ---- search ----

  /// Every receipt line in [from, to) with its receipt's store and date,
  /// ready for ranking (see retrieval.dart).
  Future<List<ItemDoc>> itemDocs({DateTime? from, DateTime? to}) async {
    final rows = await _db.rawQuery('''
      SELECT i.id AS id, i.receipt_id AS rid, i.name AS name, i.cents AS cents,
             i.category AS category, r.store AS store, r.date AS date
      FROM items i JOIN receipts r ON r.id = i.receipt_id
      WHERE r.date >= ? AND r.date < ? ORDER BY r.date DESC, i.id''', [
      (from ?? DateTime(2000)).millisecondsSinceEpoch,
      (to ?? DateTime(2100)).millisecondsSinceEpoch,
    ]);
    return [
      for (final r in rows)
        ItemDoc(
          id: r['id'] as int,
          receiptId: r['rid'] as int,
          name: r['name'] as String,
          store: r['store'] as String,
          category: r['category'] as String,
          date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
          cents: r['cents'] as int,
        )
    ];
  }

  // ---- embeddings ----

  /// Receipt lines that have no vector for [model] yet (newest first).
  Future<List<ItemDoc>> itemsMissingVectors(String model, {int limit = 400}) async {
    final rows = await _db.rawQuery('''
      SELECT i.id AS id, i.receipt_id AS rid, i.name AS name, i.cents AS cents,
             i.category AS category, r.store AS store, r.date AS date
      FROM items i JOIN receipts r ON r.id = i.receipt_id
      WHERE NOT EXISTS (SELECT 1 FROM item_vectors v WHERE v.item_id = i.id AND v.model = ?)
      ORDER BY r.date DESC LIMIT ?''', [model, limit]);
    return [
      for (final r in rows)
        ItemDoc(
          id: r['id'] as int,
          receiptId: r['rid'] as int,
          name: r['name'] as String,
          store: r['store'] as String,
          category: r['category'] as String,
          date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
          cents: r['cents'] as int,
        )
    ];
  }

  Future<void> saveVectors(String model, Map<int, Uint8List> vectors) async {
    final batch = _db.batch();
    vectors.forEach((id, bytes) => batch.insert('item_vectors', {'item_id': id, 'model': model, 'vec': bytes},
        conflictAlgorithm: ConflictAlgorithm.replace));
    await batch.commit(noResult: true);
  }

  Future<Map<int, Uint8List>> vectorsFor(String model, Iterable<int> ids) async {
    final out = <int, Uint8List>{};
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
      final rows = await _db.rawQuery(
          'SELECT item_id, vec FROM item_vectors WHERE model = ? AND item_id IN (${List.filled(chunk.length, '?').join(',')})',
          [model, ...chunk]);
      for (final r in rows) {
        out[r['item_id'] as int] = r['vec'] as Uint8List;
      }
    }
    return out;
  }

  // ---- analytics ----

  /// Total spend per calendar month for [count] months ending with [last]'s month.
  Future<List<MapEntry<DateTime, int>>> monthlyTotals(DateTime last, {int count = 6}) async {
    final out = <MapEntry<DateTime, int>>[];
    for (var i = count - 1; i >= 0; i--) {
      final m = DateTime(last.year, last.month - i);
      out.add(MapEntry(m, await totalSpend(m, DateTime(m.year, m.month + 1))));
    }
    return out;
  }

  /// Spend per day within [from, to), keyed by day of month.
  Future<Map<int, int>> dailyTotals(DateTime from, DateTime to) async {
    final rows = await _db.query('receipts',
        columns: ['date', 'total'],
        where: 'date >= ? AND date < ?',
        whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    final out = <int, int>{};
    for (final r in rows) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['date'] as int);
      out[d.day] = (out[d.day] ?? 0) + (r['total'] as int);
    }
    return out;
  }

  /// Top stores by spend within [from, to).
  Future<List<MapEntry<String, int>>> topStores(DateTime from, DateTime to, {int limit = 5}) async {
    final rows = await _db.rawQuery('''
      SELECT store, SUM(total) AS s FROM receipts
      WHERE date >= ? AND date < ? GROUP BY store ORDER BY s DESC LIMIT ?''',
        [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch, limit]);
    return [for (final r in rows) MapEntry(r['store'] as String, (r['s'] as int?) ?? 0)];
  }

  // ---- budgets ----

  Future<List<Budget>> budgets() async => (await _db.query('budgets'))
      .map((r) => Budget(category: r['category'] as String, limitCents: r['limit_cents'] as int))
      .toList();

  Future<void> setBudget(String category, int? limitCents) async {
    if (limitCents == null || limitCents <= 0) {
      await _db.delete('budgets', where: 'category = ?', whereArgs: [category]);
    } else {
      await _db.insert('budgets', {'category': category, 'limit_cents': limitCents},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ---- periodic budgets ----

  Future<List<PeriodicBudget>> periodicBudgets() async {
    final rows = await _db.query('periodic_budgets', orderBy: 'start_date DESC');
    final now = DateTime.now();
    final list = <PeriodicBudget>[];
    for (final r in rows) {
      final period = BudgetPeriod.values.byName((r['period'] as String?) ?? 'custom');
      final isRecurring = (r['is_recurring'] as int? ?? 0) == 1;
      var start = DateTime.fromMillisecondsSinceEpoch(r['start_date'] as int);
      var end = DateTime.fromMillisecondsSinceEpoch(r['end_date'] as int);

      if (isRecurring && period == BudgetPeriod.weekly) {
        final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        start = monday;
        end = DateTime(monday.year, monday.month, monday.day).add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      }

      final cat = r['category'] as String?;
      final startEpoch = DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
      final endExclusive = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
      final endEpoch = endExclusive.millisecondsSinceEpoch;

      int spent;
      if (cat == null || cat.isEmpty || cat == 'Wszystkie' || cat == 'All') {
        final res = await _db.rawQuery(
          'SELECT SUM(total) AS s FROM receipts WHERE date >= ? AND date < ?',
          [startEpoch, endEpoch],
        );
        spent = (res.first['s'] as int?) ?? 0;
      } else {
        final res = await _db.rawQuery('''
          SELECT SUM(i.cents) AS s FROM items i
          JOIN receipts r ON r.id = i.receipt_id
          WHERE r.date >= ? AND date < ? AND i.category = ?''',
          [startEpoch, endEpoch, cat],
        );
        spent = (res.first['s'] as int?) ?? 0;
      }

      list.add(PeriodicBudget(
        id: r['id'] as int?,
        name: r['name'] as String,
        category: (cat == null || cat.isEmpty || cat == 'Wszystkie' || cat == 'All') ? null : cat,
        limitCents: r['limit_cents'] as int,
        period: period,
        startDate: start,
        endDate: end,
        isRecurring: isRecurring,
        spentCents: spent,
      ));
    }
    return list;
  }

  Future<int> savePeriodicBudget(PeriodicBudget pb) => _db.insert('periodic_budgets', {
        'name': pb.name,
        'category': pb.category,
        'limit_cents': pb.limitCents,
        'period': pb.period.name,
        'start_date': pb.startDate.millisecondsSinceEpoch,
        'end_date': pb.endDate.millisecondsSinceEpoch,
        'is_recurring': pb.isRecurring ? 1 : 0,
      });

  Future<void> updatePeriodicBudget(PeriodicBudget pb) {
    final id = pb.id;
    if (id == null) throw ArgumentError('PeriodicBudget has no id');
    return _db.update(
      'periodic_budgets',
      {
        'name': pb.name,
        'category': pb.category,
        'limit_cents': pb.limitCents,
        'period': pb.period.name,
        'start_date': pb.startDate.millisecondsSinceEpoch,
        'end_date': pb.endDate.millisecondsSinceEpoch,
        'is_recurring': pb.isRecurring ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePeriodicBudget(int id) =>
      _db.delete('periodic_budgets', where: 'id = ?', whereArgs: [id]);

  // ---- subscriptions ----

  Future<List<Subscription>> subscriptions() async =>
      (await _db.query('subscriptions', orderBy: 'next_date')).map((r) => Subscription(
            id: r['id'] as int,
            name: r['name'] as String,
            cents: r['cents'] as int,
            period: BillingPeriod.values.byName(r['period'] as String),
            nextDate: DateTime.fromMillisecondsSinceEpoch(r['next_date'] as int),
            active: (r['active'] as int) == 1,
          )).toList();

  Future<void> addSubscription(Subscription s) => _db.insert('subscriptions', {
        'name': s.name,
        'cents': s.cents,
        'period': s.period.name,
        'next_date': s.nextDate.millisecondsSinceEpoch,
        'active': s.active ? 1 : 0,
      });

  Future<void> deleteSubscription(int id) =>
      _db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);

  Future<Set<String>> dismissedSubs() async =>
      (await _db.query('dismissed_subs')).map((r) => r['name'] as String).toSet();

  Future<void> dismissSub(String name) => _db.insert('dismissed_subs', {'name': name},
      conflictAlgorithm: ConflictAlgorithm.ignore);

  // ---- incomes ----

  Future<int> saveIncome(Income inc) async {
    return _db.insert('incomes', {
      'title': inc.title,
      'cents': inc.cents,
      'category': inc.category,
      'date': inc.date.millisecondsSinceEpoch,
      'note': inc.note,
    });
  }

  Future<void> updateIncome(Income inc) async {
    final id = inc.id;
    if (id == null) throw ArgumentError('Income has no id');
    await _db.update(
      'incomes',
      {
        'title': inc.title,
        'cents': inc.cents,
        'category': inc.category,
        'date': inc.date.millisecondsSinceEpoch,
        'note': inc.note,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteIncome(int id) async {
    await _db.delete('incomes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Income>> incomes({DateTime? from, DateTime? to, int? limit}) async {
    final where = <String>[];
    final args = <Object>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('date < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final rows = await _db.query(
      'incomes',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows
        .map((r) => Income(
              id: r['id'] as int,
              title: r['title'] as String,
              cents: r['cents'] as int,
              category: r['category'] as String,
              date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
              note: r['note'] as String?,
            ))
        .toList();
  }

  Future<int> totalIncome(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
      'SELECT SUM(cents) AS s FROM incomes WHERE date >= ? AND date < ?',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    return (rows.first['s'] as int?) ?? 0;
  }

  Future<Map<String, int>> incomeByCategory(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery('''
      SELECT category AS c, SUM(cents) AS s FROM incomes
      WHERE date >= ? AND date < ? GROUP BY category''',
        [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    return {for (final r in rows) r['c'] as String: (r['s'] as int?) ?? 0};
  }

  // ---- backup & restore ----

  Future<Map<String, dynamic>> exportBackup() async {
    final receiptsRows = await _db.query('receipts', orderBy: 'id ASC');
    final itemsRows = await _db.query('items', orderBy: 'id ASC');
    final budgetsRows = await _db.query('budgets');
    final subscriptionsRows = await _db.query('subscriptions', orderBy: 'id ASC');
    final dismissedRows = await _db.query('dismissed_subs');
    final bankRows = await _db.query('bank_transactions', orderBy: 'date ASC');
    final incomeRows = await _db.query('incomes', orderBy: 'id ASC');
    final periodicBudgetsRows = await _db.query('periodic_budgets', orderBy: 'id ASC');

    final itemsByReceipt = <int, List<Map<String, dynamic>>>{};
    for (final i in itemsRows) {
      final rid = i['receipt_id'] as int;
      itemsByReceipt.putIfAbsent(rid, () => []).add({
        'name': i['name'],
        'cents': i['cents'],
        'category': i['category'],
        'low_confidence': (i['low_confidence'] as int) == 1,
      });
    }

    final receiptsList = <Map<String, dynamic>>[];
    for (final r in receiptsRows) {
      final id = r['id'] as int;
      receiptsList.add({
        'backup_id': id,
        'store': r['store'],
        'date': r['date'],
        'total': r['total'],
        'source': r['source'],
        'engine': r['engine'],
        'image_path': r['image_path'],
        'items': itemsByReceipt[id] ?? [],
      });
    }

    return {
      'app': 'rachunkownik',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'receipts': receiptsList,
      'incomes': [
        for (final inc in incomeRows)
          {
            'title': inc['title'],
            'cents': inc['cents'],
            'category': inc['category'],
            'date': inc['date'],
            'note': inc['note'],
          }
      ],
      'budgets': [
        for (final b in budgetsRows)
          {'category': b['category'], 'limit_cents': b['limit_cents']}
      ],
      'periodic_budgets': [
        for (final pb in periodicBudgetsRows)
          {
            'name': pb['name'],
            'category': pb['category'],
            'limit_cents': pb['limit_cents'],
            'period': pb['period'],
            'start_date': pb['start_date'],
            'end_date': pb['end_date'],
            'is_recurring': pb['is_recurring'],
          }
      ],
      'subscriptions': [
        for (final s in subscriptionsRows)
          {
            'name': s['name'],
            'cents': s['cents'],
            'period': s['period'],
            'next_date': s['next_date'],
            'active': (s['active'] as int) == 1,
          }
      ],
      'dismissed_subs': [for (final d in dismissedRows) d['name'] as String],
      'bank_transactions': [
        for (final t in bankRows)
          {
            'hash': t['hash'],
            'date': t['date'],
            'description': t['description'],
            'cents': t['cents'],
            'receipt_backup_id': t['receipt_id'],
          }
      ],
    };
  }

  Future<String> exportBackupJson() async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(await exportBackup());
  }

  Future<BackupStats> restoreBackupJson(String jsonString) async {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Nieprawidłowy format kopii: oczekiwano obiektu JSON');
    }
    return restoreBackup(decoded);
  }

  Future<BackupStats> restoreBackup(Map<String, dynamic> data) async {
    if (data['app'] != 'rachunkownik') {
      throw const FormatException('Nieprawidłowy plik kopii zapasowej: brak sygnatury aplikacji');
    }
    final v = data['version'] as int? ?? 0;
    if (v < 1 || v > 1) {
      throw FormatException('Nieobsługiwana wersja kopii zapasowej ($v)');
    }

    final rawReceipts = (data['receipts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rawBudgets = (data['budgets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rawPeriodicBudgets = (data['periodic_budgets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rawSubs = (data['subscriptions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rawDismissed = (data['dismissed_subs'] as List?)?.cast<String>() ?? [];
    final rawBank = (data['bank_transactions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final rawIncomes = (data['incomes'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    var itemsTotal = 0;

    return await _db.transaction((tx) async {
      await tx.delete('item_vectors');
      await tx.delete('bank_transactions');
      await tx.delete('items');
      await tx.delete('receipts');
      await tx.delete('incomes');
      await tx.delete('budgets');
      await tx.delete('periodic_budgets');
      await tx.delete('subscriptions');
      await tx.delete('dismissed_subs');

      final oldToNewReceiptId = <int, int>{};

      for (final r in rawReceipts) {
        final newId = await tx.insert('receipts', {
          'store': r['store'] as String? ?? 'Nieznany sklep',
          'date': (r['date'] as num).toInt(),
          'total': (r['total'] as num).toInt(),
          'source': (r['source'] as String?) ?? 'manual',
          'engine': r['engine'] as String?,
          'image_path': r['image_path'] as String?,
        });
        final oldBackupId = r['backup_id'] as int?;
        if (oldBackupId != null) {
          oldToNewReceiptId[oldBackupId] = newId;
        }

        final items = (r['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final i in items) {
          await tx.insert('items', {
            'receipt_id': newId,
            'name': i['name'] as String? ?? 'Pozycja',
            'cents': (i['cents'] as num).toInt(),
            'category': (i['category'] as String?) ?? 'Inne',
            'low_confidence': (i['low_confidence'] == true || i['low_confidence'] == 1) ? 1 : 0,
          });
          itemsTotal++;
        }
      }

      for (final inc in rawIncomes) {
        await tx.insert('incomes', {
          'title': inc['title'] as String? ?? 'Dochód',
          'cents': (inc['cents'] as num).toInt(),
          'category': (inc['category'] as String?) ?? 'Wynagrodzenie',
          'date': (inc['date'] as num).toInt(),
          'note': inc['note'] as String?,
        });
      }

      for (final b in rawBudgets) {
        final cat = b['category'] as String?;
        final limit = (b['limit_cents'] as num?)?.toInt();
        if (cat != null && limit != null && limit > 0) {
          await tx.insert('budgets', {
            'category': cat,
            'limit_cents': limit,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      for (final pb in rawPeriodicBudgets) {
        final name = pb['name'] as String?;
        final limit = (pb['limit_cents'] as num?)?.toInt();
        final start = (pb['start_date'] as num?)?.toInt();
        final end = (pb['end_date'] as num?)?.toInt();
        if (name != null && limit != null && start != null && end != null) {
          await tx.insert('periodic_budgets', {
            'name': name,
            'category': pb['category'] as String?,
            'limit_cents': limit,
            'period': (pb['period'] as String?) ?? 'custom',
            'start_date': start,
            'end_date': end,
            'is_recurring': (pb['is_recurring'] == 1 || pb['is_recurring'] == true) ? 1 : 0,
          });
        }
      }

      for (final s in rawSubs) {
        await tx.insert('subscriptions', {
          'name': s['name'] as String? ?? 'Subskrypcja',
          'cents': (s['cents'] as num).toInt(),
          'period': (s['period'] as String?) ?? 'monthly',
          'next_date': (s['next_date'] as num).toInt(),
          'active': (s['active'] == true || s['active'] == 1) ? 1 : 0,
        });
      }

      for (final d in rawDismissed) {
        await tx.insert('dismissed_subs', {'name': d}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      for (final t in rawBank) {
        final oldRecId = t['receipt_backup_id'] as int?;
        final mappedRecId = oldRecId != null ? oldToNewReceiptId[oldRecId] : null;
        await tx.insert('bank_transactions', {
          'hash': t['hash'] as String,
          'date': (t['date'] as num).toInt(),
          'description': t['description'] as String? ?? '',
          'cents': (t['cents'] as num).toInt(),
          'receipt_id': mappedRecId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      return BackupStats(
        receiptsCount: rawReceipts.length,
        itemsCount: itemsTotal,
        incomesCount: rawIncomes.length,
        budgetsCount: rawBudgets.length,
        subscriptionsCount: rawSubs.length,
        bankTransactionsCount: rawBank.length,
      );
    });
  }
}

class BackupStats {
  const BackupStats({
    required this.receiptsCount,
    required this.itemsCount,
    required this.budgetsCount,
    required this.subscriptionsCount,
    required this.bankTransactionsCount,
    this.incomesCount = 0,
  });

  final int receiptsCount;
  final int itemsCount;
  final int budgetsCount;
  final int subscriptionsCount;
  final int bankTransactionsCount;
  final int incomesCount;

  String get summary {
    final parts = <String>[];
    if (receiptsCount > 0) parts.add('$receiptsCount paragonów ($itemsCount pozycji)');
    if (incomesCount > 0) parts.add('$incomesCount dochodów');
    if (budgetsCount > 0) parts.add('$budgetsCount budżetów');
    if (subscriptionsCount > 0) parts.add('$subscriptionsCount subskrypcji');
    if (bankTransactionsCount > 0) parts.add('$bankTransactionsCount transakcji bankowych');
    return parts.isEmpty ? 'Pusta baza danych' : parts.join(', ');
  }
}


