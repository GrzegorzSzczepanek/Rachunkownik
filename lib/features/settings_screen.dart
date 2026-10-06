import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_settings.dart';
import '../ai/local_models.dart';
import '../core/app_update.dart';
import '../core/app_version.dart';
import '../core/theme.dart';
import '../providers.dart';
import '../notifications/notification_sync.dart';
import 'data_actions.dart';
import 'widgets.dart';

const _localDetail = {
  AiTask.receiptReading: 'Model z obsługą obrazu (pobierz w Modelach lokalnych)',
  AiTask.categorization: 'Reguły słownikowe + opcjonalnie model tekstowy',
  AiTask.embeddings: 'Wyszukiwanie w kodzie: odmiana, literówki, synonimy (bez modelu)',
  AiTask.chat: 'Wymaga dużego modelu. Zwykle lepiej API',
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(aiSettingsProvider);
    final ctrl = ref.read(aiSettingsProvider.notifier);
    final downloads = ref.watch(modelDownloadsProvider);
    final installed = modelCatalog
        .where((m) => downloads[m.id]?.state == ModelState.installed)
        .fold(0, (a, m) => a + m.totalBytes);
    final apiTasks = AiTask.values.where((t) => s.engineFor(t) == AiEngine.api).toList();
    final provider = s.api.providerLabel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        const Text('Model AI', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Każde zadanie wykonuje inny silnik. Wybierz, co zostaje na telefonie.',
            style: TextStyle(color: AppColors.muted, fontSize: 16)),
        const SizedBox(height: 16),
        for (final t in AiTask.values) ...[
          SectionCard(
            border: s.engineFor(t) == AiEngine.api ? AppColors.blue : null,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                EngineToggle(
                  api: s.engineFor(t) == AiEngine.api,
                  onChanged: (api) => ctrl.setEngine(t, api ? AiEngine.api : AiEngine.local),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                  s.engineFor(t) == AiEngine.api
                      ? (t == AiTask.embeddings
                          ? (s.api.embeddingModel.isEmpty
                              ? '$provider · ustaw model embeddingów w Dostawcy API'
                              : '$provider · ${s.api.embeddingModel}')
                          : '$provider${s.api.model.isEmpty ? ' · skonfiguruj model' : ' · ${s.api.model}'}')
                      : _localDetail[t]!,
                  style: const TextStyle(color: AppColors.muted)),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: apiTasks.isEmpty ? AppColors.greenSoft : AppColors.blueSoft,
              borderRadius: BorderRadius.circular(16)),
          child: Text(
            apiTasks.isEmpty
                ? 'Wszystko zostaje na telefonie. Nic nie jest wysyłane.'
                : 'Do $provider trafia: ${apiTasks.map((t) => switch (t) {
                      AiTask.receiptReading => 'zdjęcia paragonów',
                      AiTask.categorization => 'nazwy pozycji',
                      AiTask.embeddings => 'treść pozycji',
                      AiTask.chat => 'treść pytania i dopasowane pozycje',
                    }).join(', ')}.',
            style: TextStyle(color: apiTasks.isEmpty ? AppColors.green : AppColors.blue, height: 1.4),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _link('Dostawca API', '$provider${s.api.model.isEmpty ? '' : ' · ${s.api.model}'}',
                () => context.go('/settings/api')),
            const Divider(),
            _link('Modele lokalne i pobieranie', _gb(installed), () => context.go('/settings/models')),
          ]),
        ),
        const SizedBox(height: 16),
        const _NotificationsCard(),
        const SizedBox(height: 16),
        const _SecurityCard(),
        const SizedBox(height: 16),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _link('Analiza i wykresy', '', () => context.push('/analytics')),
            const Divider(),
            _link('Import z banku (CSV)', '', () => context.push('/import')),
            const Divider(),
            _link('Eksport do CSV', '', () => exportCsv(context, ref)),
            const Divider(),
            _link('Kopia zapasowa (JSON)', '', () => exportBackupJson(context, ref)),
            const Divider(),
            _link('Przywróć z kopii (JSON)', '', () => restoreBackupJson(context, ref)),
          ]),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(children: [
            _toggle('Maskuj numer karty, PESEL i dane kontaktowe w tekście przed wysłaniem',
                'Dotyczy tekstu (OCR, kontekst czatu). Zdjęć nie zamazuje.',
                s.privacy.maskPersonalData, (v) => ctrl.setPrivacy(s.privacy.copyWith(mask: v))),
            const Divider(),
            _toggle('Pytaj o zgodę przed każdym wysłaniem zdjęcia',
                'Z nazwą dostawcy: „Zdjęcie paragonu zostanie wysłane do $provider”.',
                s.privacy.askBeforeSendingImage, (v) => ctrl.setPrivacy(s.privacy.copyWith(ask: v))),
            const Divider(),
            _toggle('Proponuj ponowną próbę przez API przy niskiej pewności',
                'Tylko jako propozycja na ekranie sprawdzania paragonu.',
                s.privacy.suggestApiRetry, (v) => ctrl.setPrivacy(s.privacy.copyWith(retry: v))),
            const Divider(),
            _toggle('Pokazuj licznik tokenów',
                'W tym miesiącu: ${s.monthlyTokens} tokenów przez API.',
                s.privacy.showTokenCounter, (v) => ctrl.setPrivacy(s.privacy.copyWith(tokens: v))),
          ]),
        ),
        const SizedBox(height: 16),
        const _AboutCard(),
      ],
    );
  }

  static String _gb(int bytes) => '${(bytes / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

  Widget _link(String title, String trailing, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(trailing, style: const TextStyle(color: AppColors.muted)),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ]),
        onTap: onTap,
      );

  Widget _toggle(String title, String sub, bool v, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub),
        value: v,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.green,
        onChanged: on,
      );
}

