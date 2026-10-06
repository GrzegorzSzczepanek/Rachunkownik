import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../domain/csv_export.dart';
import '../providers.dart';
import 'widgets.dart';

enum ExportRange { thisMonth, last3Months, thisYear, all }

({String label, DateTime? from}) _range(ExportRange r, DateTime now) => switch (r) {
      ExportRange.thisMonth => (label: 'Ten miesiąc', from: DateTime(now.year, now.month)),
      ExportRange.last3Months => (label: 'Ostatnie 3 miesiące', from: DateTime(now.year, now.month - 2)),
      ExportRange.thisYear => (label: 'Ten rok', from: DateTime(now.year)),
      ExportRange.all => (label: 'Wszystko', from: null),
    };

/// Asks for a range, writes an Excel-friendly CSV and opens the share sheet.
Future<void> exportCsv(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final choice = await showDialog<ExportRange>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Eksport CSV'),
      children: [
        for (final r in ExportRange.values)
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r), child: Text(_range(r, now).label)),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    final receipts = await ref.read(dbProvider).receipts(from: _range(choice, now).from);
    if (receipts.isEmpty) {
      if (context.mounted) showError(context, 'Brak paragonów w wybranym zakresie.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final name = 'paragon_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(receiptsToCsv(receipts));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Wydatki (CSV)'));
  } catch (e) {
    if (context.mounted) showError(context, 'Nie udało się wyeksportować: $e');
  }
}

/// Exports all database tables (receipts, items, budgets, subscriptions, bank transactions) to JSON.
Future<void> exportBackupJson(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  try {
    final jsonStr = await ref.read(dbProvider).exportBackupJson();
    final dir = await getTemporaryDirectory();
    final name = 'rachunkownik_kopia_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(jsonStr);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Kopia zapasowa Rachunkownik'));
  } catch (e) {
    if (context.mounted) showError(context, 'Nie udało się utworzyć kopii zapasowej: $e');
  }
}

/// Picks a JSON backup file, confirms overwrite, restores all data and refreshes views.
Future<void> restoreBackupJson(BuildContext context, WidgetRef ref) async {
  try {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Wybierz plik kopii zapasowej',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return;

    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Przywrócić bazę danych?'),
        content: const Text(
          'Przywrócenie kopii zapasowej zastąpi wszystkie bieżące paragony, pozycje, budżety, subskrypcje i transakcje bankowe danymi z wybranego pliku.\n\nCzy na pewno chcesz kontynuować?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Przywróć i zastąp'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final bytes = await file.readAsBytes();
    final jsonStr = utf8.decode(bytes);
    final stats = await ref.read(dbProvider).restoreBackupJson(jsonStr);
    ref.read(dataVersionProvider.notifier).bump();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pomyślnie przywrócono bazę danych:\n${stats.summary}'),
          backgroundColor: AppColors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showError(context, 'Nie udało się przywrócić kopii: $e');
  }
}


