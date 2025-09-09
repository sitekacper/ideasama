import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareTextAsAttachment(BuildContext context, String title, String body) async {
  await Share.share(body, subject: title);
}