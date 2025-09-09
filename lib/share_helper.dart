import 'package:flutter/material.dart';
import 'share_helper_web.dart' if (dart.library.io) 'share_helper_io.dart' as impl;

Future<void> shareTextAsAttachment(BuildContext context, String title, String body) => impl.shareTextAsAttachment(context, title, body);