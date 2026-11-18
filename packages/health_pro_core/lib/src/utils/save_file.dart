import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Hands [bytes] to the person as a file called [name]: a download in a
/// browser, the share sheet on a phone (to save it to Files or Drive, or
/// send it on).
Future<void> saveFile(BuildContext context, Uint8List bytes, {required String name, required String mimeType}) async {
  final file = XFile.fromData(bytes, mimeType: mimeType, name: name);
  if (kIsWeb) {
    await file.saveTo(name);
    return;
  }
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: [file],
    fileNameOverrides: [name],
    sharePositionOrigin: box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}
