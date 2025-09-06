import 'package:share_plus/share_plus.dart';

Future<void> shareTextAsAttachment(String title, String body) async {
  // Web: nie ma dostępu do systemu plików, więc udostępniamy treść bezpośrednio.
  await Share.share(body, subject: title);
}