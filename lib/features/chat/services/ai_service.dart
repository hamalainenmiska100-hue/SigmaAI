import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../models/chat_message.dart';

class AiService {
  http.Client _client;

  AiService({http.Client? client}) : _client = client ?? http.Client();

  void cancelActiveRequest() {
    _client.close();
    _client = http.Client();
  }

  Stream<String> streamMessage({
    required String message,
    required List<ChatMessage> history,
    required String languageTag,
    required String systemMode,
    String? imageData,
  }) async* {
    final trimmedHistory = history
        .take(history.length > 16 ? 16 : history.length)
        .map(
          (e) => {
            'role': e.role,
            'content': e.content,
          },
        )
        .toList();

    final req = http.Request('POST', AppConfig.proxyChatUri)
      ..headers.addAll(const {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream, application/json',
      })
      ..body = jsonEncode({
        'message': message,
        'languageTag': languageTag,
        'systemMode': systemMode,
        'chatHistory': trimmedHistory,
        if (imageData != null) 'imageData': imageData,
        'stream': true,
      });

    http.StreamedResponse response;
    try {
      response = await _client.send(req).timeout(const Duration(seconds: 80));
    } on TimeoutException catch (e) {
      throw AiException.network(debugDetails: 'Timeout while calling ${AppConfig.proxyChatUri}: ${e.message}');
    } on http.ClientException catch (e) {
      throw AiException.network(debugDetails: e.message);
    }

    if (response.statusCode == 429) {
      throw AiException.rateLimit();
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AiException.server(debugDetails: body);
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      final body = await response.stream.bytesToString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      yield (decoded['content'] ?? '').toString();
      return;
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final type = map['type'];
      if (type == 'delta') {
        yield (map['delta'] ?? '').toString();
      }
    }
  }
}

class AiException implements Exception {
  final bool isRateLimit;
  final String userMessage;
  final String? debugDetails;

  AiException._({
    required this.isRateLimit,
    required this.userMessage,
    this.debugDetails,
  });

  String get displayMessage =>
      debugDetails == null || debugDetails!.isEmpty ? userMessage : '$userMessage\n$debugDetails';

  factory AiException.network({String? debugDetails}) => AiException._(
        isRateLimit: false,
        userMessage: 'Network issue. Check your connection and try again.',
        debugDetails: debugDetails,
      );
  factory AiException.server({String? debugDetails}) => AiException._(
        isRateLimit: false,
        userMessage: 'Server error. Please try again in a moment.',
        debugDetails: debugDetails,
      );
  factory AiException.rateLimit({String? debugDetails}) => AiException._(
        isRateLimit: true,
        userMessage: 'Too many requests. Please try again later.',
        debugDetails: debugDetails,
      );
}
