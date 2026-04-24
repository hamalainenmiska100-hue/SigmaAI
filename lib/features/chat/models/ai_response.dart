import '../../artifacts/models/artifact.dart';

class AiResponse {
  final String type;
  final String? content;
  final String? message;
  final Artifact? artifact;

  const AiResponse({
    required this.type,
    this.content,
    this.message,
    this.artifact,
  });
}
