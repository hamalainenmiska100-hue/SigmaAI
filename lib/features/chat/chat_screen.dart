import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/widgets/empty_state.dart';
import '../settings/services/settings_service.dart';
import 'models/chat_message.dart';
import 'models/chat_thread.dart';
import 'services/ai_service.dart';
import 'services/chat_history_store.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/message_input.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final _uuid = const Uuid();
  final _chatStore = ChatHistoryStore(LocalStorageService());
  final _settingsService = SettingsService(LocalStorageService());
  final _aiService = AiService();

  List<ChatMessage> _messages = [];
  List<ChatThread> _threads = [];
  ChatThread? _activeThread;
  bool _isGenerating = false;
  bool _shouldAutoScroll = true;
  AiProgressPhase _progressPhase = AiProgressPhase.thinking;
  StreamSubscription<AiStreamEvent>? _activeStream;
  Completer<void>? _generationCompleter;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollChanged);
    _loadInitialData();
  }

  void _handleScrollChanged() {
    if (!_scrollController.hasClients) return;
    final distanceToBottom = _scrollController.position.maxScrollExtent - _scrollController.offset;
    final nextShouldAutoScroll = distanceToBottom <= 120;
    if (nextShouldAutoScroll != _shouldAutoScroll) {
      setState(() => _shouldAutoScroll = nextShouldAutoScroll);
    }
  }

  Future<void> _loadInitialData() async {
    final loadedThreads = await _chatStore.loadThreads();
    ChatThread active;
    if (loadedThreads.isEmpty) {
      active = ChatThread(id: _uuid.v4(), title: 'New chat', updatedAt: DateTime.now());
      await _chatStore.saveThreads([active]);
    } else {
      active = loadedThreads.first;
    }
    final loadedMessages = await _chatStore.loadMessages(active.id);
    if (!mounted) return;
    setState(() {
      _threads = loadedThreads.isEmpty ? [active] : loadedThreads;
      _activeThread = active;
      _messages = loadedMessages;
    });
    _scrollToBottom(jump: true);
  }

  Future<void> _sendMessage(String text, {List<String> imageData = const []}) async {
    final trimmed = text.trim();
    final normalizedImageData = imageData.map((e) => e.trim()).where((e) => e.isNotEmpty).take(3).toList();
    if ((trimmed.isEmpty && normalizedImageData.isEmpty) || _isGenerating) return;
    if (trimmed.length > AppConfig.maxMessageLength) return;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
      imageData: normalizedImageData,
    );

    final assistantId = _uuid.v4();
    var hasAssistantMessage = false;

    setState(() {
      _messages = [..._messages, userMessage];
      _isGenerating = true;
      _progressPhase = AiProgressPhase.thinking;
      _shouldAutoScroll = true;
    });
    await _persistCurrentThread(_messages, titleHint: trimmed.isNotEmpty ? trimmed : 'Image message');
    _scrollToBottom(jump: true);

    final settings = await _settingsService.loadSettings();
    final languageTag = _languageTag(settings.language);
    final systemMode = settings.tone.name;

    try {
      var streamed = '';
      final done = Completer<void>();
      _generationCompleter = done;
      final requestHistory = List<ChatMessage>.from(_messages);

      _activeStream = _aiService
          .streamMessage(
            message: trimmed,
            history: requestHistory,
            languageTag: languageTag,
            systemMode: systemMode,
            imageData: normalizedImageData,
          )
          .listen(
        (event) {
          if (!mounted) return;

          if (event.phase != null) {
            setState(() {
              _progressPhase = event.phase!;
            });
            return;
          }

          if (event.delta != null && event.delta!.isNotEmpty) {
            streamed += event.delta!;
            setState(() {
              _progressPhase = AiProgressPhase.responding;
              if (!hasAssistantMessage) {
                hasAssistantMessage = true;
                _messages = [
                  ..._messages,
                  ChatMessage(
                    id: assistantId,
                    role: 'assistant',
                    content: streamed,
                    createdAt: DateTime.now(),
                  ),
                ];
              } else {
                _messages = _messages
                    .map((m) => m.id == assistantId ? ChatMessage(id: m.id, role: m.role, content: streamed, createdAt: m.createdAt) : m)
                    .toList();
              }
            });
            _scrollToBottom();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!done.isCompleted) {
            done.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!done.isCompleted) {
            done.complete();
          }
        },
        cancelOnError: true,
      );

      await done.future;

      await _persistCurrentThread(_messages);
      if (!mounted) return;
      setState(() => _isGenerating = false);
    } on AiException catch (e) {
      debugPrint('AiException: ${e.displayMessage}');
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } catch (e, stackTrace) {
      debugPrint('Unhandled error while sending message: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
      });
    } finally {
      await _activeStream?.cancel();
      _activeStream = null;
      _generationCompleter = null;
    }
  }

  Future<void> _stopGeneration() async {
    if (!_isGenerating) return;
    _aiService.cancelActiveRequest();
    await _activeStream?.cancel();
    _activeStream = null;
    if (_generationCompleter != null && !_generationCompleter!.isCompleted) {
      _generationCompleter!.complete();
    }
    if (!mounted) return;
    setState(() {
      _isGenerating = false;
    });
    await _persistCurrentThread(_messages);
  }

  String _languageTag(AssistantLanguage language) {
    switch (language) {
      case AssistantLanguage.english:
        return '[ENGLISH]';
      case AssistantLanguage.swedish:
        return '[SWEDISH]';
      case AssistantLanguage.finnish:
        return '[FINNISH]';
    }
  }

  Future<void> _persistCurrentThread(List<ChatMessage> messages, {String? titleHint}) async {
    if (_activeThread == null) return;
    await _chatStore.saveMessages(_activeThread!.id, messages);
    final title = (titleHint?.trim().isNotEmpty ?? false)
        ? (() {
            final firstLine = titleHint!.trim().split('\n').first;
            final maxLen = firstLine.length > 28 ? 28 : firstLine.length;
            return firstLine.substring(0, maxLen);
          })()
        : _activeThread!.title;
    final updated = ChatThread(id: _activeThread!.id, title: title, updatedAt: DateTime.now());
    final nextThreads = _threads.where((t) => t.id != updated.id).toList();
    nextThreads.insert(0, updated);
    _threads = nextThreads;
    _activeThread = updated;
    await _chatStore.saveThreads(_threads);
  }

  Future<void> _createThread() async {
    if (_isGenerating) return;
    final thread = ChatThread(id: _uuid.v4(), title: 'New chat', updatedAt: DateTime.now());
    setState(() {
      _activeThread = thread;
      _threads = [thread, ..._threads];
      _messages = [];
    });
    await _chatStore.saveThreads(_threads);
    await _chatStore.saveMessages(thread.id, []);
  }

  Future<void> _switchThread(ChatThread thread) async {
    if (_isGenerating) return;
    final messages = await _chatStore.loadMessages(thread.id);
    if (!mounted) return;
    setState(() {
      _activeThread = thread;
      _messages = messages;
    });
    Navigator.of(context).maybePop();
    _scrollToBottom(jump: true);
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (!jump && !_shouldAutoScroll) return;
      if (jump) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _activeStream?.cancel();
    _aiService.cancelActiveRequest();
    _scrollController
      ..removeListener(_handleScrollChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sigma'),
        actions: [
          IconButton(
            onPressed: _isGenerating ? null : _createThread,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('Chat History')),
              for (final thread in _threads)
                ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: Text(thread.title),
                  selected: thread.id == _activeThread?.id,
                  onTap: _isGenerating ? null : () => _switchThread(thread),
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const EmptyState(text: 'idk ask anything gng')
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return ChatBubble(
                        content: message.content,
                        isUser: message.isUser,
                        imageData: message.imageData,
                      );
                    },
                  ),
          ),
          MessageInput(
            canSend: !_isGenerating,
            onSend: _sendMessage,
            isGenerating: _isGenerating,
            onStop: _stopGeneration,
            phase: _progressPhase,
          ),
        ],
      ),
    );
  }
}
