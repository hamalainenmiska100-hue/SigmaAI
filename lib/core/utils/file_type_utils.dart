class FileTypeInfo {
  final String fileType;
  final String language;

  const FileTypeInfo(this.fileType, this.language);
}

class FileTypeUtils {
  static const Map<String, FileTypeInfo> _byExtension = {
    '.md': FileTypeInfo('markdown', 'markdown'),
    '.txt': FileTypeInfo('text', 'text'),
    '.json': FileTypeInfo('json', 'json'),
    '.html': FileTypeInfo('html', 'html'),
    '.css': FileTypeInfo('css', 'css'),
    '.js': FileTypeInfo('javascript', 'javascript'),
    '.ts': FileTypeInfo('typescript', 'typescript'),
    '.py': FileTypeInfo('python', 'python'),
    '.csv': FileTypeInfo('csv', 'csv'),
  };

  static const Set<String> allowedFileTypes = {
    'markdown',
    'text',
    'json',
    'html',
    'css',
    'javascript',
    'typescript',
    'python',
    'csv',
  };

  static String sanitizeFilename(String input) {
    final sanitized = input
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
    if (sanitized.isEmpty || sanitized.contains('..')) {
      return 'artifact.txt';
    }
    return sanitized;
  }

  static FileTypeInfo inferFromFilename(String filename) {
    final lower = filename.toLowerCase();
    for (final entry in _byExtension.entries) {
      if (lower.endsWith(entry.key)) return entry.value;
    }
    return const FileTypeInfo('text', 'text');
  }

  static String normalizeType(String fileType, String filename) {
    if (allowedFileTypes.contains(fileType)) return fileType;
    return inferFromFilename(filename).fileType;
  }
}
