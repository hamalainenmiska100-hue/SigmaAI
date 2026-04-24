import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/file_type_utils.dart';
import '../models/artifact.dart';

class ArtifactFileService {
  Future<void> copy(Artifact artifact) async {
    await Clipboard.setData(ClipboardData(text: artifact.content));
  }

  Future<void> share(Artifact artifact) async {
    final tempDir = await getTemporaryDirectory();
    final safeFilename = FileTypeUtils.sanitizeFilename(artifact.filename);
    final file = File('${tempDir.path}/$safeFilename');
    await file.writeAsString(artifact.content);
    await Share.shareXFiles([XFile(file.path)], text: artifact.filename);
  }
}
