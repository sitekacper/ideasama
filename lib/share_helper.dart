import 'share_helper_web.dart' if (dart.library.io) 'share_helper_io.dart' as impl;

Future<void> shareTextAsAttachment(String title, String body) => impl.shareTextAsAttachment(title, body);