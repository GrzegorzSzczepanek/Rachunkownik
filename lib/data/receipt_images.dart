import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the photo of a receipt in the app's private storage so it can be
/// shown later (warranty, returns). Failures never block saving the receipt.
Future<String?> saveReceiptImage(Uint8List bytes) async {
  try {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'receipts'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> readReceiptImage(String? path) async {
  if (path == null) return null;
  try {
    final f = File(path);
    return await f.exists() ? await f.readAsBytes() : null;
  } catch (_) {
    return null;
  }
}

Future<void> deleteReceiptImage(String? path) async {
  if (path == null) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
