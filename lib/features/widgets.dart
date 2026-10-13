import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/theme.dart';

/// Flat grouping (no card in a card): a plain padded block; kept so screens keep their structure.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.symmetric(vertical: 12), this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(border: Border(top: BorderSide(color: border ?? AppColors.line))),
        padding: padding,
        child: child,
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg, this.fg});
  final String text;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: bg ?? AppColors.hero, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: fig(13, weight: 600, color: fg ?? AppColors.accentDeep)),
      );
}

class ProgressBar extends StatelessWidget {
  const ProgressBar(this.fraction, {super.key, this.color, this.height = 8, this.track});
  final double fraction;
  final Color? color;
  final Color? track;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0).toDouble(),
          minHeight: height,
          backgroundColor: track ?? AppColors.track,
          valueColor: AlwaysStoppedAnimation(color ?? AppColors.accent),
        ),
      );
}

class Initial extends StatelessWidget {
  const Initial(this.name, {super.key, this.green = false});
  final String name;
  final bool green;

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: green ? AppColors.hero : AppColors.field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: green ? AppColors.green : AppColors.ink)),
      );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: fig(16, weight: 700));
}

/// Lokalnie | API switch used per AI task.
class EngineToggle extends StatelessWidget {
  const EngineToggle({
    super.key,
    required this.api,
    required this.onChanged,
    this.localLabel = 'Lokalnie',
    this.apiLabel = 'API',
  });
  final bool api;
  final ValueChanged<bool> onChanged;
  final String localLabel;
  final String apiLabel;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool selected, Color color, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
                color: selected ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(10)),
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.muted)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(localLabel, !api, AppColors.green, () => onChanged(false)),
        seg(apiLabel, api, AppColors.blue, () => onChanged(true)),
      ]),
    );
  }
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating));
}

/// Hero zone: tinted block with rounded bottom (32 px) running under the status bar.
class HeroZone extends StatelessWidget {
  const HeroZone({super.key, required this.child, this.bottom = 24, this.radius = 32});
  final Widget child;
  final double bottom, radius;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.hero,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
        ),
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top, 20, bottom),
        child: child,
      );
}

/// Back arrow + Bricolage title (52 px), used inside [HeroZone].
class HeroBackHeader extends StatelessWidget {
  const HeroBackHeader(this.title, {super.key, this.actions = const [], this.size = 28});
  final String title;
  final List<Widget> actions;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: Row(children: [
          Transform.translate(
            offset: const Offset(-12, 0),
            child: IconButton(tooltip: 'Wróć', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context)),
          ),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(size))),
          ...actions,
        ]),
      );
}

/// Big money number with a smaller "zł" next to it. [cents] is formatted by [formatMoney].
class MoneyText extends StatelessWidget {
  const MoneyText(this.cents, {super.key, this.size = 72, this.unitSize = 28, this.color, this.plus = false});
  final int cents;
  final double size, unitSize;
  final Color? color;
  final bool plus;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${plus && cents > 0 ? '+' : ''}${formatMoney(cents, withCurrency: false)}', style: display(size, color: color)),
            ),
          ),
          SizedBox(width: unitSize * 0.28),
          Text('zł', style: display(unitSize, color: color)),
        ],
      );
}

/// Section title (Bricolage 22) with an optional right-aligned text link, on one line.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(title, style: display(22))),
        if (action != null)
          Transform.translate(
            offset: const Offset(8, 0),
            child: TextButton(onPressed: onAction, child: Text(action!, style: fig(15, weight: 600, color: AppColors.accent))),
          ),
      ]);
}

/// Line-separated list row: title (17/700 or 16/600), subtitle 14, optional trailing and leading.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.leading,
    this.trailing,
    this.onTap,
    this.topLine = true,
    this.bottomLine = false,
    this.minHeight = 64,
    this.bold = false,
    this.chevron = true,
  });
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final bool topLine, bottomLine, bold, chevron;
  final double minHeight;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          decoration: BoxDecoration(
            border: Border(
              top: topLine ? BorderSide(color: AppColors.line) : BorderSide.none,
              bottom: bottomLine ? BorderSide(color: AppColors.line) : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(title, style: fig(bold ? 17 : 16, weight: bold ? 700 : 600)),
                if (subtitle != null)
                  Text(subtitle!, style: fig(14, weight: subtitleColor != null ? 600 : 400, color: subtitleColor ?? AppColors.text2, height: 20 / 14)),
              ]),
            ),
            if (trailing != null) trailing!,
            if (trailing == null && onTap != null && chevron) Icon(Icons.chevron_right, color: AppColors.text2),
          ]),
        ),
      );
}

/// Budget line: name + "spent of limit", 8 px bar; amber and an explicit "zostało X" from 80%.
class BudgetRow extends StatelessWidget {
  const BudgetRow({super.key, required this.name, required this.spent, required this.limit, this.first = false, this.onTap, this.subtitle});
  final String name;
  final int spent, limit;
  final bool first;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final f = limit == 0 ? 0.0 : spent / limit;
    final warn = f >= 0.8;
    final over = f > 1;
    final left = limit - spent;
    final color = warn ? AppColors.warnBar : AppColors.accent;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
        decoration: BoxDecoration(border: Border(top: first ? BorderSide.none : BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: fig(16, weight: 600)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${formatMoney(spent, withCurrency: false)} z ${formatMoney(limit)}${warn ? (over ? ', ponad o ${formatMoney(-left)}' : ', zostało ${formatMoney(left)}') : ''}',
                textAlign: TextAlign.right,
                style: fig(warn ? 14 : 16, weight: warn ? 600 : 400, color: warn ? AppColors.warn : AppColors.text2),
              ),
            ),
          ]),
          if (subtitle != null) Text(subtitle!, style: fig(13, color: AppColors.text2)),
          const SizedBox(height: 6),
          ProgressBar(f, color: color, track: warn ? AppColors.warnTrack : null, height: 8),
        ]),
      ),
    );
  }
}

/// Flat rounded field used on hero zones.
class HeroField extends StatelessWidget {
  const HeroField({super.key, required this.controller, required this.hint, this.leading, this.actions = const [], this.onSubmitted, this.keyboardType, this.fill});
  final TextEditingController controller;
  final String hint;
  final Widget? leading;
  final List<Widget> actions;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final Color? fill;

  @override
  Widget build(BuildContext context) => Container(
        height: 56,
        decoration: BoxDecoration(color: fill ?? AppColors.bg, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textInputAction: TextInputAction.done,
              onSubmitted: onSubmitted,
              style: fig(16, weight: 500),
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ...actions,
        ]),
      );
}

class AccentSquareButton extends StatelessWidget {
  const AccentSquareButton({super.key, required this.onTap, this.icon, this.label, required this.semantics});
  final VoidCallback onTap;
  final IconData? icon;
  final String? label;
  final String semantics;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantics,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            width: label == null ? 44 : null,
            padding: label == null ? null : const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: label != null ? Text(label!, style: fig(15, weight: 700, color: AppColors.onAccent)) : Icon(icon, color: AppColors.onAccent),
          ),
        ),
      );
}
