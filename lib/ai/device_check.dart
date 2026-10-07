import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter_edge_ai_diagnostics/flutter_edge_ai_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'local_models.dart';

enum OsFamily { ios, android, macos, other }

class DeviceProfile {
  const DeviceProfile({
    required this.os,
    this.name = '',
    this.totalRamBytes,
    this.availableRamBytes,
    this.freeDiskBytes,
    this.appHeadroomBytes,
  });

  final OsFamily os;
  final String name;
  final int? totalRamBytes;
  final int? availableRamBytes;
  final int? freeDiskBytes;

  /// iOS only: memory this app may still allocate before jetsam kills it
  /// (os_proc_available_memory). The only exact limit any platform gives us.
  final int? appHeadroomBytes;
}

enum Fit {
  /// Comfortable: the whole model fits in RAM with room to spare.
  good,

  /// Runs, but not entirely in RAM: weights are memory-mapped, so the OS keeps
  /// part of them on flash and re-reads pages on demand. Slower, and an app
  /// switch can evict it.
  tight,

  /// Even the working memory that cannot be paged out (KV cache, compute and
  /// vision buffers) doesn't fit, or the publisher's RAM floor isn't met.
  tooHeavy,

  /// Memory is fine but the download won't fit on storage.
  noDisk,

  /// RAM couldn't be read.
  unknown,
}

class ModelFit {
  const ModelFit({
    required this.fit,
    required this.requiredRamBytes,
    required this.usableRamBytes,
    required this.headline,
    required this.detail,
  });

  final Fit fit;
  final int requiredRamBytes;
  final int? usableRamBytes;
  final String headline;
  final String detail;

  bool get canRun => fit == Fit.good || fit == Fit.tight;
}

/// Share of physical RAM one app can realistically hold before the OS kills it.
/// iOS jetsam is strict: roughly 40-50% of RAM by default, more once the app
/// carries the increased-memory-limit entitlement, which ios/Runner/
/// Runner.entitlements does. Android and macOS are more generous. These are
/// conservative rules of thumb, not guarantees.
double usableRamFraction(OsFamily os) => switch (os) {
      OsFamily.ios => 0.55,
      OsFamily.android => 0.55,
      OsFamily.macos => 0.60,
      OsFamily.other => 0.50,
    };

/// Memory that can't be paged out while the model runs: KV cache for the
/// context window, compute buffers (max(256 MB, 8% of weights)) and the vision
/// encoder's buffers. Weights are mmapped (clean file pages), so they are not
/// part of this; see [estimateRequiredRam].
int estimateAnonymousRam(LocalModel m) {
  final kv = m.kvBytesPerToken * m.contextTokens;
  final compute = (m.totalBytes * 0.08).round() < 256000000 ? 256000000 : (m.totalBytes * 0.08).round();
  return kv + compute + m.extraRamBytes;
}

/// RAM needed to hold everything resident: weights + [estimateAnonymousRam].
/// This is what "fits comfortably" means; less than this still runs, slower.
int estimateRequiredRam(LocalModel m) => m.totalBytes + estimateAnonymousRam(m);

String _gb(num bytes) => '${(bytes / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

