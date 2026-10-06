import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_settings.dart';
import '../ai/local_models.dart';
import '../core/app_update.dart';
import '../core/app_version.dart';
import '../core/localization.dart';
import '../core/theme.dart';
import '../providers.dart';
import '../notifications/notification_sync.dart';
import 'data_actions.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final str = ref.watch(appStringsProvider);
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
        Text(str.tabSettings, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          str.settingsSubtitle,
          style: const TextStyle(color: AppColors.muted, fontSize: 16),
        ),
        const SizedBox(height: 16),
        const _LanguageCard(),
        const SizedBox(height: 16),
        const _SecurityCard(),
        const SizedBox(height: 16),
        const _NotificationsCard(),
        const SizedBox(height: 16),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _link(str.backupJson, '', () => exportBackupJson(context, ref), icon: Icons.backup_outlined),
            const Divider(),
            _link(str.restoreJson, '', () => restoreBackupJson(context, ref), icon: Icons.settings_backup_restore_outlined),
            const Divider(),
            _link(str.exportCsv, '', () => exportCsv(context, ref), icon: Icons.download_outlined),
            const Divider(),
            _link(str.bankImportCsv, '', () => context.push('/import'), icon: Icons.upload_file_outlined),
            const Divider(),
            _link(str.analytics, '', () => context.push('/analytics'), icon: Icons.bar_chart_outlined),
          ]),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            str.aiSection,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: apiTasks.isEmpty ? AppColors.greenSoft : AppColors.blueSoft,
              borderRadius: BorderRadius.circular(16)),
          child: Text(
            apiTasks.isEmpty
                ? str.aiAllLocal
                : (str.isEnglish
                    ? 'Sent to $provider: ${apiTasks.map((t) => switch (t) {
                          AiTask.receiptReading => 'receipt photos',
                          AiTask.categorization => 'item names',
                          AiTask.embeddings => 'item text',
                          AiTask.chat => 'question & matching items',
                        }).join(', ')}.'
                    : 'Do $provider trafia: ${apiTasks.map((t) => switch (t) {
                          AiTask.receiptReading => 'zdjęcia paragonów',
                          AiTask.categorization => 'nazwy pozycji',
                          AiTask.embeddings => 'treść pozycji',
                          AiTask.chat => 'treść pytania i dopasowane pozycje',
                        }).join(', ')}.'),
            style: TextStyle(color: apiTasks.isEmpty ? AppColors.green : AppColors.blue, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _link(str.apiProvider, '$provider${s.api.model.isEmpty ? '' : ' · ${s.api.model}'}',
                () => context.go('/settings/api'), icon: Icons.cloud_outlined),
            const Divider(),
            _link(str.localModels, _gb(installed), () => context.go('/settings/models'), icon: Icons.memory_outlined),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded, color: AppColors.green),
              title: Text(str.enginesPerTask, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              subtitle: Text(str.enginesPerTaskSub, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              children: [
                for (final t in AiTask.values) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(str.aiTaskLabel(t), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                        EngineToggle(
                          localLabel: str.localToggle,
                          apiLabel: str.apiToggle,
                          api: s.engineFor(t) == AiEngine.api,
                          onChanged: (api) => ctrl.setEngine(t, api ? AiEngine.api : AiEngine.local),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        s.engineFor(t) == AiEngine.api
                            ? (t == AiTask.embeddings
                                ? (s.api.embeddingModel.isEmpty
                                    ? (str.isEnglish ? '$provider · configure embedding model in API Provider' : '$provider · ustaw model embeddingów w Dostawcy API')
                                    : '$provider · ${s.api.embeddingModel}')
                                : (s.api.model.isEmpty
                                    ? (str.isEnglish ? '$provider · configure model' : '$provider · skonfiguruj model')
                                    : '$provider · ${s.api.model}'))
                            : str.localDetail(t),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(children: [
            _toggle(str.privacyMaskTitle,
                str.privacyMaskSub,
                s.privacy.maskPersonalData, (v) => ctrl.setPrivacy(s.privacy.copyWith(mask: v))),
            const Divider(),
            _toggle(str.privacyConsentTitle,
                str.isEnglish
                    ? 'With provider name: “Receipt photo will be sent to $provider”.'
                    : 'Z nazwą dostawcy: „Zdjęcie paragonu zostanie wysłane do $provider”.',
                s.privacy.askBeforeSendingImage, (v) => ctrl.setPrivacy(s.privacy.copyWith(ask: v))),
            const Divider(),
            _toggle(str.privacyRetryTitle,
                str.privacyRetrySub,
                s.privacy.suggestApiRetry, (v) => ctrl.setPrivacy(s.privacy.copyWith(retry: v))),
            const Divider(),
            _toggle(str.privacyTokensTitle,
                str.isEnglish
                    ? 'This month: ${s.monthlyTokens} tokens via API.'
                    : 'W tym miesiącu: ${s.monthlyTokens} tokenów przez API.',
                s.privacy.showTokenCounter, (v) => ctrl.setPrivacy(s.privacy.copyWith(tokens: v))),
          ]),
        ),
        const SizedBox(height: 16),
        const _AboutCard(),
      ],
    );
  }

  static String _gb(int bytes) => '${(bytes / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

  Widget _link(String title, String trailing, VoidCallback onTap, {IconData? icon}) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: icon != null ? Icon(icon, color: AppColors.green, size: 22) : null,
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trailing.isNotEmpty) Text(trailing, style: const TextStyle(color: AppColors.muted)),
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
          final str = ref.read(appStringsProvider);
          showError(context, str.notifPermissionDenied);
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
    final str = ref.watch(appStringsProvider);
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(str.notifications, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(str.notifSubsTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(str.notifSubsSub),
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
              decoration: InputDecoration(labelText: str.notifRemind),
              items: [
                DropdownMenuItem(value: 0, child: Text(str.onPaymentDay)),
                DropdownMenuItem(value: 1, child: Text(str.daysBefore(1))),
                DropdownMenuItem(value: 2, child: Text(str.daysBefore(2))),
                DropdownMenuItem(value: 3, child: Text(str.daysBefore(3))),
              ],
              onChanged: (v) => v == null ? null : _set(days: v),
            ),
          ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(str.notifBudgetTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(str.notifBudgetSub),
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
    final str = ref.watch(appStringsProvider);
    final lockEnabled = ref.watch(biometricLockProvider);
    final notifier = ref.read(biometricLockProvider.notifier);

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(str.security, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(str.biometricLock, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(str.biometricLockSub),
          value: lockEnabled,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.green,
          onChanged: (val) async {
            final ok = await notifier.setEnabled(val);
            if (!ok && context.mounted) {
              showError(context, str.biometricAuthFailed);
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
    final str = ref.read(appStringsProvider);
    try {
      final client = ref.read(appUpdateClientProvider);
      final update = await client.checkForUpdate();
      if (!mounted) return;
      if (update != null && update.hasUpdate) {
        showUpdateDialog(context, update);
      } else if (update != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${str.updatesUpToDate} ($appVersion).'),
            backgroundColor: AppColors.green,
          ),
        );
      } else {
        showError(context, str.githubError);
      }
    } catch (e) {
      if (mounted) showError(context, str.updateError(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(appStringsProvider);
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: Text(str.updates, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          subtitle: Text('${str.versionLabel} $appVersion · ${str.updatesSub}'),
          trailing: _checking
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded, color: AppColors.green),
          onTap: _checking ? null : _check,
        ),
        const Divider(),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: Text(str.github, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          subtitle: const Text(githubRepo),
          trailing: const Icon(Icons.open_in_new_rounded, color: AppColors.muted, size: 20),
          onTap: () => launchUrl(Uri.parse('https://github.com/$githubRepo'), mode: LaunchMode.externalApplication),
        ),
      ]),
    );
  }
}

class _LanguageCard extends ConsumerWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final str = ref.watch(appStringsProvider);
    final currentLang = ref.watch(appLanguageProvider);
    final notifier = ref.read(appLanguageProvider.notifier);

    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.language_rounded, color: AppColors.green, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(str.language, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(str.languageDesc, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppLanguage>(
              segments: [
                ButtonSegment(value: AppLanguage.system, label: Text(str.languageSystem)),
                const ButtonSegment(value: AppLanguage.pl, label: Text('Polski')),
                const ButtonSegment(value: AppLanguage.en, label: Text('English')),
              ],
              selected: {currentLang},
              onSelectionChanged: (set) {
                if (set.isNotEmpty) notifier.setLanguage(set.first);
              },
            ),
          ),
        ],
      ),
    );
  }
}


