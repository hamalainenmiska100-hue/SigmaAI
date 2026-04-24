import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/utils/file_type_utils.dart';
import '../../artifacts/models/artifact.dart';
import '../models/ai_response.dart';
import '../models/chat_message.dart';

class AiService {
  final http.Client _client;

  AiService({http.Client? client}) : _client = client ?? http.Client();

  Future<AiResponse> sendMessage({
    required String message,
    required String customInstructions,
    required List<ChatMessage> history,
  }) async {
    try {
      final trimmedHistory = history
          .take(history.length > 12 ? 12 : history.length)
          .map(
            (e) => {
              'role': e.role,
              'content': e.content,
            },
          )
          .toList();

      final response = await _client
          .post(
            Uri.parse(AppConfig.proxyChatUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': message,
              'customInstructions': customInstructions,
              'chatHistory': trimmedHistory,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 429) {
        throw AiException.rateLimit();
      }
      if (response.statusCode != 200) {
        throw AiException.generic();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw AiException.generic();
      }

      final type = decoded['type'];
      if (type == 'message') {
        return AiResponse(type: 'message', content: (decoded['content'] ?? '').toString());
      }

      if (type == 'artifact') {
        final artifactMap = decoded['artifact'];
        if (artifactMap is! Map<String, dynamic>) {
          throw AiException.generic();
        }

        var filename = FileTypeUtils.sanitizeFilename((artifactMap['filename'] ?? 'artifact.txt').toString());
        var fileType = FileTypeUtils.normalizeType((artifactMap['fileType'] ?? '').toString(), filename);
        final inferred = FileTypeUtils.inferFromFilename(filename);
        if (!filename.contains('.')) {
          filename = 'artifact.txt';
          fileType = 'text';
        }
        final language = FileTypeUtils.allowedFileTypes.contains((artifactMap['language'] ?? '').toString())
            ? (artifactMap['language'] as String)
            : inferred.language;

        return AiResponse(
          type: 'artifact',
          message: (decoded['message'] ?? '').toString(),
          artifact: Artifact(
            id: '',
            filename: filename,
            fileType: fileType,
            language: language,
            content: (artifactMap['content'] ?? '').toString(),
            status: 'completed',
            createdAt: DateTime.now(),
          ),
        );
      }

      throw AiException.generic();
    } on TimeoutException {
      throw AiException.generic();
    } on FormatException {
      throw AiException.generic();
    } on http.ClientException {
      throw AiException.generic();
    }
  }
}

class AiException implements Exception {
  final bool isRateLimit;

  AiException._(this.isRateLimit);

  factory AiException.generic() => AiException._(false);
  factory AiException.rateLimit() => AiException._(true);
}
