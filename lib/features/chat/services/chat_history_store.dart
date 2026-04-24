import '../../../core/storage/local_storage_service.dart';
import '../models/chat_message.dart';
import '../models/chat_thread.dart';

class ChatHistoryStore {
  static const _threadsKey = 'sigma_chat_threads';
  final LocalStorageService _storage;

  ChatHistoryStore(this._storage);

  String _messagesKey(String threadId) => 'sigma_chat_messages_$threadId';

  Future<List<ChatThread>> loadThreads() async {
    final list = await _storage.readJsonList(_threadsKey);
    return list.map(ChatThread.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveThreads(List<ChatThread> threads) async {
    await _storage.writeJsonList(_threadsKey, threads.map((e) => e.toJson()).toList());
  }

  Future<List<ChatMessage>> loadMessages(String threadId) async {
    final list = await _storage.readJsonList(_messagesKey(threadId));
    return list.map(ChatMessage.fromJson).toList();
  }

  Future<void> saveMessages(String threadId, List<ChatMessage> messages) async {
    await _storage.writeJsonList(_messagesKey(threadId), messages.map((e) => e.toJson()).toList());
  }

  Future<void> clearThread(String threadId) async {
    await _storage.writeJsonList(_messagesKey(threadId), []);
  }
}
