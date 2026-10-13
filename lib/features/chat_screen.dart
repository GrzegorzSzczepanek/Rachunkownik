import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/spending_chat.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../providers.dart';
import 'income_dialog.dart';
import 'scan_flow.dart' show ReviewScreen;
import 'widgets.dart';

class _Msg {
  _Msg.user(this.text) : answer = null, user = true;
  _Msg.bot(this.answer) : text = '', user = false;
  final String text;
  final ChatAnswer? answer;
  final bool user;
  bool undone = false;
}

/// Wpisz lub zapytaj, per design/Czat-odpowiedz: a sentence is saved at once (with "Cofnij"),
/// a question gets an answer computed from your data.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 300, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _ask([String? text]) async {
    final q = (text ?? _q.text).trim();
    if (q.isEmpty || _busy) return;
    _q.clear();
    setState(() {
      _msgs.add(_Msg.user(q));
      _busy = true;
    });
    _toBottom();
    try {
      final chat = await ref.read(aiSettingsProvider.notifier).chat();
      final a = await chat.ask(q);
      if (!mounted) return;
      setState(() => _msgs.add(_Msg.bot(a)));
      if (a.createdReceipt != null || a.createdIncome != null) ref.read(dataVersionProvider.notifier).bump();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
      _toBottom();
    }
  }

  Future<void> _undo(_Msg m) async {
    final a = m.answer!;
    final db = ref.read(dbProvider);
    final str = ref.read(appStringsProvider);
    try {
      if (a.createdReceipt?.id != null) await db.deleteReceipt(a.createdReceipt!.id!);
      if (a.createdIncome?.id != null) await db.deleteIncome(a.createdIncome!.id!);
      ref.read(dataVersionProvider.notifier).bump();
      if (mounted) setState(() => m.undone = true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(str.undoSuccess)));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _bubble(String text) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(4)),
          ),
          child: Text(text, style: fig(16, color: AppColors.onAccent, height: 24 / 16)),
        ),
      );

  Widget _bot(_Msg m, AppStrings str) {
    final a = m.answer!;
    if (a.createdReceipt != null) {
      final r = a.createdReceipt!;
      return Container(
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.undone ? str.undoSuccess : '${str.addedFromChat} ${formatMoney(r.totalCents)}', style: fig(17, weight: 700)),
              Text('${r.store}, ${str.categoryName(r.mainCategory)}, ${str.relativeDate(r.date)}', style: fig(14, color: AppColors.text2)),
            ]),
          ),
          if (!m.undone) ...[
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(initial: r))),
              child: Text(str.edit),
            ),
            TextButton(onPressed: () => _undo(m), child: Text(str.undo, style: fig(16, weight: 700, color: AppColors.accent))),
          ],
        ]),
      );
    }
    if (a.createdIncome != null) {
      final inc = a.createdIncome!;
      return Container(
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.undone ? str.incomeUndone : '${str.addedIncomeFromChat} +${formatMoney(inc.cents)}', style: fig(17, weight: 700)),
              Text('${inc.title}, ${str.categoryName(inc.category)}, ${str.relativeDate(inc.date)}', style: fig(14, color: AppColors.text2)),
            ]),
          ),
          if (!m.undone) ...[
            TextButton(onPressed: () => showIncomeDialog(context, initial: inc), child: Text(str.edit)),
            TextButton(onPressed: () => _undo(m), child: Text(str.undo, style: fig(16, weight: 700, color: AppColors.accent))),
          ],
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.text, style: fig(17, height: 26 / 17)),
        const SizedBox(height: 6),
        Text(
          [
            if (a.sourceCount > 0) '${str.source}: ${str.itemsCount(a.sourceCount)}',
            a.engine == 'lokalnie' ? str.calculatedLocally : 'Model: ${a.engine}',
          ].join(' · '),
          style: fig(13, color: AppColors.text2),
        ),
        if (a.hits.length > 1)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(str.showItems, style: fig(15, weight: 600, color: AppColors.accent)),
              children: [
                for (final h in a.hits.take(15))
                  Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                    child: Row(children: [
                      SizedBox(width: 56, child: Text(shortDate(h.doc.date, isEnglish: str.isEnglish), style: fig(14, color: AppColors.text2))),
                      Expanded(child: Text(h.doc.name == h.doc.store ? h.doc.name : '${h.doc.name} · ${h.doc.store}', maxLines: 1, overflow: TextOverflow.ellipsis, style: fig(15))),
                      Text(formatMoney(h.doc.cents), style: fig(15, weight: 600)),
                    ]),
                  ),
              ],
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        HeroZone(bottom: 8, radius: 0, child: HeroBackHeader(str.isEnglish ? 'Type or ask' : 'Wpisz lub zapytaj', size: 24)),
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
            if (_msgs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str.isEnglish ? 'Add an expense with a sentence, or ask about your spending.' : 'Dodaj wydatek zdaniem albo zapytaj o swoje wydatki.', style: fig(17, color: AppColors.text3, height: 26 / 17)),
                  const SizedBox(height: 16),
                  for (final ex in str.isEnglish ? ['Coffee \$4 at Starbucks', 'How much did I spend on food this month?'] : ['Kawa 12 zł w Żabce', 'Ile wydałem na jedzenie w tym miesiącu?'])
                    InkWell(
                      onTap: () => _ask(ex),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                        child: Text(ex, style: fig(16, weight: 600)),
                      ),
                    ),
                ]),
              ),
            for (final m in _msgs) m.user ? _bubble(m.text) : _bot(m, str),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 20), child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))),
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewInsets.bottom),
          decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(26)),
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _ask(),
                  style: fig(16, weight: 500),
                  decoration: InputDecoration(
                    hintText: str.isEnglish ? 'Type an expense or a question' : 'Wpisz wydatek albo pytanie',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _busy ? null : _ask,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: _busy ? AppColors.outline : AppColors.accent, shape: BoxShape.circle),
                child: Icon(Icons.arrow_upward, color: AppColors.onAccent),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
