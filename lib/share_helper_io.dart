import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

String _sanitizeFileName(String input) {
  var s = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (s.length > 50) s = s.substring(0, 50);
  return s;
}

Future<void> shareTextAsAttachment(BuildContext context, String title, String body) async {
  // Wyznacz domyślny prostokąt kotwiczenia dla iPad (UIPopover)
  Rect origin = const Rect.fromLTWH(0, 0, 1, 1);
  try {
    final obj = context.findRenderObject();
    if (obj is RenderBox) {
      final position = obj.localToGlobal(Offset.zero);
      origin = Rect.fromLTWH(position.dx, position.dy, obj.size.width, obj.size.height);
    }
  } catch (_) {}

  try {
    final dir = await getTemporaryDirectory();
    final base = (title.isEmpty ? 'note' : title).trim();
    final safe = _sanitizeFileName(base).isEmpty ? 'note' : _sanitizeFileName(base);
    final filePath = '${dir.path}${Platform.pathSeparator}$safe.txt';
    final file = File(filePath);
    await file.writeAsString(body);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: title.isEmpty ? 'Note' : title,
      sharePositionOrigin: origin,
    );
  } catch (_) {
    await Share.share(
      body,
      subject: title,
      sharePositionOrigin: origin,
    );
  }
}