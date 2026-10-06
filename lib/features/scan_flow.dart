import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/ai_settings.dart';
import '../ai/categorizer.dart';
import '../ai/local_runtime.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/receipt_images.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'income_dialog.dart';
import 'widgets.dart';

/// Entry point for the centre button: photo, gallery, manual entry or income.
Future<void> startScan(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Zrób zdjęcie paragonu'),
            onTap: () => Navigator.pop(ctx, 'camera')),
        ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Wybierz z galerii'),
            onTap: () => Navigator.pop(ctx, 'gallery')),
        ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Wpisz wydatek ręcznie'),
            onTap: () => Navigator.pop(ctx, 'manual')),
        ListTile(
            leading: const Icon(Icons.trending_up_rounded, color: AppColors.green),
            title: const Text('Dodaj dochód', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Wypłata, premia, przelew, zlecenie'),
            onTap: () => Navigator.pop(ctx, 'income')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  final nav = Navigator.of(context);
  if (choice == 'income') {
    await showIncomeDialog(context);
    return;
  }
  if (choice == 'manual') {
    nav.push(MaterialPageRoute(
        builder: (_) => ReviewScreen(
            initial: Receipt(store: '', date: DateTime.now(), totalCents: 0, items: []))));
    return;
  }
  try {
    final file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 85);
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    nav.push(MaterialPageRoute(builder: (_) => ProcessingScreen(image: bytes)));
  } catch (e) {
    if (context.mounted) showError(context, 'Nie udało się wczytać zdjęcia: $e');
  }
}

/// Runs extraction with the engine chosen in settings, then hands over to review.
class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key, required this.image, this.forceEngine});
  final Uint8List image;
  final AiEngine? forceEngine;
  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingState();
}

class _ProcessingState extends ConsumerState<ProcessingScreen> {
  String? _error;
  final _elapsed = Stopwatch()..start();
  Timer? _ticker;
  bool _cancelled = false;

