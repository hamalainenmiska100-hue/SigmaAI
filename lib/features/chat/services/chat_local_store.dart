import '../../../core/storage/local_storage_service.dart';
import '../models/chat_message.dart';

class ChatLocalStore {
  static const _key = 'sigmaai_chat_messages';
  final LocalStorageService _storage;

  ChatLocalStore(this._storage);

  Future<List<ChatMessage>> loadMessages() async {
    try {
      final list = await _storage.readJsonList(_key);
      return list.map(ChatMessage.fromJson).toList();
    } catch (_) {
      await _storage.writeJsonList(_key, []);
      return [];
    }
  }

  Future<void> saveMessages(List<ChatMessage> messages) {
    return _storage.writeJsonList(_key, messages.map((e) => e.toJson()).toList());
  }

  Future<void> clear() => _storage.writeJsonList(_key, []);
}
