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
import 'services/image_attachment_service.dart';
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
  final _chatStore = ChatHistoryStore(LocalStorageService());
  final _settingsService = SettingsService(LocalStorageService());
  final _aiService = AiService();
  final _imageService = ImageAttachmentService();

  List<ChatMessage> _messages = [];
  List<ChatThread> _threads = [];
  ChatThread? _activeThread;
  bool _isGenerating = false;
  String? _pendingImageData;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
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

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && _pendingImageData == null) || _isGenerating) return;
    if (trimmed.length > AppConfig.maxMessageLength) return;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: trimmed,
      imageData: _pendingImageData,
      createdAt: DateTime.now(),
    );

    final assistantId = _uuid.v4();
    final placeholder = ChatMessage(
      id: assistantId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages = [..._messages, userMessage, placeholder];
      _isGenerating = true;
      _pendingImageData = null;
    });
    await _persistCurrentThread(_messages, titleHint: trimmed);
    _scrollToBottom();

    final customInstructions = await _settingsService.loadCustomInstructions();

    try {
      var streamed = '';
      await for (final delta in _aiService.streamMessage(
        message: trimmed,
        customInstructions: customInstructions,
        history: _messages,
        imageData: userMessage.imageData,
      )) {
        streamed += delta;
        if (!mounted) return;
        setState(() {
          _messages = _messages
              .map((m) => m.id == assistantId ? ChatMessage(id: m.id, role: m.role, content: streamed, createdAt: m.createdAt) : m)
              .toList();
        });
        _scrollToBottom();
      }

      await _persistCurrentThread(_messages);
      if (!mounted) return;
      setState(() => _isGenerating = false);
    } on AiException catch (e) {
      debugPrint('AiException: ${e.displayMessage}');
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } catch (e, stackTrace) {
      debugPrint('Unhandled error while sending message: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() => _isGenerating = false);
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
    final messages = await _chatStore.loadMessages(thread.id);
    if (!mounted) return;
    setState(() {
      _activeThread = thread;
      _messages = messages;
    });
    Navigator.of(context).maybePop();
    _scrollToBottom(jump: true);
  }

  Future<void> _pickImage() async {
    final data = await _imageService.pickCompressedImageDataUri();
    if (data == null || !mounted) return;
    setState(() => _pendingImageData = data);
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sigma'),
        actions: [
          IconButton(onPressed: _createThread, icon: const Icon(Icons.add_comment_outlined)),
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
                  onTap: () => _switchThread(thread),
                ),
            ],
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF090B14), Color(0xFF111A2A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? const EmptyState(text: 'Ask anything, or upload a photo.')
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
            ChatLoadingArea(isLoading: _isGenerating),
            MessageInput(
              enabled: !_isGenerating,
              hasPendingImage: _pendingImageData != null,
              onPickImage: _pickImage,
              onRemoveImage: () => setState(() => _pendingImageData = null),
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