/// Reminders before subscription renewals and alerts when a budget passes 80% / 100%.
class _NotificationsCard extends ConsumerStatefulWidget {
  const _NotificationsCard();
  @override
  ConsumerState<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends ConsumerState<_NotificationsCard> {
  bool _budget = false;
  bool _subs = false;
  int _days = 1;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _budget = p.getBool(NotificationPrefs.budget) ?? false;
        _subs = p.getBool(NotificationPrefs.subs) ?? false;
        _days = p.getInt(NotificationPrefs.days) ?? 1;
      });
    });
  }

  Future<void> _set({bool? budget, bool? subs, int? days}) async {
    final turningOn = (budget ?? false) || (subs ?? false);
    if (turningOn) {
      final ok = await ref.read(notificationGatewayProvider).requestPermission();
      if (!ok) {
        if (mounted) {
          showError(context, 'Brak zgody na powiadomienia. Włącz je dla aplikacji w ustawieniach systemu.');
        }
        return;
      }
    }
    final p = await SharedPreferences.getInstance();
    if (budget != null) await p.setBool(NotificationPrefs.budget, budget);
    if (subs != null) await p.setBool(NotificationPrefs.subs, subs);
    if (days != null) await p.setInt(NotificationPrefs.days, days);
    setState(() {
      _budget = budget ?? _budget;
      _subs = subs ?? _subs;
      _days = days ?? _days;
    });
    await ref.read(notificationSyncProvider).run();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 4),
          child: Text('Powiadomienia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Przypomnienia o odnowieniu subskrypcji', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Rano, przed dniem płatności.'),
          value: _subs,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.green,
          onChanged: (v) => _set(subs: v),
        ),
        if (_subs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<int>(
              initialValue: _days,
              decoration: const InputDecoration(labelText: 'Przypomnij'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('w dniu płatności')),
                DropdownMenuItem(value: 1, child: Text('1 dzień wcześniej')),
                DropdownMenuItem(value: 2, child: Text('2 dni wcześniej')),
                DropdownMenuItem(value: 3, child: Text('3 dni wcześniej')),
              ],
              onChanged: (v) => v == null ? null : _set(days: v),
            ),
          ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alerty budżetowe', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Po przekroczeniu 80% i 100% budżetu kategorii.'),
          value: _budget,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.green,
          onChanged: (v) => _set(budget: v),
        ),
      ]),
    );
  }
}

class _SecurityCard extends ConsumerWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockEnabled = ref.watch(biometricLockProvider);
    final notifier = ref.read(biometricLockProvider.notifier);

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 4),
          child: Text('Bezpieczeństwo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Blokada biometryczna', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Wymagaj Face ID, odcisku palca lub kodu PIN przy uruchomieniu aplikacji.'),
          value: lockEnabled,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.green,
          onChanged: (val) async {
            final ok = await notifier.setEnabled(val);
            if (!ok && context.mounted) {
              showError(context, 'Weryfikacja biometryczna nie powiodła się.');
            }
          },
        ),
      ]),
    );
  }
}

class _AboutCard extends ConsumerStatefulWidget {
  const _AboutCard();

  @override
  ConsumerState<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends ConsumerState<_AboutCard> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final client = ref.read(appUpdateClientProvider);
      final update = await client.checkForUpdate();
      if (!mounted) return;
      if (update != null && update.hasUpdate) {
        showUpdateDialog(context, update);
      } else if (update != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Masz najnowszą wersję aplikacji ($appVersion).'),
            backgroundColor: AppColors.green,
          ),
        );
      } else {
        showError(context, 'Nie udało się połączyć z GitHubem.');
      }
    } catch (e) {
      if (mounted) showError(context, 'Błąd sprawdzania aktualizacji: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: const Text('Aktualizacje', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          subtitle: const Text('Wersja $appVersion · Sprawdź nowe wydania na GitHubie'),
          trailing: _checking
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded, color: AppColors.green),
          onTap: _checking ? null : _check,
        ),
        const Divider(),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: const Text('Repozytorium GitHub', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          subtitle: const Text(githubRepo),
          trailing: const Icon(Icons.open_in_new_rounded, color: AppColors.muted, size: 20),
          onTap: () => launchUrl(Uri.parse('https://github.com/$githubRepo'), mode: LaunchMode.externalApplication),
        ),
      ]),
    );
  }
}


