import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

String _sanitizeFileName(String input) {
  var s = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (s.length > 50) s = s.substring(0, 50);
  return s;
}

Future<void> shareTextAsAttachment(String title, String body) async {
  try {
    final dir = await getTemporaryDirectory();
    final base = (title.isEmpty ? 'note' : title).trim();
    final safe = _sanitizeFileName(base).isEmpty ? 'note' : _sanitizeFileName(base);
    final filePath = '${dir.path}${Platform.pathSeparator}$safe.txt';
    final file = File(filePath);
    await file.writeAsString(body);
    await Share.shareXFiles([XFile(file.path)], subject: title.isEmpty ? 'Note' : title);
  } catch (_) {
    await Share.share(body, subject: title);
  }
}