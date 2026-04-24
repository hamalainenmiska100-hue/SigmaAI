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
            AppConfig.proxyChatUri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
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
        throw AiException.server();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw AiException.badResponse();
      }

      final type = decoded['type'];
      if (type == 'message') {
        return AiResponse(type: 'message', content: (decoded['content'] ?? '').toString());
      }

      if (type == 'artifact') {
        final artifactMap = decoded['artifact'];
        if (artifactMap is! Map<String, dynamic>) {
          throw AiException.badResponse();
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

      throw AiException.badResponse();
    } on TimeoutException {
      throw AiException.network();
    } on FormatException {
      throw AiException.badResponse();
    } on http.ClientException {
      throw AiException.network();
    }
  }
}

class AiException implements Exception {
  final bool isRateLimit;
  final String userMessage;

  AiException._({required this.isRateLimit, required this.userMessage});

  factory AiException.network() =>
      AiException._(isRateLimit: false, userMessage: 'Network issue. Check your connection and try again.');
  factory AiException.server() =>
      AiException._(isRateLimit: false, userMessage: 'Server error. Please try again in a moment.');
  factory AiException.badResponse() =>
      AiException._(isRateLimit: false, userMessage: 'Unexpected server response. Please try again.');
  factory AiException.rateLimit() =>
      AiException._(isRateLimit: true, userMessage: 'Too many requests. Please try again later.');
}