/// [alreadyDownloadedBytes] is subtracted from the disk requirement so a
/// half-finished download is not penalised.
ModelFit assessModel(LocalModel m, DeviceProfile d, {int alreadyDownloadedBytes = 0, bool isEnglish = false}) {
  final required = estimateRequiredRam(m);
  final total = d.totalRamBytes;
  if (total == null) {
    return ModelFit(
      fit: Fit.unknown,
      requiredRamBytes: required,
      usableRamBytes: null,
      headline: isEnglish ? 'Compatibility unknown' : 'Nie wiem, czy pójdzie',
      detail: isEnglish
          ? 'Could not read RAM. Model requires ~${_gb(required)} memory.'
          : 'Nie udało się odczytać RAM. Model potrzebuje ok. ${_gb(required)} pamięci.',
    );
  }
  // On iOS the OS tells us the exact headroom; elsewhere use a share of RAM.
  final headroom = d.appHeadroomBytes;
  final usable = (headroom != null && headroom > 0)
      ? headroom
      : (total * usableRamFraction(d.os)).round();
  // Floor from the model publisher's own guidance.
  if (m.recommendedTotalRamBytes > 0 && total < m.recommendedTotalRamBytes * 0.95) {
    return ModelFit(
      fit: Fit.tooHeavy,
      requiredRamBytes: required,
      usableRamBytes: usable,
      headline: isEnglish ? 'Too heavy for this device' : 'Za ciężki dla tego telefonu',
      detail: isEnglish
          ? 'Recommended minimum is ${_gb(m.recommendedTotalRamBytes)} RAM, device has ${_gb(total)}.'
          : 'Zalecane minimum to ${_gb(m.recommendedTotalRamBytes)} RAM, telefon ma ${_gb(total)}.',
    );
  }

  final needDisk = ((m.totalBytes - alreadyDownloadedBytes) * 1.05).round();
  final free = d.freeDiskBytes;
  if (free != null && needDisk > 0 && needDisk > free) {
    return ModelFit(
      fit: Fit.noDisk,
      requiredRamBytes: required,
      usableRamBytes: usable,
      headline: isEnglish ? 'Not enough storage' : 'Za mało miejsca',
      detail: isEnglish
          ? 'Requires ${_gb(needDisk)} free space, available ${_gb(free)}.'
          : 'Potrzeba ${_gb(needDisk)} wolnego miejsca, jest ${_gb(free)}.',
    );
  }

  final ratio = required / usable;
  final anon = estimateAnonymousRam(m);
  final need = isEnglish
      ? 'Requires ~${_gb(required)} RAM, app can use ~${_gb(usable)}.'
      : 'Potrzebuje ok. ${_gb(required)} RAM, aplikacja może użyć ok. ${_gb(usable)}.';
  if (ratio > 0.85) {
    if (anon > usable * 0.7) {
      return ModelFit(
        fit: Fit.tooHeavy,
        requiredRamBytes: required,
        usableRamBytes: usable,
        headline: isEnglish ? 'Too heavy for this device' : 'Za ciężki dla tego telefonu',
        detail: isEnglish
            ? '$need Working memory alone (${_gb(anon)}) will not fit. System would terminate app.'
            : '$need Nawet pamięć robocza (${_gb(anon)}) nie zmieści się. System zamknąłby aplikację.',
      );
    }
    return ModelFit(
      fit: Fit.tight,
      requiredRamBytes: required,
      usableRamBytes: usable,
      headline: isEnglish ? 'Tight fit' : 'Pójdzie na styk',
      detail: isEnglish
          ? '$need Model will not fully fit in RAM, so it will be slower. Close other apps before scanning.'
          : '$need Model nie zmieści się w całości w RAM, więc będzie wolniejszy. Zamknij inne aplikacje przed skanowaniem.',
    );
  }
  final avail = d.availableRamBytes;
  final lowFree = avail != null && avail < required;
  return ModelFit(
    fit: Fit.good,
    requiredRamBytes: required,
    usableRamBytes: usable,
    headline: isEnglish ? 'Runs smoothly' : 'Pójdzie płynnie',
    detail: lowFree
        ? (isEnglish
            ? '$need High memory in use right now, system will reclaim on demand.'
            : '$need Teraz jest zajęte dużo pamięci, system zwolni ją na żądanie.')
        : need,
  );
}

/// Picks the best model per role for this device: prefers comfortable fits,
/// then the largest (best quality) among them.
String? recommendedModelId(ModelRole role, DeviceProfile d) {
  LocalModel? best;
  var bestScore = -1;
  for (final m in modelCatalog.where((m) => m.role == role)) {
    final f = assessModel(m, d);
    final score = switch (f.fit) {
      Fit.good => 2,
      Fit.tight => 1,
      _ => 0,
    };
    if (score == 0) continue;
    if (best == null || score > bestScore || (score == bestScore && m.totalBytes > best.totalBytes)) {
      best = m;
      bestScore = score;
    }
  }
  return best?.id;
}

Future<DeviceProfile> detectDevice() async {
  final info = DeviceInfoPlugin();
  const mb = 1024 * 1024;
  try {
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      return DeviceProfile(
        os: OsFamily.ios,
        name: i.utsname.machine,
        totalRamBytes: i.physicalRamSize * mb,
        availableRamBytes: i.availableRamSize * mb,
        freeDiskBytes: await _freeDisk(),
        appHeadroomBytes: await _iosHeadroom(),
      );
    }
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return DeviceProfile(
        os: OsFamily.android,
        name: '${a.manufacturer} ${a.model}',
        totalRamBytes: a.physicalRamSize * mb,
        availableRamBytes: a.availableRamSize * mb,
        freeDiskBytes: await _freeDisk(),
      );
    }
    if (Platform.isMacOS) {
      final m = await info.macOsInfo;
      return DeviceProfile(
        os: OsFamily.macos,
        name: m.model,
        totalRamBytes: m.memorySize,
        freeDiskBytes: await _freeDisk(),
      );
    }
  } catch (_) {}
  return const DeviceProfile(os: OsFamily.other);
}

Future<int?> _iosHeadroom() async {
  try {
    if (!FlutterEdgeAiDiagnostics.isSupported) return null;
    final snap = await FlutterEdgeAiDiagnostics.memorySnapshot();
    final avail = snap.availableBytes; // null/0 on the simulator: no limit applies
    return (avail != null && avail > 0) ? avail : null;
  } catch (_) {
    return null;
  }
}

Future<int?> _freeDisk() async {
  try {
    if (Platform.isIOS || Platform.isAndroid) {
      final mb = await DiskSpacePlus().getFreeDiskSpace;
      if (mb != null) return (mb * 1024 * 1024).round();
    }
    // macOS (no plugin): ask df about the app's own volume.
    final dir = (await getApplicationSupportDirectory()).path;
    final out = await Process.run('df', ['-k', dir]);
    final lines = (out.stdout as String).trim().split('\n');
    if (lines.length >= 2) {
      final cols = lines.last.split(RegExp(r'\s+'));
      final avail = int.tryParse(cols[3]);
      if (avail != null) return avail * 1024;
    }
  } catch (_) {}
  return null;
}

final deviceProfileProvider = FutureProvider<DeviceProfile>((ref) => detectDevice());