  /// A local model on a weak CPU can take minutes; past this we stop and offer the API.
  static const _localTimeout = Duration(minutes: 4);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _error == null) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _cancel() {
    _cancelled = true;
    // Closing the model aborts a running generation and frees its memory.
    ref.read(localRuntimeProvider).release();
    Navigator.pop(context);
  }

  Future<bool> _consent(AiSettings s) async {
    final engine = widget.forceEngine ?? s.engineFor(AiTask.receiptReading);
    if (engine != AiEngine.api || !s.privacy.askBeforeSendingImage) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Wysłać zdjęcie?'),
            content: Text('Zdjęcie paragonu zostanie wysłane do ${s.api.providerLabel}. '
                'Paragon może zawierać dane osobowe.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wyślij')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _run() async {
    final ctrl = ref.read(aiSettingsProvider.notifier);
    final settings = ref.read(aiSettingsProvider);
    if (!await _consent(settings)) {
      if (mounted) Navigator.pop(context);
      return;
    }
    try {
      final extractor = await ctrl.extractor();
      final engine = widget.forceEngine ?? settings.engineFor(AiTask.receiptReading);
      var run = extractor.extract(widget.image, forceEngine: widget.forceEngine);
      if (engine == AiEngine.local) {
        run = run.timeout(_localTimeout, onTimeout: () {
          ref.read(localRuntimeProvider).release();
          throw TimeoutException('Lokalny odczyt trwa zbyt długo (ponad ${_localTimeout.inMinutes} min). '
              'Ten telefon może być za wolny dla wybranego modelu.');
        });
      }
      final res = await run;
      if (!mounted || _cancelled) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => ReviewScreen(
                  initial: res.receipt, image: widget.image, elapsed: res.elapsed)));
    } on LocalRuntimeUnavailable catch (e) {
      if (mounted && !_cancelled) setState(() => _error = e.message);
    } on TimeoutException catch (e) {
      if (mounted && !_cancelled) setState(() => _error = e.message);
    } catch (e) {
      if (mounted && !_cancelled) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Czytam paragon')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _error == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text('${_elapsed.elapsed.inSeconds} s',
                      style: mono(size: 20, weight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text(
                    (widget.forceEngine ?? settings.engineFor(AiTask.receiptReading)) == AiEngine.local
                        ? 'Wczytuję model i czytam paragon na telefonie. '
                            'Pierwszy odczyt trwa dłużej, bo model musi trafić do pamięci.'
                        : 'Czytam paragon przez ${settings.api.providerLabel}…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
                    onPressed: _cancel,
                    child: const Text('Anuluj'),
                  ),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 40, color: AppColors.amber),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  if (widget.forceEngine == null &&
                      settings.engineFor(AiTask.receiptReading) == AiEngine.local)
                    OutlinedButton(
                      onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ProcessingScreen(
                                  image: widget.image, forceEngine: AiEngine.api))),
                      child: Text('Spróbuj przez API (${settings.api.providerLabel})'),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ReviewScreen(
                                initial: Receipt(
                                    store: '', date: DateTime.now(), totalCents: 0, items: []),
                                image: widget.image))),
                    child: const Text('Wpisz ręcznie'),
                  ),
                ]),
        ),
      ),
    );
  }
}

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.initial, this.image, this.elapsed});
  final Receipt initial;
  final Uint8List? image;
  final Duration? elapsed;
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<ReviewScreen> {
  // Work on a copy so cancelling never changes the cached list behind this screen.
  late Receipt r = widget.initial.copy();
  late final _store = TextEditingController(text: r.store);

  /// Read by a model: the receipt's own total is authoritative and the lines are
  /// checked against it. Manual and bank entries just add their lines up.
  late final bool _scanned = r.source == ReadSource.local || r.source == ReadSource.api;
  bool get _editing => widget.initial.id != null;

  int? _totalOverride; // set when the user types the receipt total
  Uint8List? _image;

  int get _total => _totalOverride ?? (_scanned ? r.totalCents : r.itemsSum);

  @override
  void initState() {
    super.initState();
    _image = widget.image;
    if (_image == null && r.imagePath != null) {
      readReceiptImage(r.imagePath).then((b) {
        if (mounted && b != null) setState(() => _image = b);
      });
    }
  }

  Future<void> _editTotal() async {
    final c = TextEditingController(text: formatMoney(_total, withCurrency: false).replaceAll('\u00A0', ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suma paragonu'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'zł'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    final cents = parseMoney(c.text);
    if (ok == true && cents != null && cents > 0) setState(() => _totalOverride = cents);
  }

  void _showImage() {
    final img = _image;
    if (img == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          InteractiveViewer(maxScale: 5, child: Image.memory(img, fit: BoxFit.contain)),
          Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))),
        ]),
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć paragon ${r.store}?'),
        content: const Text('Zniknie też zapisane zdjęcie.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).deleteReceipt(r.id!);
    await deleteReceiptImage(r.imagePath);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _editItem(ReceiptItem? item) async {
    final name = TextEditingController(text: item?.name ?? '');
    final price = TextEditingController(text: item == null ? '' : formatMoney(item.cents, withCurrency: false));
    var cat = item?.category ?? 'Inne';
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(item == null ? 'Nowa pozycja' : 'Edytuj pozycję'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nazwa')),
            const SizedBox(height: 10),
            TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Kwota', suffixText: 'zł')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: cat,
              items: [for (final c in defaultCategories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setS(() => cat = v ?? cat),
              decoration: const InputDecoration(labelText: 'Kategoria'),
            ),
          ]),
          actions: [
            if (item != null)
              TextButton(
                  onPressed: () {
                    r.items.remove(item);
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Usuń')),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            TextButton(
                onPressed: () {
                  final cents = parseMoney(price.text);
                  if (name.text.trim().isEmpty || cents == null) return;
                  if (item == null) {
                    final guessed = cat == 'Inne' ? guessCategory(name.text, store: r.store) : cat;
                    r.items.add(ReceiptItem(name: name.text.trim(), cents: cents, category: guessed));
                  } else {
                    item
                      ..name = name.text.trim()
                      ..cents = cents
                      ..category = cat
                      ..lowConfidence = false;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('OK')),
          ],
        ),
      ),
    );
    if (res == true) setState(() {});
  }

  Future<void> _save() async {
    r.store = _store.text.trim().isEmpty ? 'Nieznany sklep' : _store.text.trim();
    r.totalCents = _total;
    if (r.totalCents <= 0) {
      showError(context, 'Dodaj co najmniej jedną pozycję z kwotą.');
      return;
    }
    final db = ref.read(dbProvider);
    if (_editing) {
      await db.updateReceipt(r);
    } else {
      if (widget.image != null) r.imagePath = await saveReceiptImage(widget.image!);
      await db.saveReceipt(r);
    }
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    if (_editing) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final canRetry = !_editing &&
        widget.image != null &&
        r.source == ReadSource.local &&
        settings.privacy.suggestApiRetry;
    final low = r.items.where((i) => i.lowConfidence).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Paragon' : 'Sprawdź paragon'),
        actions: [
          if (_editing)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Usuń paragon'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Eyebrow('SKLEP'),
              TextField(
                controller: _store,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                    hintText: 'Nazwa sklepu', border: InputBorder.none, filled: false, enabledBorder: InputBorder.none),
              ),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: r.date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)));
                  if (d != null) setState(() => r.date = d);
                },
                child: Text('${longDate(r.date)} · ${r.items.length} pozycji  ✎',
                    style: const TextStyle(color: AppColors.muted)),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _editTotal,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatMoney(_total), style: mono(size: 32)),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_outlined, size: 18, color: AppColors.muted),
                ]),
              ),
            ]),
          ),
          if (_image != null) ...[
            const SizedBox(height: 14),
            InkWell(
              onTap: _showImage,
              borderRadius: BorderRadius.circular(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.memory(_image!, fit: BoxFit.cover, alignment: Alignment.topCenter),
                    const Positioned(
                      right: 10,
                      bottom: 10,
                      child: Pill('Powiększ zdjęcie', bg: Colors.white, fg: AppColors.ink),
                    ),
                  ]),
                ),
              ),
            ),
          ],
          if (_scanned) ...[
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Pill(r.source == ReadSource.local ? 'Lokalnie' : 'API',
                  bg: r.source == ReadSource.local ? AppColors.greenSoft : AppColors.blueSoft,
                  fg: r.source == ReadSource.local ? AppColors.green : AppColors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    '${r.engineLabel ?? ''}${widget.elapsed == null ? '' : ' · ${(widget.elapsed!.inMilliseconds / 1000).toStringAsFixed(1)} s'}',
                    style: const TextStyle(color: AppColors.muted)),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Eyebrow('POZYCJE'), Eyebrow('KWOTA')]),
              ),
              for (final i in r.items)
                InkWell(
                  onTap: () => _editItem(i),
                  child: Container(
                    color: i.lowConfidence ? AppColors.amberSoft : null,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: i.lowConfidence ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(i.name, style: const TextStyle(fontSize: 16))),
                        Pill(i.lowConfidence ? '${i.category}?' : i.category,
                            bg: i.lowConfidence ? const Color(0xFFF3DDB0) : AppColors.chip,
                            fg: i.lowConfidence ? AppColors.amberInk : AppColors.ink),
                        const SizedBox(width: 12),
                        Text(formatMoney(i.cents, withCurrency: false), style: mono(size: 16, weight: FontWeight.w500)),
                      ]),
                      if (i.lowConfidence)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('⚠ Niska pewność odczytu. Sprawdź nazwę i kategorię.',
                              style: TextStyle(color: AppColors.amberInk, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                ),
              InkWell(
                onTap: () => _editItem(null),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                  child: const Row(children: [
                    Icon(Icons.add, color: AppColors.green),
                    SizedBox(width: 8),
                    Text('Dodaj pozycję', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (_scanned || _totalOverride != null)
            r.itemsSum == _total
                ? Text('✓ Suma pozycji ${formatMoney(r.itemsSum, withCurrency: false)} = suma paragonu ${formatMoney(_total, withCurrency: false)}',
                    style: mono(size: 13, weight: FontWeight.w500, color: AppColors.green))
                : Text('⚠ Suma pozycji ${formatMoney(r.itemsSum, withCurrency: false)} ≠ suma paragonu ${formatMoney(_total, withCurrency: false)}. Sprawdź pozycje.',
                    style: mono(size: 13, weight: FontWeight.w600, color: AppColors.amberInk)),
          if (low > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('$low pozycji do sprawdzenia', style: const TextStyle(color: AppColors.amberInk)),
            ),
          const SizedBox(height: 20),
          if (canRetry) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.cloud_outlined),
              label: Text('Ponów przez API (wyśle zdjęcie do ${settings.api.providerLabel})',
                  textAlign: TextAlign.center),
              onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ProcessingScreen(image: widget.image!, forceEngine: AiEngine.api))),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(onPressed: _save, child: Text(_editing ? 'Zapisz zmiany' : 'Zapisz paragon')),
        ],
      ),
    );
  }
}
