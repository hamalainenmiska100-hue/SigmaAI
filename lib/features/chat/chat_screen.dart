import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/widgets/empty_state.dart';
import '../artifacts/artifact_viewer_screen.dart';
import '../artifacts/models/artifact.dart';
import '../artifacts/services/artifact_file_service.dart';
import '../artifacts/services/artifact_local_store.dart';
import '../settings/services/settings_service.dart';
import 'models/chat_message.dart';
import 'services/ai_service.dart';
import 'services/chat_local_store.dart';
import 'widgets/chat_artifact_card.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_loading_area.dart';
import 'widgets/message_input.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final _uuid = const Uuid();
  final _chatStore = ChatLocalStore(LocalStorageService());
  final _settingsService = SettingsService(LocalStorageService());
  final _aiService = AiService();
  final _artifactStore = ArtifactLocalStore(LocalStorageService());
  final _artifactFileService = ArtifactFileService();

  List<ChatMessage> _messages = [];
  List<Artifact> _artifacts = [];
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final loadedMessages = await _chatStore.loadMessages();
    final loadedArtifacts = await _artifactStore.loadArtifacts();
    if (!mounted) return;
    setState(() {
      _messages = loadedMessages;
      _artifacts = loadedArtifacts;
    });
    _scrollToBottom(jump: true);
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isGenerating) return;
    if (trimmed.length > AppConfig.maxMessageLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
      return;
    }

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages = [..._messages, userMessage];
      _isGenerating = true;
    });
    await _chatStore.saveMessages(_messages);
    _scrollToBottom();

    final customInstructions = await _settingsService.loadCustomInstructions();

    try {
      final response = await _aiService.sendMessage(
        message: trimmed,
        customInstructions: customInstructions,
        history: _messages,
      );

      Artifact? createdArtifact;
      ChatMessage? assistantMessage;

      if (response.type == 'message') {
        assistantMessage = ChatMessage(
          id: _uuid.v4(),
          role: 'assistant',
          content: response.content ?? '',
          createdAt: DateTime.now(),
        );
      } else if (response.type == 'artifact' && response.artifact != null) {
        createdArtifact = Artifact(
          id: _uuid.v4(),
          filename: response.artifact!.filename,
          fileType: response.artifact!.fileType,
          language: response.artifact!.language,
          content: response.artifact!.content,
          status: response.artifact!.status,
          createdAt: DateTime.now(),
        );

        assistantMessage = ChatMessage(
          id: _uuid.v4(),
          role: 'assistant',
          content: (response.message?.trim().isNotEmpty ?? false)
              ? response.message!.trim()
              : 'Artifact ready',
          createdAt: DateTime.now(),
          artifactId: createdArtifact.id,
        );
      }

      if (assistantMessage != null) {
        _messages = [..._messages, assistantMessage];
      }
      if (createdArtifact != null) {
        _artifacts = [..._artifacts, createdArtifact];
        await _artifactStore.saveArtifacts(_artifacts);
      }

      await _chatStore.saveMessages(_messages);
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
      });
      _scrollToBottom();
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.isRateLimit
              ? 'Too many requests. Please try again later.'
              : 'Something went wrong. Please try again.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    }
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (jump) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Artifact? _artifactForMessage(ChatMessage message) {
    if (message.artifactId == null) return null;
    for (final a in _artifacts) {
      if (a.id == message.artifactId) return a;
    }
    return null;
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text('This will remove the current chat history from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _messages = []);
      await _chatStore.clear();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SigmaAI'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              onPressed: _isGenerating ? null : _clearChat,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const EmptyState(text: 'Ask anything.')
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final artifact = _artifactForMessage(message);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ChatBubble(content: message.content, isUser: message.isUser),
                          if (artifact != null)
                            ChatArtifactCard(
                              artifact: artifact,
                              onOpen: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ArtifactViewerScreen(artifact: artifact),
                                  ),
                                );
                              },
                              onCopy: () async {
                                await _artifactFileService.copy(artifact);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Copied')));
                              },
                              onShare: () async {
                                try {
                                  await _artifactFileService.share(artifact);
                                } catch (_) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Could not share artifact')),
                                  );
                                }
                              },
                            ),
                        ],
                      );
                    },
                  ),
          ),
          ChatLoadingArea(isLoading: _isGenerating),
          MessageInput(enabled: !_isGenerating, onSend: _sendMessage),
        ],
      ),
    );
  }
}
