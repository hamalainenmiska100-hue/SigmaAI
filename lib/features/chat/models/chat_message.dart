class ChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final List<String> imageData;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.imageData = const [],
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'imageData': imageData,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawImageData = json['imageData'];
    final images = rawImageData is List
        ? rawImageData.map((e) => e.toString()).where((e) => e.isNotEmpty).take(3).toList()
        : rawImageData is String && rawImageData.isNotEmpty
            ? [rawImageData]
            : <String>[];
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: (json['content'] ?? '').toString(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      imageData: images,
    );
  }
}
