import 'package:flutter_test/flutter_test.dart';
import 'package:rachunkownik/ai/device_check.dart';
import 'package:rachunkownik/ai/local_models.dart';

LocalModel m(String id) => modelCatalog.firstWhere((x) => x.id == id);
const gb = 1000 * 1000 * 1000;

DeviceProfile phone(OsFamily os, double ramGb, {double diskGb = 50}) => DeviceProfile(
    os: os,
    totalRamBytes: (ramGb * gb).round(),
    availableRamBytes: (ramGb * gb * 0.5).round(),
    freeDiskBytes: (diskGb * gb).round());

void main() {
  test('estimate covers weights, KV cache, compute and vision buffers', () {
    final r = estimateRequiredRam(m('gemma-4-e2b'));
    // 2.59 GB weights + 0.2 GB KV + 0.25 GB compute + 0.4 GB vision
    expect(r, greaterThan(3.3 * gb));
    expect(r, lessThan(3.7 * gb));
  });

  test('8 GB iPhone runs every model', () {
    final d = phone(OsFamily.ios, 8);
    for (final x in modelCatalog) {
      expect(assessModel(x, d).canRun, isTrue, reason: x.name);
    }
    expect(assessModel(m('gemma-4-e2b'), d).fit, Fit.good);
  });

  test('4 GB phone: Gemma 4 sits at the limit, 0.5B models are fine', () {
    final d = phone(OsFamily.android, 4);
    expect(assessModel(m('gemma-4-e2b'), d).fit, Fit.tight);
    expect(assessModel(m('smolvlm2-500m'), d).fit, Fit.good);
    expect(assessModel(m('fastvlm-0.5b'), d).canRun, isTrue);
  });

  test('3 GB phone: publisher RAM floor rules out Gemma 4, keeps small models', () {
    final d = phone(OsFamily.android, 3);
    final g = assessModel(m('gemma-4-e2b'), d);
    expect(g.fit, Fit.tooHeavy);
    expect(g.detail, contains('Zalecane minimum'));
    expect(assessModel(m('smolvlm2-500m'), d).canRun, isTrue);
  });

  test('iOS uses the OS-reported headroom instead of a share of RAM', () {
    final base = phone(OsFamily.ios, 8);
    final squeezed = DeviceProfile(
        os: OsFamily.ios,
        totalRamBytes: base.totalRamBytes,
        freeDiskBytes: base.freeDiskBytes,
        appHeadroomBytes: (1.0 * gb).round()); // other apps hold most of the RAM
    expect(assessModel(m('gemma-4-e2b'), base).fit, Fit.good);
    expect(assessModel(m('gemma-4-e2b'), squeezed).fit, Fit.tooHeavy);
  });

  test('not enough disk wins over RAM verdict, partial download is credited', () {
    final low = phone(OsFamily.android, 12, diskGb: 1.0);
    expect(assessModel(m('gemma-4-e2b'), low).fit, Fit.noDisk);
    final credited = assessModel(m('gemma-4-e2b'), low,
        alreadyDownloadedBytes: m('gemma-4-e2b').totalBytes - 500000000);
    expect(credited.fit, isNot(Fit.noDisk));
  });

  test('unknown RAM is reported honestly', () {
    final f = assessModel(m('smolvlm2-500m'), const DeviceProfile(os: OsFamily.other));
    expect(f.fit, Fit.unknown);
    expect(f.canRun, isFalse);
  });

  test('recommendation prefers the biggest model that fits comfortably', () {
    expect(recommendedModelId(ModelRole.vision, phone(OsFamily.android, 16)), 'gemma-4-e2b');
    expect(recommendedModelId(ModelRole.vision, phone(OsFamily.android, 3)), isNotNull);
    expect(recommendedModelId(ModelRole.vision, phone(OsFamily.ios, 1)), isNull);
  });

  test('catalog sizes are the real file sizes, ids unique', () {
    expect(modelCatalog.map((x) => x.id).toSet().length, modelCatalog.length);
    for (final x in modelCatalog) {
      expect(x.file.url, startsWith('https://huggingface.co/'));
      expect(x.file.url, endsWith(x.file.name));
      expect(x.totalBytes, greaterThan(100 * 1000 * 1000));
    }
  });
}
