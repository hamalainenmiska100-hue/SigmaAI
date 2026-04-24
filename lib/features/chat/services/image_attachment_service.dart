import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

class ImageAttachmentService {
  Future<String?> pickCompressedImageDataUri() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
      compressionQuality: 70,
    );

    final bytes = result?.files.single.bytes;
    if (bytes == null || bytes.isEmpty) return null;

    final compressed = _compress(bytes);
    final encoded = base64Encode(compressed);
    return 'data:image/jpeg;base64,$encoded';
  }

  Uint8List _compress(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final resized = decoded.width > 1280 ? img.copyResize(decoded, width: 1280) : decoded;
    final jpg = img.encodeJpg(resized, quality: 72);
    return Uint8List.fromList(jpg);
  }
}
