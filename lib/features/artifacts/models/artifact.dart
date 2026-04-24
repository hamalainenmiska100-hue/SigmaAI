class Artifact {
  final String id;
  final String filename;
  final String fileType;
  final String language;
  final String content;
  final String status;
  final DateTime createdAt;

  const Artifact({
    required this.id,
    required this.filename,
    required this.fileType,
    required this.language,
    required this.content,
    required this.status,
    required this.createdAt,
  });

  bool get isMarkdown {
    return fileType == 'markdown' || filename.toLowerCase().endsWith('.md');
  }

  bool get isCompleted => status == 'completed';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'fileType': fileType,
      'language': language,
      'content': content,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Artifact.fromJson(Map<String, dynamic> json) {
    return Artifact(
      id: json['id'] as String,
      filename: json['filename'] as String,
      fileType: json['fileType'] as String,
      language: json['language'] as String,
      content: json['content'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
