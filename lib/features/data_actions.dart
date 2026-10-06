import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/localization.dart';
import '../core/theme.dart';
import '../domain/csv_export.dart';
import '../providers.dart';
import 'widgets.dart';

enum ExportRange { thisMonth, last3Months, thisYear, all }

({String label, DateTime? from}) _range(ExportRange r, DateTime now, AppStrings str) => switch (r) {
      ExportRange.thisMonth => (label: str.isEnglish ? 'This month' : 'Ten miesiąc', from: DateTime(now.year, now.month)),
      ExportRange.last3Months => (label: str.isEnglish ? 'Last 3 months' : 'Ostatnie 3 miesiące', from: DateTime(now.year, now.month - 2)),
      ExportRange.thisYear => (label: str.isEnglish ? 'This year' : 'Ten rok', from: DateTime(now.year)),
      ExportRange.all => (label: str.isEnglish ? 'All' : 'Wszystko', from: null),
    };

/// Asks for a range, writes an Excel-friendly CSV and opens the share sheet.
Future<void> exportCsv(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final str = ref.read(appStringsProvider);
  final choice = await showDialog<ExportRange>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(str.exportCsv),
      children: [
        for (final r in ExportRange.values)
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r), child: Text(_range(r, now, str).label)),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    final receipts = await ref.read(dbProvider).receipts(from: _range(choice, now, str).from);
    if (receipts.isEmpty) {
      if (context.mounted) showError(context, str.exportNoReceipts);
      return;
    }
    final dir = await getTemporaryDirectory();
    final name = 'paragon_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(receiptsToCsv(receipts));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: str.expensesCsvSubject));
  } catch (e) {
    if (context.mounted) showError(context, str.exportFailed(e));
  }
}

/// Exports all database tables (receipts, items, budgets, subscriptions, bank transactions) to JSON.
Future<void> exportBackupJson(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final str = ref.read(appStringsProvider);
  try {
    final jsonStr = await ref.read(dbProvider).exportBackupJson();
    final dir = await getTemporaryDirectory();
    final name = 'rachunkownik_kopia_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(jsonStr);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: str.backupSubject));
  } catch (e) {
    if (context.mounted) showError(context, str.backupFailed(e));
  }
}

/// Picks a JSON backup file, confirms overwrite, restores all data and refreshes views.
Future<void> restoreBackupJson(BuildContext context, WidgetRef ref) async {
  final str = ref.read(appStringsProvider);
  try {
    final file = await FilePicker.pickFile(
      dialogTitle: str.isEnglish ? 'Select backup file' : 'Wybierz plik kopii zapasowej',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return;

    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(str.restoreDialogTitle),
        content: Text(str.restoreDialogContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(str.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(str.restoreAndReplace),
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
          content: Text(str.restoreSuccess(stats.summary)),
          backgroundColor: AppColors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showError(context, str.restoreFailed(e));
  }
}


