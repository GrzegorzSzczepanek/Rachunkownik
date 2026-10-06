import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/receipt_images.dart';
import '../providers.dart';
import 'income_dialog.dart';
import 'overview_screen.dart';
import 'scan_flow.dart' show ReviewScreen;
import 'widgets.dart';

enum _ViewMode { expenses, incomes }

class ReceiptsScreen extends ConsumerStatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  ConsumerState<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends ConsumerState<ReceiptsScreen> {
  _ViewMode _mode = _ViewMode.expenses;

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsProvider);
    final incomes = ref.watch(incomesProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Paragony', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            if (_mode == _ViewMode.incomes)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: () => showIncomeDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Dodaj dochód'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_ViewMode>(
            segments: [
              ButtonSegment(
                value: _ViewMode.expenses,
                label: Text('Wydatki (${receipts.valueOrNull?.length ?? 0})'),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
              ),
              ButtonSegment(
                value: _ViewMode.incomes,
                label: Text('Dochody (${incomes.valueOrNull?.length ?? 0})'),
                icon: const Icon(Icons.trending_up_rounded, size: 18),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (set) {
              if (set.isNotEmpty) setState(() => _mode = set.first);
            },
          ),
        ),
        const SizedBox(height: 16),
        if (_mode == _ViewMode.expenses) ...[
          receipts.when(
            data: (list) => list.isEmpty
                ? const SectionCard(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                      child: Center(
                        child: Text(
                          'Brak paragonów. Dotknij przycisku aparatu, aby dodać pierwszy.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    ),
                  )
                : SectionCard(
                    child: Column(children: [
                      for (final r in list)
                        ReceiptTile(
                          r,
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => ReviewScreen(initial: r))),
                          onLongPress: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Usunąć paragon ${r.store}?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await ref.read(dbProvider).deleteReceipt(r.id!);
                              await deleteReceiptImage(r.imagePath);
                              ref.read(dataVersionProvider.notifier).bump();
                            }
                          },
                        ),
                    ]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
          ),
          const SizedBox(height: 8),
          const Text('Dotknij paragon, aby go zobaczyć lub poprawić. Przytrzymaj, aby usunąć.',
              style: TextStyle(color: Colors.black45)),
        ] else ...[
          incomes.when(
            data: (list) => list.isEmpty
                ? SectionCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                      child: Column(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, size: 48, color: AppColors.muted),
                          const SizedBox(height: 12),
                          const Text(
                            'Brak zapisanych dochodów',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Dodaj pensję, przelew, zlecenie lub premię, aby śledzić swój bilans.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                            onPressed: () => showIncomeDialog(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Dodaj pierwszy dochód'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SectionCard(
                    child: Column(children: [
                      for (final inc in list)
                        IncomeTile(
                          inc,
                          onTap: () => showIncomeDialog(context, initial: inc),
                          onLongPress: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Usunąć dochód ${inc.title}?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await ref.read(dbProvider).deleteIncome(inc.id!);
                              ref.read(dataVersionProvider.notifier).bump();
                            }
                          },
                        ),
                    ]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
          ),
          const SizedBox(height: 8),
          const Text('Dotknij dochód, aby edytować. Przytrzymaj, aby usunąć.',
              style: TextStyle(color: Colors.black45)),
        ],
      ],
    );
  }
}
