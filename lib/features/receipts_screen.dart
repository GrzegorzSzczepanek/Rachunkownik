import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/receipt_images.dart';
import '../providers.dart';
import 'overview_screen.dart';
import 'scan_flow.dart' show ReviewScreen;
import 'widgets.dart';

class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        const Text('Paragony', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        receipts.when(
          data: (list) => list.isEmpty
              ? const Text('Nic tu jeszcze nie ma.')
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
        const Text('Dotknij paragon, aby go zobaczyć lub poprawić. Przytrzymaj, aby usunąć.', style: TextStyle(color: Colors.black45)),
      ],
    );
  }
}
