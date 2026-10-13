import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/ai_settings.dart';
import '../ai/categorizer.dart';
import '../ai/local_runtime.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../data/receipt_images.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'income_dialog.dart';
import 'widgets.dart';

/// Entry point for the centre button: photo, gallery, manual entry or income.
Future<void> startScan(BuildContext context) async {
  final s = ProviderScope.containerOf(context).read(appStringsProvider);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)))),
          Text(s.addReceipt, style: display(26)),
          const SizedBox(height: 8),
          NavRow(topLine: false, minHeight: 60, leading: Icon(Icons.photo_camera_outlined, color: AppColors.accent), title: s.takePhoto, onTap: () => Navigator.pop(ctx, 'camera')),
          NavRow(minHeight: 60, leading: Icon(Icons.photo_library_outlined, color: AppColors.accent), title: s.chooseGallery, onTap: () => Navigator.pop(ctx, 'gallery')),
          NavRow(minHeight: 60, leading: Icon(Icons.edit_outlined, color: AppColors.accent), title: s.enterManual, onTap: () => Navigator.pop(ctx, 'manual')),
          NavRow(minHeight: 60, bottomLine: true, leading: Icon(Icons.trending_up_rounded, color: AppColors.accent), title: s.addIncome, subtitle: s.incomeSubtitle, onTap: () => Navigator.pop(ctx, 'income')),
        ]),
      ),
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
    if (context.mounted) {
      final str = ProviderScope.containerOf(context).read(appStringsProvider);
      showError(context, str.isEnglish ? 'Failed to load photo: $e' : 'Nie udało się wczytać zdjęcia: $e');
    }
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
    final str = ref.read(appStringsProvider);
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(str.isEnglish ? 'Send photo?' : 'Wysłać zdjęcie?'),
            content: Text(str.isEnglish
                ? 'Receipt photo will be sent to ${s.api.providerLabel}. The receipt may contain personal data.'
                : 'Zdjęcie paragonu zostanie wysłane do ${s.api.providerLabel}. Paragon może zawierać dane osobowe.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(str.cancel)),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(str.isEnglish ? 'Send' : 'Wyślij')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _run() async {
    final ctrl = ref.read(aiSettingsProvider.notifier);
    final settings = ref.read(aiSettingsProvider);
    final str = ref.read(appStringsProvider);
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
          throw TimeoutException(str.isEnglish
              ? 'Local recognition is taking too long (over ${_localTimeout.inMinutes} min). This device might be too slow for this model.'
              : 'Lokalny odczyt trwa zbyt długo (ponad ${_localTimeout.inMinutes} min). Ten telefon może być za wolny dla wybranego modelu.');
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
    final str = ref.watch(appStringsProvider);
    final local = (widget.forceEngine ?? settings.engineFor(AiTask.receiptReading)) == AiEngine.local;
    final bottom = MediaQuery.of(context).padding.bottom + 24;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _error == null
          ? Stack(children: [
              ListView(children: [
                HeroZone(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 52),
                    Text(str.isEnglish ? 'Reading receipt' : 'Czytam paragon', style: display(32)),
                    const SizedBox(height: 16),
                    Text('${_elapsed.elapsed.inSeconds} s', style: display(72)),
                    const SizedBox(height: 4),
                    Text(local ? (str.isEnglish ? 'on your phone' : 'na telefonie') : (str.isEnglish ? 'via ${settings.api.providerLabel}' : 'przez ${settings.api.providerLabel}'), style: fig(17, weight: 600)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  child: Text(
                    local
                        ? (str.isEnglish
                            ? 'Loading model and reading receipt on device. First run takes longer as the model loads into RAM.'
                            : 'Wczytuję model i czytam paragon na telefonie. Pierwszy odczyt trwa dłużej, bo model musi trafić do pamięci.')
                        : (str.isEnglish ? 'Reading receipt via ${settings.api.providerLabel}…' : 'Czytam paragon przez ${settings.api.providerLabel}…'),
                    style: fig(16, color: AppColors.text3, height: 24 / 16),
                  ),
                ),
              ]),
              Positioned(left: 24, right: 24, bottom: bottom, child: OutlinedButton(onPressed: _cancel, child: Text(str.cancel))),
            ])
          : Stack(children: [
              ListView(children: [
                HeroZone(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 52),
                    Text(str.isEnglish ? 'Could not read the receipt.' : 'Nie udało się odczytać paragonu.', style: display(32, height: 1.1)),
                    const SizedBox(height: 12),
                    Text(_error!, style: fig(16, color: AppColors.text3, height: 24 / 16)),
                  ]),
                ),
                const SizedBox(height: 180),
              ]),
              Positioned(
                left: 24,
                right: 24,
                bottom: bottom,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.forceEngine == null && settings.engineFor(AiTask.receiptReading) == AiEngine.local) ...[
                    FilledButton(
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProcessingScreen(image: widget.image, forceEngine: AiEngine.api))),
                      child: Text('${str.tryViaApi} (${settings.api.providerLabel})'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton(
                    onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => ReviewScreen(initial: Receipt(store: '', date: DateTime.now(), totalCents: 0, items: []), image: widget.image))),
                    child: Text(str.typeManually),
                  ),
                ]),
              ),
            ]),
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
    final str = ref.read(appStringsProvider);
    final c = TextEditingController(text: formatMoney(_total, withCurrency: false).replaceAll('\u00A0', ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(str.receiptTotal),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'zł'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(str.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(str.ok)),
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
    final str = ref.read(appStringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(str.deleteReceiptConfirm(r.store)),
        content: Text(str.deleteReceiptSub),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(str.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(str.delete)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).deleteReceipt(r.id!);
    await deleteReceiptImage(r.imagePath);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _editItem(ReceiptItem? item, {bool isCopy = false}) async {
    final str = ref.read(appStringsProvider);
    final name = TextEditingController(text: item?.name ?? '');
    final price = TextEditingController(text: item == null ? '' : formatMoney(item.cents, withCurrency: false));
    var cat = item?.category ?? 'Inne';
    int quantity = 1;
    bool separateItems = true;

    final isNew = item == null || isCopy;
    final dialogTitle = isCopy
        ? str.copyItem
        : (item == null ? str.newItem : str.editItem);

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final unitCents = parseMoney(price.text);
          final hasMultiple = quantity > 1;
          final totalPreview = (unitCents != null && hasMultiple)
              ? formatMoney(unitCents * quantity)
              : null;

          return AlertDialog(
            title: Text(dialogTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: str.itemName)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(str.quantity, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: quantity > 1 ? () => setS(() => quantity--) : null,
                      ),
                      Text('$quantity', style: figure(size: 16, weight: FontWeight.w700)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setS(() => quantity++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(
                      labelText: hasMultiple ? str.unitPrice : str.itemPrice,
                      suffixText: 'zł',
                    ),
                  ),
                  if (hasMultiple && totalPreview != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        '${str.totalSummary}: $quantity × ${price.text} zł = $totalPreview',
                        style: figure(size: 13, weight: FontWeight.w600, color: AppColors.green),
                      ),
                    ),
                  if (hasMultiple)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(str.separateItems, style: const TextStyle(fontSize: 13)),
                      value: separateItems,
                      onChanged: (v) => setS(() => separateItems = v ?? true),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: cat,
                    items: [for (final c in defaultCategories) DropdownMenuItem(value: c, child: Text(str.categoryName(c)))],
                    onChanged: (v) => setS(() => cat = v ?? cat),
                    decoration: InputDecoration(labelText: str.category),
                  ),
                ],
              ),
            ),
            actions: [
              if (!isNew)
                TextButton(
                  onPressed: () {
                    r.items.remove(item);
                    Navigator.pop(ctx, true);
                  },
                  child: Text(str.delete, style: const TextStyle(color: Colors.red)),
                ),
              if (!isNew)
                TextButton(
                  onPressed: () {
                    final cents = parseMoney(price.text);
                    if (name.text.trim().isEmpty || cents == null) return;
                    final guessed = cat == 'Inne' ? guessCategory(name.text, store: r.store) : cat;
                    if (hasMultiple && separateItems) {
                      for (int k = 0; k < quantity; k++) {
                        r.items.add(ReceiptItem(name: name.text.trim(), cents: cents, category: guessed));
                      }
                    } else {
                      final totalCents = cents * quantity;
                      r.items.add(ReceiptItem(
                        name: hasMultiple ? '${name.text.trim()} (×$quantity)' : name.text.trim(),
                        cents: totalCents,
                        category: guessed,
                      ));
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: Text(str.saveAsCopy),
                ),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(str.cancel)),
              TextButton(
                onPressed: () {
                  final cents = parseMoney(price.text);
                  if (name.text.trim().isEmpty || cents == null) return;
                  if (isNew) {
                    final guessed = cat == 'Inne' ? guessCategory(name.text, store: r.store) : cat;
                    if (hasMultiple && separateItems) {
                      for (int k = 0; k < quantity; k++) {
                        r.items.add(ReceiptItem(name: name.text.trim(), cents: cents, category: guessed));
                      }
                    } else {
                      final totalCents = cents * quantity;
                      r.items.add(ReceiptItem(
                        name: hasMultiple ? '${name.text.trim()} (×$quantity)' : name.text.trim(),
                        cents: totalCents,
                        category: guessed,
                      ));
                    }
                  } else {
                    if (hasMultiple && separateItems) {
                      item
                        ..name = name.text.trim()
                        ..cents = cents
                        ..category = cat
                        ..lowConfidence = false;
                      for (int k = 1; k < quantity; k++) {
                        r.items.add(ReceiptItem(name: name.text.trim(), cents: cents, category: cat));
                      }
                    } else {
                      final totalCents = cents * quantity;
                      item
                        ..name = hasMultiple ? '${name.text.trim()} (×$quantity)' : name.text.trim()
                        ..cents = totalCents
                        ..category = cat
                        ..lowConfidence = false;
                    }
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(str.ok),
              ),
            ],
          );
        },
      ),
    );
    if (res == true) setState(() {});
  }

  Future<void> _save() async {
    final str = ref.read(appStringsProvider);
    r.store = _store.text.trim().isEmpty ? (str.isEnglish ? 'Unknown store' : 'Nieznany sklep') : _store.text.trim();
    r.totalCents = _total;
    if (r.totalCents <= 0) {
      showError(context, str.needAtLeastOneItem);
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
    final str = ref.watch(appStringsProvider);
    final canRetry = !_editing && widget.image != null && r.source == ReadSource.local && settings.privacy.suggestApiRetry;
    final low = r.items.where((i) => i.lowConfidence).length;
    final sumsMatch = r.itemsSum == _total;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 24), children: [
        HeroZone(
          bottom: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HeroBackHeader(_editing ? str.receiptTitle : str.reviewTitle, size: 18, actions: [
              if (_editing) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: str.deleteReceipt),
            ]),
            Text(str.storeLabel, style: fig(14, color: AppColors.text3)),
            const SizedBox(height: 6),
            HeroField(controller: _store, hint: str.storeName),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: r.date, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)));
                if (d != null) setState(() => r.date = d);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${longDate(r.date, isEnglish: str.isEnglish)}, ${str.itemsCount(r.items.length)}', style: fig(15, color: AppColors.text3)),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.text2),
                ]),
              ),
            ),
            InkWell(
              onTap: _editTotal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                MoneyText(_total, size: 56, unitSize: 24),
                const SizedBox(width: 10),
                Icon(Icons.edit_outlined, size: 20, color: AppColors.text2),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_image != null)
              InkWell(
                onTap: _showImage,
                borderRadius: BorderRadius.circular(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.memory(_image!, fit: BoxFit.cover, alignment: Alignment.topCenter),
                      Positioned(right: 10, bottom: 10, child: Pill(str.isEnglish ? 'Zoom photo' : 'Powiększ zdjęcie', bg: AppColors.bg, fg: AppColors.text)),
                    ]),
                  ),
                ),
              ),
            if (_scanned)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${r.source == ReadSource.local ? str.localToggle : str.apiToggle}${(r.engineLabel ?? '').isEmpty ? '' : ' · ${r.engineLabel}'}${widget.elapsed == null ? '' : ' · ${(widget.elapsed!.inMilliseconds / 1000).toStringAsFixed(1)} s'}',
                  style: fig(13, color: AppColors.text2),
                ),
              ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(str.itemsLabel, style: display(22)),
              if (_scanned || _totalOverride != null)
                Flexible(
                  child: Text(
                    sumsMatch
                        ? (str.isEnglish ? 'sum matches' : 'suma się zgadza')
                        : (str.isEnglish ? 'check items: ${formatMoney(r.itemsSum - _total)}' : 'sprawdź: ${r.itemsSum - _total > 0 ? '+' : ''}${formatMoney(r.itemsSum - _total)}'),
                    textAlign: TextAlign.right,
                    style: fig(14, weight: 600, color: sumsMatch ? AppColors.accent : AppColors.warn),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            for (var n = 0; n < r.items.length; n++) _itemRow(r.items[n], str, first: n == 0),
            InkWell(
              onTap: () => _editItem(null),
              child: Container(
                height: 56,
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: BorderSide(color: AppColors.line))),
                child: Row(children: [
                  Icon(Icons.add, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(str.addItem, style: fig(15, weight: 600, color: AppColors.accent)),
                ]),
              ),
            ),
            if (_scanned || _totalOverride != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  sumsMatch
                      ? (str.isEnglish
                          ? 'Items ${formatMoney(r.itemsSum, withCurrency: false)} = receipt ${formatMoney(_total, withCurrency: false)}'
                          : 'Suma pozycji ${formatMoney(r.itemsSum, withCurrency: false)} = suma paragonu ${formatMoney(_total, withCurrency: false)}')
                      : (str.isEnglish
                          ? 'Items ${formatMoney(r.itemsSum, withCurrency: false)} ≠ receipt ${formatMoney(_total, withCurrency: false)}. Please check items.'
                          : 'Suma pozycji ${formatMoney(r.itemsSum, withCurrency: false)} ≠ suma paragonu ${formatMoney(_total, withCurrency: false)}. Sprawdź pozycje.'),
                  style: fig(13, weight: sumsMatch ? 400 : 600, color: sumsMatch ? AppColors.text2 : AppColors.warn),
                ),
              ),
            if (low > 0)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(str.isEnglish ? '$low items to check' : '$low pozycji do sprawdzenia', style: fig(13, weight: 600, color: AppColors.warn))),
            const SizedBox(height: 20),
            if (canRetry) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_outlined),
                label: Text(str.isEnglish ? 'Retry via API (sends photo to ${settings.api.providerLabel})' : 'Ponów przez API (wyśle zdjęcie do ${settings.api.providerLabel})', textAlign: TextAlign.center),
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProcessingScreen(image: widget.image!, forceEngine: AiEngine.api))),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(onPressed: _save, child: Text(_editing ? str.saveChanges : str.saveReceipt)),
          ]),
        ),
      ]),
    );
  }

  /// Item row: name and category, amount; amber "Sprawdź" when the reader was unsure.
  Widget _itemRow(ReceiptItem i, AppStrings str, {required bool first}) => InkWell(
        onTap: () => _editItem(i),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(border: Border(top: first ? BorderSide(color: AppColors.line) : BorderSide(color: AppColors.line))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.name, style: fig(16, weight: 600)),
                Text(
                  i.lowConfidence ? '${str.categoryName(i.category)}? ${str.isEnglish ? 'Check name and category' : 'Sprawdź nazwę i kategorię'}' : str.categoryName(i.category),
                  style: fig(14, weight: i.lowConfidence ? 600 : 400, color: i.lowConfidence ? AppColors.warn : AppColors.text2),
                ),
              ]),
            ),
            Text(i.lowConfidence ? '~${formatMoney(i.cents, withCurrency: false)}' : formatMoney(i.cents, withCurrency: false), style: fig(17, weight: 700)),
            IconButton(
              icon: Icon(Icons.copy_rounded, size: 20, color: AppColors.text2),
              tooltip: str.copyItem,
              onPressed: () => _editItem(i, isCopy: true),
            ),
          ]),
        ),
      );
}
