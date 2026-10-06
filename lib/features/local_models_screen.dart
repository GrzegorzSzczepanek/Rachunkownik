import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/device_check.dart';
import '../ai/local_models.dart';
import '../core/theme.dart';
import 'widgets.dart';

String _gb(num bytes) => '${(bytes / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

class LocalModelsScreen extends ConsumerStatefulWidget {
  const LocalModelsScreen({super.key});
  @override
  ConsumerState<LocalModelsScreen> createState() => _LocalModelsState();
}

class _LocalModelsState extends ConsumerState<LocalModelsScreen> {
  bool _wifiOnly = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _wifiOnly = p.getBool('wifi_only') ?? true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(modelDownloadsProvider);
    final active = ref.watch(activeModelsProvider);
    final mgr = ref.read(modelDownloadsProvider.notifier);
    final device = ref.watch(deviceProfileProvider).value ?? const DeviceProfile(os: OsFamily.other);
    final deviceLoaded = ref.watch(deviceProfileProvider).hasValue;
    final installed = modelCatalog
        .where((m) => st[m.id]?.state == ModelState.installed)
        .fold(0, (a, m) => a + m.totalBytes);
    return Scaffold(
      appBar: AppBar(title: const Text('Modele lokalne')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          SectionCard(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Eyebrow('TO URZĄDZENIE'),
                Flexible(
                  child: Text(device.name,
                      overflow: TextOverflow.ellipsis,
                      style: mono(size: 13, weight: FontWeight.w400, color: AppColors.muted)),
                ),
              ]),
              const SizedBox(height: 8),
              if (!deviceLoaded)
                const Text('Sprawdzam parametry…', style: TextStyle(color: AppColors.muted))
              else ...[
                _spec('RAM', device.totalRamBytes == null ? 'nieznany' : _gb(device.totalRamBytes!),
                    device.totalRamBytes == null
                        ? null
                        : 'dla modelu ok. ${_gb(device.totalRamBytes! * usableRamFraction(device.os))}'),
                _spec('Wolne miejsce', device.freeDiskBytes == null ? 'nieznane' : _gb(device.freeDiskBytes!),
                    'modele ${_gb(installed)}'),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pobieraj tylko przez Wi-Fi', style: TextStyle(fontWeight: FontWeight.w600)),
                value: _wifiOnly,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.green,
                onChanged: (v) async {
                  setState(() => _wifiOnly = v);
                  (await SharedPreferences.getInstance()).setBool('wifi_only', v);
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(children: [
              for (final m in modelCatalog)
                _row(m, st[m.id] ?? ModelStatus.none, mgr, device, deviceLoaded, recommendedModelId(m.role, device) == m.id,
                    active[m.role] == m.id),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(16)),
            child: const Text(
                '⚠ Modele powyżej 1 GB zużywają dużo baterii i RAM. Aplikacja zwalnia model z pamięci, gdy trafi w tło.\n\n'
                'Werdykty „pójdzie / na styk” to szacunek z RAM i rozmiaru modelu, nie pomiar. '
                'Pierwszy odczyt po wczytaniu modelu trwa dłużej.',
                style: TextStyle(color: AppColors.amberInk, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _spec(String k, String v, String? note) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: AppColors.muted))),
          Text(v, style: mono(size: 14)),
          if (note != null) ...[
            const SizedBox(width: 10),
            Expanded(child: Text(note, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          ],
        ]),
      );

  Future<void> _confirmDownload(LocalModel m, ModelFit fit, ModelDownloads mgr) async {
    if (fit.fit == Fit.tooHeavy || fit.fit == Fit.noDisk) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(fit.headline),
          content: Text('${fit.detail}\n\nPobrać mimo to?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pobierz mimo to')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await mgr.download(m);
  }

  Widget _fitBadge(ModelFit f) {
    final (bg, fg, icon) = switch (f.fit) {
      Fit.good => (AppColors.greenSoft, AppColors.green, '✓'),
      Fit.tight => (AppColors.amberSoft, AppColors.amberInk, '⚠'),
      Fit.tooHeavy || Fit.noDisk => (const Color(0xFFF8E1DC), const Color(0xFF9A2A14), '✗'),
      Fit.unknown => (AppColors.chip, AppColors.muted, '?'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$icon ${f.headline}. ', style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
          TextSpan(text: f.detail, style: TextStyle(color: fg, fontSize: 13)),
        ])),
      ),
    );
  }

  Widget _row(LocalModel m, ModelStatus s, ModelDownloads mgr, DeviceProfile device,
      bool deviceLoaded, bool recommended, bool isActive) {
    final fit = assessModel(m, device, alreadyDownloadedBytes: s.received);
    final downloading = s.state == ModelState.downloading;
    final frac = m.totalBytes == 0 ? 0.0 : s.received / m.totalBytes;
    Widget action;
    switch (s.state) {
      case ModelState.installed:
        action = OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(52, 48), padding: EdgeInsets.zero),
            onPressed: () => mgr.delete(m),
            child: const Icon(Icons.delete_outline));
      case ModelState.downloading:
        action = OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(52, 48), padding: EdgeInsets.zero),
            onPressed: () => mgr.pause(m.id),
            child: const Icon(Icons.pause));
      case ModelState.paused || ModelState.failed:
        action = FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => _confirmDownload(m, fit, mgr),
            child: const Text('Wznów'));
      case ModelState.notInstalled:
        action = FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => _confirmDownload(m, fit, mgr),
            child: const Text('Pobierz'));
    }
    final eta = downloading && s.bytesPerSec > 0
        ? 'jeszcze ok. ${((m.totalBytes - s.received) / s.bytesPerSec / 60).ceil()} min'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(m.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                s.state == ModelState.installed
                    ? Pill(isActive ? 'Aktywny' : 'Zainstalowany',
                        bg: AppColors.greenSoft, fg: AppColors.green)
                    : Pill(m.role.label),
                if (recommended && s.state != ModelState.installed)
                  const Pill('Polecany', bg: AppColors.ink, fg: Colors.white),
              ]),
              const SizedBox(height: 4),
              Text('${m.description} · ~${_gb(m.totalBytes)}', style: const TextStyle(color: AppColors.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          action,
        ]),
        if (downloading || s.state == ModelState.paused) ...[
          const SizedBox(height: 10),
          ProgressBar(frac),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${(frac * 100).round()}% · ${_gb(s.received)} z ${_gb(m.totalBytes)}',
                style: mono(size: 12, weight: FontWeight.w400, color: AppColors.muted)),
            Text(s.state == ModelState.paused ? 'wstrzymano' : eta,
                style: mono(size: 12, weight: FontWeight.w400, color: AppColors.muted)),
          ]),
        ],
        if (s.state == ModelState.installed && !isActive)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: () => mgr.setActive(m), child: Text('Użyj do: ${m.role.label.toLowerCase()}')),
          ),
        if (deviceLoaded && s.state != ModelState.installed) _fitBadge(fit),
        if (s.state == ModelState.failed && s.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(s.error!, style: const TextStyle(color: AppColors.amberInk))),
          ),
      ]),
    );
  }
}
